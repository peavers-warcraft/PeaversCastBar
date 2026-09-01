local addonName, PCB = ...

--------------------------------------------------------------------------------
-- ConfigUI
--
-- Builds the PeaversConfig pages. One page per unit plus a shared appearance
-- page, so a unit's whole story fits on one screen without scrolling past three
-- other units' settings to reach it.
--------------------------------------------------------------------------------

local ConfigUI = {}
PCB.ConfigUI = ConfigUI

local PeaversCommons = _G.PeaversCommons
if not PeaversCommons then
    print("|cffff0000Error:|r PeaversCommons not found.")
    return
end

local W = PeaversCommons.Widgets
local ConfigManager = PeaversCommons.ConfigManager
local ConfigUIUtils = PeaversCommons.ConfigUIUtils

local CooldownManager = PCB.CooldownManager

local INDENT = 25

local function ResolveWidth(parentFrame)
    local parentWidth = parentFrame:GetWidth() or 0
    if parentWidth > 100 then
        return parentWidth - (INDENT * 2) - 10
    end
    return 360
end

local function Apply()
    PCB.Config:Save()
    PCB.Core:ApplyConfig()
end

-- Turn ConfigManager's { [path] = displayName } hash into the sorted array the
-- dropdown widget expects.
local function ToOptions(hash)
    local options = {}
    for value, label in pairs(hash) do
        table.insert(options, { value = value, label = label })
    end
    table.sort(options, function(a, b) return a.label < b.label end)
    return options
end

-- Grey out and block a control rather than disabling it.
--
-- These widgets are composites - a checkbox is a Frame wrapping a Button, a
-- slider wraps a Slider - so EnableMouse on the outer frame does nothing, and
-- walking the children to disable each one cannot be undone reliably (the inner
-- pieces did not all start mouse-enabled). A transparent blocker parked on top
-- is exact in both directions.
local function SetControlEnabled(control, enabled)
    control:SetAlpha(enabled and 1 or 0.4)

    if not control.pcbBlocker then
        local blocker = CreateFrame("Frame", nil, control)
        blocker:SetAllPoints(control)
        blocker:SetFrameLevel(control:GetFrameLevel() + 20)
        blocker:EnableMouse(true)
        blocker:Hide()
        control.pcbBlocker = blocker
    end

    control.pcbBlocker:SetShown(not enabled)
end

local function CooldownManagerOptions()
    local options = {}
    for _, viewer in ipairs(CooldownManager.Viewers) do
        table.insert(options, { value = viewer.key, label = viewer.label })
    end
    return options
end

--------------------------------------------------------------------------------
-- Per-unit page
--------------------------------------------------------------------------------

