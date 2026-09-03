-- Run with: wezterm --config-file tests/previous_workspace.lua ls-fonts
-- Uses the real plugin callbacks with simulated GUI and mux events.
local runtime = require("wezterm")
local root = runtime.config_dir .. "/../plugin/"
local events, current, focused = {}, "A", true
local selector, prompt, fail_switch, focus_during_switch
local switch_count, pending_restore = 0, nil
local fake = {
  home_dir = runtime.home_dir,
  GLOBAL = { workspace_access_times = {} },
  action = setmetatable({}, {
    __index = function(_, kind)
      return function(opts) return { kind = kind, opts = opts } end
    end,
  }),
  action_callback = function(callback) return callback end,
  on = function(name, callback) events[name] = callback end,
  emit = function() end,
  format = function() return "" end,
  mux = { get_active_workspace = function() return current end },
}
package.loaded.wezterm = fake
local history = assert(loadfile(root .. "history.lua"))()
-- Recency persistence is unrelated to this test; never write user history.
history.update_access_time = function() end
local actions = assert(loadfile(root .. "actions.lua"))()
local config = assert(loadfile(root .. "config.lua"))()
local settings = { session_enabled = false }
local deps = {
  history = history,
  actions = actions,
  theme = {
    fg = function() return {} end,
    get_color = function() return "" end,
    build_heading = function() return {} end,
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
      }, false, {}
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
      pending_restore = callback
    end,
  },
}
actions.setup(settings, deps)
config.setup(settings, deps)
config.apply_to_config({})

local window = {
  active_workspace = function() return current end,
  is_focused = function() return focused end,
}
function window:perform_action(action)
  if type(action) ~= "table" then return end
  if action.kind == "SwitchToWorkspace" then
    if fail_switch then error("switch failed") end
    current = action.opts.name
    switch_count = switch_count + 1
    if focus_during_switch then events["window-focus-changed"](self) end
  elseif action.kind == "InputSelector" then
    selector = action.opts.action
  elseif action.kind == "PromptInputLine" then
    prompt = action.opts.action
  end
end
local pane = {}
local toggle = actions.switch_to_previous_workspace()
local next_workspace = actions.next_workspace()
local previous_workspace = actions.previous_workspace()
local function check_pair(active, previous)
  assert(current == active, "wrong active workspace: " .. current)
  assert(
    fake.GLOBAL.last_focused_workspace == active,
    "stale tracked workspace"
  )
  assert(fake.GLOBAL.previous_workspace == previous, "wrong previous workspace")
end
local function reset()
  fake.GLOBAL = { workspace_access_times = {} }
  current, focused, switch_count = "A", true, 0
  selector, prompt, fail_switch, focus_during_switch = nil, nil, false, false
  events["window-focus-changed"](window, pane)
  check_pair("A", nil)
end
local function select_workspace(name)
  actions.workspace_switcher()(window, pane)
  assert(selector, "switcher did not open")
  selector(window, pane, name, name)
end

-- First switch, repeated toggles, and switching normally into the old target.
reset()
toggle(window, pane)
assert(switch_count == 0, "first workspace should have no previous target")
next_workspace(window, pane)
check_pair("B", "A")
toggle(window, pane)
check_pair("A", "B")
toggle(window, pane)
check_pair("B", "A")
previous_workspace(window, pane)
check_pair("A", "B")
next_workspace(window, pane)
toggle(window, pane)
check_pair("A", "B")

-- A -> B -> C must return to B without requiring any OS focus events.
reset()
next_workspace(window, pane)
next_workspace(window, pane)
check_pair("C", "B")
toggle(window, pane)
check_pair("B", "C")
events["window-focus-changed"](window, pane)
events["update-status"](window, pane)
check_pair("B", "C")
toggle(window, pane)
check_pair("C", "B")

-- Focus events during and after switching cannot overwrite the pair.
reset()
focus_during_switch = true
next_workspace(window, pane)
toggle(window, pane)
events["window-focus-changed"](window, pane)
check_pair("A", "B")

-- Every switcher route records the source: live, saved, custom, and path.
for _, name in ipairs({ "B", "Saved", "Custom", "~/project" }) do
  reset()
  select_workspace(name)
  check_pair(name, "A")
  toggle(window, pane)
  check_pair("A", name)
end
for _, mode in ipairs({ "new", "new_at_path" }) do
  reset()
  actions.workspace_switcher()(window, pane)
  actions.switcher_keymap("n", "CTRL", mode).action(window, pane)
  selector(window, pane, "B", "B")
  assert(prompt, "new-workspace prompt did not open")
  prompt(window, pane, "Created")
  check_pair("Created", "A")
  toggle(window, pane)
  check_pair("A", "Created")
end

-- Cancelling and reselecting the current workspace keep the existing target.
reset()
next_workspace(window, pane)
actions.workspace_switcher()(window, pane)
selector(window, pane, nil, nil)
check_pair("B", "A")
settings.show_current_workspace_in_switcher = true
select_workspace("B")
check_pair("B", "A")
settings.show_current_workspace_in_switcher = nil

-- A rejected switch must not replace the old target with the current workspace.
fail_switch = true
assert(not pcall(toggle, window, pane), "switch should have failed")
check_pair("B", "A")
fail_switch = false

-- External switches are observed on status updates, even without focus changes.
reset()
current, focused = "B", false
events["window-focus-changed"](window, pane)
events["update-status"](window, pane)
assert(
  fake.GLOBAL.previous_workspace == nil,
  "unfocused observer wrote history"
)
assert(fake.GLOBAL.last_focused_workspace == "A")
focused = true
events["update-status"](window, pane)
check_pair("B", "A")
for _ = 1, 3 do events["update-status"](window, pane) end
check_pair("B", "A")
current = "C"
-- A GUI notification can still refer to the old mux window during a switch.
events["window-focus-changed"]({
  is_focused = function() return true end,
  active_workspace = function() return "A" end,
}, pane)
check_pair("C", "B")
toggle(window, pane)
check_pair("B", "C")

-- Startup restore completion must not rewind history after the user switches.
reset()
settings.session_enabled = true
settings.session_restore_on_startup = true
package.loaded["session.pane_tree"] = {}
fake.mux.spawn_window = function(opts)
  current = opts.workspace
  return {}, pane, {}
end
config.apply_to_config({})
events["gui-startup"]()
check_pair("B", nil)
next_workspace(window, pane)
check_pair("C", "B")
assert(pending_restore, "startup restore was not deferred")
pending_restore()
check_pair("C", "B")

package.loaded.wezterm = runtime
io.stdout:write(
  "PASS: previous-workspace tracking across all plugin switch routes, "
    .. "focus/status events, and startup restoration\n"
)
io.stdout:flush()
return {}
