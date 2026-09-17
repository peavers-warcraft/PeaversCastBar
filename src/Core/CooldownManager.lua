local addonName, PCB = ...

--------------------------------------------------------------------------------
-- CooldownManager
--
-- Reads the size and position of Blizzard's Cooldown Manager rows so a cast bar
-- can line up with them exactly.
--
-- Two independent things are on offer, and either can be used without the other:
--   * width matching  - the bar takes the row's width, so the two edges agree
--   * anchoring       - the bar is pinned to the row, so it follows it around
--                       Edit Mode without the user re-positioning anything
--
-- The viewers live in Blizzard_CooldownViewer, which is load-on-demand and may
-- never load at all if the player has the Cooldown Manager turned off. Nothing
-- here assumes they exist; callers get a nil width and fall back to their own
-- configured size.
--------------------------------------------------------------------------------

local CooldownManager = {}
PCB.CooldownManager = CooldownManager

-- Order matters: this drives the dropdown in the settings UI.
CooldownManager.Viewers = {
    { key = "EssentialCooldownViewer", label = "Essential Cooldowns" },
    { key = "UtilityCooldownViewer", label = "Utility Cooldowns" },
    { key = "BuffIconCooldownViewer", label = "Tracked Buffs (icons)" },
    { key = "BuffBarCooldownViewer", label = "Tracked Buffs (bars)" },
}

-- A row narrower than this is empty or mid-layout rather than genuinely tiny,
-- and matching it would collapse the cast bar to nothing.
-- WoW Forever ships the whole Cooldown Manager and none of it works: on the beta
-- Blizzard_CooldownViewer is listed and loaded, C_CooldownViewer is complete, all
-- four viewers exist hidden at width 1, and IsCooldownViewerAvailable() returns
-- true - while no player can use it and Blizzard have said it will not be
-- available. So this is the one question here asked as a flavour rather than a
-- capability: every capability signal answers yes. Identified by interface range
-- because Forever reports WOW_PROJECT_ID as mainline, and derived locally because
-- a released PeaversCommons has no isForever. If the feature ships, delete this
-- and let IsCooldownViewerAvailable answer.
local IS_FOREVER = (function()
    local compat = _G.PeaversCommons and _G.PeaversCommons.Compat
    if compat and compat.isForever ~= nil then
        return compat.isForever and true or false
    end
    local interface = tonumber((select(4, GetBuildInfo()))) or 0
    return interface >= 16000 and interface < 20000
end)()

local MIN_USABLE_WIDTH = 20

local listeners = {}
local hooked = {}
local notifyQueued = false

local function Notify()
    if notifyQueued then return end
    notifyQueued = true
    -- Coalesce to the next frame: Edit Mode resizes a row several times in one
    -- pass, and every listener does a full relayout.
    C_Timer.After(0, function()
        notifyQueued = false
        for _, listener in ipairs(listeners) do
            listener()
        end
    end)
end

-- Watch a viewer for the changes that would leave a matched bar out of step.
-- Hooked once per frame, on first resolve, and never removed.
local function EnsureHooks(key, frame)
    if hooked[key] then return end
    hooked[key] = true

    frame:HookScript("OnSizeChanged", Notify)
    frame:HookScript("OnShow", Notify)
    frame:HookScript("OnHide", Notify)
end

function CooldownManager:GetFrame(key)
    if not key then return nil end

    local frame = _G[key]
    if type(frame) ~= "table" or type(frame.GetWidth) ~= "function" then
        return nil
    end

    EnsureHooks(key, frame)
    return frame
end

function CooldownManager:IsAvailable()
    for _, viewer in ipairs(self.Viewers) do
        if self:GetFrame(viewer.key) then return true end
    end
    return false
end

-- Whether this client has a Cooldown Manager at all.
--
-- A different question from IsAvailable, and the one the settings need: the
-- viewers are load-on-demand, so on retail every one of them can be absent for a
-- whole session and still be a keypress away. Asking about the client instead -
-- the API namespace, or failing that the addon being listed at all - is what
-- keeps the settings on retail and drops them on a Classic client, where there
-- is no Cooldown Manager and a bar keeps its own width and position.
--
-- Three nets rather than one, because the two answers are not equally cheap to
-- get wrong: a false where the client does have a Cooldown Manager would take
-- the settings away from the people most likely to want them, so saying no
-- takes the API namespace, the addon listing and any viewer already on screen
-- all missing together.
function CooldownManager:IsSupported()
    if IS_FOREVER then return false end

    if _G.C_CooldownViewer ~= nil then return true end

    if C_AddOns and type(C_AddOns.GetAddOnInfo) == "function" then
        local ok, name = pcall(C_AddOns.GetAddOnInfo, "Blizzard_CooldownViewer")
        if ok and name then return true end
    end

    for _, viewer in ipairs(self.Viewers) do
        if type(_G[viewer.key]) == "table" then return true end
    end

    return false
end

-- The viewer's width expressed in `relativeTo`'s coordinate space.
--
-- Both frames can sit at different effective scales - the Cooldown Manager is
-- scaled by Edit Mode, the cast bar by its own parent chain - so the raw widths
-- are not comparable. Converting through screen space is what makes the two
-- edges actually line up on screen rather than merely share a number.
function CooldownManager:GetMatchedWidth(key, relativeTo)
    local frame = self:GetFrame(key)
    if not frame then return nil end

    local width = frame:GetWidth()
    if not width or width < MIN_USABLE_WIDTH then return nil end

    if relativeTo then
        local sourceScale = frame:GetEffectiveScale()
        local targetScale = relativeTo:GetEffectiveScale()
        if sourceScale and targetScale and targetScale > 0 then
            width = width * sourceScale / targetScale
        end
    end

    return width
end

-- Pin `frame` above or below the chosen viewer. Returns false when the viewer is
-- unavailable so the caller can fall back to the saved free position.
function CooldownManager:AnchorFrame(frame, key, side, gap)
    local viewer = self:GetFrame(key)
    if not viewer then return false end

    -- Existing is not the same as usable. A viewer can be present and hidden at
    -- a placeholder size - every one of Forever's sits hidden at width 1 - and
    -- pinning to it would park the bar at an invisible frame's position instead
    -- of leaving it where the player put it. GetMatchedWidth already refuses the
    -- same frame; anchoring has to refuse it too.
    if not viewer:IsShown() then return false end
    local width = viewer:GetWidth()
    if not width or width < MIN_USABLE_WIDTH then return false end

    gap = gap or 6

    frame:ClearAllPoints()
    if side == "TOP" then
        frame:SetPoint("BOTTOM", viewer, "TOP", 0, gap)
    else
        frame:SetPoint("TOP", viewer, "BOTTOM", 0, -gap)
    end

    return true
end

function CooldownManager:RegisterListener(listener)
    table.insert(listeners, listener)
end

-- Blizzard_CooldownViewer is load-on-demand, so the viewers can appear long
-- after this addon has finished initialising. EventUtil handles the case where
-- it is already loaded, and the notify re-runs every matched layout once it is.
--
-- Skipped where there is no Cooldown Manager: waiting on an addon the client has
-- never heard of is a callback that never fires at best, and asking about an
-- unknown addon name is not something every client answers politely.
function CooldownManager:Initialize()
    if not self:IsSupported() then return end

    if type(EventUtil) == "table" and type(EventUtil.ContinueOnAddOnLoaded) == "function" then
        pcall(EventUtil.ContinueOnAddOnLoaded, "Blizzard_CooldownViewer", function()
            Notify()
        end)
    end
end

return CooldownManager