function ConfigUI:BuildUnitPage(parentFrame, unitKey, unitLabel)
    local cfg = PCB.Config:GetUnit(unitKey)
    local width = ResolveWidth(parentFrame)
    local y = -10

    -- Widgets that only make sense once the bar itself is switched on.
    local dependents = {}
    -- Widgets that only make sense while the width is NOT being matched.
    local widthDependents = {}

    -- CreateSlider calls SetValue during construction, and SetValue fires
    -- OnValueChanged, so every slider on the page would write its own current
    -- value back and trigger a full relayout just by being built. Held true for
    -- the duration of the build.
    local updatingUI = true

    local function SetGroupEnabled(group, enabled)
        for _, control in ipairs(group) do
            SetControlEnabled(control, enabled)
        end
    end

    local function RefreshDependents()
        SetGroupEnabled(dependents, cfg.enabled == true)
        SetGroupEnabled(widthDependents, cfg.enabled == true and not cfg.matchCooldownManager)
    end

    local function Add(control, spacing)
        control:SetPoint("TOPLEFT", INDENT, y)
        y = y - (spacing or 34)
        return control
    end

    local _, headerY = W:CreateSectionHeader(parentFrame, unitLabel .. " Cast Bar", INDENT, y)
    y = headerY - 8

    Add(W:CreateCheckbox(parentFrame, "Enable the " .. unitLabel:lower() .. " cast bar", {
        checked = cfg.enabled == true,
        width = width,
        onChange = function(checked)
            cfg.enabled = checked
            Apply()
            RefreshDependents()
        end,
    }))

    table.insert(dependents, Add(W:CreateCheckbox(parentFrame, "Hide Blizzard's default cast bar", {
        checked = cfg.hideBlizzard ~= false,
        width = width,
        description = "Turning this off shows both bars at once.",
        onChange = function(checked)
            cfg.hideBlizzard = checked
            Apply()
        end,
    }), 42))

    --------------------------------------------------------------------------
    -- Size
    --------------------------------------------------------------------------

    local _, sizeY = W:CreateSectionHeader(parentFrame, "Size", INDENT, y)
    y = sizeY - 8

    local cooldownManagerAvailable = CooldownManager:IsAvailable()

    table.insert(dependents, Add(W:CreateCheckbox(parentFrame, "Match Cooldown Manager width", {
        checked = cfg.matchCooldownManager == true,
        width = width,
        description = cooldownManagerAvailable
            and "The bar takes its width from the row selected below."
            or "Blizzard's Cooldown Manager is not active - turn it on in Edit Mode.",
        onChange = function(checked)
            cfg.matchCooldownManager = checked
            Apply()
            RefreshDependents()
        end,
    }), 42))

    local widthSlider = W:CreateSlider(parentFrame, "Width", {
        min = 60,
        max = 600,
        step = 1,
        value = cfg.width or 220,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            cfg.width = value
            Apply()
        end,
    })
    Add(widthSlider, 56)
    table.insert(widthDependents, widthSlider)

    table.insert(dependents, Add(W:CreateSlider(parentFrame, "Height", {
        min = 8,
        max = 60,
        step = 1,
        value = cfg.height or 24,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            cfg.height = value
            Apply()
        end,
    }), 56))

    --------------------------------------------------------------------------
    -- Position
    --------------------------------------------------------------------------

    local _, posY = W:CreateSectionHeader(parentFrame, "Position", INDENT, y)
    y = posY - 8

    table.insert(dependents, Add(W:CreateCheckbox(parentFrame, "Attach to the Cooldown Manager", {
        checked = cfg.anchorToCooldownManager == true,
        width = width,
        description = "The bar follows the row instead of sitting at a fixed spot.",
        onChange = function(checked)
            cfg.anchorToCooldownManager = checked
            Apply()
        end,
    }), 42))

    table.insert(dependents, Add(W:CreateDropdown(parentFrame, "Cooldown Manager row", {
        options = CooldownManagerOptions(),
        selected = cfg.cooldownManagerFrame,
        width = width,
        onChange = function(value)
            cfg.cooldownManagerFrame = value
            Apply()
        end,
    }), 52))

    table.insert(dependents, Add(W:CreateDropdown(parentFrame, "Attach on the", {
        options = {
            { value = "BOTTOM", label = "Below the row" },
            { value = "TOP", label = "Above the row" },
        },
        selected = cfg.anchorSide or "BOTTOM",
        width = width,
        onChange = function(value)
            cfg.anchorSide = value
            Apply()
        end,
    }), 52))

    table.insert(dependents, Add(W:CreateSlider(parentFrame, "Gap", {
        min = 0,
        max = 60,
        step = 1,
        value = cfg.anchorGap or 6,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            cfg.anchorGap = value
            Apply()
        end,
    }), 56))

    local unlockBtn = W:CreateButton(parentFrame, PCB.Core.unlocked and "Lock bars" or "Unlock bars to drag", {
        width = width,
        variant = "primary",
        onClick = function(button)
            local unlocked = PCB.Core:ToggleUnlocked()
            button:SetLabel(unlocked and "Lock bars" or "Unlock bars to drag")
        end,
    })
    Add(unlockBtn)

    local unlockHint = W:CreateLabel(parentFrame,
        "Unlocking parks a preview bar for every enabled unit so it can be dragged.",
        { font = "GameFontNormalSmall", color = { 0.5, 0.5, 0.5 } })
    Add(unlockHint, 24)

    local resetBtn = W:CreateButton(parentFrame, "Reset " .. unitLabel:lower() .. " bar to defaults", {
        width = width,
        variant = "danger",
        onClick = function()
            PCB.Config:ResetUnit(unitKey)
            -- The page holds a reference to the old table, so it has to be
            -- rebuilt against the fresh one rather than merely refreshed.
            cfg = PCB.Config:GetUnit(unitKey)
            PCB.Core:ApplyConfig()
            ConfigUI:Rebuild()
        end,
    })
    Add(resetBtn)

    --------------------------------------------------------------------------
    -- Contents
    --------------------------------------------------------------------------

    local _, contentY = W:CreateSectionHeader(parentFrame, "Contents", INDENT, y)
    y = contentY - 8

    table.insert(dependents, Add(W:CreateCheckbox(parentFrame, "Show the spell icon", {
        checked = cfg.showIcon ~= false,
        width = width,
        onChange = function(checked)
            cfg.showIcon = checked
            Apply()
        end,
    })))

    table.insert(dependents, Add(W:CreateDropdown(parentFrame, "Icon side", {
        options = {
            { value = "LEFT", label = "Left" },
            { value = "RIGHT", label = "Right" },
        },
        selected = cfg.iconSide or "LEFT",
        width = width,
        onChange = function(value)
            cfg.iconSide = value
            Apply()
        end,
    }), 52))

    table.insert(dependents, Add(W:CreateCheckbox(parentFrame, "Show the spell name", {
        checked = cfg.showSpellName ~= false,
        width = width,
        onChange = function(checked)
            cfg.showSpellName = checked
            Apply()
        end,
    })))

    table.insert(dependents, Add(W:CreateCheckbox(parentFrame, "Show the remaining cast time", {
        checked = cfg.showCastTime ~= false,
        width = width,
        onChange = function(checked)
            cfg.showCastTime = checked
            Apply()
        end,
    })))

    updatingUI = false
    RefreshDependents()

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Appearance page
--------------------------------------------------------------------------------

