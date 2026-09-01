local addonName, PCB = ...

--------------------------------------------------------------------------------
-- CastBar
--
-- One bar per unit. Owns its own frame, drives its own fill, and knows nothing
-- about configuration beyond the two tables handed to Layout.
--
-- The fill is driven one of three ways, chosen per cast:
--   * readable timings -> an ordinary OnUpdate against GetTime()
--   * secret timings   -> a DurationObject passed to StatusBar:SetTimerDuration,
--                         letting the client animate data we may not read
--   * neither          -> a full bar with the spell name, which beats showing
--                         nothing at all
--------------------------------------------------------------------------------

local PeaversCommons = _G.PeaversCommons
local Utils = PeaversCommons.Utils

local Secret = PCB.Secret
local CooldownManager = PCB.CooldownManager

local Safe = Secret.Safe
local IsSecret = Secret.IsSecret
local ReadBool = Secret.ReadBool
local Present = Secret.Present
local Number = Secret.Number

local CastBar = {}
PCB.CastBar = CastBar
CastBar.__index = CastBar

-- SetTimerDuration interpolation / direction constants.
local INTERPOLATION_IMMEDIATE = 0
local DIRECTION_ELAPSED = 0

local FADE_TIME = 0.35
local INSET = 1

local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

local PREVIEW_TEXT = {
    player = "Preview Cast",
    target = "Target Cast",
    focus = "Focus Cast",
    pet = "Pet Cast",
}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function CastBar.New(unit)
    local self = setmetatable({}, CastBar)
    self.unit = unit

    local frame = CreateFrame("Frame", "PeaversCastBar" .. (unit:gsub("^%l", string.upper)),
        UIParent, "BackdropTemplate")
    frame:SetSize(220, 24)
    frame:SetPoint("CENTER")
    frame:SetBackdrop(BACKDROP)
    frame:SetClampedToScreen(true)
    frame:Hide()
    self.frame = frame

    local icon = frame:CreateTexture(nil, "ARTWORK")
    -- Trim the stock icon border so the art sits flush inside the hairline.
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    self.icon = icon

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    self.bar = bar

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    self.barBg = bg

    -- OVERLAY rather than ARTWORK: the status bar's own fill texture lives on
    -- ARTWORK, and two textures on the same layer have no defined order, so the
    -- latency zone would flicker in and out from behind the fill. Sub-level -1
    -- keeps it under the spell text.
    local latency = bar:CreateTexture(nil, "OVERLAY", nil, -1)
    latency:Hide()
    self.latency = latency

    local spark = bar:CreateTexture(nil, "OVERLAY", nil, 2)
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:Hide()
    self.spark = spark

    local spellText = bar:CreateFontString(nil, "OVERLAY")
    spellText:SetJustifyH("LEFT")
    self.spellText = spellText

    local timeText = bar:CreateFontString(nil, "OVERLAY")
    timeText:SetJustifyH("RIGHT")
    self.timeText = timeText

    -- Empower stage dividers, created lazily and reused.
    self.pips = {}

    frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)

    return self
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function Color(color, fallback)
    if type(color) ~= "table" then return fallback.r, fallback.g, fallback.b end
    return color.r or fallback.r, color.g or fallback.g, color.b or fallback.b
end

-- Resolve the width to use: the matched Cooldown Manager row if that is turned
-- on and actually available, otherwise the unit's own configured width.
function CastBar:ResolveWidth(unitCfg)
    if unitCfg.matchCooldownManager then
        local matched = CooldownManager:GetMatchedWidth(unitCfg.cooldownManagerFrame, self.frame)
        if matched then return matched end
    end
    return unitCfg.width or 220
end

