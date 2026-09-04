local modules = require("helpers.modules")
local fake_wezterm = require("helpers.fake_wezterm")

describe("scrollback capture and replay", function()
  local pane_tree
  local tab_state
  local pane
  local captured
  local injected

  before_each(function()
    modules.reset()
    captured, injected = nil, nil
    package.loaded.wezterm = fake_wezterm.new({
      target_triple = "x86_64-pc-windows-msvc",
      mux = {
        get_domain = function()
          return { is_spawnable = function() return true end }
        end,
      },
      shell_join_args = function() error("must not construct shell commands") end,
    }).wezterm
    pane_tree = require("session.pane_tree")
    tab_state = require("session.tab_state")
    pane = {
      send_text = function() error("must not send commands to the shell") end,
      inject_output = function(_, text) injected = text end,
      get_dimensions = function()
        return { viewport_rows = 10, scrollback_rows = 100 }
      end,
      get_lines_as_escapes = function(_, nlines)
        captured = nlines
        return "saved output\r\n"
      end,
      get_domain_name = function() return "local" end,
      get_current_working_dir = function() return nil end,
      get_foreground_process_info = function()
        error("must not capture guessed foreground processes")
      end,
    }
  end)

  after_each(modules.reset)

  it("does not replay legacy process metadata on alternate screens", function()
    tab_state.default_on_pane_restore({
      pane = pane,
      alt_screen_active = true,
      process = {
        argv = { [[C:\Users\test\mason\lua-language-server.exe]] },
      },
    })
    tab_state.default_on_pane_restore({ pane = pane, alt_screen_active = true })

    assert.is_nil(injected)
  end)

  it("injects saved text without executing legacy process metadata", function()
    tab_state.default_on_pane_restore({
      pane = pane,
      text = "EXPECTED-SCROLLBACK\r\n",
      process = { argv = { "must-not-run" } },
    })

    assert.is_truthy(injected:find("EXPECTED-SCROLLBACK", 1, true))
  end)

  it("omits scrollback for alternate screens", function()
    pane.is_alt_screen_active = function() return true end

    local captured_tree = pane_tree.create_pane_tree({
      { pane = pane, left = 0, top = 0, width = 80, height = 10 },
    })

    assert.is_nil(captured_tree.process)
    assert.is_nil(captured_tree.text)
  end)

  it("captures bounded local scrollback without process metadata", function()
    pane.is_alt_screen_active = function() return false end

    local captured_tree = pane_tree.create_pane_tree({
      { pane = pane, left = 0, top = 0, width = 80, height = 10 },
    })

    assert.are.equal("saved output\r\n", captured_tree.text)
    assert.are.equal(100, captured)
    assert.is_nil(captured_tree.process)
  end)
end)
