-- Run with: wezterm --config-file tests/workspace_switcher.lua ls-fonts
-- Exercise public actions with a simulated GUI; never modify user workspaces.
local runtime = require("wezterm")
local root = runtime.config_dir .. "/../plugin/"
local current, selector, prompt, timers, calls, settings, actions
local formatted
local directory_exists, mkdir_ok, zoxide, excluded, saved_focus
local window, pane = {}, {}
local function record(kind, ...)
  table.insert(calls, { kind = kind, args = table.pack(...) })
end
local function recorded(kind)
  local result = {}
  for _, call in ipairs(calls) do
    if call.kind == kind then table.insert(result, call.args) end
  end
  return result
end
local function format(parts)
  local text = {}
  for _, part in ipairs(parts) do
    if part.Text then table.insert(text, part.Text) end
  end
  local label = table.concat(text):gsub("\27%[[%d;]*m", "")
  formatted[label] = parts
  return label
end
local fake = {
  home_dir = "/home/test",
  GLOBAL = {},
  action = setmetatable({}, {
    __index = function(_, kind)
      return function(opts) return { kind = kind, opts = opts } end
    end,
  }),
  action_callback = function(callback) return callback end,
  emit = function(name, ...) record(name, ...) end,
  format = format,
  column_width = runtime.column_width,
  log_info = function() end,
  log_warn = function() end,
  json_parse = function() return { { workspace = "B", pane_id = 20 } } end,
  run_child_process = function(args)
    record("command", args)
    return true, "[]", ""
  end,
  time = {
    call_after = function(delay, callback)
      assert(delay == 0.1)
      table.insert(timers, callback)
    end,
  },
}
local mux_window = {
  get_workspace = function() return "B" end,
  window_id = function() return 42 end,
  gui_window = function()
    return { focus = function() record("focus", "B") end }
  end,
  set_workspace = function(_, name) record("move_window", name) end,
}
fake.mux = {
  get_workspace_names = function() return { "A", "B" } end,
  all_windows = function() return { mux_window } end,
  rename_workspace = function(...) record("rename", ...) end,
}
function window:active_workspace() return current end
function window:perform_action(action)
  if type(action) == "function" then return action(self, pane) end
  record("action", action.kind, action.opts)
  if action.kind == "InputSelector" then
    selector = action.opts
  elseif action.kind == "PromptInputLine" then
    prompt = action.opts
  elseif action.kind == "SwitchToWorkspace" then
    current = action.opts.name
  end
end
local function normalize(name)
  return name:gsub("^/home/test", "~"), name:gsub("^~", "/home/test")
end
local function workspace_choices()
  local result = {}
  -- Deliberately place saved and other live entries before the current one.
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
    directory_exists = function() return directory_exists end,
    create_directory = function(path)
      record("mkdir", path)
      return mkdir_ok, "", "mkdir failed"
    end,
    get_wezterm_path = function() return "wezterm" end,
    notify = function(_, _, message) record("notify", message) end,
  },
  history = {
    record_workspace_switch = function(...) record("history_switch", ...) end,
    update_access_time = function(...) record("access", ...) end,
    save = function() record("save_history") end,
  },
  state = {
    is_excluded_workspace = function(name) return excluded == name end,
    save_workspace_state = function(name) record("save", name) end,
    restore_workspace_state = function(...) record("restore", ...) end,
    delete_workspace_state = function(...) record("delete", ...) end,
    rename_workspace_state = function(...) record("rename_state", ...) end,
    load_workspace_state = function()
      return {
        window_states = saved_focus and {
          { window_id = 42, is_focused = true },
        } or {},
      }
    end,
  },
  data = {
    get_workspace_choices = workspace_choices,
    get_workspace_choices_alphabetical = function()
      record("alphabetical")
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
      }, zoxide, { A = "Current label", B = "Other label" }
    end,
    get_current_mux_window = function(name) return "mux:" .. name end,
    get_workspace_counts = function()
      return { B = { windows = 1, tabs = 2, panes = 3 } }
    end,
  },
}
local function reset()
  current, selector, prompt = "A", nil, nil
  timers, calls, formatted = {}, {}, {}
  directory_exists, mkdir_ok, zoxide = true, true, false
  excluded, saved_focus = nil, false
  fake.GLOBAL = { workspace_access_times = { A = 1, B = 2, Saved = 3 } }
  settings = { session_enabled = true, zoxide_path = "zoxide" }
  package.loaded.wezterm = fake
  deps.theme = assert(loadfile(root .. "theme.lua"))()
  deps.theme.setup(settings)
  deps.data.format_counts = assert(loadfile(root .. "data.lua"))().format_counts
  actions = assert(loadfile(root .. "actions.lua"))()
  actions.setup(settings, deps)
