local addonName, PCB = ...

--------------------------------------------------------------------------------
-- Core
--
-- Owns the set of bars, keeps them in step with config, and routes the client's
-- spellcast events to whichever bar cares.
--
-- Events are registered per bar with RegisterUnitEvent on the bar's own frame,
-- rather than through the shared PeaversCommons event frame. Unit-filtered
-- registration is done in the client, so an idle raid never wakes this addon up
-- for casts belonging to units it is not showing.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons

local CastBar = PCB.CastBar
local Blizzard = PCB.Blizzard
local CooldownManager = PCB.CooldownManager
local Secret = PCB.Secret

local Core = {}
PCB.Core = Core

Core.bars = {}
Core.unlocked = false

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START",
    "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP",
}

--------------------------------------------------------------------------------
-- Event plumbing
--------------------------------------------------------------------------------

-- Point a bar's event frame at a unit token. Called again whenever the token
-- changes under it, which is what vehicle handling below relies on.
local function BindEvents(bar, unit)
    local frame = bar.eventFrame
    frame:UnregisterAllEvents()

    if not unit then return end

    for _, event in ipairs(CAST_EVENTS) do
        -- Guarded: an event that does not exist on an older interface version
        -- would otherwise take the whole registration loop down with it.
        pcall(frame.RegisterUnitEvent, frame, event, unit)
    end
end

-- While the player is driving something, their casts belong to the "vehicle"
-- unit and nothing at all arrives on "player". Swapping the token keeps the one
-- player bar correct in both cases instead of going quiet in vehicles.
local function ResolvePlayerUnit()
    local hasVehicleUI = Secret.ReadBool(Secret.Safe(UnitHasVehicleUI, "player"))
    if hasVehicleUI and UnitExists("vehicle") then
        return "vehicle"
    end
    return "player"
end

function Core:UpdatePlayerUnit()
    local bar = self.bars.player
    if not bar then return end

    local unit = ResolvePlayerUnit()
    if bar.unit == unit then return end

    bar.unit = unit
    BindEvents(bar, bar.enabled and unit or nil)
    bar:Hide()
    bar:Refresh()
end

--------------------------------------------------------------------------------
-- Bars
--------------------------------------------------------------------------------

function Core:CreateBars()
    for _, unit in ipairs(PCB.Units) do
        local bar = CastBar.New(unit.key)

        local eventFrame = CreateFrame("Frame")
        -- The payload matters: every spellcast event carries the cast GUID it
        -- belongs to, which is the only way to tell this bar's cast apart from
        -- another attempt on the same unit.
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            bar:OnEvent(event, ...)
        end)
        bar.eventFrame = eventFrame

        self.bars[unit.key] = bar
    end
end

-- Single entry point for "config changed, make the world match". Cheap enough to
-- call on every settings interaction.
function Core:ApplyConfig()
    local config = PCB.Config

    for _, unit in ipairs(PCB.Units) do
        local bar = self.bars[unit.key]
        local unitCfg = config:GetUnit(unit.key)
        if bar and unitCfg then
            bar:SetEnabled(unitCfg.enabled)
            bar:Layout(config, unitCfg, self.unlocked)

            BindEvents(bar, unitCfg.enabled and bar.unit or nil)

            if self.unlocked then
                if unitCfg.enabled then
                    bar:ShowPreview()
                else
                    -- An unlocked bar for a disabled unit would be a ghost the
                    -- user can drag but will never see again.
                    bar:HidePreview()
                end
            elseif unitCfg.enabled then
                bar:Refresh()
            end
        end
    end

    Blizzard:Apply(config)
    self:UpdatePlayerUnit()
end

-- Re-run layout only. Used by the Cooldown Manager listener, where nothing about
-- the config changed - only the row the bars are measuring against.
--
-- The listener fires for any hooked viewer, and the buff rows in particular
-- resize whenever a tracked buff comes or goes, which in combat is often. Layout
-- is not free - fonts, backdrop colours, a dozen anchors - so a bar whose width
-- has not actually moved is skipped. Anchored bars are relaid out regardless,
-- since their anchor may have changed without any width changing.
function Core:RelayoutMatched()
    local config = PCB.Config

    for _, unit in ipairs(PCB.Units) do
        local bar = self.bars[unit.key]
        local unitCfg = config:GetUnit(unit.key)
        if bar and unitCfg then
            if unitCfg.anchorToCooldownManager then
                bar:Layout(config, unitCfg, self.unlocked)
            elseif unitCfg.matchCooldownManager then
                local width = bar:ResolveWidth(unitCfg)
                if math.abs(width - (bar.frame:GetWidth() or 0)) > 0.5 then
                    bar:Layout(config, unitCfg, self.unlocked)
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Unlock mode
--------------------------------------------------------------------------------

function Core:SetUnlocked(unlocked)
    self.unlocked = unlocked and true or false

    for _, unit in ipairs(PCB.Units) do
        local bar = self.bars[unit.key]
        local unitCfg = PCB.Config:GetUnit(unit.key)
        if bar and unitCfg then
            if self.unlocked and unitCfg.enabled then
                bar:Layout(PCB.Config, unitCfg, true)
                bar:ShowPreview()
            else
                bar:HidePreview()
                bar:Layout(PCB.Config, unitCfg, false)
            end
        end
    end

    return self.unlocked
end

function Core:ToggleUnlocked()
    return self:SetUnlocked(not self.unlocked)
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function Core:Initialize()
    self:CreateBars()

    CooldownManager:Initialize()
    CooldownManager:RegisterListener(function()
        self:RelayoutMatched()
    end)

    -- Unit tokens for target, focus and pet point at a different creature over
    -- time; RegisterUnitEvent follows the token, but a bar showing the previous
    -- unit's cast has to be re-read by hand.
    local events = PeaversCommons.Events
    events:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        local bar = self.bars.target
        if bar and bar.enabled then bar:Hide(); bar:Refresh() end
    end)
    events:RegisterEvent("PLAYER_FOCUS_CHANGED", function()
        local bar = self.bars.focus
        if bar and bar.enabled then bar:Hide(); bar:Refresh() end
    end)
    events:RegisterEvent("UNIT_PET", function()
        local bar = self.bars.pet
        if bar and bar.enabled then bar:Hide(); bar:Refresh() end
    end)

    events:RegisterEvent("UNIT_ENTERED_VEHICLE", function() self:UpdatePlayerUnit() end)
    events:RegisterEvent("UNIT_EXITED_VEHICLE", function() self:UpdatePlayerUnit() end)

    -- Blizzard rebuilds its cast bars during a loading screen, so the
    -- suppression has to be reasserted on the far side of one.
    events:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        self:ApplyConfig()
    end)

    self:ApplyConfig()
end

return Core
