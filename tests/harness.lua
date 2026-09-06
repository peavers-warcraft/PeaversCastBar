--------------------------------------------------------------------------------
-- The offline harness - loads src/UI/CastBar.lua under a stubbed client so the
-- event routing can be driven by hand.
--
-- The routing is the part of this addon that cannot be checked by playing it.
-- Whether a stop event belongs to the cast on the bar depends on the order the
-- client happens to deliver two packets in, which is latency, which is not
-- something anybody can reproduce on demand. So the orderings are written down
-- here instead and driven directly.
--
-- Run with the system lua (tests/run.sh). Two things differ from WoW's 5.1:
-- loop control variables are const in 5.4+, and `unpack` is `table.unpack`.
-- Neither may appear in addon code - it would work in game and break here,
-- which is where the checking happens.
--------------------------------------------------------------------------------

local harness = {}

---This file is `<PeaversCastBar>/tests/harness.lua`, whatever the checkout is
---called and wherever a worktree puts it, so the addon root is two levels up.
---@return string
local function root()
	local here = debug.getinfo(1, "S").source:sub(2)
	local testsDir = here:match("^(.*)[/\\][^/\\]+$") or "."
	return testsDir .. "/.."
end

harness.root = root

--------------------------------------------------------------------------------
-- Widget stubs
--
-- Deliberately not a WoW emulator. Only the handful of things the cast bar
-- reads back are modelled - whether a frame is shown, what a bar's value is,
-- what a font string says. Everything else is an inert no-op, so a call the
-- addon makes for its own sake cannot fail a test about event routing.
--------------------------------------------------------------------------------

local Widget = {}

Widget.__index = function(_, key)
	-- Internal state fields must not be swallowed by the catch-all, or an unset
	-- "_text" reads back as a stub closure instead of nil and every assertion
	-- about it silently passes.
	if type(key) == "string" and key:sub(1, 1) == "_" then return nil end

	return function(self, ...)
		if key == "Show" then
			self._shown = true
		elseif key == "Hide" then
			self._shown = false
		elseif key == "SetShown" then
			self._shown = (...) and true or false
		elseif key == "IsShown" or key == "IsVisible" then
			return self._shown
		elseif key == "SetValue" then
			self._value = ...
		elseif key == "GetValue" then
			return self._value
		elseif key == "SetAlpha" then
			self._alpha = ...
		elseif key == "GetAlpha" then
			return self._alpha or 1
		elseif key == "SetText" then
			self._text = ...
		elseif key == "GetText" then
			return self._text
		elseif key == "SetScript" then
			local script, fn = ...
			self._scripts = self._scripts or {}
			self._scripts[script] = fn
		elseif key == "GetScript" then
			return self._scripts and self._scripts[...]
		elseif key == "SetStatusBarTexture" then
			self._fill = self._fill or harness.widget()
		elseif key == "GetStatusBarTexture" then
			return self._fill
		elseif key == "CreateTexture" or key == "CreateFontString" then
			return harness.widget()
		elseif key == "GetWidth" then
			return self._width or 0
		elseif key == "SetSize" then
			self._width = ...
		elseif key == "GetPoint" then
			return "CENTER", nil, "CENTER", 0, 0
		end
	end
end

---A stand-in for any widget: frame, status bar, texture or font string.
function harness.widget()
	return setmetatable({ _shown = false }, Widget)
end

--------------------------------------------------------------------------------
-- Client stubs
--------------------------------------------------------------------------------

-- What the unit is doing, as the two Unit*Info functions would report it. Tests
-- assign these directly, then fire the event the client would have fired.
harness.casting = nil
harness.channeling = nil
harness.now = 1000

