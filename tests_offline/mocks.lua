-- Mocks mínimos ------------------------------------------------------------
local warn = function() end
local task = { spawn = function(f, ...) f(...) end, wait = function() end }

local function encode(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        local v = t[k]
        local s = type(v) == "string" and ('"' .. v .. '"') or tostring(v)
        table.insert(parts, '"' .. k .. '":' .. s)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function decode(s)
    if type(s) ~= "string" or not s:match("^%s*{.*}%s*$") then error("bad json") end
    local out = {}
    for k, v in s:gmatch('"([%w_]+)"%s*:%s*([^,}]+)') do
        v = v:gsub("^%s+", ""):gsub("%s+$", "")
        if v == "true" then out[k] = true
        elseif v == "false" then out[k] = false
        elseif v:match('^".*"$') then out[k] = v:sub(2, -2)
        elseif tonumber(v) then out[k] = tonumber(v)
        else error("bad json value") end
    end
    return out
end
local game = { GetService = function(_, name)
    if name == "HttpService" then return { JSONEncode = function(_, t) return encode(t) end, JSONDecode = function(_, s) return decode(s) end } end
    return {}
end }
local typeof = type


return { game = game, task = task, warn = warn, typeof = typeof }
