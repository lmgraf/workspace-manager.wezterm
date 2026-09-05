local wezterm = require("wezterm") --[[@as Wezterm]]

local M = {}

---@alias WorkspaceManagerStateEventType "workspace"|"window"|"tab"

---Writes a string to a file.
---@param file_path string full filename
---@param str string file contents
---@return boolean success result
---@return string|nil error
function M.write_file(file_path, str)
  local handle
  local suc, err = pcall(function()
    handle = io.open(file_path, "w+")
    if not handle then error("Could not open file: " .. file_path) end
    local wrote, write_err = handle:write(str)
    if not wrote then error("Could not write file: " .. tostring(write_err)) end
    local flushed, flush_err = handle:flush()
    if not flushed then
      error("Could not flush file: " .. tostring(flush_err))
    end
    local closed, close_err = handle:close()
    handle = nil
    if not closed then
      error("Could not close file: " .. tostring(close_err))
    end
  end)
  if handle then pcall(function() handle:close() end) end
  return suc, err
end

---Reads and returns a file's contents.
---@param file_path string full filename
---@return boolean success result
---@return string|nil error
function M.read_file(file_path)
  local stdout
  local suc, err = pcall(function()
    local handle = io.open(file_path, "r")
    if not handle then error("Could not open file: " .. file_path) end
    stdout = handle:read("*a")
    handle:close()
  end)
  if suc then
    return suc, stdout
  else
    return suc, err
  end
end

---Escapes control characters so the input can be encoded as JSON.
---@param data string
---@return string
local function sanitize_json(data)
  -- escapes control characters to ensure valid json
  data = data:gsub(
    "[\x00-\x1F]",
    function(c) return string.format("\\u00%02X", string.byte(c)) end
  )
  return data
end

---Serializes and writes a saved session state.
---@param file_path string
---@param state table
---@param event_type WorkspaceManagerStateEventType
---@return boolean success result
---@return string|nil error
function M.write_state(file_path, state, event_type)
  local json_state = wezterm.json_encode(state)
  json_state = sanitize_json(json_state)
  local ok, err = M.write_file(file_path, json_state)
  if not ok then
    wezterm.log_error("Failed to write state: " .. tostring(err))
  end
  return ok, err
end

---Loads and decodes a JSON file.
---@param file_path string
---@return table|nil
function M.load_json(file_path)
  local lines = {}
  local ok, err = pcall(function()
    for line in io.lines(file_path) do
      table.insert(lines, line)
    end
  end)
  if not ok then
    wezterm.log_error("Failed to read state file: " .. tostring(err))
    return nil
  end
  local json = table.concat(lines)
  if not json or json == "" then return nil end
  json = sanitize_json(json)
  local parsed, parse_err = pcall(
    function() return wezterm.json_parse(json) end
  )
  if not parsed then
    wezterm.log_error("Failed to parse state JSON: " .. tostring(parse_err))
    return nil
  end
  return wezterm.json_parse(json)
end

return M
