local addonName, PCB = ...

--------------------------------------------------------------------------------
-- Edit Mode
--
-- Four cast bars, each registered as its own Edit Mode frame, so selecting one
-- gives you that bar's settings rather than a picker for which bar you meant.
--
-- Two things are particular to this addon.
--
-- The bars are plain unprotected frames that already know how to drag
-- themselves, so unlike the unit frames there is no mover to register in their
-- place - the bar itself goes in, and its own drag handlers come off while Edit
-- Mode owns it.
--
-- And a bar pinned to the Cooldown Manager has no free position at all: it
-- takes its place and its width from that frame. Edit Mode cannot move such a
-- bar, so the position settings hide themselves while it is pinned rather than
-- offering a drag that would be silently undone on the next layout.
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons

local EditMode = {}
PCB.EditMode = EditMode

--------------------------------------------------------------------------------
-- Applying a change
--------------------------------------------------------------------------------

function PCB.ApplySetting()
    if PCB.Core and PCB.Core.ApplyConfig then
        PCB.Core:ApplyConfig()
    end
end

--------------------------------------------------------------------------------
-- Groups
--
-- Appearance and the cast colours are addon-wide - one look for all four bars -
-- so they are marked global and read from the config itself rather than from
-- the selected bar's slice of it. They appear on every bar's panel because they
-- are the same settings whichever bar you have selected.
--------------------------------------------------------------------------------

EditMode.SECTIONS = {
    { key = "bar", label = "Bar" },
    { key = "position", label = "Position" },
    { key = "cooldown", label = "Cooldown Manager" },
    { key = "contents", label = "Contents" },
    { key = "appearance", label = "Appearance (All Bars)" },
    { key = "colors", label = "Colours (All Bars)" },
}

-- A bar taking its place from the Cooldown Manager has no position of its own.
local function WhenFree(cfg) return cfg.anchorToCooldownManager end

