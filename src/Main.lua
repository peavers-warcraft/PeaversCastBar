local addonName, PCB = ...

local PeaversCommons = _G.PeaversCommons
local Utils = PeaversCommons.Utils

PCB.name = addonName
PCB.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"

PeaversCommons.SlashCommands:Register(addonName, "pcb", {
    default = function()
        PCB.ConfigUI:OpenOptions()
    end,
    unlock = function()
        PCB.Core:SetUnlocked(true)
        Utils.Print(PCB, "Bars unlocked - drag them into place, then /pcb lock.")
    end,
    lock = function()
        PCB.Core:SetUnlocked(false)
        Utils.Print(PCB, "Bars locked.")
    end,
    toggle = function()
        local unlocked = PCB.Core:ToggleUnlocked()
        Utils.Print(PCB, unlocked and "Bars unlocked." or "Bars locked.")
    end,
    reset = function()
        PCB.Config:Reset()
        PCB.Core:ApplyConfig()
        if PCB.ConfigUI and PCB.ConfigUI.Rebuild then
            PCB.ConfigUI:Rebuild()
        end
        Utils.Print(PCB, "All settings restored to defaults.")
    end,
    help = function()
        Utils.Print(PCB, "Commands:")
        print("  /pcb - Open settings")
        print("  /pcb unlock - Show every bar so it can be dragged")
        print("  /pcb lock - Finish positioning")
        print("  /pcb reset - Restore every setting to its default")
    end,
})

PeaversCommons.Events:Init(addonName, function()
    PCB.Config:Initialize()
    PCB.Core:Initialize()

    if PCB.ConfigUI and PCB.ConfigUI.Initialize then
        PCB.ConfigUI:Initialize()
    end

    if PCB.Patrons and PCB.Patrons.Initialize then
        PCB.Patrons:Initialize()
    end

    -- Use the centralized SettingsUI system from PeaversCommons
    C_Timer.After(0.5, function()
        PeaversCommons.SettingsUI:CreateRedirectPage(PCB, "PeaversCastBar", "Peavers Cast Bar")
    end)

    -- Register with the PeaversConfig registry
    if PeaversCommons.ConfigRegistry then
        PeaversCommons.ConfigRegistry:Register({
            name = "PeaversCastBar",
            displayName = "Cast Bar",
            description = "A clean cast bar that can match your Cooldown Manager",
            addonRef = PCB,
            config = PCB.Config,
            pages = PCB.ConfigUI:GetPages(),
            order = 13,
        })
    end
end, {
    suppressAnnouncement = true
})

_G.PeaversCastBar = PCB
