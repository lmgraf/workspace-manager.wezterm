local modules = require("helpers.modules")
local fixture = require("helpers.previous_workspace_fixture")

describe("previous workspace tracking", function()
  local ctx

  before_each(function() ctx = fixture.new() end)
  after_each(modules.reset)

  local function check_pair(active, previous)
    assert.are.equal(active, ctx.current)
    assert.are.equal(active, ctx.fake.GLOBAL.last_focused_workspace)
    assert.are.equal(previous, ctx.fake.GLOBAL.previous_workspace)
  end

  it("tracks first switches, repeated toggles, and cycle actions", function()
    check_pair("A", nil)
    ctx.toggle(ctx.window, ctx.pane)
    assert.are.equal(0, ctx.switch_count)
    ctx.next_workspace(ctx.window, ctx.pane)
    check_pair("B", "A")
    ctx.toggle(ctx.window, ctx.pane)
    check_pair("A", "B")
    ctx.toggle(ctx.window, ctx.pane)
    check_pair("B", "A")
    ctx.previous_workspace(ctx.window, ctx.pane)
    check_pair("A", "B")
    ctx.next_workspace(ctx.window, ctx.pane)
    ctx.toggle(ctx.window, ctx.pane)
    check_pair("A", "B")
  end)

  it("returns from A to B after switching through C without focus events", function()
    ctx.next_workspace(ctx.window, ctx.pane)
    ctx.next_workspace(ctx.window, ctx.pane)
    check_pair("C", "B")
    ctx.toggle(ctx.window, ctx.pane)
    check_pair("B", "C")
    ctx.events["window-focus-changed"](ctx.window, ctx.pane)
    ctx.events["update-status"](ctx.window, ctx.pane)
    check_pair("B", "C")
    ctx.toggle(ctx.window, ctx.pane)
    check_pair("C", "B")
  end)

  it("does not let focus callbacks overwrite an in-flight switch", function()
    ctx.focus_during_switch = true
    ctx.next_workspace(ctx.window, ctx.pane)
    ctx.toggle(ctx.window, ctx.pane)
    ctx.events["window-focus-changed"](ctx.window, ctx.pane)
    check_pair("A", "B")
  end)

  it("tracks every live, saved, custom, path, and new switcher route", function()
    for _, name in ipairs({ "B", "Saved", "Custom", "~/project" }) do
      ctx:reset()
      ctx:select_workspace(name)
      check_pair(name, "A")
      ctx.toggle(ctx.window, ctx.pane)
      check_pair("A", name)
    end

    for _, mode in ipairs({ "new", "new_at_path" }) do
      ctx:reset()
      ctx.actions.workspace_switcher()(ctx.window, ctx.pane)
      ctx.actions.switcher_keymap("n", "CTRL", mode).action(
        ctx.window,
        ctx.pane
      )
      ctx.selector(ctx.window, ctx.pane, "B", "B")
      assert.is_function(ctx.prompt)
      ctx.prompt(ctx.window, ctx.pane, "Created")
      check_pair("Created", "A")
      ctx.toggle(ctx.window, ctx.pane)
      check_pair("A", "Created")
    end
  end)

  it("preserves the target after cancellation, reselection, and failure", function()
    ctx.next_workspace(ctx.window, ctx.pane)
    ctx.actions.workspace_switcher()(ctx.window, ctx.pane)
    ctx.selector(ctx.window, ctx.pane, nil, nil)
    check_pair("B", "A")

    ctx.settings.show_current_workspace_in_switcher = true
    ctx:select_workspace("B")
    check_pair("B", "A")

    ctx.fail_switch = true
    assert.has_error(function() ctx.toggle(ctx.window, ctx.pane) end)
    check_pair("B", "A")
  end)

  it("observes external changes only from a focused window", function()
    ctx.current, ctx.focused = "B", false
    ctx.events["window-focus-changed"](ctx.window, ctx.pane)
    ctx.events["update-status"](ctx.window, ctx.pane)
    assert.is_nil(ctx.fake.GLOBAL.previous_workspace)
    assert.are.equal("A", ctx.fake.GLOBAL.last_focused_workspace)

    ctx.focused = true
    ctx.events["update-status"](ctx.window, ctx.pane)
    check_pair("B", "A")
    for _ = 1, 3 do ctx.events["update-status"](ctx.window, ctx.pane) end
    check_pair("B", "A")

    ctx.current = "C"
    ctx.events["window-focus-changed"]({
      is_focused = function() return true end,
      active_workspace = function() return "A" end,
    }, ctx.pane)
    check_pair("C", "B")
    ctx.toggle(ctx.window, ctx.pane)
    check_pair("B", "C")
  end)

  it("does not rewind history when startup restoration finishes late", function()
    ctx.settings.session_enabled = true
    ctx.settings.session_restore_on_startup = true
    package.loaded["session.pane_tree"] = {}
    ctx.fake.mux.spawn_window = function(opts)
      ctx.current = opts.workspace
      return {}, ctx.pane, {}
    end
    ctx.config.apply_to_config({})

    ctx.events["gui-startup"]()
    check_pair("B", nil)
    ctx.next_workspace(ctx.window, ctx.pane)
    check_pair("C", "B")
    assert.is_function(ctx.pending_restore)
    ctx.pending_restore()
    check_pair("C", "B")
  end)
end)
