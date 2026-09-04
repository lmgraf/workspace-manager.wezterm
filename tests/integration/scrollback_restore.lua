-- Run from the repository root on Windows:
-- wezterm-mux-server --config-file tests/integration/scrollback_restore.lua
local wezterm = require("wezterm")
local root = wezterm.config_dir .. "/../.."
package.path = root .. "/plugin/?.lua;" .. package.path

local tab_state = require("session.tab_state")
local theme = require("theme")
local use_profile = os.getenv("SCROLLBACK_TEST_PROFILE") == "1"
local results = {}
local assertions = 0

local function check(condition, message)
  assertions = assertions + 1
  if not condition then error(message, 2) end
end

local function add_result(name, ok, err)
  table.insert(results, { name = name, ok = ok, err = err })
end

local function run_case(name, callback)
  local ok, err = pcall(callback)
  add_result(name, ok, err)
end

local function finish(name, ok, err)
  add_result(name, ok, err)
  local passed = 0
  for _, result in ipairs(results) do
    if result.ok then
      passed = passed + 1
      io.stdout:write("PASS: " .. result.name .. "\n")
    else
      io.stderr:write("FAIL: " .. result.name .. "\n")
      io.stderr:write("  " .. tostring(result.err) .. "\n")
    end
  end
  local failed = #results - passed
  local summary = string.format(
    "%d scenarios, %d passed, %d failed, %d assertions\n",
    #results,
    passed,
    failed,
    assertions
  )
  if failed == 0 then
    io.stdout:write(summary)
  else
    io.stderr:write(summary)
  end
  io.stdout:flush()
  io.stderr:flush()
  os.exit(failed == 0 and 0 or 1)
end

run_case("formats switcher labels with real WezTerm APIs", function()
  check(wezterm.column_width("") == 0, "empty text must occupy zero columns")
  check(wezterm.column_width("●") == 1, "status icon must occupy one column")
  check(wezterm.column_width("界") == 2, "wide icon must occupy two columns")

  theme.setup({
    workspace_status_format = "icons",
    workspace_icon = "界  ",
    workspace_icon_current = "●",
    workspace_icon_saved = "◇",
    entry_icon = "",
  })
  local escaped =
    theme.build_switcher_label("界  ", "workspace", " (2t 3p)", "workspace")
  check(escaped:find("界", 1, true), "formatted label lost its icon")
  check(escaped:find("workspace", 1, true), "formatted label lost its name")
  check(escaped:find("2t 3p", 1, true), "formatted label lost its counts")
  check(
    not escaped:find("\27[27m", 1, true),
    "formatter emitted reverse-video reset that breaks selection"
  )
end)

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

  tab_state.default_on_pane_restore({
    pane = pane,
    text = "STARTUP-FIRST\r\nSTARTUP-LAST\r\n",
  })

  local attempts = 0
  local function run()
    attempts = attempts + 1
    if not pane:get_lines_as_text():find("LIVE>", 1, true) then
      if attempts > 50 then
        return finish(
          "restores scrollback and accepts Enter in PowerShell",
          false,
          "prompt did not appear"
        )
      end
      wezterm.time.call_after(0.1, run)
      return
    end

    local ok, err = pcall(function()
      local before = pane:get_lines_as_text()
      local cursor = pane:get_cursor_position()
      local row = cursor.y - pane:get_dimensions().physical_top
      local histories = {
        "SAVED-FIRST\r\n\x1b[31mSAVED-LAST\x1b[0m\r\n",
        "LONG-FIRST\r\n" .. string.rep("older output\r\n", 30) .. "LONG-LAST",
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
      check(all:find("STARTUP-FIRST", 1, true), "startup erased first line")
      check(all:find("STARTUP-LAST", 1, true), "startup erased last line")
      check(all:find("SAVED-FIRST", 1, true), "first saved line missing")
      check(all:find("SAVED-LAST", 1, true), "last saved line missing")
      pane:send_text("\r")
    end)
    if not ok then
      return finish(
        "restores scrollback and accepts Enter in PowerShell",
        false,
        err
      )
    end

    wezterm.time.call_after(0.5, function()
      local after_ok, after_err = pcall(function()
        local scrollback_rows = pane:get_dimensions().scrollback_rows
        local all = pane:get_lines_as_text(scrollback_rows)
        check(all:find("SAVED-FIRST", 1, true), "Enter erased first line")
        check(all:find("SAVED-LAST", 1, true), "Enter erased last line")
        check(all:find("LONG-FIRST", 1, true), "Enter erased long history")
        check(all:find("LONG-LAST", 1, true), "long history was truncated")
        check(all:find("WRAPPED-LAST", 1, true), "wrapped history truncated")
        local _, prompts = pane:get_lines_as_text():gsub("LIVE>", "")
        check(prompts >= 2, "Enter did not produce a new prompt")
      end)
      finish(
        "restores scrollback and accepts Enter in PowerShell",
        after_ok,
        after_err
      )
    end)
  end
  wezterm.time.call_after(0.1, run)
end)

local pid = tostring(wezterm.procinfo.pid())
return {
  unix_domains = {
    {
      name = "scrollback-restore-test-" .. pid,
      socket_path = wezterm.config_dir .. "/scrollback-test-" .. pid .. ".sock",
    },
  },
  scrollback_lines = 1000,
  automatically_reload_config = false,
}
