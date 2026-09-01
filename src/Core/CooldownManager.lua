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
function CooldownManager:Initialize()
    if type(EventUtil) == "table" and type(EventUtil.ContinueOnAddOnLoaded) == "function" then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_CooldownViewer", function()
            Notify()
        end)
    end
end

return CooldownManager
