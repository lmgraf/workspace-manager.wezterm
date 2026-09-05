local modules = require("helpers.modules")
local fake_wezterm = require("helpers.fake_wezterm")

local M = {}

function M.new()
  local ctx = {}
  local window, pane = {}, {}

  function ctx:record(kind, ...)
    table.insert(self.calls, { kind = kind, args = table.pack(...) })
  end

  function ctx:recorded(kind)
    local result = {}
    for _, call in ipairs(self.calls) do
      if call.kind == kind then table.insert(result, call.args) end
    end
    return result
  end

  local common = fake_wezterm.new()
  local fake = common.wezterm
  fake.emit = function(name, ...) ctx:record(name, ...) end
  fake.format = function(parts)
    local text = {}
    for _, part in ipairs(parts) do
      if part.Text then table.insert(text, part.Text) end
    end
    local label = table.concat(text):gsub("\27%[[%d;]*m", "")
    ctx.formatted[label] = parts
    return label
  end
  fake.json_parse = function()
    return {
      { workspace = "A", pane_id = 10 },
      { workspace = "A", pane_id = 11 },
      { workspace = "B", pane_id = 20 },
      { workspace = "B", pane_id = 21 },
      { workspace = "C", pane_id = 30 },
    }
  end
  fake.run_child_process = function(args)
    ctx:record("command", args)
    if args[3] == "list" and not ctx.list_ok then
      return false, "", "list failed"
    end
    if
      args[3] == "kill-pane"
      and args[4] == "--pane-id=" .. tostring(ctx.kill_fail_id)
    then
      return false, "", "kill failed"
    end
    return true, "[]", ""
  end
  fake.time = {
    call_after = function(delay, callback)
      if delay ~= 0.1 then error("unexpected timer delay") end
      table.insert(ctx.timers, callback)
    end,
  }

  local mux_window = {
    get_workspace = function() return "B" end,
    window_id = function() return 42 end,
    gui_window = function()
      return { focus = function() ctx:record("focus", "B") end }
    end,
    set_workspace = function(_, name) ctx:record("move_window", name) end,
  }
  fake.mux = {
    get_workspace_names = function() return { "A", "B" } end,
    all_windows = function() return { mux_window } end,
    rename_workspace = function(...) ctx:record("rename", ...) end,
  }

  function window:active_workspace() return ctx.current end
  function window:perform_action(action)
    if type(action) == "function" then return action(self, pane) end
    ctx:record("action", action.kind, action.opts)
    if action.kind == "InputSelector" then
      ctx.selector = action.opts
    elseif action.kind == "PromptInputLine" then
      ctx.prompt = action.opts
    elseif action.kind == "SwitchToWorkspace" then
      ctx.current = action.opts.name
    end
  end

  local function normalize(name)
    return name:gsub("^/home/test", "~"), name:gsub("^~", "/home/test")
  end
  local function workspace_choices()
    local result = {}
    for _, name in ipairs({ "Saved", "B", "A" }) do
      table.insert(result, {
        id = name,
        normalized = name,
        label = name,
        is_workspace = true,
        is_saved = name == "Saved",
      })
    end
    return result
  end

  local deps = {
    helpers = {
      normalize_workspace_name = normalize,
      get_workspace_name_and_path = normalize,
      directory_exists = function() return ctx.directory_exists end,
      create_directory = function(path)
        ctx:record("mkdir", path)
        return ctx.mkdir_ok, "", "mkdir failed"
      end,
      get_wezterm_path = function() return "wezterm" end,
      notify = function(_, _, message) ctx:record("notify", message) end,
    },
    history = {
      record_workspace_switch = function(...) ctx:record("history_switch", ...) end,
      update_access_time = function(...) ctx:record("access", ...) end,
      save = function() ctx:record("save_history") end,
    },
    state = {
      is_excluded_workspace = function(name) return ctx.excluded == name end,
      save_workspace_state = function(name, gui_window)
        ctx:record("save", name, gui_window)
        return ctx.save_ok, ctx.save_ok and nil or "disk full"
      end,
      restore_workspace_state = function(...) ctx:record("restore", ...) end,
      delete_workspace_state = function(...) ctx:record("delete", ...) end,
      rename_workspace_state = function(...) ctx:record("rename_state", ...) end,
      load_workspace_state = function()
        return {
          window_states = ctx.saved_focus and {
            { window_id = 42, is_focused = true },
          } or {},
        }
      end,
    },
    data = {
      get_workspace_cycle_order = function()
        local result = {}
        for _, name in ipairs(ctx.live_workspaces) do
          table.insert(result, { id = name })
        end
        return result
      end,
      get_workspace_choices = workspace_choices,
      get_workspace_choices_alphabetical = function()
        ctx:record("alphabetical")
        return workspace_choices()
      end,
      get_custom_choices = function(known)
        assert(known.A and known.B and known.Saved)
        return {
          {
            id = "Custom",
            name = "Named",
            normalized = "Named",
            label = "Named",
          },
          {
            id = "WithPath",
            name = "Project",
            path = "~/project",
            has_path = true,
            normalized = "Project",
            label = "Project",
          },
          { id = "~/raw", normalized = "~/raw", label = "Raw path" },
        },
          ctx.zoxide,
          { A = "Current label", B = "Other label" }
      end,
      get_current_mux_window = function(name) return "mux:" .. name end,
      get_workspace_counts = function()
        return { B = { windows = 1, tabs = 2, panes = 3 } }
      end,
    },
  }

  ctx.fake = fake
  ctx.window = window
  ctx.pane = pane
  ctx.deps = deps

  function ctx:reset()
    modules.reset()
    self.current, self.selector, self.prompt = "A", nil, nil
    self.timers, self.calls, self.formatted = {}, {}, {}
    self.directory_exists, self.mkdir_ok, self.zoxide = true, true, false
    self.excluded, self.saved_focus = nil, false
    self.save_ok, self.list_ok, self.kill_fail_id = true, true, nil
    self.live_workspaces = { "A", "B" }
    fake.GLOBAL = { workspace_access_times = { A = 1, B = 2, Saved = 3 } }
    self.settings = { session_enabled = true, zoxide_path = "zoxide" }
    package.loaded.wezterm = fake
    package.loaded["workspace_manager.settings"] = self.settings
    package.loaded["workspace_manager.helpers"] = deps.helpers
    package.loaded["workspace_manager.history"] = deps.history
    package.loaded["workspace_manager.state"] = deps.state
    deps.theme = require("workspace_manager.theme")
    deps.data.format_counts = require("workspace_manager.data").format_counts
    package.loaded["workspace_manager.data"] = deps.data
    self.actions = require("workspace_manager.actions")
  end

  function ctx:open() self.actions.workspace_switcher()(window, pane) end

  function ctx:choose(id, pending)
    self:open()
    assert(self.selector, "switcher did not open")
    if pending then
      self.actions.switcher_keymap("x", "CTRL", pending).action(window, pane)
    end
    self.selector.action(window, pane, id, id)
  end

  function ctx:flush_reopen()
    assert(#self.timers == 1, "expected one delayed reopen")
    local callback = table.remove(self.timers, 1)
    self.selector = nil
    callback()
  end

  ctx:reset()
  return ctx
end

return M
