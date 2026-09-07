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

-- Applying a setting lives with the addon's schema now, in EditMode.lua, so the
-- settings page and the Edit Mode panel cannot disagree about what a change
-- should do.

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
    return {
        { key = "info", label = "Information", builder = function(f) self:BuildInfoPage(f) end },
    }
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
