--------------------------------------------------------------------------------
-- CastBar:OnEvent - which events are allowed to take a bar down.
--
-- Every case below is an event ordering the client really produces. They are
-- written down here because they cannot be produced on demand in game: whether
-- a finished cast's STOP arrives before or after the next spell's START is a
-- race between the client's local prediction and the server's confirmation, so
-- the bug they guard against shows up as "sometimes, at random".
--------------------------------------------------------------------------------

local h = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]+$") or ".")
	.. "/harness.lua")

local CastBar = h.load()

--------------------------------------------------------------------------------
-- The regression: a hard cast queued into a channel
--
-- Cast A finishes and channel B is already sent, so the client predicts B's
-- CHANNEL_START locally while A's STOP is still on the wire. When the STOP lost
-- that race it was ending B - a channel that had only just appeared - and the
-- player saw the bar flash and vanish for no reason they could name.
--------------------------------------------------------------------------------

do
	local bar = h.bar(CastBar)

	h.startCast(bar, "guid-A", 101, 1.5)
	h.assertRunning("cast A running", bar)

	h.startChannel(bar, "guid-B", 202, 3)
	h.assertRunning("channel B running", bar)
	h.equal("channel B is on the bar", bar.cast.channeling, true)

	-- A's stop, arriving late.
	bar:OnEvent("UNIT_SPELLCAST_STOP", "player", "guid-A", 101)
	h.assertRunning("late STOP for cast A leaves channel B alone", bar)
	h.equal("channel B still on the bar", bar.cast and bar.cast.spellID, 202)
end

--------------------------------------------------------------------------------
-- The same race with an empowered cast in front, which is the Evoker version of
-- it: EMPOWER_STOP for the finished empower against the channel behind it.
--------------------------------------------------------------------------------

do
	local bar = h.bar(CastBar)

	h.startChannel(bar, "guid-E", 303, 2, "UNIT_SPELLCAST_EMPOWER_START")
	h.startChannel(bar, "guid-F", 404, 3)
	h.assertRunning("channel F running", bar)

	bar:OnEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player", "guid-E", 303)
	h.assertRunning("late EMPOWER_STOP for another spell leaves channel F alone", bar)
end

--------------------------------------------------------------------------------
-- And the mirror image: a channel's CHANNEL_STOP arriving after the hard cast
-- that follows it has already started.
--------------------------------------------------------------------------------

do
	local bar = h.bar(CastBar)

	h.startChannel(bar, "guid-C", 505, 3)
	h.startCast(bar, "guid-D", 606, 2)
	h.assertRunning("cast D running", bar)

	bar:OnEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid-C", 505)
	h.assertRunning("late CHANNEL_STOP leaves cast D alone", bar)
end

--------------------------------------------------------------------------------
-- A channel cannot fail. It is committed the instant it starts, and one that
-- gets kicked reports CHANNEL_STOP - so every FAILED landing during a channel
-- belongs to some other press on the unit. Hammering a key during a channel is
-- exactly how a player produces a stream of them.
--------------------------------------------------------------------------------

do
	local bar = h.bar(CastBar)

	h.startChannel(bar, "guid-G", 707, 3)

	bar:OnEvent("UNIT_SPELLCAST_FAILED", "player", "guid-H", 808)
	bar:OnEvent("UNIT_SPELLCAST_FAILED", "player", "guid-I", 707)
	h.assertRunning("FAILED during a channel is ignored", bar)
end

--------------------------------------------------------------------------------
-- An interrupt aimed at another spell must not end the channel either. Before
-- channels carried a spell id this could not be told apart from their own,
-- because a channel's cast GUID is nil and the check gave up on that.
--------------------------------------------------------------------------------

do
	local bar = h.bar(CastBar)

	h.startChannel(bar, "guid-J", 909, 3)

	bar:OnEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "guid-K", 111)
	h.assertRunning("INTERRUPTED for a different spell is ignored", bar)

	bar:OnEvent("UNIT_SPELLCAST_INTERRUPTED", "player", "guid-J", 909)
	h.assertStopped("INTERRUPTED for the channel's own spell stops it", bar)
	h.equal("and marks it failed", bar.failed, true)
end

--------------------------------------------------------------------------------
-- The ordinary endings still end things. A guard that never lets go is a worse
-- bug than the one it replaced.
--------------------------------------------------------------------------------

do
	local bar = h.bar(CastBar)

	h.startChannel(bar, "guid-L", 121, 3)
	h.channeling = nil
	bar:OnEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player", "guid-L", 121)
	h.assertStopped("CHANNEL_STOP ends its own channel", bar)
end

do
	local bar = h.bar(CastBar)

	h.startChannel(bar, "guid-M", 131, 3, "UNIT_SPELLCAST_EMPOWER_START")
	h.channeling = nil
	bar:OnEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player", "guid-M", 131)
	h.assertStopped("EMPOWER_STOP ends its own empowered channel", bar)
end

do
	local bar = h.bar(CastBar)

	h.startCast(bar, "guid-N", 141, 2)
	h.casting = nil
	bar:OnEvent("UNIT_SPELLCAST_STOP", "player", "guid-N", 141)
	h.assertStopped("STOP ends its own hard cast", bar)
end

--------------------------------------------------------------------------------
-- The behaviour this all started from, kept: a failure belonging to a press
-- that never started must not take down the cast that is actually running,
-- while the running cast's own failure must.
--------------------------------------------------------------------------------

do
	local bar = h.bar(CastBar)

	h.startCast(bar, "guid-O", 151, 2)
	bar:OnEvent("UNIT_SPELLCAST_FAILED", "player", "guid-P", 161)
	h.assertRunning("FAILED for another attempt is ignored", bar)

	bar:OnEvent("UNIT_SPELLCAST_FAILED", "player", "guid-O", 151)
	h.assertStopped("FAILED for the running cast stops it", bar)
end

--------------------------------------------------------------------------------
-- A bar driven by restricted data has no readable end time, so nothing runs it
-- out; it clears only when its stop event arrives. Now that a stop of the wrong
-- kind is correctly ignored, the poll in OnUpdate is its only remaining way out
-- of a stop that never comes.
--------------------------------------------------------------------------------

do
	local bar = h.bar(CastBar)

	h.startChannel(bar, "guid-Q", 171, 3)
	-- Force the indeterminate path: no readable timings, no timer capability.
	bar.mode = "indeterminate"
	bar.startTime, bar.endTime = nil, nil

	bar:OnUpdate(0.016)
	h.assertRunning("indeterminate bar survives while the unit is still casting", bar)

	h.channeling = nil
	for _ = 1, 20 do bar:OnUpdate(0.016) end
	h.assertStopped("indeterminate bar clears once the unit goes idle", bar)
end

os.exit(h.report("CastBar events"))