function ConfigUI:BuildAppearancePage(parentFrame)
    local config = PCB.Config
    local width = ResolveWidth(parentFrame)
    local y = -10
    -- See the note in BuildUnitPage: sliders fire onChange while being built.
    local updatingUI = true

    local function Add(control, spacing)
        control:SetPoint("TOPLEFT", INDENT, y)
        y = y - (spacing or 34)
        return control
    end

    local function AddColor(label, key, fallback)
        local color = config[key] or fallback
        Add(W:CreateColorPicker(parentFrame, label, {
            r = color.r, g = color.g, b = color.b,
            width = width,
            onChange = function(r, g, b)
                config[key] = { r = r, g = g, b = b }
                Apply()
            end,
        }), 28)
    end

    local _, barY = W:CreateSectionHeader(parentFrame, "Bar", INDENT, y)
    y = barY - 8

    Add(W:CreateDropdown(parentFrame, "Bar texture", {
        options = ToOptions(ConfigManager.GetBarTextures()),
        selected = config.barTexture,
        width = width,
        onChange = function(value)
            config.barTexture = value
            Apply()
        end,
    }), 52)

    Add(W:CreateCheckbox(parentFrame, "Show the moving spark", {
        checked = config.showSpark ~= false,
        width = width,
        onChange = function(checked)
            config.showSpark = checked
            Apply()
        end,
    }))

    Add(W:CreateCheckbox(parentFrame, "Show the latency zone on the player bar", {
        checked = config.showLatency ~= false,
        width = width,
        description = "Marks the tail of the cast where recasting is already safe.",
        onChange = function(checked)
            config.showLatency = checked
            Apply()
        end,
    }), 42)

    --------------------------------------------------------------------------
    local _, colorY = W:CreateSectionHeader(parentFrame, "Colours", INDENT, y)
    y = colorY - 8

    AddColor("Casting", "castColor", { r = 0.35, g = 0.55, b = 0.95 })
    AddColor("Channelling", "channelColor", { r = 0.30, g = 0.70, b = 0.90 })
    AddColor("Cannot be interrupted", "uninterruptibleColor", { r = 0.60, g = 0.60, b = 0.60 })
    AddColor("Failed or interrupted", "failedColor", { r = 0.85, g = 0.25, b = 0.25 })
    AddColor("Latency zone", "latencyColor", { r = 0.90, g = 0.20, b = 0.20 })
    AddColor("Text", "textColor", { r = 1, g = 1, b = 1 })
    AddColor("Background", "bgColor", { r = 0, g = 0, b = 0 })
    AddColor("Border", "borderColor", { r = 0, g = 0, b = 0 })

    y = y - 6

    Add(W:CreateSlider(parentFrame, "Background opacity", {
        min = 0, max = 1, step = 0.05,
        value = config.bgAlpha or 0.8,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            config.bgAlpha = value
            Apply()
        end,
    }), 56)

    Add(W:CreateSlider(parentFrame, "Empty bar opacity", {
        min = 0, max = 1, step = 0.05,
        value = config.barBgAlpha or 0.6,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            config.barBgAlpha = value
            Apply()
        end,
    }), 56)

    --------------------------------------------------------------------------
    local _, textY = W:CreateSectionHeader(parentFrame, "Text", INDENT, y)
    y = textY - 8

    Add(W:CreateDropdown(parentFrame, "Font", {
        options = ToOptions(ConfigManager.GetFonts()),
        selected = config.fontFace,
        width = width,
        onChange = function(value)
            config.fontFace = value
            Apply()
        end,
    }), 52)

    Add(W:CreateSlider(parentFrame, "Font size", {
        min = 6, max = 24, step = 1,
        value = config.fontSize or 11,
        width = width,
        onChange = function(value)
            if updatingUI then return end
            config.fontSize = value
            Apply()
        end,
    }), 56)

    Add(W:CreateDropdown(parentFrame, "Font outline", {
        options = {
            { value = "NONE", label = "None" },
            { value = "OUTLINE", label = "Outline" },
            { value = "THICKOUTLINE", label = "Thick outline" },
        },
        selected = config.fontOutline or "OUTLINE",
        width = width,
        onChange = function(value)
            config.fontOutline = value
            Apply()
        end,
    }), 52)

    --------------------------------------------------------------------------
    local _, layerY = W:CreateSectionHeader(parentFrame, "Layering", INDENT, y)
    y = layerY - 8

    Add(W:CreateDropdown(parentFrame, "Frame strata", {
        options = {
            { value = "BACKGROUND", label = "Background" },
            { value = "LOW", label = "Low" },
            { value = "MEDIUM", label = "Medium" },
            { value = "HIGH", label = "High" },
            { value = "DIALOG", label = "Dialog" },
        },
        selected = config.frameStrata or "MEDIUM",
        width = width,
        onChange = function(value)
            config.frameStrata = value
            Apply()
        end,
    }), 52)

    updatingUI = false

    parentFrame:SetHeight(math.abs(y) + 30)