end
local function open()
  actions.workspace_switcher()(window, pane)
end
local function choose(id, pending)
  open()
  assert(selector, "switcher did not open")
  if pending then
    actions.switcher_keymap("x", "CTRL", pending).action(window, pane)
  end
  selector.action(window, pane, id, id)
end
local function flush_reopen()
  assert(#timers == 1, "expected one delayed reopen")
  local callback = table.remove(timers, 1)
  selector = nil
  callback()
  assert(selector and selector.title == "Workspace Switcher")
end
local event_prefix = "workspace_manager.workspace_switcher."
local function check_switch(name, event, restores, event_path, has_path_arg)
  assert(current == name)
  local before = recorded(event_prefix .. "switching")[1]
  assert(before[1] == "mux:A" and before[3] == "A" and before[4] == name)
  local after = recorded(event_prefix .. event)[1]
  assert(after[1] == "mux:" .. name and after[2] == pane and after[3] == name)
  assert(after.n == (has_path_arg and 4 or 3), "changed event argument count")
  assert(after[4] == event_path)
  assert(#recorded("restore") == restores)
  assert(recorded("save")[1][1] == "A")
  assert(recorded("history_switch")[1][2] == name)
  -- Saves and events must bracket the switch, and restoration follows it.
  local order = {}
  for _, call in ipairs(calls) do
    if
      call.kind == "save"
      or call.kind == "history_switch"
      or call.kind == "restore"
      or call.kind == "access"
      or call.kind == event_prefix .. "switching"
      or call.kind == event_prefix .. event
    then
      table.insert(order, call.kind)
    end
  end
  local expected = {
    "save",
    event_prefix .. "switching",
    "history_switch",
    "access",
  }
  if restores == 1 then table.insert(expected, "restore") end
  table.insert(expected, event_prefix .. event)
  assert(table.concat(order, ",") == table.concat(expected, ","))
end

-- Labels, sorting, filtering, descriptions, and an empty result.
reset()
settings.workspace_switcher_sort = "alphabetical"
settings.show_current_workspace_in_switcher = true
settings.show_current_workspace_hint = true
settings.show_switcher_hints = true
settings.workspace_count_format = "full"
settings.workspace_icon, settings.workspace_icon_current = "W ", "C "
settings.entry_icon = "E "
settings.start_in_fuzzy_mode = true
settings.switcher_keys = {
  delete = false,
  new = { key = "a", mods = "ALT" },
}
open()
assert(#recorded("alphabetical") == 1 and selector.fuzzy)
assert(selector.choices[1].label == "C Current label  current")
assert(selector.choices[2].label == "W Other label (2 tabs, 3 panes)")
assert(selector.choices[3].label == "○ Saved")
assert(selector.choices[4].label == "E Named")
assert(selector.choices[1].id == "A" and selector.choices[3].id == "Saved")
assert(
  selector.description
    == "Current label | M-a=new ^P=path ^R=rename | Esc=cancel"
)
assert(
  selector.fuzzy_description
    == "Current label | M-a=new ^P=path ^R=rename | Switch to: "
)
settings.workspace_count_format = "compact"
open()
assert(selector.choices[2].label == "W Other label (2t 3p)")
settings.workspace_count_format = nil
open()
assert(selector.choices[2].label == "W Other label")

-- Status prefixes use the category color and inherit native selection.
local function check_prefix(index, prefix, expected_color)
  local parts = formatted[selector.choices[index].label]
  local found = false
  local foreground
  for _, part in ipairs(parts) do
    if part == "ResetAttributes" then foreground = nil end
    if part.Foreground then
      foreground = part.Foreground.AnsiColor or part.Foreground.Color
    end
    if part.Text then
      assert(not part.Text:find("\27", 1, true))
      if part.Text == prefix then
        assert(foreground == expected_color)
        found = true
      end
    end
  end
  assert(found)
  -- Also validate FormatItems against WezTerm's actual formatter.
  local escaped = runtime.format(parts)
  assert(escaped:find(prefix, 1, true))
  assert(not escaped:find("\27[27m", 1, true), string.format("%q", escaped))
end

settings.workspace_icon, settings.workspace_icon_current = nil, nil
settings.entry_icon = nil
for _, format in ipairs({ "icons", "words" }) do
  settings.workspace_status_format = format
  settings.workspace_count_format = "compact"
  settings.colors = nil
  open()
  local prefixes = format == "icons" and { "●", "○", "·" }
    or { "[live]", "[disk]", "[path]" }
  assert(selector.choices[1].label == prefixes[1] .. " Current label  current")
  assert(selector.choices[2].label == prefixes[1] .. " Other label (2t 3p)")
  assert(selector.choices[3].label == prefixes[2] .. " Saved")
  assert(selector.choices[4].label == prefixes[3] .. " Named")
  check_prefix(1, prefixes[1], "Green")
  check_prefix(2, prefixes[1], "Green")
  check_prefix(3, prefixes[2], "Purple")
  check_prefix(4, prefixes[3], nil)

  settings.colors = {
    workspace_status_live = "Green",
    workspace_status_saved = "#ff9e64",
    workspace_status_path = { { Foreground = { Color = "#e0af68" } } },
    workspace_icon = "Red",
    workspace_name = "Blue",
    workspace_current_marker = "Yellow",
  }
  open()
  check_prefix(2, prefixes[1], "Green")
  check_prefix(3, prefixes[2], "#ff9e64")
  check_prefix(4, prefixes[3], "#e0af68")
end
settings.workspace_status_format = "invalid"
local ok, err = pcall(open)
assert(not ok and err:find("workspace_status_format", 1, true))

-- Empty suggestion icons and wide custom icons still align names.
settings.workspace_status_format = "icons"
settings.workspace_count_format = nil
settings.workspace_icon, settings.workspace_icon_current = "界  ", "C "
settings.workspace_icon_saved = "◇"
settings.entry_icon = ""
open()
assert(selector.choices[1].label == "C  Current label  current")
assert(selector.choices[2].label == "界 Other label")
assert(selector.choices[3].label == "◇  Saved")
assert(selector.choices[4].label == "   Named")
settings.workspace_status_format = "words"
open()
assert(selector.choices[2].label == "[live] Other label")
assert(selector.choices[3].label == "[disk] Saved")
assert(selector.choices[4].label == "[path] Named")
reset()
settings.filter_choices = { "/home/test/raw" }
open()
assert(#selector.choices == 3 and selector.choices[3].id == "~/raw")
assert(selector.description == "Enter=switch | Esc=cancel")
assert(selector.fuzzy_description == "Switch to: ")
settings.filter_choices = function(choice) return choice.id == "B" end
open()
assert(#selector.choices == 1 and selector.choices[1].id == "B")
settings.filter_choices = function() return false end
selector = nil
open()
assert(
  not selector
    and recorded("notify")[1][1] == "No other workspaces available"
)

-- Live, saved, named custom, explicit path, and zoxide selections.
reset()
saved_focus = true
choose("B")
check_switch("B", "selected", 0)
assert(#recorded("focus") == 1)
reset()
choose("Saved")
check_switch("Saved", "created", 1)
for _, scenario in ipairs({
  { "Custom", "Named", nil },
  { "WithPath", "Project", "/home/test/project" },
  { "~/raw", "~/raw", "/home/test/raw" },
}) do
  reset()
  zoxide = scenario[1] == "~/raw"
  choose(scenario[1])
  check_switch(scenario[2], "created", 1, scenario[3], true)
  if zoxide then assert(recorded("command")[1][1][4] == "~/raw") end
end
reset()
settings.session_enabled = false
choose("Custom")
assert(#recorded("save") == 0 and #recorded("restore") == 0)
reset()
excluded = "A"
choose("B")
assert(#recorded("save") == 0)

-- Creation prompts and directory confirmation preserve cancellation behavior.
reset()
choose("B", "new")
prompt.action(window, pane, "New")
check_switch("New", "created", 1)
reset()
choose("B", "new_at_path")
prompt.action(window, pane, "~/new")
check_switch("~/new", "created", 1, "/home/test/new", true)
for _, answer in ipairs({ "yes", "no", "cancel", "failure" }) do
  reset()
  directory_exists, zoxide = false, true
  choose("B", "new_at_path")
  prompt.action(window, pane, "~/new")
  assert(current == "A" and selector.title == "Create directory")
  mkdir_ok = answer ~= "failure"
  local id = answer == "failure" and "yes" or answer
  if answer == "cancel" then id = nil end
  selector.action(window, pane, id, id)
  if answer == "yes" then
    check_switch("~/new", "created", 1, "/home/test/new", true)
    assert(recorded("mkdir")[1][1] == "/home/test/new")
    assert(recorded("command")[1][1][4] == "~/new")
  else
    assert(current == "A" and #recorded("save") == 0)
    if answer == "failure" then assert(#recorded("notify") == 1) end
  end
end
for _, pending in ipairs({ "new", "new_at_path", "rename" }) do
  reset()
  choose("B", pending)
  prompt.action(window, pane, "")
  assert(current == "A")
  flush_reopen()
end
reset()
choose(nil, "delete")
assert(#recorded("workspace_manager.switcher.canceled") == 1)
assert(#timers == 0 and #recorded("delete") == 0)
choose("B")
assert(current == "B", "canceled action leaked into next selection")

-- Delete protection, saved state cleanup, live pane closure, rename and merge.
for _, id in ipairs({ "A", "Custom", "Saved", "B" }) do
  reset()
  choose(id, "delete")
  if id == "A" or id == "Custom" then
    assert(#recorded("delete") == 0 and #recorded("notify") == 1)
  else
    assert(recorded("delete")[1][1] == id)
    assert(fake.GLOBAL.workspace_access_times[id] == nil)
    assert(#recorded(event_prefix .. "deleted") == 1)
    if id == "B" then assert(#recorded("command") == 2) end
  end
  flush_reopen()
end
for _, id in ipairs({ "B", "Saved" }) do
  reset()
  choose(id, "rename")
  prompt.action(window, pane, "Renamed")
  assert(#recorded("rename") == (id == "B" and 1 or 0))
  assert(recorded("rename_state")[1][1] == id)
  assert(fake.GLOBAL.workspace_access_times.Renamed == (id == "B" and 2 or 3))
  flush_reopen()
end
reset()
choose("B", "rename")
prompt.action(window, pane, "A")
assert(recorded("move_window")[1][1] == "A")
flush_reopen()
reset()
choose("Custom", "rename")
assert(not prompt and #recorded("notify") == 1)
flush_reopen()

package.loaded.wezterm = runtime
io.stdout:write(
  "PASS: workspace switcher choices, events, prompts, and action routes\n"
)
io.stdout:flush()
return {}
