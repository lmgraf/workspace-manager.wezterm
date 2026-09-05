local wezterm = require("wezterm") --[[@as Wezterm]]
local helpers = require("workspace_manager.helpers")

local M = {}

---@alias WorkspaceManagerHistory table<string, integer>

M.HISTORY_DIR = wezterm.home_dir .. "/.local/share/wezterm"
M.HISTORY_FILE = M.HISTORY_DIR .. "/workspace_history.json"

local function ensure_dir()
  -- See state.lua: os.execute() flashes a console window on Windows.
  helpers.create_directory(M.HISTORY_DIR)
end

---Loads workspace access timestamps from disk.
---@return WorkspaceManagerHistory
function M.load()
  local file = io.open(M.HISTORY_FILE, "r")
  if file then
    local content = file:read("*all")
    file:close()
    local success, data = pcall(wezterm.json_parse, content)
    if success then return data end
  end
  return {}
end

---Writes workspace access timestamps to disk.
---@param history WorkspaceManagerHistory
function M.save(history)
  ensure_dir()
  local file = io.open(M.HISTORY_FILE, "w")
  if file then
    file:write(wezterm.json_encode(history))
    file:close()
  end
end

---Tracks raw workspace ids because display normalization can change identity.
---@param old_workspace? string
---@param new_workspace? string
function M.record_workspace_switch(old_workspace, new_workspace)
  if not new_workspace then return end
  if old_workspace and old_workspace ~= new_workspace then
    wezterm.GLOBAL.previous_workspace = old_workspace
  end
  wezterm.GLOBAL.last_focused_workspace = new_workspace
end

---Records the current time as a workspace's most recent access.
---@param workspace_name string
function M.update_access_time(workspace_name)
  local normalized = helpers.normalize_workspace_name(workspace_name)
  wezterm.GLOBAL.workspace_access_times = wezterm.GLOBAL.workspace_access_times
    or {}
  wezterm.GLOBAL.workspace_access_times[normalized] = os.time()
  M.save(wezterm.GLOBAL.workspace_access_times)
end

-- Initialize on first load
wezterm.GLOBAL.workspace_access_times = wezterm.GLOBAL.workspace_access_times
  or M.load()

return M