-- Deliberately not PeaversCommons.FrameLock. That helper leaves EnableMouse(true)
-- on a locked frame, which is right for a panel you want to keep clickable but
-- wrong here: a cast bar sits over the middle of the screen, and an always-mouse-
-- enabled one would silently swallow clicks meant for the world beneath it. A
-- cast bar takes the mouse only while it is being positioned.
function CastBar:SetDraggable(unitCfg, draggable)
    local frame = self.frame

    if not draggable then
        frame:SetMovable(false)
        frame:EnableMouse(false)
        frame:RegisterForDrag()
        frame:SetScript("OnDragStart", nil)
        frame:SetScript("OnDragStop", nil)
        return
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()

        -- The relative point is stored alongside the anchor point rather than
        -- assumed equal to it: StopMovingOrSizing is free to leave the frame
        -- anchored by a different corner than it started on, and re-applying the
        -- offsets against the wrong corner is what makes a bar jump on reload.
        local point, _, relativePoint, x, y = f:GetPoint()
        unitCfg.framePoint = point
        unitCfg.frameRelativePoint = relativePoint
        unitCfg.frameX = x
        unitCfg.frameY = y

        if PCB.Config then PCB.Config:Save() end
    end)
end

function CastBar:ApplyPosition(unitCfg, unlocked)
    local frame = self.frame

    local anchored = false
    if unitCfg.anchorToCooldownManager then
        anchored = CooldownManager:AnchorFrame(frame, unitCfg.cooldownManagerFrame,
            unitCfg.anchorSide, unitCfg.anchorGap)
    end

    if not anchored then
        local point = unitCfg.framePoint or "CENTER"
        frame:ClearAllPoints()
        frame:SetPoint(point, UIParent, unitCfg.frameRelativePoint or point,
            unitCfg.frameX or 0, unitCfg.frameY or 0)
    end

    -- A bar pinned to the Cooldown Manager has no free position to drag to, so
    -- it stays put even while the rest are unlocked for positioning.
    self:SetDraggable(unitCfg, unlocked and not anchored)
end

function CastBar:Layout(appearance, unitCfg, unlocked)
    self.appearance = appearance
    self.unitCfg = unitCfg

    local frame = self.frame
    local height = unitCfg.height or 24
    local width = self:ResolveWidth(unitCfg)

    frame:SetSize(width, height)

    local bgR, bgG, bgB = Color(appearance.bgColor, { r = 0, g = 0, b = 0 })
    frame:SetBackdropColor(bgR, bgG, bgB, appearance.bgAlpha or 0.8)
    local brR, brG, brB = Color(appearance.borderColor, { r = 0, g = 0, b = 0 })
    frame:SetBackdropBorderColor(brR, brG, brB, appearance.borderAlpha or 1)

    self:ApplyPosition(unitCfg, unlocked)

    local iconSize = height - (INSET * 2)
    local showIcon = unitCfg.showIcon and iconSize > 0

    if showIcon then
        self.icon:Show()
        self.icon:ClearAllPoints()
        self.icon:SetSize(iconSize, iconSize)
        if unitCfg.iconSide == "RIGHT" then
            self.icon:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -INSET, -INSET)
        else
            self.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, -INSET)
        end
    else
        self.icon:Hide()
    end

    -- The bar fills whatever the icon does not.
    local leftPad = INSET + ((showIcon and unitCfg.iconSide ~= "RIGHT") and (iconSize + 1) or 0)
    local rightPad = INSET + ((showIcon and unitCfg.iconSide == "RIGHT") and (iconSize + 1) or 0)

    self.bar:ClearAllPoints()
    self.bar:SetPoint("TOPLEFT", frame, "TOPLEFT", leftPad, -INSET)
    self.bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -rightPad, INSET)
    self.bar:SetStatusBarTexture(appearance.barTexture or "Interface\\TargetingFrame\\UI-StatusBar")

    -- Derived arithmetically instead of read back with GetWidth. The bar is
    -- sized by its anchors, and an anchor-derived size is not resolved until the
    -- client's next layout pass, so GetWidth can still answer 0 here - which
    -- would silently collapse the latency zone and the empower pips on the very
    -- first cast after a settings change.
    self.barWidth = math.max(0, width - leftPad - rightPad)

    local bbR, bbG, bbB = Color(appearance.barBgColor, { r = 0.12, g = 0.12, b = 0.14 })
    self.barBg:SetColorTexture(bbR, bbG, bbB, appearance.barBgAlpha or 0.6)

    local latR, latG, latB = Color(appearance.latencyColor, { r = 0.9, g = 0.2, b = 0.2 })
    self.latency:SetColorTexture(latR, latG, latB, appearance.latencyAlpha or 0.5)

    self.spark:SetSize(16, height * 1.6)

    -- Parked on the right edge of the status bar's own fill texture, which is
    -- exactly where the cast has reached. The client then moves the spark as it
    -- resizes the fill, so the per-frame update never has to touch it - this is
    -- what takes the spark from three widget calls a frame to none. Re-anchored
    -- on every Layout because SetStatusBarTexture above can hand back a
    -- different texture object.
    local fillTexture = self.bar:GetStatusBarTexture()
    if fillTexture then
        self.spark:ClearAllPoints()
        self.spark:SetPoint("CENTER", fillTexture, "RIGHT", 0, 0)
    end

    -- Recomputed rather than blanked: Layout also runs mid-cast, whenever a
    -- matched Cooldown Manager row resizes.
    self.spark:SetShown(self.mode == "manual" and appearance.showSpark ~= false)

    local fontFace = appearance.fontFace or Utils.GetDefaultFont()
    local fontSize = appearance.fontSize or 11
    local outline = appearance.fontOutline
    if outline == "NONE" then outline = nil end
    Utils.SafeSetFont(self.spellText, fontFace, fontSize, outline)
    Utils.SafeSetFont(self.timeText, fontFace, fontSize, outline)

    local txR, txG, txB = Color(appearance.textColor, { r = 1, g = 1, b = 1 })
    self.spellText:SetTextColor(txR, txG, txB)
    self.timeText:SetTextColor(txR, txG, txB)

    self.timeText:ClearAllPoints()
    self.timeText:SetPoint("RIGHT", self.bar, "RIGHT", -4, 0)

    self.spellText:ClearAllPoints()
    self.spellText:SetPoint("LEFT", self.bar, "LEFT", 4, 0)
    self.spellText:SetPoint("RIGHT", self.timeText, "LEFT", -4, 0)

    self.spellText:SetShown(unitCfg.showSpellName ~= false)
    self.showTime = unitCfg.showCastTime ~= false
    self.timeText:SetShown(self.showTime)

    frame:SetFrameStrata(appearance.frameStrata or "MEDIUM")

    if self.previewing then
        self:ShowPreview()
    end
