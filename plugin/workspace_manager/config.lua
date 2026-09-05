local wezterm = require("wezterm") --[[@as Wezterm]]
local mux = wezterm.mux
local settings = require("workspace_manager.settings")
local theme = require("workspace_manager.theme")
local helpers = require("workspace_manager.helpers")
local history = require("workspace_manager.history")
local state = require("workspace_manager.state")
local actions = require("workspace_manager.actions")

local M = {}

---Formats the configured in-switcher action legend.
---@return string
function M.get_switcher_legend()
  local hints = actions.build_switcher_hints("  ")
  local text = hints ~= "" and ("  " .. hints .. "  Esc=cancel")
    or "  Esc=cancel"
  return theme.format({
    { text = text, style = theme.get_color("muted") },
  })
end

---Registers workspace tracking, session persistence, and switcher keys.
---@param config Config
function M.apply_to_config(config)
  -- Plugin actions track switches directly. Observe external switches too:
  -- WezTerm can reuse a focused GUI window without a focus-change event.
  ---Tracks an externally activated workspace when its GUI window is focused.
  ---@param window? Window
  local function track_workspace(window)
    if not window or not window:is_focused() then return end
    history.record_workspace_switch(
      wezterm.GLOBAL.last_focused_workspace,
      mux.get_active_workspace()
    )
  end
  wezterm.on("window-focus-changed", track_workspace)
  wezterm.on("update-status", track_workspace)

  -- Session persistence setup
  if settings.session_enabled then
    -- Apply max scrollback lines config
    local pane_tree_mod = require("workspace_manager.session.pane_tree")
    pane_tree_mod.max_nlines = settings.session_max_scrollback_lines

    -- Periodic save timer
    if settings.session_periodic_save_interval then
      ---Schedules the next session save after the configured interval.
      local function periodic_save()
        wezterm.time.call_after(
          settings.session_periodic_save_interval,
          function()
            if settings.session_periodic_save_all then
              for _, ws_name in ipairs(mux.get_workspace_names()) do
                if not state.is_excluded_workspace(ws_name) then
                  state.save_workspace_state(ws_name)
                end
              end
            else
              local active = mux.get_active_workspace()
              if active and not state.is_excluded_workspace(active) then
                state.save_workspace_state(active)
              end
            end
            periodic_save()
          end
        )
      end
      periodic_save()
    end

    -- Restore most recently used workspace on startup
    if settings.session_restore_on_startup then
      wezterm.on("gui-startup", function(_cmd)
        local workspace_name = state.get_most_recent_saved_workspace()
        if not workspace_name then return end
        local ws_state = state.load_workspace_state(workspace_name)
        if not ws_state then return end
        local _, expanded = helpers.normalize_workspace_name(workspace_name)

        local ws = ws_state.window_states and ws_state.window_states[1]
        local has_saved_pixels = ws
          and ws.window_pixel_width
          and ws.window_pixel_height
        -- Spawn window first; startup restore will wait for geometry to settle
        -- and then restore panes to avoid post-restore split reflow.
        local spawn_args = { workspace = workspace_name, cwd = expanded }
        if not has_saved_pixels and ws and ws.size then
          spawn_args.width = ws.size.cols
          spawn_args.height = ws.size.rows
        end
        local _, _, window = mux.spawn_window(spawn_args)
        history.record_workspace_switch(nil, workspace_name)

        ---Restores the saved layout after startup window geometry stabilizes.
        local function do_restore()
          state.restore_workspace_state(workspace_name, window, {
            relative = true,
            close_open_panes = true,
            resize_window = false,
            defer_pane_restore = true,
          })
          history.update_access_time(workspace_name)
        end

        state.wait_for_stable_window(window, 0.10, 2, 15, function()
          if has_saved_pixels then
            local ok, err = pcall(function()
              local gui_win = window:gui_window()
              if gui_win then
                gui_win:set_inner_size(
                  ws.window_pixel_width,
                  ws.window_pixel_height
                )
              else
                error("missing gui_window while applying startup pixel size")
              end
            end)
            if not ok then
              wezterm.log_warn(
                "workspace_manager: failed to apply startup pixel size: "
                  .. tostring(err)
              )
              do_restore()
              return
            end
            state.wait_for_stable_window(
              window,
              0.10,
              2,
              8,
              function() do_restore() end
            )
            return
          end
          do_restore()
        end)
      end)
    end
  end

  -- Key table for in-switcher actions (built from M.switcher_keys config)
  config.key_tables = config.key_tables or {}
  config.key_tables.workspace_switcher_actions =
    actions.build_switcher_key_table()
end

---Appends the plugin's default workspace key assignments.
---@param config Config
function M.apply_default_keybindings(config)
  -- Default keybindings (users can override by setting their own keys)
  local keys = config.keys or {}

  table.insert(keys, {
    key = "s",
    mods = "LEADER",
    action = actions.workspace_switcher(),
  })

  table.insert(keys, {
    key = "S",
    mods = "LEADER",
    action = actions.last_workspace(),
  })

  table.insert(keys, {
    key = "]",
    mods = "CTRL",
    action = actions.next_workspace(),
  })

  table.insert(keys, {
    key = "[",
    mods = "CTRL",
    action = actions.previous_workspace(),
  })

  config.keys = keys
end

return M
