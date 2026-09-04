local modules = require("helpers.modules")
local fixture = require("helpers.switcher_fixture")

local event_prefix = "workspace_manager.workspace_switcher."

describe("workspace switcher", function()
  local ctx

  before_each(function() ctx = fixture.new() end)
  after_each(modules.reset)

  local function check_switch(name, event, restores, event_path, has_path_arg)
    assert.are.equal(name, ctx.current)
    local before = ctx:recorded(event_prefix .. "switching")[1]
    assert.are.same({ "mux:A", ctx.pane, "A", name }, {
      before[1],
      before[2],
      before[3],
      before[4],
    })
    local after = ctx:recorded(event_prefix .. event)[1]
    assert.are.same({ "mux:" .. name, ctx.pane, name }, {
      after[1],
      after[2],
      after[3],
    })
    assert.are.equal(has_path_arg and 4 or 3, after.n)
    assert.are.equal(event_path, after[4])
    assert.are.equal(restores, #ctx:recorded("restore"))
    assert.are.equal("A", ctx:recorded("save")[1][1])
    assert.are.equal(name, ctx:recorded("history_switch")[1][2])

    local order = {}
    for _, call in ipairs(ctx.calls) do
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
    assert.are.same(expected, order)
  end

  local function prefix_color(index, prefix)
    local parts = ctx.formatted[ctx.selector.choices[index].label]
    local foreground
    for _, part in ipairs(parts) do
      if part == "ResetAttributes" then foreground = nil end
      if part.Foreground then
        foreground = part.Foreground.AnsiColor or part.Foreground.Color
      end
      if part.Text == prefix then return foreground end
    end
    error("prefix was not formatted: " .. prefix)
  end

  local function assert_flat_format_items(parts)
    assert.is_table(parts)
    for _, part in ipairs(parts) do
      assert.is_nil(part[1], "format list contained a nested item list")
    end
  end

  it("orders choices, formats counts, and builds configurable hints", function()
    local settings = ctx.settings
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

    ctx:open()

    assert.are.equal(1, #ctx:recorded("alphabetical"))
    assert.is_true(ctx.selector.fuzzy)
    assert.are.same({
      "C Current label  current",
      "W Other label (2 tabs, 3 panes)",
      "○ Saved",
      "E Named",
    }, {
      ctx.selector.choices[1].label,
      ctx.selector.choices[2].label,
      ctx.selector.choices[3].label,
      ctx.selector.choices[4].label,
    })
    assert.are.same({ "A", "Saved" }, {
      ctx.selector.choices[1].id,
      ctx.selector.choices[3].id,
    })
    assert.are.equal(
      "Current label | ^U=unload M-a=new ^P=path ^R=rename | Esc=cancel",
      ctx.selector.description
    )
    assert.are.equal(
      "Current label | ^U=unload M-a=new ^P=path ^R=rename | Switch to: ",
      ctx.selector.fuzzy_description
    )

    settings.switcher_keys.unload = false
    ctx:open()
    assert.is_nil(ctx.selector.description:find("unload", 1, true))
    settings.switcher_keys.unload = { key = "x", mods = "ALT", hint = "drop" }
    ctx:open()
    assert.is_truthy(ctx.selector.description:find("M-x=drop", 1, true))
    settings.switcher_keys.unload = nil
    settings.workspace_count_format = "compact"
    ctx:open()
    assert.are.equal("W Other label (2t 3p)", ctx.selector.choices[2].label)
    settings.workspace_count_format = nil
    ctx:open()
    assert.are.equal("W Other label", ctx.selector.choices[2].label)
  end)

  it("formats category status and aligns custom-width icons", function()
    local settings = ctx.settings
    settings.show_current_workspace_in_switcher = true
    settings.workspace_status_format = "icons"
    settings.workspace_count_format = "compact"
    ctx:open()

    assert.are.same({
      "● Current label  current",
      "● Other label (2t 3p)",
      "○ Saved",
      "· Named",
    }, {
      ctx.selector.choices[1].label,
      ctx.selector.choices[2].label,
      ctx.selector.choices[3].label,
      ctx.selector.choices[4].label,
    })
    assert.are.equal("Green", prefix_color(1, "●"))
    assert.are.equal("Purple", prefix_color(3, "○"))
    assert.is_nil(prefix_color(4, "·"))

    settings.colors = {
      workspace_status_live = "Green",
      workspace_status_saved = "#ff9e64",
      workspace_status_path = { { Foreground = { Color = "#e0af68" } } },
      workspace_icon = "Red",
      workspace_name = "Blue",
      workspace_current_marker = "Yellow",
    }
    ctx:open()
    assert.are.equal("Green", prefix_color(2, "●"))
    assert.are.equal("#ff9e64", prefix_color(3, "○"))
    assert.are.equal("#e0af68", prefix_color(4, "·"))

    settings.workspace_count_format = nil
    settings.workspace_icon, settings.workspace_icon_current = "界  ", "C "
    settings.workspace_icon_saved = "◇"
    settings.entry_icon = ""
    ctx:open()
    assert.are.same({
      "C  Current label  current",
      "界 Other label",
      "◇  Saved",
      "   Named",
    }, {
      ctx.selector.choices[1].label,
      ctx.selector.choices[2].label,
      ctx.selector.choices[3].label,
      ctx.selector.choices[4].label,
    })

    settings.workspace_status_format = "words"
    ctx:open()
    assert.are.same({
      "[live] Other label",
      "[disk] Saved",
      "[path] Named",
    }, {
      ctx.selector.choices[2].label,
      ctx.selector.choices[3].label,
      ctx.selector.choices[4].label,
    })

    settings.workspace_status_format = "invalid"
    assert.has_error(function() ctx:open() end)
  end)

  it("flattens structured switcher, legend, and prompt styles", function()
    ctx.settings.show_current_workspace_hint = true
    ctx.settings.show_switcher_hints = false
    ctx.settings.colors = {
      prompt_accent = {
        { Foreground = { Color = "#50fa7b" } },
        { Attribute = { Intensity = "Bold" } },
      },
      prompt_heading = {
        { Attribute = { Intensity = "Bold" } },
      },
      muted = {
        { Foreground = { Color = "#6272a4" } },
        { Attribute = { Intensity = "Half" } },
      },
    }

    ctx:open()
    assert.are.equal("Current label | Esc=cancel", ctx.selector.description)
    assert_flat_format_items(ctx.formatted[ctx.selector.description])
    assert_flat_format_items(ctx.formatted[ctx.selector.fuzzy_description])

    local config = require("workspace_manager.config")
    local legend = config.get_switcher_legend()
    assert.are.equal(
      "  ^D=del  ^U=unload  ^N=new  ^P=path  ^R=rename  Esc=cancel",
      legend
    )
    assert_flat_format_items(ctx.formatted[legend])

    ctx:choose("B", "rename")
    assert.are.equal("Renaming: B | Enter new name:", ctx.prompt.description)
    assert_flat_format_items(ctx.formatted[ctx.prompt.description])

    ctx.directory_exists = false
    ctx:choose("B", "new_at_path")
    ctx.prompt.action(ctx.window, ctx.pane, "~/new")
    assert.are.equal(
      "Directory does not exist: ~/new. Create it?",
      ctx.selector.description
    )
    assert_flat_format_items(ctx.formatted[ctx.selector.description])
  end)

  it("filters by path or callback and reports an empty result", function()
    ctx.settings.filter_choices = { "/home/test/raw" }
    ctx:open()
    assert.are.equal(3, #ctx.selector.choices)
    assert.are.equal("~/raw", ctx.selector.choices[3].id)
    assert.are.equal("Enter=switch | Esc=cancel", ctx.selector.description)
    assert.are.equal("Switch to: ", ctx.selector.fuzzy_description)

    ctx.settings.filter_choices = nil
    ctx.settings.show_switcher_hints = true
    ctx.settings.show_current_workspace_hint = false
    ctx:open()
    assert.are.equal(
      "^D=del ^U=unload ^N=new ^P=path ^R=rename | Switch to: ",
      ctx.selector.fuzzy_description
    )

    ctx.settings.filter_choices = function(choice) return choice.id == "B" end
    ctx:open()
    assert.are.same({ "B" }, { ctx.selector.choices[1].id })

    ctx.settings.filter_choices = function() return false end
    ctx.selector = nil
    ctx:open()
    assert.is_nil(ctx.selector)
    assert.are.equal(
      "No other workspaces available",
      ctx:recorded("notify")[1][1]
    )
  end)

  it("routes live, saved, custom, path, and zoxide selections", function()
    ctx.saved_focus = true
    ctx:choose("B")
    check_switch("B", "selected", 0)
    assert.are.equal(1, #ctx:recorded("focus"))

    for _, scenario in ipairs({
      { id = "Saved", name = "Saved", event = "created", restores = 1 },
      { id = "Custom", name = "Named", path = nil },
      { id = "WithPath", name = "Project", path = "/home/test/project" },
      { id = "~/raw", name = "~/raw", path = "/home/test/raw", zoxide = true },
    }) do
      ctx:reset()
      ctx.zoxide = scenario.zoxide or false
      ctx:choose(scenario.id)
      check_switch(
        scenario.name,
        scenario.event or "created",
        scenario.restores or 1,
        scenario.path,
        scenario.id ~= "Saved"
      )
      if scenario.zoxide then
        assert.are.equal("~/raw", ctx:recorded("command")[1][1][4])
      end
    end

    ctx:reset()
    ctx.settings.session_enabled = false
    ctx:choose("Custom")
    assert.are.equal(0, #ctx:recorded("save"))
    assert.are.equal(0, #ctx:recorded("restore"))

    ctx:reset()
    ctx.excluded = "A"
    ctx:choose("B")
    assert.are.equal(0, #ctx:recorded("save"))
  end)

  it(
    "handles creation prompts, directory confirmation, and cancellation",
    function()
      ctx:choose("B", "new")
      ctx.prompt.action(ctx.window, ctx.pane, "New")
      check_switch("New", "created", 1)

      ctx:reset()
      ctx:choose("B", "new_at_path")
      ctx.prompt.action(ctx.window, ctx.pane, "~/new")
      check_switch("~/new", "created", 1, "/home/test/new", true)

      for _, answer in ipairs({ "yes", "no", "cancel", "failure" }) do
        ctx:reset()
        ctx.directory_exists, ctx.zoxide = false, true
        ctx:choose("B", "new_at_path")
        ctx.prompt.action(ctx.window, ctx.pane, "~/new")
        assert.are.equal("A", ctx.current)
        assert.are.equal("Create directory", ctx.selector.title)
        ctx.mkdir_ok = answer ~= "failure"
        local id = answer == "failure" and "yes" or answer
        if answer == "cancel" then id = nil end
        ctx.selector.action(ctx.window, ctx.pane, id, id)
        if answer == "yes" then
          check_switch("~/new", "created", 1, "/home/test/new", true)
          assert.are.equal("/home/test/new", ctx:recorded("mkdir")[1][1])
          assert.are.equal("~/new", ctx:recorded("command")[1][1][4])
        else
          assert.are.equal("A", ctx.current)
          assert.are.equal(0, #ctx:recorded("save"))
          if answer == "failure" then
            assert.are.equal(1, #ctx:recorded("notify"))
          end
        end
      end

      for _, pending in ipairs({ "new", "new_at_path", "rename" }) do
        ctx:reset()
        ctx:choose("B", pending)
        ctx.prompt.action(ctx.window, ctx.pane, "")
        assert.are.equal("A", ctx.current)
        ctx:flush_reopen()
        assert.are.equal("Workspace Switcher", ctx.selector.title)
      end

      ctx:reset()
      ctx:choose(nil, "delete")
      assert.are.equal(1, #ctx:recorded("workspace_manager.switcher.canceled"))
      assert.are.equal(0, #ctx.timers)
      assert.are.equal(0, #ctx:recorded("delete"))
      ctx:choose("B")
      assert.are.equal("B", ctx.current)
    end
  )

  it(
    "protects current and custom entries while deleting valid targets",
    function()
      for _, id in ipairs({ "A", "Custom", "Saved", "B" }) do
        ctx:reset()
        ctx:choose(id, "delete")
        if id == "A" or id == "Custom" then
          assert.are.equal(0, #ctx:recorded("delete"))
          assert.are.equal(1, #ctx:recorded("notify"))
        else
          assert.are.equal(id, ctx:recorded("delete")[1][1])
          assert.is_nil(ctx.fake.GLOBAL.workspace_access_times[id])
          assert.are.equal(1, #ctx:recorded(event_prefix .. "deleted"))
          if id == "B" then assert.are.equal(3, #ctx:recorded("command")) end
        end
        ctx:flush_reopen()
        assert.are.equal("Workspace Switcher", ctx.selector.title)
      end
    end
  )

  it("unloads only live targets and preserves state on failures", function()
    ctx:choose("B", "unload")
    assert.are.equal("B", ctx:recorded("save")[1][1])
    assert.are.equal(3, #ctx:recorded("command"))
    assert.are.equal(0, #ctx:recorded("delete"))
    assert.are.equal(2, ctx.fake.GLOBAL.workspace_access_times.B)
    assert.are.equal(1, #ctx:recorded(event_prefix .. "unloaded"))
    local order = {}
    for _, call in ipairs(ctx.calls) do
      if
        call.kind == "save"
        or call.kind == "command"
        or call.kind == event_prefix .. "unloaded"
      then
        table.insert(order, call.kind)
      end
    end
    assert.are.same({
      "save",
      "command",
      "command",
      "command",
      event_prefix .. "unloaded",
    }, order)

    for _, without_save in ipairs({ "disabled", "excluded" }) do
      ctx:reset()
      if without_save == "disabled" then
        ctx.settings.session_enabled = false
      else
        ctx.excluded = "B"
      end
      ctx:choose("B", "unload")
      assert.are.equal(0, #ctx:recorded("save"))
      assert.are.equal(3, #ctx:recorded("command"))
      assert.are.equal(1, #ctx:recorded(event_prefix .. "unloaded"))
      ctx:flush_reopen()
    end

    for _, failure in ipairs({ "save", "list", "kill" }) do
      ctx:reset()
      if failure == "save" then
        ctx.save_ok = false
      elseif failure == "list" then
        ctx.list_ok = false
      else
        ctx.kill_fail_id = 21
      end
      ctx:choose("B", "unload")
      assert.are.equal(0, #ctx:recorded(event_prefix .. "unloaded"))
      assert.are.equal(0, #ctx:recorded("delete"))
      assert.are.equal(2, ctx.fake.GLOBAL.workspace_access_times.B)
      assert.are.equal(
        failure == "save" and 0 or failure == "list" and 1 or 3,
        #ctx:recorded("command")
      )
      assert.is_true(#ctx:recorded("notify") >= 1)
      ctx:flush_reopen()
    end

    for _, id in ipairs({ "A", "Saved", "Custom" }) do
      ctx:reset()
      ctx:choose(id, "unload")
      assert.are.equal(0, #ctx:recorded("save"))
      assert.are.equal(0, #ctx:recorded("command"))
      assert.are.equal(1, #ctx:recorded("notify"))
      ctx:flush_reopen()
    end
  end)

  it("renames live and saved targets and merges live workspaces", function()
    for _, id in ipairs({ "B", "Saved" }) do
      ctx:reset()
      ctx:choose(id, "rename")
      ctx.prompt.action(ctx.window, ctx.pane, "Renamed")
      assert.are.equal(id == "B" and 1 or 0, #ctx:recorded("rename"))
      assert.are.equal(id, ctx:recorded("rename_state")[1][1])
      assert.are.equal(
        id == "B" and 2 or 3,
        ctx.fake.GLOBAL.workspace_access_times.Renamed
      )
      ctx:flush_reopen()
    end

    ctx:reset()
    ctx:choose("B", "rename")
    ctx.prompt.action(ctx.window, ctx.pane, "A")
    assert.are.equal("A", ctx:recorded("move_window")[1][1])
    ctx:flush_reopen()

    ctx:reset()
    ctx:choose("Custom", "rename")
    assert.is_nil(ctx.prompt)
    assert.are.equal(1, #ctx:recorded("notify"))
    ctx:flush_reopen()
  end)
end)
