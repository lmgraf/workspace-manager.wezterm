local wezterm = require("wezterm") --[[@as Wezterm]]

-- A direct development load can specify its module directory so an installed
-- clone cannot take precedence over the checkout being edited.
---@class WorkspaceManagerLoadOptions
---@field plugin_dir? string Module directory for a directly loaded checkout.

---@type WorkspaceManagerLoadOptions?
local load_options = ...
local plugin_dir = type(load_options) == "table" and load_options.plugin_dir
if not plugin_dir then
  for _, plugin in ipairs(wezterm.plugin.list()) do
    if plugin.url:find("workspace%-manager") then
      plugin_dir = plugin.plugin_dir .. "/plugin"
      break
    end
  end
end
if plugin_dir then package.path = plugin_dir .. "/?.lua;" .. package.path end

---@type WorkspaceManager
local M = require("workspace_manager.settings")
local actions = require("workspace_manager.actions")
local config_mod = require("workspace_manager.config")
local data = require("workspace_manager.data")

-- Public API
M.workspace_switcher = actions.workspace_switcher
M.switch_to_previous_workspace = actions.switch_to_previous_workspace
M.next_workspace = actions.next_workspace
M.previous_workspace = actions.previous_workspace
M.unload_current_workspace = actions.unload_current_workspace
M.save_workspace = actions.save_workspace
M.apply_to_config = config_mod.apply_to_config
M.get_switcher_legend = config_mod.get_switcher_legend
M.get_zoxide_paths = function(limit) return data.get_zoxide_paths(limit) end

return M