end

--------------------------------------------------------------------------------
-- Info page
--------------------------------------------------------------------------------

function ConfigUI:BuildInfoPage(parentFrame)
    local width = ResolveWidth(parentFrame)

    ConfigUIUtils.BuildInfoPage(parentFrame, "Cast Bar", {
        "An ultra-lightweight replacement for the default cast bar, for the " ..
            "player, target, focus and pet - with the option to take its width " ..
            "straight from Blizzard's Cooldown Manager so the two line up exactly.",

        { command = "/pcb", desc = "open the settings" },
        { command = "/pcb unlock", desc = "show every bar so it can be dragged" },
        { command = "/pcb lock", desc = "finish positioning" },
        { command = "/pcb reset", desc = "restore every setting to its default" },

        { header = "Matching the Cooldown Manager" },
        "Turn on Match Cooldown Manager width and pick a row, and the bar " ..
            "resizes itself whenever that row does - including when you change " ..
            "spec, edit the row in Edit Mode, or gain a tracked cooldown. " ..
            "Attach to the Cooldown Manager goes further and pins the bar to " ..
            "the row, so moving the row moves the bar.",

        { header = "Positioning" },
        "Cast bars only exist while something is being cast, so use " ..
            "/pcb unlock (or the button on each unit's page) to park a preview " ..
            "bar on screen and drag it where you want it.",

        { header = "Blizzard's own bars" },
        "Each unit hands its default cast bar over when you enable it, and " ..
            "hands it straight back when you turn it off - no reload needed.",

        { header = "Built for performance" },
        "A bar costs about one client call per frame while something is " ..
            "casting, and nothing at all the rest of the time - hidden frames " ..
            "are never ticked, and events are filtered by the client rather " ..
            "than by Lua. Progress is read from the game clock instead of " ..
            "accumulated frame times, so a stutter can never drift the bar out " ..
            "of step with the cast. The whole addon is around 80 KB with no " ..
            "bundled libraries. Every one of those numbers is re-measured on " ..
            "each release and published in the README.",
    })

    -- Sits under the generated blocks; BuildInfoPage leaves the height set, so
    -- the button is placed against that and the height extended to cover it.
    local y = -(parentFrame:GetHeight() - 20)

    local unlockBtn = W:CreateButton(parentFrame, PCB.Core.unlocked and "Lock bars" or "Unlock bars to drag", {
        width = width,
        variant = "primary",
        height = 28,
        onClick = function(button)
            local unlocked = PCB.Core:ToggleUnlocked()
            button:SetLabel(unlocked and "Lock bars" or "Unlock bars to drag")
        end,
    })
    unlockBtn:SetPoint("TOPLEFT", INDENT, y)

    parentFrame:SetHeight(math.abs(y) + 50)
