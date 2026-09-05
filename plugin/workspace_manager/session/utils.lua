local wezterm = require("wezterm") --[[@as Wezterm]]

local M = {}

M.is_windows = wezterm.target_triple == "x86_64-pc-windows-msvc"
M.is_mac = (
  wezterm.target_triple == "x86_64-apple-darwin"
  or wezterm.target_triple == "aarch64-apple-darwin"
)
M.separator = M.is_windows and "\\" or "/"

---Removes terminal formatting escape sequences from a string.
---@param str string
---@return string
function M.strip_format_esc_seq(str)
  local clean_str, _ = str:gsub(string.char(27) .. "%[[^m]*m", "")
  return clean_str
end

---Returns the focused window width, or a conservative fallback.
---@return number
function M.get_current_window_width()
  local windows = wezterm.gui.gui_windows()
  for _, window in ipairs(windows) do
    if window:is_focused() then return window:active_tab():get_size().cols end
  end
  return 80
end

---Replaces the center of a string with another string.
---@param str string string to be modified
---@param len number length to be removed from the middle of str
---@param pad string string that must be inserted in place of the missing part of str
function M.replace_center(str, len, pad)
  local mid = #str // 2
  local start = mid - (len // 2)
  return str:sub(1, start) .. pad .. str:sub(start + len + 1)
end

---Returns the number of UTF-8 code points in a string.
---@param str string
---@return number
function M.utf8len(str)
  local _, len = str:gsub("[%z\1-\127\194-\244][\128-\191]*", "")
  return len
end

---Executes a command and returns its standard output.
---@param cmd string command
---@return boolean success result
---@return string|nil error
function M.execute(cmd)
  local stdout
  local suc, err = pcall(function()
    local handle = io.popen(cmd)
    if not handle then error("Could not open process: " .. cmd) end
    stdout = handle:read("*a")
    if stdout == nil then error("Error running process: " .. cmd) end
    handle:close()
  end)
  if suc then
    return suc, stdout
  else
    return suc, err
  end
end

---Creates a directory if it does not exist.
---@param path string
function M.ensure_folder_exists(path)
  -- os.execute() flashes a console window on Windows; run_child_process() does not.
  if M.is_windows then
    wezterm.run_child_process({ "cmd", "/c", "mkdir", (path:gsub("/", "\\")) })
  else
    wezterm.run_child_process({ "mkdir", "-p", path })
  end
end

---Creates a recursive copy while preserving the input value's type.
---@generic T
---@param original T
---@return T copy
function M.deepcopy(original)
  local copy
  if type(original) == "table" then
    copy = {}
    for k, v in pairs(original) do
      copy[k] = M.deepcopy(v)
    end
  else
    copy = original
  end
  return copy
end

---@alias WorkspaceManagerMergeBehavior
---| 'error' # Raises an error if a key exists in multiple tables
---| 'keep'  # Uses the value from the leftmost table (first occurrence)
---| 'force' # Uses the value from the rightmost table (last occurrence)
---
---Recursively merges tables according to the selected conflict behavior.
---@generic T: table
---@param behavior WorkspaceManagerMergeBehavior
---@param ... T
---@return T
function M.tbl_deep_extend(behavior, ...)
  local tables = { ... }
  if #tables == 0 then return {} end

  local result = {}
  for k, v in pairs(tables[1]) do
    if type(v) == "table" then
      result[k] = M.deepcopy(v)
    else
      result[k] = v
    end
  end

  for i = 2, #tables do
    for k, v in pairs(tables[i]) do
      if type(result[k]) == "table" and type(v) == "table" then
        -- For nested tables, we recurse with the same behavior
        result[k] = M.tbl_deep_extend(behavior, result[k], v)
      elseif result[k] ~= nil then
        -- Key exists in the result already
        if behavior == "error" then
          error("Key '" .. tostring(k) .. "' exists in multiple tables")
        elseif behavior == "force" then
          -- "force" uses value from rightmost table
          if type(v) == "table" then
            result[k] = M.deepcopy(v)
          else
            result[k] = v
          end
        end
      -- "keep" keeps the leftmost value, which is already in result
      else
        -- Key doesn't exist in result yet, add it
        if type(v) == "table" then
          result[k] = M.deepcopy(v)
        else
          result[k] = v
        end
      end
    end
  end

  return result
end

return M
