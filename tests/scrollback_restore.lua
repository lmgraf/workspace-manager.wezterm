-- Run from the repository root:
-- wezterm-mux-server --config-file tests/scrollback_restore.lua
-- Uses an isolated mux socket and exits after checking a real PowerShell pane.
local wezterm = require("wezterm")
local root = wezterm.config_dir .. "/.."
package.path = root .. "/plugin/?.lua;" .. package.path
local tab_state = require("session.tab_state")
local use_profile = os.getenv("SCROLLBACK_TEST_PROFILE") == "1"

local function check(condition, message)
  if not condition then error(message) end
end

wezterm.on("mux-startup", function()
  local args = {
    "pwsh",
    "-NoLogo",
    "-NoExit",
    "-Command",
    "function prompt { 'LIVE> ' }",
  }
  if not use_profile then table.insert(args, 3, "-NoProfile") end
  local _, pane = wezterm.mux.spawn_window({
    args = args,
    width = 40,
    height = 10,
  })

  -- Startup restoration runs before the new shell has printed its prompt.
  tab_state.default_on_pane_restore({
    pane = pane,
    text = "STARTUP-FIRST\r\nSTARTUP-LAST\r\n",
  })

  local function finish(ok, err)
    if ok then
      io.stdout:write("PASS: scrollback restore and PowerShell Enter\n")
    else
      io.stderr:write("FAIL: " .. tostring(err) .. "\n")
    end
    io.stdout:flush()
    io.stderr:flush()
    os.exit(ok and 0 or 1)
  end

  local attempts = 0
  local function run()
    attempts = attempts + 1
    if not pane:get_lines_as_text():find("LIVE>", 1, true) then
      if attempts > 50 then return finish(false, "prompt did not appear") end
      wezterm.time.call_after(0.1, run)
      return
    end

    local ok, err = pcall(function()
      local before = pane:get_lines_as_text()
      local cursor = pane:get_cursor_position()
      local row = cursor.y - pane:get_dimensions().physical_top
      local histories = {
        "SAVED-FIRST\r\n\x1b[31mSAVED-LAST\x1b[0m\r\n",
        "LONG-FIRST\r\n"
          .. string.rep("older output\r\n", 30)
          .. "LONG-LAST",
        string.rep("W", 80) .. "\r\nWRAPPED-LAST",
      }
      for _, history in ipairs(histories) do
        tab_state.default_on_pane_restore({ pane = pane, text = history })
        local after = pane:get_cursor_position()
        check(pane:get_lines_as_text() == before, "live screen changed")
        check(after.x == cursor.x, "cursor column changed")
        check(
          after.y - pane:get_dimensions().physical_top == row,
          "cursor row changed"
        )
      end
      local all = pane:get_lines_as_text(pane:get_dimensions().scrollback_rows)
      check(all:find("STARTUP-FIRST", 1, true), "startup erased first saved line")
      check(all:find("STARTUP-LAST", 1, true), "startup erased last saved line")
      check(all:find("SAVED-FIRST", 1, true), "first saved line missing")
      check(all:find("SAVED-LAST", 1, true), "last saved line missing")
      pane:send_text("\r")
    end)
    if not ok then return finish(false, err) end

    wezterm.time.call_after(0.5, function()
      local ok, err = pcall(function()
        local all = pane:get_lines_as_text(pane:get_dimensions().scrollback_rows)
        check(
          all:find("SAVED-FIRST", 1, true),
          "Enter overwrote first saved line"
        )
        check(
          all:find("SAVED-LAST", 1, true),
          "Enter overwrote last saved line"
        )
        check(all:find("LONG-FIRST", 1, true), "Enter overwrote long history")
        check(all:find("LONG-LAST", 1, true), "long history truncated")
        check(all:find("WRAPPED-LAST", 1, true), "wrapped history truncated")
        local _, prompts = pane:get_lines_as_text():gsub("LIVE>", "")
        check(prompts >= 2, "Enter did not produce a new prompt")
      end)
      finish(ok, err)
    end)
  end
  wezterm.time.call_after(0.1, run)
end)

return {
  unix_domains = {
    {
      name = "scrollback-restore-test",
      socket_path = wezterm.config_dir .. "/scrollback-test.sock",
    },
  },
  scrollback_lines = 1000,
  automatically_reload_config = false,
}
