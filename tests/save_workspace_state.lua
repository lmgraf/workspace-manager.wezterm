-- Run with: wezterm --config-file tests/save_workspace_state.lua ls-fonts
-- Verify save success/failure propagation without writing user session files.
local runtime = require("wezterm")
local root = runtime.config_dir .. "/../plugin/"
local writes, directories = {}, {}
local state_value, state_error, write_ok, write_error

local fake = {
  mux = {},
  log_info = function() end,
  log_error = function() end,
}
package.loaded.wezterm = fake

local real_file_io = assert(loadfile(root .. "session/file_io.lua"))()
assert(type(real_file_io.write_state) == "function")

package.loaded["session.workspace_state"] = {
  get_workspace_state_for = function(name)
    if state_error then error(state_error) end
    return state_value or {
      workspace = name,
      window_states = { { window_id = 1 } },
    }
  end,
}
package.loaded["session.tab_state"] = {}
package.loaded["session.file_io"] = {
  write_state = function(...)
    table.insert(writes, table.pack(...))
    return write_ok, write_error
  end,
}

local settings = {
  session_state_dir = "/tmp/workspace-manager-test",
  session_exclude_workspaces = { "excluded" },
}
local helpers = {
  path_sep = "/",
  normalize_workspace_name = function(name) return name end,
  create_directory = function(path) table.insert(directories, path) end,
}
local history = { HISTORY_DIR = "/tmp", load = function() return {} end }
local state = assert(loadfile(root .. "state.lua"))()
state.setup(settings, { helpers = helpers, history = history })

local function reset()
  writes, directories = {}, {}
  state_value, state_error = nil, nil
  write_ok, write_error = true, nil
end

reset()
local ok, err = state.save_workspace_state("saved")
assert(ok and err == nil)
assert(#directories == 1 and #writes == 1)
assert(writes[1][1]:find("saved.json", 1, true))

reset()
write_ok, write_error = false, "disk full"
ok, err = state.save_workspace_state("write-failure")
assert(not ok and err:find("disk full", 1, true))
assert(#writes == 1)

reset()
state_value = { workspace = "empty", window_states = {} }
ok, err = state.save_workspace_state("empty")
assert(not ok and err:find("no windows", 1, true))
assert(#writes == 0)

reset()
state_error = "collection failed"
ok, err = state.save_workspace_state("collection-failure")
assert(not ok and err:find("collection failed", 1, true))
assert(#writes == 0)

reset()
ok, err = state.save_workspace_state("excluded")
assert(not ok and err:find("excluded", 1, true))
assert(#directories == 0 and #writes == 0)

package.loaded.wezterm = runtime
io.stdout:write("PASS: workspace save success and failure propagation\n")
io.stdout:flush()
return {}
