local addonName, PCB = ...

--------------------------------------------------------------------------------
-- PeaversCastBar Configuration
--
-- Account-wide: a cast bar's position and size belong to the screen, not to a
-- character, so this uses the flat (non-profile) ConfigManager variant.
--
-- Appearance keys are deliberately stored flat on the config table rather than
-- nested. That is what lets PeaversCommons GlobalAppearance sync barTexture,
-- fontFace, bgAlpha and friends across every Peavers addon, and it means the
-- config table can be handed to CastBar:Layout as the appearance table directly.
-- Per-unit settings live under `units`.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons
local ConfigManager = PeaversCommons.ConfigManager
local Utils = PeaversCommons.Utils

PCB.name = PCB.name or addonName

-- Every unit starts from this, then applies its own overrides below.
local UNIT_DEFAULTS = {
    enabled = false,

    -- Size
    width = 220,
    height = 24,

    -- Cooldown Manager integration
    matchCooldownManager = false,
    anchorToCooldownManager = false,
    cooldownManagerFrame = "EssentialCooldownViewer",
    anchorSide = "BOTTOM",
    anchorGap = 6,

    -- Contents
    showIcon = true,
    iconSide = "LEFT",
    showSpellName = true,
    showCastTime = true,

    -- Position (only used when not anchored to the Cooldown Manager)
    framePoint = "CENTER",
    frameRelativePoint = "CENTER",
    frameX = 0,
    frameY = -180,

    -- Hand the unit's default Blizzard cast bar over to us
    hideBlizzard = true,
}

-- Order matters: this drives the settings sidebar and the update loop.
PCB.Units = {
    { key = "player", label = "Player" },
    { key = "target", label = "Target" },
    { key = "focus", label = "Focus" },
    { key = "pet", label = "Pet" },
}

-- Only the differences from UNIT_DEFAULTS. Player and target are on out of the
-- box because that is what "replace the default cast bar" means to most people;
-- focus and pet are opt-in.
local UNIT_OVERRIDES = {
    player = { enabled = true, frameY = -180 },
    target = { enabled = true, frameY = 200, width = 200, height = 22 },
    focus = { frameX = -320, frameY = 120, width = 180, height = 20 },
    pet = { frameY = -240, width = 160, height = 16, showCastTime = false },
}

local function BuildUnitDefaults()
    local units = {}
    for _, unit in ipairs(PCB.Units) do
        local cfg = Utils.DeepCopy(UNIT_DEFAULTS)
        for key, value in pairs(UNIT_OVERRIDES[unit.key] or {}) do
            cfg[key] = value
        end
        units[unit.key] = cfg
    end
    return units
end

local PCB_DEFAULTS = {
    -- Appearance (bgAlpha, bgColor, barTexture, fontFace, fontSize and
    -- fontOutline all come from ConfigManager.CommonDefaults)
    fontSize = 11,
    barBgColor = { r = 0.10, g = 0.10, b = 0.12 },
    barBgAlpha = 0.6,
    borderColor = { r = 0, g = 0, b = 0 },
    borderAlpha = 1,
    textColor = { r = 1, g = 1, b = 1 },
    frameStrata = "MEDIUM",

    -- Cast state colours
    castColor = { r = 0.35, g = 0.55, b = 0.95 },
    channelColor = { r = 0.30, g = 0.70, b = 0.90 },
    uninterruptibleColor = { r = 0.60, g = 0.60, b = 0.60 },
    failedColor = { r = 0.85, g = 0.25, b = 0.25 },
    latencyColor = { r = 0.90, g = 0.20, b = 0.20 },
    latencyAlpha = 0.5,

    showSpark = true,
    showLatency = true,

    units = BuildUnitDefaults(),
}

local Config = ConfigManager:New(PCB, PCB_DEFAULTS, {
    savedVariablesName = "PeaversCastBarDB",
})
PCB.Config = Config

--------------------------------------------------------------------------------
-- Unit access
--------------------------------------------------------------------------------

function Config:GetUnit(unit)
    if type(self.units) ~= "table" then
        self.units = BuildUnitDefaults()
    end
    return self.units[unit]
end

-- ConfigManager only backfills missing *top-level* keys, so a saved `units`
-- table written by an older version keeps whatever shape it had. Anything added
-- to UNIT_DEFAULTS after the fact would arrive as nil at the point of use, so
-- the nested tables are filled in explicitly here.
function Config:EnsureUnitDefaults()
    local defaults = BuildUnitDefaults()

    if type(self.units) ~= "table" then
        self.units = defaults
        return
    end

    -- On a first run ConfigManager seeds the live value with the *same table*
    -- it holds as the default, so editing a bar's width would quietly rewrite
    -- the default it is supposed to be restorable to. Break the alias before
    -- anything gets a chance to write through it.
    if self.units == self.defaults.units then
        self.units = defaults
        return
    end

    for unitKey, unitDefaults in pairs(defaults) do
        local saved = self.units[unitKey]
        if type(saved) ~= "table" then
            self.units[unitKey] = unitDefaults
        else
            for key, value in pairs(unitDefaults) do
                if saved[key] == nil then
                    saved[key] = value
                end
            end
        end
    end
end

function Config:ResetUnit(unit)
    local defaults = BuildUnitDefaults()
    if not defaults[unit] then return false end

    self.units[unit] = defaults[unit]
    self:Save()
    return true
end

-- Initialize and Reset are created inside ConfigManager:New, so they are wrapped
-- rather than replaced. Both need the nested `units` table handled afterwards:
-- ConfigManager's own copy is one level deep, which leaves Reset pointing the
-- live table straight back at the defaults it was already aliasing.
local baseInitialize = Config.Initialize
function Config:Initialize()
    baseInitialize(self)
    self:EnsureUnitDefaults()
    self:Save()
end

local baseReset = Config.Reset
function Config:Reset()
    baseReset(self)
    self.units = BuildUnitDefaults()
    self:Save()
    return true
end

return Config