end

--------------------------------------------------------------------------------
-- Empower stages
--------------------------------------------------------------------------------

function CastBar:ClearPips()
    for _, pip in ipairs(self.pips) do
        pip:Hide()
    end
end

-- Evoker empowered casts hold at each stage boundary, so the boundaries are the
-- only thing on the bar worth reading. Every stage duration is fetched
-- individually because any one of them can come back secret.
function CastBar:LayoutPips(numStages, totalDuration)
    self:ClearPips()

    if not numStages or numStages < 2 or not totalDuration or totalDuration <= 0 then
        return
    end

    local elapsed = 0
    for stage = 1, numStages - 1 do
        -- 0-indexed, exactly as Blizzard's own casting bar queries it.
        local raw = Safe(GetUnitEmpowerStageDuration, self.unit, stage - 1)
        local duration = Number(raw)
        if not duration then return end

        elapsed = elapsed + (duration / 1000)
        local fraction = elapsed / totalDuration
        if fraction <= 0 or fraction >= 1 then return end

        local pip = self.pips[stage]
        if not pip then
            pip = self.bar:CreateTexture(nil, "OVERLAY")
            pip:SetWidth(1)
            self.pips[stage] = pip
        end

        pip:SetColorTexture(0, 0, 0, 0.8)
        pip:ClearAllPoints()
        local offset = (self.barWidth or 0) * fraction
        pip:SetPoint("TOP", self.bar, "TOPLEFT", offset, 0)
        pip:SetPoint("BOTTOM", self.bar, "BOTTOMLEFT", offset, 0)
        pip:Show()
    end
end

--------------------------------------------------------------------------------
-- Latency
--------------------------------------------------------------------------------

