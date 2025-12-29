-- Minimal JSON parser
-- Based on rxi's json.lua (MIT)

local json = { _version = "0.1.0" }

local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if string.sub(str, i, i) == "\n" then
      line_count = line_count + 1
      col_count = 1
    end
  end
  error( string.format("%s at line %d col %d", msg, line_count, col_count) )
end

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do
    res[ select(i, ...) ] = true
  end
  return res
end

local space_chars   = create_set(" ", "\t", "\r", "\n")
local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals      = create_set("true", "false", "null")

local literal_map = {
  [ "true"  ] = true,
  [ "false" ] = false,
  [ "null"  ] = nil
}


local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[string.sub(str, i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end


local function decode_scanArray(str, idx)
  local res = {}
  local val
  local i = idx + 1
  while 1 do
    i = next_char(str, i, space_chars, true)
    -- Empty array?
    if string.sub(str, i, i) == "]" then return res, i + 1 end
    val, i = json.decode_scan(str, i)
    table.insert(res, val)
    i = next_char(str, i, space_chars, true)
    local ch = string.sub(str, i, i)
    if ch == "]" then return res, i + 1 end
    if ch ~= "," then decode_error(str, i, "Expected ']' or ','") end
    i = i + 1
  end
end


local function decode_scanObject(str, idx)
  local res = {}
  local key, val
  local i = idx + 1
  while 1 do
    i = next_char(str, i, space_chars, true)
    if string.sub(str, i, i) == "}" then return res, i + 1 end
    key, i = json.decode_scan(str, i)
    if type(key) ~= "string" then decode_error(str, i, "Expected string key") end
    i = next_char(str, i, space_chars, true)
    if string.sub(str, i, i) ~= ":" then decode_error(str, i, "Expected ':'") end
    i = i + 1
    val, i = json.decode_scan(str, i)
    res[key] = val
    i = next_char(str, i, space_chars, true)
    local ch = string.sub(str, i, i)
    if ch == "}" then return res, i + 1 end
    if ch ~= "," then decode_error(str, i, "Expected '}' or ','") end
    i = i + 1
  end
end


local function decode_scanString(str, idx)
  local res = ""
  local i = idx + 1
  while 1 do
    local start = i
    -- Find next quote or escape
    local nc = string.find(str, '[\\"]', i)
    if not nc then decode_error(str, i, "Unterminated string") end
    res = res .. string.sub(str, i, nc - 1)
    if string.sub(str, nc, nc) == '"' then
      return res, nc + 1
    end
    -- Handle Escape
    local esc = string.sub(str, nc + 1, nc + 1)
    if esc == "u" then
       -- Unicode not fully supported in this minimal version, fallback
       res = res .. "?"
       i = nc + 6
    else
       local map = { b="\b", f="\f", n="\n", r="\r", t="\t" }
       res = res .. (map[esc] or esc)
       i = nc + 2
    end
  end
end


local function decode_scanNumber(str, idx)
  local end_idx = next_char(str, idx, delim_chars, false)
  local num_str = string.sub(str, idx, end_idx - 1)
  local val = tonumber(num_str)
  if not val then decode_error(str, idx, "Invalid number") end
  return val, end_idx
end


function json.decode_scan(str, idx)
  local i = next_char(str, idx, space_chars, true)
  local ch = string.sub(str, i, i)
  if ch == "{" then return decode_scanObject(str, i) end
  if ch == "[" then return decode_scanArray(str, i) end
  if ch == '"' then return decode_scanString(str, i) end
  if string.find("0123456789-.", ch, 1, true) then return decode_scanNumber(str, i) end
  if literal_map[ch] ~= nil then 
     -- crude check
     local end_idx = next_char(str, i, delim_chars, false)
     local word = string.sub(str, i, end_idx - 1)
     if literal_map[word] ~= nil then return literal_map[word], end_idx end
  end
  decode_error(str, i, "Unexpected character")
end

function json.decode(str)
  if type(str) ~= "string" then error("Expected string") end
  local res, idx = json.decode_scan(str, 1)
  return res
end

return json
