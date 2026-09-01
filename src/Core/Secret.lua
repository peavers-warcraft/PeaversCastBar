local addonName, PCB = ...

--------------------------------------------------------------------------------
-- Secret
--
-- Guards for the "secret value" system the client uses from 12.0 onwards.
--
-- Restricted unit data (cast names, textures, timings, interrupt flags) arrives
-- as a *secret*: it may be stored, passed around, and handed to a widget setter,
-- but arithmetic, comparison, or use as a table key is a hard Lua error. Every
-- unit read in this addon goes through one of the helpers below.
--
-- Also holds the one-time capability probes, so the per-frame paths stay free of
-- pcall on builds where the 12.x display APIs exist.
--------------------------------------------------------------------------------

local Secret = {}
PCB.Secret = Secret

-- True when the client handed us a restricted value we may not inspect.
-- issecretvalue only exists from 12.0 onwards.
function Secret.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value) or false
end

local IsSecret = Secret.IsSecret

-- Call an API that may be restricted (or missing on an older build) without
-- letting the error escape into an OnUpdate handler and spam the user.
-- Ten results rather than a packed table: UnitCastingInfo alone returns nine,
-- and this sits on the per-cast path where allocating would show up.
function Secret.Safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h, i, j = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h, i, j end
    return nil
end

-- Booleans are the sharp edge of the secret system. A secret string or number
-- can at least be truth-tested, but a secret *boolean* cannot be tested or
-- compared at all. Everything boolean the client hands us comes back through
-- here as a plain true/false, or nil meaning "not allowed to know".
--
-- Order matters: issecretvalue is safe to call on anything, so it is always
-- asked first, before any comparison against nil.
function Secret.ReadBool(value)
    if IsSecret(value) then return nil end
    if value == nil then return nil end
    return value and true or false
end

-- Truth-test a value that may be secret but is known not to be a boolean (a
-- name, an icon, a spell id). Testing those is permitted; comparing them is
-- not, so this keeps `~= nil` out of the call sites.
function Secret.Present(value)
    if IsSecret(value) then return true end
    return value ~= nil
end

-- A plain number, or nil when the value is secret or absent. Anything that gets
-- used in arithmetic has to pass through here first.
function Secret.Number(value)
    if IsSecret(value) then return nil end
    if type(value) ~= "number" then return nil end
    return value
end

--------------------------------------------------------------------------------
-- Capability probes
--
-- The 12.x display APIs are the only legal way to show restricted data, but the
-- addon still loads on the older interface versions listed in the TOC.
--------------------------------------------------------------------------------

Secret.Caps = {}

do
    local probe = CreateFrame("StatusBar")
    probe:SetMinMaxValues(0, 1)

    -- Cast bars for restricted units can only be driven by a DurationObject the
    -- client animates on our behalf.
    Secret.Caps.timerDuration = (type(probe.SetTimerDuration) == "function")
        and (type(C_DurationUtil) == "table")
        and (type(C_DurationUtil.CreateDuration) == "function")
end

return Secret
