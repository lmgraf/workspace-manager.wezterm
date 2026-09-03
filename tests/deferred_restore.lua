-- Run without starting a GUI or a shell:
-- wezterm --config-file tests/deferred_restore.lua ls-fonts
local runtime = require("wezterm")
package.path = runtime.config_dir .. "/../plugin/?.lua;" .. package.path

local queue, warnings = {}, {}
local fake_wezterm = {
  add_to_config_reload_watch_list = function() end,
  time = {
    call_after = function(_, callback) table.insert(queue, callback) end,
  },
  log_warn = function(message) table.insert(warnings, message) end,
  log_info = function() end,
  log_error = function(message) error(message) end,
}
package.loaded.wezterm = fake_wezterm
package.loaded["session.pane_tree"] = {}
local tab_state = require("session.tab_state")

local screen, cols, rows = "", 80, 12
local pane = {
  get_dimensions = function()
    return { cols = cols, viewport_rows = rows, physical_top = 100 }
  end,
  get_cursor_position = function() return { x = 6, y = 101 } end,
  get_lines_as_text = function() return screen end,
}
local tree = { pane = pane }
local restored = 0
local function restore(value)
  assert(value == tree)
  restored = restored + 1
end
local function tick(count)
  for _ = 1, count do
    assert(#queue > 0, "wait stopped too early")
    table.remove(queue, 1)()
  end
end

tab_state.restore_pane_when_stable(tree, restore)
tick(10)
assert(restored == 0, "restored before shell initialization")
screen = "LIVE> "
tick(4)
assert(restored == 0)
rows = 24
tick(4)
assert(restored == 0, "pane resize did not restart the wait")
screen = "profile finished\nLIVE> "
tick(5)
assert(restored == 0, "shell output did not restart the wait")
tick(1)
assert(restored == 1 and #queue == 0, "restore must run exactly once")

-- Prompts which never become quiet must not leave restoration pending forever.
restored = 0
tab_state.restore_pane_when_stable(tree, restore)
for i = 1, 50 do
  screen = tostring(i)
  tick(1)
end
assert(restored == 1 and #queue == 0, "restore wait was not bounded")

-- A pane closed during the wait must not leave an unhandled timer error.
tab_state.restore_pane_when_stable({
  pane = { get_dimensions = function() error("pane closed") end },
}, restore)
tick(1)
assert(#warnings == 1 and #queue == 0, "closed pane was not handled")

-- Exercise state.restore_workspace_state: callbacks must be queued until
-- the complete layout is constructed, including custom restore callbacks.
local layout_ready, called_during_layout = false, false
package.loaded["session.workspace_state"] = {
  restore_workspace = function(_, opts)
    layout_ready = false
    opts.on_pane_restore(tree)
    assert(#queue == 0, "pane wait began before layout completed")
    layout_ready = true
  end,
}
package.loaded["session.file_io"] = {
  load_json = function() return { window_states = {} } end,
}
local state = require("state")
state.setup({
  session_state_dir = ".",
  session_on_pane_restore = function()
    restored = restored + 1
    called_during_layout = not layout_ready
  end,
}, { helpers = { path_sep = "/" }, history = {} })

screen, restored = "LIVE> ", 0
state.restore_workspace_state("test", {}, { defer_pane_restore = true })
assert(restored == 0 and #queue == 1)
tick(6)
assert(restored == 1 and not called_during_layout)

restored = 0
state.restore_workspace_state("test", {})
assert(restored == 1 and called_during_layout and #queue == 0,
  "switcher restore timing changed")

package.loaded.wezterm = runtime
io.stdout:write("PASS: deferred startup restore timing and cancellation\n")
io.stdout:flush()
return { disable_default_key_bindings = true }
