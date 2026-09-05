local modules = require("helpers.modules")
local fake_wezterm = require("helpers.fake_wezterm")

local M = {}

function M.new()
  modules.reset()
  local ctx = {
    events = {},
    current = "A",
    focused = true,
    switch_count = 0,
  }
  local common = fake_wezterm.new()
  local fake = common.wezterm
  fake.GLOBAL = { workspace_access_times = {} }
  fake.on = function(name, callback) ctx.events[name] = callback end
  fake.emit = function() end
  fake.format = function() return "" end
  fake.mux = { get_active_workspace = function() return ctx.current end }
  package.loaded.wezterm = fake

  local settings = { session_enabled = false }
  local deps = {
    theme = {
      fg = function() return {} end,
      get_color = function() return "" end,
      build_heading = function() return {} end,
      format = function() return "" end,
      build_format_items = function(segments)
        local items = {}
        for _, segment in ipairs(segments) do
          table.insert(items, { Text = segment.text })
        end
        return items
      end,
      build_switcher_label = function(_, label) return label end,
    },
    helpers = {
      normalize_workspace_name = function(name) return name, name end,
      get_workspace_name_and_path = function(name) return name, name end,
      directory_exists = function() return true end,
      notify = function() end,
    },
    data = {
      get_workspace_cycle_order = function()
        return { { id = "A" }, { id = "B" }, { id = "C" } }
      end,
      get_workspace_choices = function()
        return {
          { id = "A", normalized = "A", label = "A" },
          { id = "B", normalized = "B", label = "B" },
          { id = "C", normalized = "C", label = "C" },
          {
            id = "Saved",
            normalized = "Saved",
            label = "Saved",
            is_saved = true,
          },
        }
      end,
      get_custom_choices = function()
        return {
          { id = "Custom", name = "Custom", label = "Custom" },
          { id = "~/project", label = "Project" },
        },
          false,
          {}
      end,
      get_current_mux_window = function(name) return { name = name } end,
    },
    state = {
      is_excluded_workspace = function() return false end,
      save_workspace_state = function() end,
      restore_workspace_state = function() end,
      get_most_recent_saved_workspace = function() return "B" end,
      load_workspace_state = function() return { window_states = {} } end,
      wait_for_stable_window = function(_, _, _, _, callback)
        ctx.pending_restore = callback
      end,
    },
  }
  package.loaded["workspace_manager.settings"] = settings
  package.loaded["workspace_manager.theme"] = deps.theme
  package.loaded["workspace_manager.helpers"] = deps.helpers
  package.loaded["workspace_manager.data"] = deps.data
  package.loaded["workspace_manager.state"] = deps.state

  local history = require("workspace_manager.history")
  history.update_access_time = function() end
  local actions = require("workspace_manager.actions")
  local config = require("workspace_manager.config")
  config.apply_to_config({})

  local window = {
    active_workspace = function() return ctx.current end,
    is_focused = function() return ctx.focused end,
  }
  function window:perform_action(action)
    if type(action) ~= "table" then return end
    if action.kind == "SwitchToWorkspace" then
      if ctx.fail_switch then error("switch failed") end
      ctx.current = action.opts.name
      ctx.switch_count = ctx.switch_count + 1
      if ctx.focus_during_switch then
        ctx.events["window-focus-changed"](self)
      end
    elseif action.kind == "InputSelector" then
      ctx.selector = action.opts.action
    elseif action.kind == "PromptInputLine" then
      ctx.prompt = action.opts.action
    end
  end

  ctx.fake = fake
  ctx.actions = actions
  ctx.config = config
  ctx.settings = settings
  ctx.deps = deps
  ctx.window = window
  ctx.pane = {}
  ctx.toggle = actions.last_workspace()
  ctx.next_workspace = actions.next_workspace()
  ctx.previous_workspace = actions.previous_workspace()

  function ctx:reset()
    fake.GLOBAL = { workspace_access_times = {} }
    self.current, self.focused, self.switch_count = "A", true, 0
    self.selector, self.prompt = nil, nil
    self.fail_switch, self.focus_during_switch = false, false
    self.pending_restore = nil
    self.events["window-focus-changed"](window, self.pane)
  end

  function ctx:select_workspace(name)
    actions.workspace_switcher()(window, self.pane)
    assert(self.selector, "switcher did not open")
    self.selector(window, self.pane, name, name)
  end

  ctx:reset()
  return ctx
end

return M
