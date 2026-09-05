local modules = require("helpers.modules")
local fake_wezterm = require("helpers.fake_wezterm")

describe("plugin entrypoint", function()
  local original_package_path

  local function install_wezterm(plugin_list)
    local fake = fake_wezterm.new({
      GLOBAL = { workspace_access_times = {} },
      mux = {},
      target_triple = "x86_64-unknown-linux-gnu",
      plugin = { list = plugin_list },
    }).wezterm
    package.loaded.wezterm = fake
    return fake
  end

  local function load_plugin(options)
    local chunk, err = loadfile("plugin/init.lua")
    assert(chunk, err)
    return chunk(options)
  end

  before_each(function()
    original_package_path = package.path
    modules.reset()
  end)

  after_each(function()
    modules.reset()
    package.path = original_package_path
  end)

  it(
    "loads namespaced modules from an explicit development directory",
    function()
      install_wezterm(
        function() error("plugin list should not be inspected") end
      )

      local plugin = load_plugin({ plugin_dir = "./plugin" })

      assert.are.equal("./plugin/?.lua;", package.path:sub(1, 15))
      assert.are.equal(plugin, require("workspace_manager.settings"))
      assert.are.equal("zoxide", plugin.zoxide_path)
      assert.is_false(plugin.session_enabled)
      for _, name in ipairs({
        "workspace_switcher",
        "last_workspace",
        "next_workspace",
        "previous_workspace",
        "unload_current_workspace",
        "rename_current_workspace",
        "save_workspace",
        "apply_to_config",
        "get_switcher_legend",
        "get_zoxide_paths",
      }) do
        assert.are.equal("function", type(plugin[name]), name)
      end
    end
  )

  it("discovers the installed plugin directory", function()
    install_wezterm(
      function()
        return {
          { url = "https://example.test/unrelated", plugin_dir = "./other" },
          {
            url = "https://example.test/workspace-manager.wezterm",
            plugin_dir = ".",
          },
        }
      end
    )

    load_plugin()

    assert.are.equal("./plugin/?.lua;", package.path:sub(1, 15))
  end)

  it("shares settings with dependencies and keeps session code lazy", function()
    install_wezterm(function() return {} end)
    local plugin = load_plugin({ plugin_dir = "./plugin" })

    plugin.colors = { muted = "Blue" }

    local theme = require("workspace_manager.theme")
    assert.are.equal("Blue", theme.get_color("muted"))
    assert.is_nil(package.loaded["workspace_manager.session.workspace_state"])
    assert.is_nil(package.loaded["workspace_manager.session.tab_state"])
    assert.is_nil(package.loaded["workspace_manager.session.file_io"])
  end)
end)
