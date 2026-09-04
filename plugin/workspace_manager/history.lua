local wezterm = require("wezterm")
local helpers = require("workspace_manager.helpers")

local mod = {}

mod.HISTORY_DIR = wezterm.home_dir .. "/.local/share/wezterm"
mod.HISTORY_FILE = mod.HISTORY_DIR .. "/workspace_history.json"

local function ensure_dir()
  -- See state.lua: os.execute() flashes a console window on Windows.
  helpers.create_directory(mod.HISTORY_DIR)
end

function mod.load()
  local file = io.open(mod.HISTORY_FILE, "r")
  if file then
    local content = file:read("*all")
    file:close()
    local success, data = pcall(wezterm.json_parse, content)
    if success then return data end
  end
  return {}
end

function mod.save(history)
  ensure_dir()
  local file = io.open(mod.HISTORY_FILE, "w")
  if file then
    file:write(wezterm.json_encode(history))
    file:close()
  end
end

-- Track raw workspace ids; display normalization can change their identity.
function mod.record_workspace_switch(old_workspace, new_workspace)
  if not new_workspace then return end
  if old_workspace and old_workspace ~= new_workspace then
    wezterm.GLOBAL.previous_workspace = old_workspace
  end
  wezterm.GLOBAL.last_focused_workspace = new_workspace
end

function mod.update_access_time(workspace_name)
  local normalized = helpers.normalize_workspace_name(workspace_name)
  wezterm.GLOBAL.workspace_access_times = wezterm.GLOBAL.workspace_access_times
    or {}
  wezterm.GLOBAL.workspace_access_times[normalized] = os.time()
  mod.save(wezterm.GLOBAL.workspace_access_times)
end

-- Initialize on first load
wezterm.GLOBAL.workspace_access_times = wezterm.GLOBAL.workspace_access_times
  or mod.load()

return mod