end

--------------------------------------------------------------------------------
-- Page registration
--------------------------------------------------------------------------------

function ConfigUI:GetPages()
    local pages = {
        { key = "info", label = "Information", builder = function(f) self:BuildInfoPage(f) end },
    }

    for _, unit in ipairs(PCB.Units) do
        table.insert(pages, {
            key = unit.key,
            label = unit.label,
            builder = function(f) self:BuildUnitPage(f, unit.key, unit.label) end,
        })
    end

    table.insert(pages, {
        key = "appearance",
        label = "Appearance",
        builder = function(f) self:BuildAppearancePage(f) end,
    })

    return pages
end

-- Ask PeaversConfig to throw its cached pages away and build them again. Needed
-- after a reset, where the controls on screen are bound to a config table that
-- no longer exists. Deferred by a frame so the click handler that triggered it
-- has returned before its own page is torn down.
function ConfigUI:Rebuild()
    local PeaversConfig = _G.PeaversConfig
    local contentArea = PeaversConfig and PeaversConfig.ContentArea
    if not contentArea or not contentArea.InvalidateCache then return end

    C_Timer.After(0, function()
        contentArea:InvalidateCache(addonName)
        if contentArea.ShowAddon then
            contentArea:ShowAddon(addonName)
        end
    end)
end

function ConfigUI:OpenOptions()
    if _G.PeaversConfig and _G.PeaversConfig.MainFrame then
        _G.PeaversConfig.MainFrame:Show()
        _G.PeaversConfig.MainFrame:SelectAddon("PeaversCastBar")
        return
    end

    if Settings and Settings.OpenToCategory then
        if PCB.directSettingsCategoryID then
            if pcall(Settings.OpenToCategory, PCB.directSettingsCategoryID) then return end
        end
        if PCB.directCategoryID then
            if pcall(Settings.OpenToCategory, PCB.directCategoryID) then return end
        end
    end

    if SettingsPanel then
        SettingsPanel:Open()
    end
end

function ConfigUI:BuildIntoFrame(parentFrame)
    self:BuildInfoPage(parentFrame)
    return parentFrame
end

function ConfigUI:Initialize()
end

return ConfigUI
