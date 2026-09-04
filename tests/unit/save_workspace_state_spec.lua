local modules = require("helpers.modules")
local fake_wezterm = require("helpers.fake_wezterm")

describe("workspace state saving", function()
  local state
  local state_value
  local state_error
  local write_ok
  local write_error
  local write_state
  local create_directory

  before_each(function()
    modules.reset()
    state_value, state_error = nil, nil
    write_ok, write_error = true, nil
    write_state = spy.new(function() return write_ok, write_error end)
    create_directory = spy.new(function() end)

    package.loaded.wezterm = fake_wezterm.new({ mux = {} }).wezterm
    package.loaded["workspace_manager.session.workspace_state"] = {
      get_workspace_state_for = function(name)
        if state_error then error(state_error) end
        return state_value
          or {
            workspace = name,
            window_states = { { window_id = 1 } },
          }
      end,
    }
    package.loaded["workspace_manager.session.tab_state"] = {}
    package.loaded["workspace_manager.session.file_io"] = {
      write_state = write_state,
    }
    package.loaded["workspace_manager.settings"] = {
      session_state_dir = "/tmp/workspace-manager-test",
      session_exclude_workspaces = { "excluded" },
    }
    package.loaded["workspace_manager.helpers"] = {
      path_sep = "/",
      normalize_workspace_name = function(name) return name end,
      create_directory = create_directory,
    }
    package.loaded["workspace_manager.history"] = {
      HISTORY_DIR = "/tmp",
      load = function() return {} end,
    }

    state = require("workspace_manager.state")
  end)

  after_each(modules.reset)

  it("writes a collected workspace to its state file", function()
    local ok, err = state.save_workspace_state("saved")

    assert.is_true(ok)
    assert.is_nil(err)
    assert.spy(create_directory).was.called(1)
    assert.spy(write_state).was.called(1)
    local path = write_state.calls[1].vals[1]
    assert.is_truthy(path:find("saved.json", 1, true))
  end)

  it("propagates a state-file write failure", function()
    write_ok, write_error = false, "disk full"

    local ok, err = state.save_workspace_state("write-failure")

    assert.is_false(ok)
    assert.is_truthy(err:find("disk full", 1, true))
    assert.spy(write_state).was.called(1)
  end)

  it("rejects a workspace without windows", function()
    state_value = { workspace = "empty", window_states = {} }

    local ok, err = state.save_workspace_state("empty")

    assert.is_false(ok)
    assert.is_truthy(err:find("no windows", 1, true))
    assert.spy(write_state).was_not.called()
  end)

  it("reports collection failures without writing", function()
    state_error = "collection failed"

    local ok, err = state.save_workspace_state("collection-failure")

    assert.is_false(ok)
    assert.is_truthy(err:find("collection failed", 1, true))
    assert.spy(write_state).was_not.called()
  end)

  it("does not create files for an excluded workspace", function()
    local ok, err = state.save_workspace_state("excluded")

    assert.is_false(ok)
    assert.is_truthy(err:find("excluded", 1, true))
    assert.spy(create_directory).was_not.called()
    assert.spy(write_state).was_not.called()
  end)
end)