-- The trailing slice of a cast that has already been sent to the server: casting
-- again inside it is free, because the next cast is queued rather than clipped.
-- Only meaningful for the player, and only when the cast length is readable.
function CastBar:LayoutLatency(totalDuration)
    self.latency:Hide()

    if self.unit ~= "player" then return end
    if not self.appearance or not self.appearance.showLatency then return end
    if not totalDuration or totalDuration <= 0 then return end
    -- Only meaningful for a cast. A channel is already committed, so there is no
    -- queue window at its end to mark.
    if self.cast and self.cast.channeling then return end

    local _, _, _, world = GetNetStats()
    if not world or world <= 0 then return end

    local fraction = math.min((world / 1000) / totalDuration, 1)
    local width = (self.barWidth or 0) * fraction
    if width < 1 then return end

    self.latency:ClearAllPoints()
    self.latency:SetPoint("TOPRIGHT", self.bar, "TOPRIGHT", 0, 0)
    self.latency:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT", 0, 0)
    self.latency:SetWidth(width)
    self.latency:Show()
end

--------------------------------------------------------------------------------
-- Cast tracking
--------------------------------------------------------------------------------

function CastBar:SetBarColor(key, fallback)
    local color = self.appearance and self.appearance[key]
    local r, g, b = Color(color, fallback)
    self.bar:SetStatusBarColor(r, g, b)
end

-- Read whatever the unit is doing right now, or nil when it is idle.
--
-- Every field can come back secret inside an encounter. Names and textures are
-- only truth-tested, never compared, and notInterruptible goes through ReadBool
-- because a secret boolean cannot legally be tested at all.
local function ReadCast(unit)
    local name, text, texture, startTime, endTime, _, castID, notInterruptible = Safe(UnitCastingInfo, unit)
    if Present(name) then
        return {
            name = text or name,
            texture = texture,
            startTime = startTime,
            endTime = endTime,
            notInterruptible = ReadBool(notInterruptible),
            channeling = false,
            castID = castID,
        }
    end

    local cName, cText, cTexture, cStart, cEnd, _, cNotInterruptible, _, isEmpowered, numStages =
        Safe(UnitChannelInfo, unit)
    if Present(cName) then
        return {
            name = cText or cName,
            texture = cTexture,
            startTime = cStart,
            endTime = cEnd,
            notInterruptible = ReadBool(cNotInterruptible),
            channeling = true,
            empowered = ReadBool(isEmpowered),
            numStages = Number(numStages),
        }
    end

    return nil
end

-- Hand the fill to a DurationObject so the client animates values we are not
-- permitted to inspect ourselves.
function CastBar:StartSecretTimer(cast)
    if not Secret.Caps.timerDuration then return false end

    local duration = Safe(C_DurationUtil.CreateDuration)
    if not duration then return false end

    if not pcall(duration.SetTimeSpan, duration, cast.startTime, cast.endTime) then
        return false
    end

    if not pcall(self.bar.SetTimerDuration, self.bar, duration, INTERPOLATION_IMMEDIATE, DIRECTION_ELAPSED) then
        return false
    end

    self.bar:SetReverseFill(cast.channeling and true or false)
    self.timerActive = true
    return true
end

-- A duration handed to the status bar keeps driving it, so it has to be taken
-- back before SetValue means anything again. Guarded: clearing by passing nil is
-- the documented shape but the addon still loads on builds that predate the API,
-- and failing to clear is no worse than not trying.
function CastBar:ClearSecretTimer()
    if not self.timerActive then return end
    self.timerActive = false
    pcall(self.bar.SetTimerDuration, self.bar, nil)
end

