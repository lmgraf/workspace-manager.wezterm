local modules = require("helpers.modules")
local fake_wezterm = require("helpers.fake_wezterm")

describe("deferred pane restoration", function()
  local queue
  local warnings
  local tab_state
  local screen
  local cols
  local rows
  local pane
  local tree
  local restored

  local function tick(count)
    for _ = 1, count do
      assert.is_true(#queue > 0, "wait stopped too early")
      table.remove(queue, 1)()
    end
  end

  before_each(function()
    modules.reset()
    queue, warnings = {}, {}
    package.loaded.wezterm = fake_wezterm.new({
      time = {
        call_after = function(_, callback) table.insert(queue, callback) end,
      },
      log_warn = function(message) table.insert(warnings, message) end,
      log_error = function(message) error(message) end,
    }).wezterm
    package.loaded["session.pane_tree"] = {}
    tab_state = require("session.tab_state")

    screen, cols, rows = "", 80, 12
    pane = {
      get_dimensions = function()
        return { cols = cols, viewport_rows = rows, physical_top = 100 }
      end,
      get_cursor_position = function() return { x = 6, y = 101 } end,
      get_lines_as_text = function() return screen end,
    }
    tree = { pane = pane }
    restored = 0
  end)

  after_each(modules.reset)

  it("waits for prompt, resize, and profile output to stabilize", function()
    tab_state.restore_pane_when_stable(tree, function(value)
      assert.are.equal(tree, value)
      restored = restored + 1
    end)
    tick(10)
    assert.are.equal(0, restored)
    screen = "LIVE> "
    tick(4)
    assert.are.equal(0, restored)
    rows = 24
    tick(4)
    assert.are.equal(0, restored)
    screen = "profile finished\nLIVE> "
    tick(5)
    assert.are.equal(0, restored)
    tick(1)

    assert.are.equal(1, restored)
    assert.are.equal(0, #queue)
  end)

  it("bounds a prompt that never becomes stable", function()
    tab_state.restore_pane_when_stable(tree, function()
      restored = restored + 1
    end)
    for i = 1, 50 do
      screen = tostring(i)
      tick(1)
    end

    assert.are.equal(1, restored)
    assert.are.equal(0, #queue)
  end)

  it("handles a pane closing during the wait", function()
    tab_state.restore_pane_when_stable({
      pane = { get_dimensions = function() error("pane closed") end },
    }, function() restored = restored + 1 end)
    tick(1)

    assert.are.equal(0, restored)
    assert.are.equal(1, #warnings)
    assert.are.equal(0, #queue)
  end)

  it("defers callbacks until the complete layout exists", function()
    local layout_ready = false
    local called_during_layout = false
    package.loaded["session.workspace_state"] = {
      restore_workspace = function(_, opts)
        layout_ready = false
        opts.on_pane_restore(tree)
        assert.are.equal(0, #queue)
        layout_ready = true
      end,
    }
    package.loaded["session.file_io"] = {
      load_json = function() return { window_states = {} } end,
    }
    local state = require("state")
    state.setup({
      session_state_dir = ".",
      session_exclude_workspaces = {},
      session_on_pane_restore = function()
        restored = restored + 1
        called_during_layout = not layout_ready
      end,
    }, { helpers = { path_sep = "/" }, history = {} })

    screen = "LIVE> "
    state.restore_workspace_state("test", {}, { defer_pane_restore = true })
    assert.are.equal(0, restored)
    assert.are.equal(1, #queue)
    tick(6)

    assert.are.equal(1, restored)
    assert.is_false(called_during_layout)
  end)

  it("retains immediate restore timing for switcher restores", function()
    local layout_ready = false
    local called_during_layout = false
    package.loaded["session.workspace_state"] = {
      restore_workspace = function(_, opts)
        layout_ready = false
        opts.on_pane_restore(tree)
        layout_ready = true
      end,
    }
    package.loaded["session.file_io"] = {
      load_json = function() return { window_states = {} } end,
    }
    local state = require("state")
    state.setup({
      session_state_dir = ".",
      session_exclude_workspaces = {},
      session_on_pane_restore = function()
        restored = restored + 1
        called_during_layout = not layout_ready
      end,
    }, { helpers = { path_sep = "/" }, history = {} })

    state.restore_workspace_state("test", {})

    assert.are.equal(1, restored)
    assert.is_true(called_during_layout)
    assert.are.equal(0, #queue)
  end)
end)
