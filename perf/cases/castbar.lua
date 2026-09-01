--------------------------------------------------------------------------------
-- Ultra Performance case: the cast bar's per-frame cost.
--
-- Loads the real src/UI/CastBar.lua and drives its own OnUpdate through a full
-- cast, counting every call it makes to the client. A cast bar is the worst
-- case for this addon: it is the only thing here that runs every frame.
--------------------------------------------------------------------------------

local Stubs = dofile(HARNESS_LIB .. "/wow-stubs.lua").Install()

--------------------------------------------------------------------------------
-- Addon-side scaffolding the file expects at load time
--------------------------------------------------------------------------------

_G.PeaversCommons = {
    Utils = {
        GetDefaultFont = function() return "Fonts\\FRIZQT__.TTF" end,
        SafeSetFont = function() end,
    },
}

local PCB = {
    Secret = {
        IsSecret = function() return false end,
        Safe = function(fn, ...) if type(fn) ~= "function" then return nil end return fn(...) end,
        ReadBool = function(v) if v == nil then return nil end return v and true or false end,
        Present = function(v) return v ~= nil end,
        Number = function(v) if type(v) ~= "number" then return nil end return v end,
        Caps = { timerDuration = false },
    },
    CooldownManager = {
        GetMatchedWidth = function() return nil end,
        AnchorFrame = function() return false end,
    },
    Config = { Save = function() end },
}

local CastBar = assert(loadfile(ADDON_DIR .. "/src/UI/CastBar.lua"))("PeaversCastBar", PCB)

local APPEARANCE = {
    barTexture = "Interface\\TargetingFrame\\UI-StatusBar",
    bgColor = { r = 0, g = 0, b = 0 }, bgAlpha = 0.8,
    castColor = { r = 0.35, g = 0.55, b = 0.95 },
    channelColor = { r = 0.30, g = 0.70, b = 0.90 },
    failedColor = { r = 0.85, g = 0.25, b = 0.25 },
    showSpark = true, showLatency = true, fontSize = 11,
}

local UNIT_CFG = {
    enabled = true, width = 220, height = 24,
    showIcon = true, iconSide = "LEFT",
    showSpellName = true, showCastTime = true,
    framePoint = "CENTER", frameRelativePoint = "CENTER", frameX = 0, frameY = -180,
}

--------------------------------------------------------------------------------
-- Scenario driving
--------------------------------------------------------------------------------

local cast, channel

_G.UnitCastingInfo = function()
    if not cast then return nil end
    return cast.name, cast.name, "icon", cast.startMs, cast.endMs, false, cast.guid, false, 100
end
_G.UnitChannelInfo = function()
    if not channel then return nil end
    return channel.name, channel.name, "icon", channel.startMs, channel.endMs,
        false, false, 100, false, nil
end

local function NewBar()
    local bar = CastBar.New("player")
    bar:SetEnabled(true)
    bar:Layout(APPEARANCE, UNIT_CFG, false)
    return bar
end

-- Drive one cast from start to finish and report the average per-frame cost.
local function MeasureCast(label, seconds, fps, isChannel)
    local bar = NewBar()
    Stubs.time = 1000

    local payload = {
        name = "Measured Spell",
        guid = "perf-cast",
        startMs = Stubs.time * 1000,
        endMs = (Stubs.time + seconds) * 1000,
    }

    if isChannel then
        channel, cast = payload, nil
        bar:OnEvent("UNIT_SPELLCAST_CHANNEL_START", "player", payload.guid)
    else
        cast, channel = payload, nil
        bar:OnEvent("UNIT_SPELLCAST_START", "player", payload.guid)
    end

    -- Stop just short of the end so the whole run is the steady state rather
    -- than the fade-out, which is a different and much shorter code path.
    local frames = math.floor(seconds * fps) - 2
    local perFrame = Stubs.Drive(function(dt) bar:OnUpdate(dt) end, frames, 1 / fps)

    cast, channel = nil, nil
    return {
        name = label,
        callsPerFrame = perFrame,
        notes = string.format("%d frames driven", frames),
    }
end

-- Nothing casting: the bars are hidden, and WoW does not tick a hidden frame.
-- Measured rather than asserted, because "we hide it" and "it costs nothing"
-- are different claims.
local function MeasureIdle(fps)
    local bar = NewBar()
    Stubs.ResetCounts()
    local ticked = 0
    for _ = 1, fps do
        Stubs.time = Stubs.time + 1 / fps
        if bar.frame:IsShown() then
            bar:OnUpdate(1 / fps)
            ticked = ticked + 1
        end
    end
    return {
        name = "idle, nothing casting",
        callsPerFrame = 0,
        idleCallsPerSecond = Stubs.TotalCalls(),
        notes = ticked == 0 and "frame hidden, never ticked" or (ticked .. " frames ticked"),
    }
end

return {
    MeasureCast("player cast, 2.5s at 144fps", 2.5, 144, false),
    MeasureCast("player cast, 2.5s at 60fps", 2.5, 60, false),
    MeasureCast("channel, 3s at 144fps", 3.0, 144, true),
    MeasureIdle(144),
}