function CastBar:Refresh()
    if not self.enabled or self.previewing then return end

    local cast = ReadCast(self.unit)
    if not cast then
        self:Stop()
        return
    end

    self.cast = cast
    self.castID = cast.castID
    self.fading = nil
    self.failed = nil
    self.frame:SetAlpha(1)

    -- notInterruptible is true / false / nil, where nil means the client would
    -- not say. An unknown falls through to the ordinary cast colour rather than
    -- claiming the cast cannot be kicked.
    if cast.notInterruptible == true then
        self:SetBarColor("uninterruptibleColor", { r = 0.6, g = 0.6, b = 0.6 })
    elseif cast.channeling then
        self:SetBarColor("channelColor", { r = 0.3, g = 0.7, b = 0.9 })
    else
        self:SetBarColor("castColor", { r = 0.35, g = 0.55, b = 0.95 })
    end

    if Present(cast.texture) then
        pcall(self.icon.SetTexture, self.icon, cast.texture)
    else
        self.icon:SetTexture(nil)
    end

    -- FontString:SetText accepts secret strings, so the spell name still shows
    -- even when we are not allowed to read it.
    pcall(self.spellText.SetText, self.spellText, cast.name)

    local startTime = Number(cast.startTime)
    local endTime = Number(cast.endTime)

    if startTime and endTime then
        self:ClearSecretTimer()
        self.mode = "manual"
        -- Channels drain rather than fill, which is the only thing that tells a
        -- channel apart from a cast at a glance. Done by counting the value down
        -- with an ordinary left-anchored fill, the way the default UI does it,
        -- rather than by reversing the fill direction.
        self.bar:SetReverseFill(false)
        self.bar:SetMinMaxValues(0, 1)
        self.startTime = startTime / 1000
        self.endTime = endTime / 1000

        local total = self.endTime - self.startTime
        self:LayoutLatency(total)
        if cast.empowered then
            self:LayoutPips(cast.numStages, total)
        else
            self:ClearPips()
        end

        -- Draw the opening frame here rather than waiting for OnUpdate. The
        -- frame is shown at the bottom of this function, so without this the
        -- bar's first visible frame still carries the previous cast's fill -
        -- which, after a cast that completed, is a full bar flashing for one
        -- frame every time a new cast starts.
        self.lastTenths = nil
        if not self:UpdateProgress(GetTime()) then
            self.bar:SetValue(0)
        end
    elseif self:StartSecretTimer(cast) then
        -- Nothing about the timing is readable, so there is no honest number to
        -- print alongside a bar the client is animating for us. A channel here
        -- grows right-to-left instead of draining: the client only animates a
        -- duration forwards, and reversing the fill is the one direction control
        -- available without inventing an undocumented enum value.
        self.mode = "timer"
        self.timeText:SetText("")
        self.latency:Hide()
        self:ClearPips()
    else
        self:ClearSecretTimer()
        self.mode = "indeterminate"
        self.bar:SetReverseFill(false)
        self.bar:SetMinMaxValues(0, 1)
        self.bar:SetValue(1)
        self.timeText:SetText("")
        self.latency:Hide()
        self:ClearPips()
    end

    self.spark:SetShown(self.mode == "manual" and (self.appearance and self.appearance.showSpark ~= false))
    self.frame:Show()
end

function CastBar:MarkFailed()
    if self.failed then return end
    self.failed = true

    -- The bar is deliberately left at whatever value it reached. Snapping it to
    -- full on the way out turns a cancelled cast into a red bar that appears to
    -- flash, and it also lies about how far the cast actually got.
    self:SetBarColor("failedColor", { r = 0.85, g = 0.25, b = 0.25 })
    self.timeText:SetText("")
end

function CastBar:Stop(failed)
    self.cast = nil
    self.mode = nil
    self.spark:Hide()

    if not self.frame:IsShown() or self.previewing then return end

    -- Unconditional, and before the fade guard: the client does not promise
    -- that INTERRUPTED lands before the plain STOP beside it, so a failure
    -- arriving second still has to be able to colour a bar already on its way
    -- out. MarkFailed is idempotent.
    if failed then self:MarkFailed() end

    -- Cancelling a cast does not produce one event, it produces a burst:
    -- INTERRUPTED, then STOP, sometimes FAILED as well, over a handful of
    -- frames. Restarting the fade on each of them snapped the alpha back to
    -- full every time, which is what read as a red bar pulsing two or three
    -- times before it finally went away. The first stop to arrive owns the
    -- fade; nothing restarts it.
    if self.fading then return end

    self.fading = FADE_TIME
end

function CastBar:Hide()
    self.fading = nil
    self.failed = nil
    self.lastTenths = nil
    self.cast = nil
    self.castID = nil
    self.mode = nil
    self:ClearSecretTimer()
    self.spark:Hide()
    self.latency:Hide()
    self:ClearPips()
    self.frame:Hide()
end

function CastBar:SetEnabled(enabled)
    self.enabled = enabled and true or false
    if not self.enabled and not self.previewing then
        self:Hide()
    end
end

