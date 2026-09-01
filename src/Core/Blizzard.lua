local addonName, PCB = ...

--------------------------------------------------------------------------------
-- Blizzard
--
-- Silences the default cast bars for whichever units this addon has taken over.
--
-- Deliberately gentle: the only state change is CastingBarFrameMixin:SetUnit(nil),
-- which is the mixin's own "stop tracking anything" path and unregisters the unit
-- events it registered itself. Nothing is reparented, nothing is permanently
-- unregistered, so turning a unit back off restores Blizzard's bar in place
-- without a reload. The OnShow guard exists because Edit Mode and the target
-- frame both re-show their bars on their own schedule.
--------------------------------------------------------------------------------

local Blizzard = {}
PCB.Blizzard = Blizzard

-- unit -> { name = global frame name, restore = { SetUnit arguments } }
--
-- The restore arguments mirror what Blizzard's own FrameXML passes: the second
-- and third flags are "show trade skills" and "show the uninterruptible shield".
local FRAMES = {
    player = { name = "PlayerCastingBarFrame", restore = { "player", true, false } },
    target = { name = "TargetFrameSpellBar", restore = { "target", false, true } },
    focus  = { name = "FocusFrameSpellBar", restore = { "focus", false, true } },
    pet    = { name = "PetCastingBarFrame", restore = { "pet", false, false } },
}

-- Units currently suppressed, so the OnShow guard knows whether to act.
local suppressed = {}

local function GetFrame(unit)
    local entry = FRAMES[unit]
    if not entry then return nil, nil end
    return _G[entry.name], entry
end

local function EnsureGuard(unit, frame)
    if frame.pcbGuarded then return end
    frame.pcbGuarded = true
    frame:HookScript("OnShow", function(f)
        if suppressed[unit] then
            f:Hide()
        end
    end)
end

function Blizzard:Suppress(unit)
    local frame = GetFrame(unit)
    if not frame then return false end

    suppressed[unit] = true
    EnsureGuard(unit, frame)

    -- SetUnit is the supported way to stop a casting bar tracking a unit. It is
    -- missing on frames that have not run their mixin init yet, hence the probe.
    if type(frame.SetUnit) == "function" then
        pcall(frame.SetUnit, frame, nil)
    end
    frame:Hide()

    return true
end

function Blizzard:Restore(unit)
    local frame, entry = GetFrame(unit)
    if not frame or not entry then return false end

    suppressed[unit] = nil

    if type(frame.SetUnit) == "function" then
        pcall(frame.SetUnit, frame, unpack(entry.restore))
    end

    return true
end

-- Drive every unit from config in one pass. Called on load and whenever a unit
-- is enabled or disabled, so a bar that gets turned off hands its unit straight
-- back to Blizzard.
function Blizzard:Apply(config)
    for unit in pairs(FRAMES) do
        local unitConfig = config:GetUnit(unit)
        if unitConfig and unitConfig.enabled and unitConfig.hideBlizzard then
            self:Suppress(unit)
        else
            self:Restore(unit)
        end
    end
end

function Blizzard:IsSuppressed(unit)
    return suppressed[unit] == true
end

return Blizzard