---Install the globals CastBar.lua reads, and return the loaded module.
---@return table CastBar
function harness.load()
	_G.UIParent = harness.widget()
	_G.CreateFrame = function() return harness.widget() end
	_G.GetTime = function() return harness.now end
	_G.GetNetStats = function() return 0, 0, 0, 0 end
	_G.GetUnitEmpowerStageDuration = function() return 0 end
	_G.issecretvalue = nil

	_G.UnitCastingInfo = function()
		local c = harness.casting
		if not c then return nil end
		return c.name, c.name, "icon", c.startMs, c.endMs, false, c.guid, false, c.spellID
	end

	_G.UnitChannelInfo = function()
		local c = harness.channeling
		if not c then return nil end
		-- No cast GUID: UnitChannelInfo does not return one, which is the whole
		-- reason a channel needs its spell id to identify itself.
		return c.name, c.name, "icon", c.startMs, c.endMs, false, false,
			c.spellID, c.empowered or false, c.numStages
	end

	_G.PeaversCommons = {
		Utils = {
			GetDefaultFont = function() return "Fonts\\FRIZQT__.TTF" end,
			SafeSetFont = function() end,
		},
	}

	local PCB = {
		Secret = {
			IsSecret = function() return false end,
			Safe = function(fn, ...)
				if type(fn) ~= "function" then return nil end
				return fn(...)
			end,
			ReadBool = function(v)
				if v == nil then return nil end
				return v and true or false
			end,
			Present = function(v) return v ~= nil end,
			Number = function(v)
				if type(v) ~= "number" then return nil end
				return v
			end,
			Caps = { timerDuration = false },
		},
		CooldownManager = {
			GetMatchedWidth = function() return nil end,
			AnchorFrame = function() return false end,
		},
		Config = { Save = function() end },
	}

	local path = root() .. "/src/UI/CastBar.lua"
	local chunk = assert(loadfile(path), "cannot load " .. path)
	return chunk("PeaversCastBar", PCB)
end

harness.APPEARANCE = {
	barTexture = "Interface\\TargetingFrame\\UI-StatusBar",
	bgColor = { r = 0, g = 0, b = 0 }, bgAlpha = 0.8,
	castColor = { r = 0.35, g = 0.55, b = 0.95 },
	channelColor = { r = 0.30, g = 0.70, b = 0.90 },
	failedColor = { r = 0.85, g = 0.25, b = 0.25 },
	showSpark = true, showLatency = false, fontSize = 11,
}

harness.UNIT_CFG = {
	enabled = true, width = 220, height = 24,
	showIcon = true, iconSide = "LEFT",
	showSpellName = true, showCastTime = true,
	framePoint = "CENTER", frameRelativePoint = "CENTER", frameX = 0, frameY = -180,
}

---A bar wired up the way Core wires one, with the unit idle.
function harness.bar(CastBar)
	harness.casting, harness.channeling = nil, nil
	local bar = CastBar.New("player")
	bar:SetEnabled(true)
	bar:Layout(harness.APPEARANCE, harness.UNIT_CFG, false)
	return bar
end

---Put a hard cast on the unit and tell the bar it started.
function harness.startCast(bar, guid, spellID, seconds)
	harness.casting = {
		name = "Cast " .. tostring(spellID),
		guid = guid,
		spellID = spellID,
		startMs = harness.now * 1000,
		endMs = (harness.now + (seconds or 2)) * 1000,
	}
	harness.channeling = nil
	bar:OnEvent("UNIT_SPELLCAST_START", "player", guid, spellID)
end

---Put a channel on the unit and tell the bar it started. `event` overrides the
---start event so empowered casts can be driven the same way.
function harness.startChannel(bar, guid, spellID, seconds, event)
	harness.channeling = {
		name = "Channel " .. tostring(spellID),
		spellID = spellID,
		startMs = harness.now * 1000,
		endMs = (harness.now + (seconds or 3)) * 1000,
	}
	harness.casting = nil
	bar:OnEvent(event or "UNIT_SPELLCAST_CHANNEL_START", "player", guid, spellID)
end

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

local failures, checks = {}, 0

function harness.check(label, ok, detail)
	checks = checks + 1
	if not ok then
		table.insert(failures, label .. (detail and ("  -> " .. detail) or ""))
	end
end

function harness.equal(label, got, want)
	harness.check(label, got == want,
		("got %s, want %s"):format(tostring(got), tostring(want)))
end

---The bar is on screen and running, rather than on its way out. A bar that has
---been stopped is still shown for the length of its fade, so "shown" alone does
---not answer the question these tests ask.
function harness.assertRunning(label, bar)
	harness.check(label .. ": shown", bar.frame:IsShown() == true)
	harness.check(label .. ": not fading", bar.fading == nil,
		("fading = %s"):format(tostring(bar.fading)))
	harness.check(label .. ": not failed", bar.failed == nil)
end

function harness.assertStopped(label, bar)
	harness.check(label .. ": fading out", bar.fading ~= nil or bar.frame:IsShown() == false,
		"bar is still running")
end

function harness.report(name)
	if #failures == 0 then
		print(("%s: %d checks OK"):format(name, checks))
		return 0
	end

	print(("%s: %d of %d checks FAILED"):format(name, #failures, checks))
	for _, failure in ipairs(failures) do
		print("  " .. failure)
	end
	return 1
end

return harness