EditMode.ENTRIES = {
    ------------------------------------------------------------------- bar ---
    {
        key = "enabled", label = "Enabled", kind = "checkbox", section = "bar",
        desc = "Off leaves this unit's cast bar to Blizzard.",
    },
    {
        key = "width", label = "Width", kind = "slider", section = "bar",
        min = 80, max = 500, step = 2, unit = "px",
        -- Width comes from the Cooldown Manager when matched to it.
        hidden = function(cfg) return cfg.matchCooldownManager end,
    },
    {
        key = "height", label = "Height", kind = "slider", section = "bar",
        min = 8, max = 60, step = 1, unit = "px",
    },
    {
        key = "hideBlizzard", label = "Hide Blizzard's Cast Bar", kind = "checkbox",
        section = "bar", default = true,
    },

    -------------------------------------------------------------- position ---
    {
        key = "framePoint", label = "Anchor", kind = "dropdown", section = "position",
        fallback = "CENTER", hidden = WhenFree,
        values = {
            { value = "CENTER", label = "Centre" },
            { value = "TOP", label = "Top" },
            { value = "BOTTOM", label = "Bottom" },
            { value = "TOPLEFT", label = "Top left" },
            { value = "TOPRIGHT", label = "Top right" },
            { value = "BOTTOMLEFT", label = "Bottom left" },
            { value = "BOTTOMRIGHT", label = "Bottom right" },
        },
    },
    { key = "frameX", label = "X Offset", kind = "number", section = "position",
      default = 0, hidden = WhenFree },
    { key = "frameY", label = "Y Offset", kind = "number", section = "position",
      default = 0, hidden = WhenFree },

    -------------------------------------------------------------- cooldown ---
    {
        key = "matchCooldownManager", label = "Match Its Width", kind = "checkbox",
        section = "cooldown", default = false, revealsOthers = true,
        desc = "Takes the bar's width from the Cooldown Manager so the two line up.",
    },
    {
        key = "anchorToCooldownManager", label = "Pin To It", kind = "checkbox",
        section = "cooldown", default = false, revealsOthers = true,
        desc = "Pins the bar to the Cooldown Manager. Edit Mode cannot move a bar "
            .. "that is pinned.",
    },
    {
        key = "cooldownManagerFrame", label = "Which Viewer", kind = "dropdown",
        section = "cooldown", fallback = "EssentialCooldownViewer",
        hidden = function(cfg)
            return not (cfg.matchCooldownManager or cfg.anchorToCooldownManager)
        end,
        values = {
            { value = "EssentialCooldownViewer", label = "Essential" },
            { value = "UtilityCooldownViewer", label = "Utility" },
            { value = "BuffIconCooldownViewer", label = "Buff icons" },
            { value = "BuffBarCooldownViewer", label = "Buff bars" },
        },
    },
    {
        key = "anchorSide", label = "Which Side", kind = "dropdown", section = "cooldown",
        fallback = "BOTTOM",
        hidden = function(cfg) return not cfg.anchorToCooldownManager end,
        values = {
            { value = "TOP", label = "Above it" },
            { value = "BOTTOM", label = "Below it" },
        },
    },
    {
        key = "anchorGap", label = "Gap", kind = "slider", section = "cooldown",
        min = 0, max = 40, step = 1, unit = "px", default = 6,
        hidden = function(cfg) return not cfg.anchorToCooldownManager end,
    },

    -------------------------------------------------------------- contents ---
    {
        key = "showIcon", label = "Show The Spell Icon", kind = "checkbox",
        section = "contents", default = true, revealsOthers = true,
    },
    {
        key = "iconSide", label = "Icon Side", kind = "dropdown", section = "contents",
        fallback = "LEFT", hidden = function(cfg) return not cfg.showIcon end,
        values = {
            { value = "LEFT", label = "Left of the bar" },
            { value = "RIGHT", label = "Right of the bar" },
        },
    },
    {
        key = "showSpellName", label = "Show The Spell Name", kind = "checkbox",
        section = "contents", default = true,
    },
    {
        key = "showCastTime", label = "Show The Cast Time", kind = "checkbox",
        section = "contents", default = true,
    },

    ------------------------------------------------------------ appearance ---
    -- One look for all four bars.
    { key = "barTexture", section = "appearance", global = true, height = 300 },
    { key = "fontFace", section = "appearance", global = true, height = 300 },
    { key = "fontSize", section = "appearance", global = true },
    { key = "fontOutline", section = "appearance", global = true },
    { key = "bgColor", section = "appearance", global = true },
    { key = "bgAlpha", section = "appearance", global = true },
    {
        key = "barBgColor", label = "Empty Bar Colour", kind = "color",
        section = "appearance", global = true, default = { r = 0.10, g = 0.10, b = 0.12 },
    },
    {
        key = "barBgAlpha", label = "Empty Bar Opacity", kind = "slider",
        section = "appearance", global = true,
        min = 0, max = 1, step = 0.05, unit = "percent", default = 0.6,
    },
    {
        key = "borderColor", label = "Border Colour", kind = "color",
        section = "appearance", global = true, default = { r = 0, g = 0, b = 0 },
    },
    {
        key = "borderAlpha", label = "Border Opacity", kind = "slider",
        section = "appearance", global = true,
        min = 0, max = 1, step = 0.05, unit = "percent", default = 1,
    },
    {
        key = "textColor", label = "Text Colour", kind = "color",
        section = "appearance", global = true, default = { r = 1, g = 1, b = 1 },
    },
    {
        key = "frameStrata", label = "Layer", kind = "dropdown",
        section = "appearance", global = true, fallback = "MEDIUM",
        desc = "Which layer the bars sit on, if something else is covering them.",
        values = {
            { value = "LOW", label = "Low" },
            { value = "MEDIUM", label = "Medium" },
            { value = "HIGH", label = "High" },
            { value = "DIALOG", label = "Dialog" },
        },
    },

    ---------------------------------------------------------------- colors ---
    {
        key = "castColor", label = "Casting", kind = "color", section = "colors",
        global = true, default = { r = 0.35, g = 0.55, b = 0.95 },
    },
    {
        key = "channelColor", label = "Channelling", kind = "color", section = "colors",
        global = true, default = { r = 0.30, g = 0.70, b = 0.90 },
    },
    {
        key = "uninterruptibleColor", label = "Uninterruptible", kind = "color",
        section = "colors", global = true, default = { r = 0.60, g = 0.60, b = 0.60 },
    },
    {
        key = "failedColor", label = "Failed", kind = "color", section = "colors",
        global = true, default = { r = 0.85, g = 0.25, b = 0.25 },
    },
    {
        key = "showSpark", label = "Show The Spark", kind = "checkbox",
        section = "colors", global = true, default = true,
    },
    {
        key = "showLatency", label = "Show Latency", kind = "checkbox",
        section = "colors", global = true, default = true, revealsOthers = true,
        desc = "The band at the end of your own cast bar showing where the spell "
            .. "is already committed.",
    },
    {
        key = "latencyColor", label = "Latency Colour", kind = "color",
        section = "colors", global = true, default = { r = 0.90, g = 0.20, b = 0.20 },
        hidden = function(cfg) return not cfg.showLatency end,
    },
    {
        key = "latencyAlpha", label = "Latency Opacity", kind = "slider",
        section = "colors", global = true,
        min = 0, max = 1, step = 0.05, unit = "percent", default = 0.5,
        hidden = function(cfg) return not cfg.showLatency end,
    },
}

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

