local wezterm = require("wezterm") --[[@as Wezterm]]
local mux = wezterm.mux
local settings = require("workspace_manager.settings")

local mod = {}

-- Platform constants
mod.is_windows = wezterm.target_triple:find("windows") ~= nil
mod.path_sep = mod.is_windows and "\\" or "/"

---Shows a toast when plugin notifications are enabled.
---@param window GuiWindow
---@param title string
---@param message string
---@param timeout? integer
function mod.notify(window, title, message, timeout)
  if not settings.notifications_enabled then return end
  pcall(
    function() window:toast_notification(title, message, nil, timeout or 2000) end
  )
end

---Returns the configured or detected WezTerm executable path.
---@return string?
function mod.get_wezterm_path()
  if settings.wezterm_path then
    return settings.wezterm_path -- User override
  end

  local exe_dir = wezterm.executable_dir
  if not exe_dir then return nil end

  local exe_name = mod.is_windows and "wezterm.exe" or "wezterm"
  return exe_dir .. "/" .. exe_name
end

-- ============================================================================
-- Path Normalization
-- ============================================================================

---Normalizes a workspace name for display and expands it for filesystem use.
---@param name string
---@return string normalized
---@return string expanded
function mod.normalize_workspace_name(name)
  if not name then return name end
  -- If starts with ~, expand to full path for cwd operations
  local expanded = string.gsub(name, "^~", wezterm.home_dir)
  -- For display/storage, always use ~ prefix for home paths
  local normalized = string.gsub(expanded, "^" .. wezterm.home_dir, "~")
  return normalized, expanded
end

---Derives the workspace name and expanded path for a raw path.
---@param raw_path string
---@return string workspace_name
---@return string expanded_path
function mod.get_workspace_name_and_path(raw_path)
  local normalized, expanded = mod.normalize_workspace_name(raw_path)

  if not settings.use_basename_for_workspace_names then
    return normalized, expanded
  end

  -- Extract basename
  local basename = string.match(normalized, "([^/]+)$")

  -- Fallback if extraction fails
  if not basename or basename == "" then return normalized, expanded end

  -- Check for duplicate basenames
  for _, ws in ipairs(mux.get_workspace_names()) do
    local ws_normalized = mod.normalize_workspace_name(ws)
    if ws == basename and ws_normalized ~= normalized then
      -- Conflict: fall back to full path
      return normalized, expanded
    end
  end

  return basename, expanded
end

-- ============================================================================
-- Platform Filesystem Helpers
-- ============================================================================

---Returns whether a directory exists.
---@param path string
---@return boolean
function mod.directory_exists(path)
  if mod.is_windows then
    local success = wezterm.run_child_process({
      "cmd",
      "/c",
      'if exist "' .. path .. '\\" (exit 0) else (exit 1)',
    })
    return success
  else
    local success = wezterm.run_child_process({ "test", "-d", path })
    return success
  end
end

---Creates a directory and returns the child-process result.
---@param path string
---@return boolean success
---@return string stdout
---@return string stderr
function mod.create_directory(path)
  if mod.is_windows then
    return wezterm.run_child_process({ "cmd", "/c", "mkdir", path })
  else
    return wezterm.run_child_process({ "mkdir", "-p", path })
  end
end

return mod