--------------------------------------------------------------------------------
-- Preview
--
-- Bars only exist while something is being cast, which makes them impossible to
-- position. Preview parks a static bar on screen so it can be dragged.
--------------------------------------------------------------------------------

function CastBar:ShowPreview()
    self.previewing = true
    self.mode = nil
    self.cast = nil
    self.castID = nil
    self.fading = nil
    self.failed = nil
    self.lastTenths = nil
    self:ClearSecretTimer()

    self.frame:SetAlpha(1)
    self:SetBarColor("castColor", { r = 0.35, g = 0.55, b = 0.95 })
    self.bar:SetReverseFill(false)
    self.bar:SetMinMaxValues(0, 1)
    self.bar:SetValue(0.65)
    self.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    self.spellText:SetText(PREVIEW_TEXT[self.unit] or "Cast")
    self.timeText:SetText("1.4")
    self.spark:Hide()
    self.latency:Hide()
    self:ClearPips()
    self.frame:Show()
end

function CastBar:HidePreview()
    self.previewing = false
    self:Hide()
    -- A cast already in flight when preview ends should reappear immediately.
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Per-frame update
--------------------------------------------------------------------------------

-- Draw the cast at time `now`. Returns false once it has run past its end.
--
-- Everything the bar shows per frame lives here, and it is deliberately down to
-- a single SetValue in the common case: the spark rides the fill texture (see
-- Layout) and the countdown only touches its FontString when the digit it shows
-- actually changes.
function CastBar:UpdateProgress(now)
    local total = self.endTime - self.startTime
    if total <= 0 then return false end

    local elapsed = now - self.startTime
    if elapsed >= total then return false end

    local progress = elapsed / total
    self.bar:SetValue(self.cast.channeling and (1 - progress) or progress)

    if self.showTime then
        -- The label only ever renders one decimal place, so the string is only
        -- rebuilt when that decimal moves: ten times a second rather than once
        -- per frame. Every SetText makes the FontString re-measure its string
        -- width, and at 144fps better than nine in ten of those measurements
        -- were producing the identical string.
        --
        -- Truncated rather than rounded, so the countdown never claims more time
        -- remains than actually does.
        local tenths = math.floor((self.endTime - now) * 10)
        if tenths ~= self.lastTenths then
            self.lastTenths = tenths
            self.timeText:SetText(string.format("%.1f", tenths / 10))
        end
    end

    return true
end

function CastBar:OnUpdate(elapsed)
    if self.previewing then return end

    if self.fading then
        self.fading = self.fading - elapsed
        if self.fading <= 0 then
            self:Hide()
        else
            self.frame:SetAlpha(self.fading / FADE_TIME)
        end
        return
    end

    if self.mode ~= "manual" or not self.cast then return end

    if not self:UpdateProgress(GetTime()) then
        self:Stop()
    end
end

-- True when this event belongs to some other cast attempt than the one on the
-- bar, and must not be allowed to end it.
--
-- This matters most for UNIT_SPELLCAST_FAILED. It fires for every rejected cast
-- attempt on the unit, not only the one being displayed, so hammering a spell
-- key during a cast produces a stream of failures belonging to presses that
-- never started. Without this check each of those turned the running bar red and
-- stopped it, while the real cast carried on invisibly underneath.
--
-- Unknowns deliberately fall through as "mine": channels carry no cast GUID at
-- all, and a restricted GUID cannot legally be compared. Both cases keep the old
-- behaviour of trusting the event rather than risking a bar that never clears.
function CastBar:IsForeignCast(castGUID)
    local mine = self.castID
    if mine == nil or castGUID == nil then return false end
    if IsSecret(mine) or IsSecret(castGUID) then return false end
    return mine ~= castGUID
end

-- Every spellcast event for the unit funnels through here. Re-reading the unit
-- is cheaper and far less error prone than tracking timings by hand; only the
-- identity of the cast is tracked, and only to reject events from other casts.
function CastBar:OnEvent(event, _, castGUID)
    if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if self:IsForeignCast(castGUID) then return end
        self:Stop(true)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        if self:IsForeignCast(castGUID) then return end
        self:Stop()
    else
        self:Refresh()
    end
end

return CastBar