function EditMode:BuildSchema()
    if self.schema then return self.schema end

    self.schema = PeaversCommons.SettingsSchema:New({
        config = PCB.Config,
        sections = self.SECTIONS,
        entries = self.ENTRIES,
        scope = function(config, unitKey) return config:GetUnit(unitKey) or {} end,
        scopeDefaults = function(config, unitKey)
            local units = config.defaults and config.defaults.units
            return units and units[unitKey] or {}
        end,
        apply = function() PCB.ApplySetting() end,
    })

    return self.schema
end

-- Edit Mode reports an anchor point and an offset, which is what this addon
-- already stores - including the relative point, which it keeps separately
-- because StopMovingOrSizing is free to leave a frame anchored by a different
-- corner than it started on.
local function SavePosition(unitKey)
    return function(frame, point, x, y)
        local unitCfg = PCB.Config:GetUnit(unitKey)
        if not unitCfg then return end

        local _, _, relativePoint = frame:GetPoint()
        unitCfg.framePoint = point
        unitCfg.frameRelativePoint = relativePoint or point
        unitCfg.frameX = x
        unitCfg.frameY = y
        PCB.Config:Save()
    end
end

function EditMode:Register()
    if not PeaversCommons.EditMode or not PeaversCommons.EditMode.available then
        return false
    end
    if not (PCB.Core and PCB.Core.bars) then return false end
    if self.registered then return true end

    local schema = self:BuildSchema()

    for _, unit in ipairs(PCB.Units) do
        local bar = PCB.Core.bars[unit.key]
        local unitCfg = PCB.Config:GetUnit(unit.key)

        if bar and bar.frame and unitCfg then
            PeaversCommons.EditMode:Register({
                frame = bar.frame,
                name = "Peavers Cast Bar - " .. unit.label,
                schema = schema,
                context = unit.key,
                default = {
                    point = unitCfg.framePoint or "CENTER",
                    x = unitCfg.frameX or 0,
                    y = unitCfg.frameY or 0,
                },
                onPositionChanged = SavePosition(unit.key),

                onEnter = function(frame)
                    -- The bar drags itself when unlocked, and Edit Mode drags it
                    -- through its own overlay; both at once means two systems
                    -- answering one drag.
                    frame:RegisterForDrag()
                    frame:SetScript("OnDragStart", nil)
                    frame:SetScript("OnDragStop", nil)
                    -- A bar only appears while something is casting, and a
                    -- hidden frame takes its own Edit Mode handle down with it.
                    frame:Show()
                end,
                onExit = function()
                    PCB.ApplySetting()
                end,
            })
        end
    end

    self.registered = true
    return true
end

return EditMode
