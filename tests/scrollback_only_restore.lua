-- Lua-only regression; does not start a terminal or run saved commands:
-- wezterm --config-file tests/scrollback_only_restore.lua ls-fonts
local runtime = require("wezterm")
package.path = runtime.config_dir .. "/../plugin/?.lua;" .. package.path

local captured, injected
local fake_wezterm = {
  target_triple = runtime.target_triple,
  add_to_config_reload_watch_list = function() end,
  mux = {
    get_domain = function()
      return { is_spawnable = function() return true end }
    end,
  },
  shell_join_args = function() error("must not construct shell commands") end,
}
package.loaded.wezterm = fake_wezterm
local pane_tree = require("session.pane_tree")
local tab_state = require("session.tab_state")
local pane = {
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

-- Older saved states may contain a language server mistaken for Neovim.
tab_state.default_on_pane_restore({
  pane = pane,
  alt_screen_active = true,
  process = {
    argv = { [[C:\Users\test\mason\lua-language-server.exe]] },
  },
})
assert(injected == nil)
tab_state.default_on_pane_restore({ pane = pane, alt_screen_active = true })
assert(injected == nil)

-- Actual saved text is restored, even if legacy process metadata is present.
tab_state.default_on_pane_restore({
  pane = pane,
  text = "EXPECTED-SCROLLBACK\r\n",
  process = { argv = { "must-not-run" } },
})
assert(injected:find("EXPECTED-SCROLLBACK", 1, true))

local function capture(alt_screen)
  pane.is_alt_screen_active = function() return alt_screen end
  return pane_tree.create_pane_tree({
    { pane = pane, left = 0, top = 0, width = 80, height = 10 },
  })
end

local alternate = capture(true)
assert(alternate.process == nil and alternate.text == nil)
local normal = capture(false)
assert(normal.text == "saved output\r\n" and captured == 100)
assert(normal.process == nil)

package.loaded.wezterm = runtime
io.stdout:write("PASS: scrollback restoration never replays processes\n")
io.stdout:flush()
return {}
