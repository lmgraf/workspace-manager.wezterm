local wezterm = require("wezterm") --[[@as Wezterm]]
local act = wezterm.action
local mux = wezterm.mux
local settings = require("workspace_manager.settings")
local theme = require("workspace_manager.theme")
local helpers = require("workspace_manager.helpers")
local history = require("workspace_manager.history")
local state = require("workspace_manager.state")
local data = require("workspace_manager.data")

local M = {}

---@class WorkspaceManagerResolvedKeyBinding: WorkspaceManagerKeyBinding
---@field mods string
---@field hint string
---@field action_name WorkspaceManagerSwitcherAction

---@class WorkspaceManagerSwitcherKeyEntry
---@field key string
---@field mods string
---@field action KeyAssignment

---@class WorkspaceManagerSwitchOptions
---@field name string
---@field spawn? { cwd?: string }

---@class WorkspaceManagerSwitcherContext
---@field workspace_choices WorkspaceManagerWorkspaceChoice[]
---@field custom_choices WorkspaceManagerSuggestionChoice[]
---@field is_zoxide boolean
---@field label_overrides table<string, string>
---@field workspace_counts? table<string, WorkspaceManagerCounts>
---@field current_workspace string
---@field current_display string
---@field existing_workspace_ids table<string, boolean>
---@field saved_workspace_ids table<string, boolean>
---@field custom_entry_map table<string, WorkspaceManagerSuggestionChoice>

---@class WorkspaceManagerDisplayChoice
---@field id string
---@field label string

-- ============================================================================
-- Switcher Key Configuration
-- ============================================================================

-- Default in-switcher action key bindings. Single source of truth — key table,
-- description hints, and legend are all generated from this.
---@type table<WorkspaceManagerSwitcherAction, WorkspaceManagerKeyBinding>
local DEFAULT_SWITCHER_KEYS = {
  delete = { key = "d", mods = "CTRL", hint = "del" },
  unload = { key = "u", mods = "CTRL", hint = "unload" },
  new = { key = "n", mods = "CTRL", hint = "new" },
  new_at_path = { key = "p", mods = "CTRL", hint = "path" },
  rename = { key = "r", mods = "CTRL", hint = "rename" },
}
-- Explicit order for deterministic hint text (pairs() order is undefined in Lua)
---@type WorkspaceManagerSwitcherAction[]
local SWITCHER_KEY_ORDER = {
  "delete",
  "unload",
  "new",
  "new_at_path",
  "rename",
}

---Returns the resolved switcher bindings in display order.
---Disabled actions are omitted.
---@return WorkspaceManagerResolvedKeyBinding[]
local function get_resolved_switcher_keys()
  local result = {}
  local user_keys = settings.switcher_keys or {}
  for _, action_name in ipairs(SWITCHER_KEY_ORDER) do
    local override = user_keys[action_name]
    local def = DEFAULT_SWITCHER_KEYS[action_name]
    if override == false then
      -- explicitly disabled
    elseif override == nil then
      table.insert(result, {
        key = def.key,
        mods = def.mods,
        hint = def.hint,
        action_name = action_name,
      })
    else
      table.insert(result, {
        key = override.key,
        mods = override.mods or "NONE",
        hint = override.hint or def.hint,
        action_name = action_name,
      })
    end
  end
  return result
end

---Converts a binding to a short display string such as `^D`.
---@param binding WorkspaceManagerResolvedKeyBinding
---@return string
local function format_key_hint(binding)
  local mods = binding.mods or "NONE"
  local prefix = ""
  if mods:find("CTRL") then prefix = prefix .. "^" end
  if mods:find("ALT") or mods:find("META") then prefix = prefix .. "M-" end
  if mods:find("SHIFT") then prefix = prefix .. "S-" end
  local key = binding.key
  -- Single-char CTRL-only keys use uppercase convention (^D not ^d)
  if prefix == "^" and #key == 1 then key = key:upper() end
  return prefix .. key
end

---Builds the configured switcher-action hint text.
---@param separator? string text between entries; defaults to two spaces
---@return string
function M.build_switcher_hints(separator)
  separator = separator or "  "
  local parts = {}
  for _, binding in ipairs(get_resolved_switcher_keys()) do
    table.insert(parts, format_key_hint(binding) .. "=" .. binding.hint)
  end
  return table.concat(parts, separator)
end

---Builds the workspace switcher's key-table entries.
---Enter and Escape are always included.
---@return WorkspaceManagerSwitcherKeyEntry[]
function M.build_switcher_key_table()
  local entries = { M.switcher_keymap_cancel("Enter") }
  for _, binding in ipairs(get_resolved_switcher_keys()) do
    table.insert(
      entries,
      M.switcher_keymap(binding.key, binding.mods, binding.action_name)
    )
  end
  table.insert(entries, M.switcher_keymap_cancel("Escape"))
  return entries
end

-- ============================================================================
-- Switcher State
-- ============================================================================

---@class WorkspaceManagerSwitcherState
---@field pending_action? WorkspaceManagerSwitcherAction

---Tracks which action the key table intercepted for callback dispatch.
---@type WorkspaceManagerSwitcherState
local switcher_state = {
  pending_action = nil,
}

---Creates a switcher key entry that dispatches a configured action.
---@param key string
---@param mods string
---@param action WorkspaceManagerSwitcherAction
---@return WorkspaceManagerSwitcherKeyEntry
function M.switcher_keymap(key, mods, action)
  return {
    key = key,
    mods = mods,
    action = wezterm.action_callback(function(window, pane)
      switcher_state.pending_action = action
      window:perform_action(act.PopKeyTable, pane)
      window:perform_action(act.SendKey({ key = "Enter" }), pane)
    end),
  }
end

---Creates a key entry that forwards selection or cancellation.
---@param key string
---@param mods? string
---@return WorkspaceManagerSwitcherKeyEntry
function M.switcher_keymap_cancel(key, mods)
  return {
    key = key,
    mods = mods or "NONE",
    action = wezterm.action_callback(function(window, pane)
      switcher_state.pending_action = nil
      window:perform_action(act.PopKeyTable, pane)
      window:perform_action(act.SendKey({ key = key }), pane)
    end),
  }
end

-- ============================================================================
-- Action Handlers
-- ============================================================================

---Switches workspaces and records the transition in history.
---@param window Window
---@param pane Pane
---@param opts WorkspaceManagerSwitchOptions
local function switch_workspace(window, pane, opts)
  local old_workspace = window:active_workspace()
  window:perform_action(act.SwitchToWorkspace(opts), pane)
  history.record_workspace_switch(old_workspace, opts.name)
end

---Closes all panes belonging to a workspace.
---@param workspace_name string
---@param window Window
---@return boolean
local function close_workspace_panes(workspace_name, window)
  wezterm.log_info(
    "workspace_manager: close_workspace_panes called for: "
      .. tostring(workspace_name)
  )

  local wezterm_path = helpers.get_wezterm_path()
  if not wezterm_path then
    wezterm.log_warn("workspace_manager: wezterm_path not found")
    helpers.notify(
      window,
      "Workspace Manager",
      "Failed to detect wezterm path. Please set wezterm_path manually.",
      4000
    )
    return false
  end

  local current_workspace = window:active_workspace()
  wezterm.log_info(
    "workspace_manager: current_workspace="
      .. tostring(current_workspace)
      .. " target="
      .. tostring(workspace_name)
  )

  if workspace_name == current_workspace then
    wezterm.log_warn(
      "workspace_manager: blocked — cannot close active workspace"
    )
    helpers.notify(window, "Workspace", "Cannot close active workspace")
    return false
  end

  -- Get all panes via CLI (most reliable method)
  local success, stdout, stderr = wezterm.run_child_process({
    wezterm_path,
    "cli",
    "list",
    "--format=json",
  })

  if not success then
    wezterm.log_warn("workspace_manager: cli list failed: " .. tostring(stderr))
    helpers.notify(
      window,
      "Workspace",
      "Failed to list panes: " .. tostring(stderr),
      4000
    )
    return false
  end

  local parse_ok, panes = pcall(
    function() return wezterm.json_parse(stdout) end
  )
  if not parse_ok or type(panes) ~= "table" then
    wezterm.log_warn(
      "workspace_manager: failed to parse pane list: " .. tostring(panes)
    )
    helpers.notify(window, "Workspace", "Failed to parse pane list", 4000)
    return false
  end
  local panes_to_kill = {}

  -- Diagnostic: dump all workspace names seen in cli list output
  local ws_names_seen = {}
  for _, p in ipairs(panes) do
    ws_names_seen[p.workspace or "nil"] = true
  end
  local ws_list = {}
  for k in pairs(ws_names_seen) do
    table.insert(ws_list, '"' .. k .. '"')
  end
  wezterm.log_info(
    "workspace_manager: workspaces in cli list: " .. table.concat(ws_list, ", ")
  )
  wezterm.log_info(
    'workspace_manager: looking for workspace: "' .. workspace_name .. '"'
  )

  for _, p in ipairs(panes) do
    if p.workspace == workspace_name then
      table.insert(panes_to_kill, p.pane_id)
    end
  end

  wezterm.log_info(
    "workspace_manager: found "
      .. #panes_to_kill
      .. " panes to kill in workspace: "
      .. workspace_name
  )

  if #panes_to_kill == 0 then
    wezterm.log_warn(
      "workspace_manager: no panes found for workspace: " .. workspace_name
    )
    helpers.notify(window, "Workspace", "No panes found in workspace")
    return false
  end

  if #panes_to_kill > 1 then
    helpers.notify(
      window,
      "Workspace",
      "Closing " .. #panes_to_kill .. " panes in: " .. workspace_name
    )
  end

  -- Kill each pane, but continue after failures so every pane gets an attempt.
  local failed = 0
  for _, pane_id in ipairs(panes_to_kill) do
    local kill_ok, _, kill_err = wezterm.run_child_process({
      wezterm_path,
      "cli",
      "kill-pane",
      "--pane-id=" .. tostring(pane_id),
    })
    if kill_ok then
      wezterm.log_info("workspace_manager: killed pane " .. tostring(pane_id))
    else
      failed = failed + 1
      wezterm.log_warn(
        "workspace_manager: failed to kill pane "
          .. tostring(pane_id)
          .. ": "
          .. tostring(kill_err)
      )
    end
  end

  if failed > 0 then
    helpers.notify(
      window,
      "Workspace",
      "Failed to close "
        .. failed
        .. " of "
        .. #panes_to_kill
        .. " panes in: "
        .. workspace_name,
      4000
    )
    return false
  end
  return true
end

---Saves a workspace before unloading it when session persistence applies.
---@param workspace_name string
---@param notification_window Window
---@param gui_window? Window
---@return boolean
local function save_workspace_for_unload(
  workspace_name,
  notification_window,
  gui_window
)
  local should_save = settings.session_enabled
    and not state.is_excluded_workspace(workspace_name)
  if not should_save then return true end

  local save_ok, save_err =
    state.save_workspace_state(workspace_name, gui_window)
  if save_ok then return true end

  wezterm.log_warn(
    "workspace_manager: refusing to unload '"
      .. workspace_name
      .. "' because save failed: "
      .. tostring(save_err)
  )
  helpers.notify(
    notification_window,
    "Workspace",
    "Failed to save; workspace was not unloaded",
    4000
  )
  return false
end

---@class WorkspaceManagerUnloadOptions
---@field gui_window? Window GUI context used to capture active window dimensions.
---@field before_close? fun() Work to perform after saving and before closing panes.

---Saves, closes, and emits the completion event for a workspace unload.
---@param workspace_name string
---@param window Window
---@param pane Pane
---@param opts? WorkspaceManagerUnloadOptions
---@return boolean
local function unload_workspace(workspace_name, window, pane, opts)
  opts = opts or {}
  if not save_workspace_for_unload(workspace_name, window, opts.gui_window) then
    return false
  end

  if opts.before_close then opts.before_close() end
  if not close_workspace_panes(workspace_name, window) then return false end

  wezterm.emit(
    "workspace_manager.workspace_switcher.unloaded",
    window,
    pane,
    workspace_name
  )
  return true
end

---Removes a workspace from persisted access history.
---@param workspace_name string
local function remove_workspace_history(workspace_name)
  local normalized = helpers.normalize_workspace_name(workspace_name)
  if wezterm.GLOBAL.workspace_access_times then
    wezterm.GLOBAL.workspace_access_times[normalized] = nil
    history.save(wezterm.GLOBAL.workspace_access_times)
  end
end

---Renames or merges a workspace and its persisted state.
---@param old_name string
---@param new_name? string
---@param window Window
---@param pane Pane
local function do_rename_workspace(old_name, new_name, window, pane)
  if not new_name or new_name == "" or new_name == old_name then return end

  local new_normalized = helpers.normalize_workspace_name(new_name)

  -- Check if target name already exists (merge scenario)
  local name_exists = false
  for _, ws in ipairs(mux.get_workspace_names()) do
    local ws_normalized = helpers.normalize_workspace_name(ws)
    if ws_normalized == new_normalized then
      name_exists = true
      break
    end
  end

  if name_exists then
    helpers.notify(
      window,
      "Workspace Rename",
      'Merging "' .. old_name .. '" into existing "' .. new_normalized .. '"',
      3000
    )
    -- For merge: move windows to existing workspace
    for _, mux_win in ipairs(mux.all_windows()) do
      if mux_win:get_workspace() == old_name then
        mux_win:set_workspace(new_normalized)
      end
    end
  else
    -- Only rename in mux if the workspace actually exists there (saved-only workspaces don't)
    local old_exists_in_mux = false
    for _, ws in ipairs(mux.get_workspace_names()) do
      if ws == old_name then
        old_exists_in_mux = true
        break
      end
    end
    if old_exists_in_mux then mux.rename_workspace(old_name, new_normalized) end
  end

  -- Update history
  local old_normalized = helpers.normalize_workspace_name(old_name)
  if wezterm.GLOBAL.workspace_access_times then
    local old_time = wezterm.GLOBAL.workspace_access_times[old_normalized]
    wezterm.GLOBAL.workspace_access_times[old_normalized] = nil
    wezterm.GLOBAL.workspace_access_times[new_normalized] = old_time
      or os.time()
    history.save(wezterm.GLOBAL.workspace_access_times)
  end

  -- Rename state file if it exists
  if settings.session_enabled then
    state.rename_workspace_state(old_name, new_normalized)
  end

  helpers.notify(
    window,
    "Workspace Rename",
    'Renamed "' .. old_name .. '" to "' .. new_normalized .. '"'
  )
  wezterm.emit(
    "workspace_manager.workspace_switcher.renamed",
    window,
    pane,
    old_name,
    new_normalized
  )
end

-- ============================================================================
-- Switcher Choices
-- ============================================================================

---Builds the unformatted choice collections used by the switcher.
---@param window Window
---@return WorkspaceManagerSwitcherContext
local function build_switcher_context(window)
  local workspace_choices
  if settings.workspace_switcher_sort == "alphabetical" then
    workspace_choices = data.get_workspace_choices_alphabetical()
  else
    workspace_choices = data.get_workspace_choices()
  end

  local workspace_normalized_set = {}
  for _, choice in ipairs(workspace_choices) do
    workspace_normalized_set[choice.normalized] = true
  end
  local custom_choices, is_zoxide, label_overrides =
    data.get_custom_choices(workspace_normalized_set)

  local workspace_counts
  if settings.workspace_count_format then
    workspace_counts = data.get_workspace_counts()
  end

  local current_workspace = window:active_workspace()
  local current_normalized = helpers.normalize_workspace_name(current_workspace)
  local context = {
    workspace_choices = workspace_choices,
    custom_choices = custom_choices,
    is_zoxide = is_zoxide,
    label_overrides = label_overrides,
    workspace_counts = workspace_counts,
    current_workspace = current_workspace,
    current_display = label_overrides[current_workspace] or current_normalized,
    existing_workspace_ids = {},
    saved_workspace_ids = {},
    custom_entry_map = {},
  }
  for _, choice in ipairs(workspace_choices) do
    if choice.is_saved then
      context.saved_workspace_ids[choice.id] = true
    else
      context.existing_workspace_ids[choice.id] = true
    end
  end
  for _, choice in ipairs(custom_choices) do
    context.custom_entry_map[choice.id] = choice
  end
  return context
end

---Returns the configured choice predicate, if any.
---@return WorkspaceManagerChoiceFilter?
local function get_switcher_filter()
  if type(settings.filter_choices) == "function" then
    return settings.filter_choices
  end
  if type(settings.filter_choices) == "table" then
    local set = {}
    for _, path in ipairs(settings.filter_choices) do
      set[helpers.normalize_workspace_name(path)] = true
    end
    return function(choice)
      if choice.is_workspace then return true end
      return set[choice.normalized] or false
    end
  end
end

---Formats a live or saved workspace for the switcher.
---@param context WorkspaceManagerSwitcherContext
---@param choice WorkspaceManagerWorkspaceChoice
---@param is_current boolean
---@return WorkspaceManagerDisplayChoice
local function format_workspace_choice(context, choice, is_current)
  local count_suffix = ""
  if context.workspace_counts and context.workspace_counts[choice.id] then
    count_suffix = data.format_counts(
      context.workspace_counts[choice.id],
      settings.workspace_count_format
    )
  end

  local display_label = context.label_overrides[choice.id] or choice.label
  local category = is_current and "current" or "workspace"
  if choice.is_saved and not is_current then category = "saved" end
  local ws_icon = settings.workspace_icon or "●"
  local icon = is_current and (settings.workspace_icon_current or ws_icon)
    or ws_icon
  if category == "saved" then icon = settings.workspace_icon_saved or "○" end
  return {
    id = choice.id,
    label = theme.build_switcher_label(
      icon,
      display_label,
      count_suffix,
      category
    ),
  }
end

---Builds all visible switcher choices in display order.
---@param context WorkspaceManagerSwitcherContext
---@return WorkspaceManagerDisplayChoice[]
local function build_switcher_choices(context)
  local filter = get_switcher_filter()
  local choices = {}
  local current_choices = {}
  local live_choices = {}
  local saved_choices = {}
  for _, choice in ipairs(context.workspace_choices) do
    local is_current = choice.id == context.current_workspace
    local is_visible = not is_current
      or settings.show_current_workspace_in_switcher
    if is_visible and (not filter or filter(choice)) then
      local group = is_current and current_choices
        or choice.is_saved and saved_choices
        or live_choices
      table.insert(group, format_workspace_choice(context, choice, is_current))
    end
  end
  for _, choice in ipairs(current_choices) do
    table.insert(choices, choice)
  end
  for _, choice in ipairs(live_choices) do
    table.insert(choices, choice)
  end
  for _, choice in ipairs(saved_choices) do
    table.insert(choices, choice)
  end
  for _, choice in ipairs(context.custom_choices) do
    if not filter or filter(choice) then
      table.insert(choices, {
        id = choice.id,
        label = theme.build_switcher_label(
          settings.entry_icon or "·",
          choice.label,
          "",
          "entry"
        ),
      })
    end
  end
  return choices
end

---Builds normal and fuzzy-mode switcher descriptions.
---@param current_display string
---@return string description
---@return string fuzzy_description
local function build_switcher_descriptions(current_display)
  local sep = " | "
  local accent = theme.get_color("prompt_accent")
  local muted = theme.get_color("muted")

  local prefix = ""
  if settings.show_switcher_hints then
    local hints = M.build_switcher_hints(" ")
    if hints ~= "" then prefix = hints .. sep end
  end

  local workspace_item = nil
  local normal_prefix = "Enter=switch" .. sep
  local fuzzy_prefix = ""

  if settings.show_current_workspace_hint then
    workspace_item = { text = current_display, style = accent }
    normal_prefix = sep
    fuzzy_prefix = sep
  end

  local normal = theme.format({
    workspace_item,
    { text = normal_prefix .. prefix .. "Esc=cancel", style = muted },
  })

  local fuzzy = theme.format({
    workspace_item,
    { text = fuzzy_prefix .. prefix .. "Switch to: ", style = muted },
  })

  return normal, fuzzy
end

-- ============================================================================
-- Switcher Actions
-- ============================================================================

---Reopens the workspace switcher after a nested action.
---@param window Window
---@param pane Pane
local function reopen_switcher(window, pane)
  wezterm.time.call_after(
    0.1,
    function() window:perform_action(M.workspace_switcher(), pane) end
  )
end

---Saves and announces the source before switching workspaces.
---@param window Window
---@param pane Pane
---@param opts WorkspaceManagerSwitchOptions
local function switch_from_switcher(window, pane, opts)
  local old_workspace = window:active_workspace()
  if
    settings.session_enabled
    and old_workspace
    and not state.is_excluded_workspace(old_workspace)
  then
    state.save_workspace_state(old_workspace, window)
  end
  if old_workspace then
    local old_mux_window = data.get_current_mux_window(old_workspace)
    wezterm.emit(
      "workspace_manager.workspace_switcher.switching",
      old_mux_window,
      pane,
      old_workspace,
      opts.name
    )
  end
  switch_workspace(window, pane, opts)
  history.update_access_time(opts.name)
end

---Finishes workspace creation and emits the creation event.
---@param pane Pane
---@param workspace_name string
---@param ... string?
local function finish_workspace_creation(pane, workspace_name, ...)
  local new_mux_window = data.get_current_mux_window(workspace_name)
  if settings.session_enabled then
    state.restore_workspace_state(workspace_name, new_mux_window)
  end
  wezterm.emit(
    "workspace_manager.workspace_switcher.created",
    new_mux_window,
    pane,
    workspace_name,
    ...
  )
end

---Restores focus to the window focused when a workspace was saved.
---@param workspace_name string
local function restore_workspace_focus(workspace_name)
  if
    not settings.session_enabled or state.is_excluded_workspace(workspace_name)
  then
    return
  end
  local saved = state.load_workspace_state(workspace_name)
  if not saved or not saved.window_states then return end

  local all_mux_wins = mux.all_windows()
  for _, ws in ipairs(saved.window_states) do
    if ws.is_focused and ws.window_id then
      for _, mux_win in ipairs(all_mux_wins) do
        if
          mux_win:get_workspace() == workspace_name
          and mux_win:window_id() == ws.window_id
        then
          local ok, gui_win = pcall(function() return mux_win:gui_window() end)
          if ok and gui_win then gui_win:focus() end
          break
        end
      end
      break
    end
  end
end

---Selects an existing live workspace.
---@param window Window
---@param pane Pane
---@param workspace_name string
local function select_live_workspace(window, pane, workspace_name)
  switch_from_switcher(window, pane, { name = workspace_name })
  local new_mux_window = data.get_current_mux_window(workspace_name)
  restore_workspace_focus(workspace_name)
  wezterm.emit(
    "workspace_manager.workspace_switcher.selected",
    new_mux_window,
    pane,
    workspace_name
  )
end

---Selects and restores a saved-only workspace.
---@param window Window
---@param pane Pane
---@param workspace_name string
local function select_saved_workspace(window, pane, workspace_name)
  switch_from_switcher(window, pane, { name = workspace_name })
  local new_mux_window = data.get_current_mux_window(workspace_name)
  state.restore_workspace_state(workspace_name, new_mux_window)
  wezterm.emit(
    "workspace_manager.workspace_switcher.created",
    new_mux_window,
    pane,
    workspace_name
  )
end

---Creates a workspace from a configured or zoxide suggestion.
---@param context WorkspaceManagerSwitcherContext
---@param window Window
---@param pane Pane
---@param id string
local function select_custom_entry(context, window, pane, id)
  local entry = context.custom_entry_map[id]
  local workspace_name, expanded_path
  if entry and entry.name then
    workspace_name = entry.name
    if entry.has_path then
      _, expanded_path = helpers.normalize_workspace_name(entry.path)
    end
  else
    workspace_name, expanded_path = helpers.get_workspace_name_and_path(id)
  end

  switch_from_switcher(window, pane, {
    name = workspace_name,
    spawn = { cwd = expanded_path or wezterm.home_dir },
  })
  if context.is_zoxide then
    wezterm.run_child_process({ settings.zoxide_path, "add", "--", id })
  end
  finish_workspace_creation(pane, workspace_name, expanded_path)
end

---Deletes the selected saved or live workspace.
---@param context WorkspaceManagerSwitcherContext
---@param window Window
---@param pane Pane
---@param id string
local function delete_selected_workspace(context, window, pane, id)
  wezterm.log_info(
    "workspace_manager: switcher delete action, id=" .. tostring(id)
  )
  if id == window:active_workspace() then
    wezterm.log_warn(
      "workspace_manager: switcher blocked delete of active workspace"
    )
    helpers.notify(window, "Workspace", "Cannot delete active workspace")
  elseif context.saved_workspace_ids[id] then
    -- Saved-only workspace: remove its snapshot and history.
    wezterm.log_info("workspace_manager: deleting saved-only workspace: " .. id)
    remove_workspace_history(id)
    if settings.session_enabled then state.delete_workspace_state(id) end
    wezterm.emit(
      "workspace_manager.workspace_switcher.deleted",
      window,
      pane,
      id
    )
  elseif context.existing_workspace_ids[id] then
    if close_workspace_panes(id, window) then
      remove_workspace_history(id)
      if settings.session_enabled then
        state.delete_workspace_state(id)
        wezterm.log_info("workspace_manager: deleted saved state for: " .. id)
      end
      wezterm.emit(
        "workspace_manager.workspace_switcher.deleted",
        window,
        pane,
        id
      )
    end
  else
    helpers.notify(window, "Workspace", "Cannot delete: not a workspace")
  end
  reopen_switcher(window, pane)
end

---Saves and closes the selected live workspace.
---@param context WorkspaceManagerSwitcherContext
---@param window Window
---@param pane Pane
---@param id string
local function unload_selected_workspace(context, window, pane, id)
  wezterm.log_info(
    "workspace_manager: switcher unload action, id=" .. tostring(id)
  )
  if id == window:active_workspace() then
    wezterm.log_warn(
      "workspace_manager: switcher blocked unload of active workspace"
    )
    helpers.notify(window, "Workspace", "Cannot unload active workspace")
  elseif not context.existing_workspace_ids[id] then
    helpers.notify(window, "Workspace", "Cannot unload: not a live workspace")
  else
    unload_workspace(id, window, pane)
  end
  reopen_switcher(window, pane)
end

---Prompts for a replacement workspace name.
---@param window Window
---@param pane Pane
---@param id string
---@param on_complete? fun(window: Window, pane: Pane)
local function prompt_workspace_rename(window, pane, id, on_complete)
  window:perform_action(
    act.PromptInputLine({
      description = theme.format({
        {
          text = "Renaming: " .. helpers.normalize_workspace_name(id),
          style = theme.get_color("prompt_accent"),
        },
        { text = " | Enter new name:", style = theme.get_color("muted") },
      }),
      action = wezterm.action_callback(function(inner_win, inner_p, line)
        if line and line ~= "" then
          do_rename_workspace(id, line, inner_win, inner_p)
        end
        if on_complete then on_complete(inner_win, inner_p) end
      end),
    }),
    pane
  )
end

---Prompts to rename a workspace selected in the switcher.
---@param context WorkspaceManagerSwitcherContext
---@param window Window
---@param pane Pane
---@param id string
local function prompt_selected_workspace_rename(context, window, pane, id)
  if
    not context.existing_workspace_ids[id]
    and not context.saved_workspace_ids[id]
  then
    helpers.notify(window, "Workspace", "Cannot rename: not a workspace")
    reopen_switcher(window, pane)
    return
  end
  prompt_workspace_rename(window, pane, id, reopen_switcher)
end

---Prompts for a new workspace name.
---@param window Window
---@param pane Pane
local function prompt_workspace_name(window, pane)
  window:perform_action(
    act.PromptInputLine({
      description = wezterm.format(
        theme.build_heading("Enter name for new workspace:")
      ),
      action = wezterm.action_callback(function(inner_win, inner_p, line)
        if not line or line == "" then
          reopen_switcher(inner_win, inner_p)
          return
        end
        switch_from_switcher(inner_win, inner_p, {
          name = line,
          spawn = { cwd = wezterm.home_dir },
        })
        finish_workspace_creation(inner_p, line)
      end),
    }),
    pane
  )
end

---Confirms and creates a missing workspace directory.
---@param window Window
---@param pane Pane
---@param path string expanded path
---@param display_path string user-entered path
---@param on_ready fun()
local function confirm_directory_creation(
  window,
  pane,
  path,
  display_path,
  on_ready
)
  window:perform_action(
    act.InputSelector({
      title = "Create directory",
      description = theme.format({
        {
          text = "Directory does not exist: ",
          style = theme.get_color("prompt_heading"),
        },
        {
          text = helpers.normalize_workspace_name(display_path),
          style = theme.get_color("prompt_accent"),
        },
        {
          text = ". Create it?",
          style = theme.get_color("prompt_heading"),
        },
      }),
      fuzzy = false,
      choices = {
        { id = "yes", label = "Yes" },
        { id = "no", label = "No" },
      },
      action = wezterm.action_callback(function(confirm_win, _, id)
        if id ~= "yes" then return end
        local mkdir_ok, _, mkdir_err = helpers.create_directory(path)
        if mkdir_ok then
          on_ready()
        else
          wezterm.log_warn(
            "workspace_manager: mkdir failed for "
              .. path
              .. ": "
              .. tostring(mkdir_err)
          )
          helpers.notify(
            confirm_win,
            "Workspace",
            "Failed to create directory: " .. tostring(mkdir_err),
            4000
          )
        end
      end),
    }),
    pane
  )
end

---Creates a workspace rooted at a path, prompting to create it if needed.
---@param context WorkspaceManagerSwitcherContext
---@param window Window
---@param pane Pane
---@param path string
local function create_workspace_at_path(context, window, pane, path)
  local workspace_name, expanded_path =
    helpers.get_workspace_name_and_path(path)
  local function create_workspace()
    switch_from_switcher(window, pane, {
      name = workspace_name,
      spawn = { cwd = expanded_path },
    })
    if context.is_zoxide then
      wezterm.run_child_process({ settings.zoxide_path, "add", "--", path })
    end
    finish_workspace_creation(pane, workspace_name, expanded_path)
  end

  if helpers.directory_exists(expanded_path) then
    create_workspace()
  else
    confirm_directory_creation(
      window,
      pane,
      expanded_path,
      path,
      create_workspace
    )
  end
end

---Prompts for a new workspace path.
---@param context WorkspaceManagerSwitcherContext
---@param window Window
---@param pane Pane
local function prompt_workspace_path(context, window, pane)
  window:perform_action(
    act.PromptInputLine({
      description = wezterm.format(
        theme.build_heading("Enter path for new workspace:")
      ),
      action = wezterm.action_callback(function(inner_win, inner_p, line)
        if not line or line == "" then
          reopen_switcher(inner_win, inner_p)
          return
        end
        create_workspace_at_path(context, inner_win, inner_p, line)
      end),
    }),
    pane
  )
end

---Dispatches the selection or configured action that closed the switcher.
---@param context WorkspaceManagerSwitcherContext
---@param window Window
---@param pane Pane
---@param id? string
---@param label? string
local function handle_switcher_selection(context, window, pane, id, label)
  local pending = switcher_state.pending_action
  switcher_state.pending_action = nil
  if not id and not label then
    wezterm.emit("workspace_manager.switcher.canceled", window, pane)
    return
  end

  if pending == "delete" then
    delete_selected_workspace(context, window, pane, id)
  elseif pending == "unload" then
    unload_selected_workspace(context, window, pane, id)
  elseif pending == "rename" then
    prompt_selected_workspace_rename(context, window, pane, id)
  elseif pending == "new" then
    prompt_workspace_name(window, pane)
  elseif pending == "new_at_path" then
    prompt_workspace_path(context, window, pane)
  elseif context.existing_workspace_ids[id] then
    select_live_workspace(window, pane, id)
  elseif context.saved_workspace_ids[id] then
    select_saved_workspace(window, pane, id)
  else
    select_custom_entry(context, window, pane, id)
  end
end

-- ============================================================================
-- Exported Actions
-- ============================================================================

---Returns an action that opens the workspace switcher.
---@return KeyAssignment
function M.workspace_switcher()
  return wezterm.action_callback(function(window, pane)
    local context = build_switcher_context(window)
    local choices = build_switcher_choices(context)
    if #choices == 0 then
      helpers.notify(window, "Workspace", "No other workspaces available")
      return
    end
    local description, fuzzy_description =
      build_switcher_descriptions(context.current_display)

    switcher_state.pending_action = nil
    window:perform_action(
      act.ActivateKeyTable({
        name = "workspace_switcher_actions",
        one_shot = false,
      }),
      pane
    )
    wezterm.emit("workspace_manager.switcher.opened", window, pane)

    window:perform_action(
      act.InputSelector({
        title = "Workspace Switcher",
        description = description,
        fuzzy = settings.start_in_fuzzy_mode,
        fuzzy_description = fuzzy_description,
        choices = choices,
        action = wezterm.action_callback(
          function(win, p, id, label)
            handle_switcher_selection(context, win, p, id, label)
          end
        ),
      }),
      pane
    )
  end)
end

---Returns an action that switches to the last active workspace.
---@return KeyAssignment
function M.last_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local previous_workspace = wezterm.GLOBAL.previous_workspace

    if current_workspace == previous_workspace or previous_workspace == nil then
      return
    end

    -- Save current workspace state before switching
    if
      settings.session_enabled
      and not state.is_excluded_workspace(current_workspace)
    then
      state.save_workspace_state(current_workspace, window)
    end

    -- Emit pre-switch event with old workspace's MuxWindow
    local old_mux_window = data.get_current_mux_window(current_workspace)
    wezterm.emit(
      "workspace_manager.workspace_switcher.switching",
      old_mux_window,
      pane,
      current_workspace,
      previous_workspace
    )

    switch_workspace(window, pane, { name = previous_workspace })

    -- Emit post-switch event with new workspace's MuxWindow
    local new_mux_window = data.get_current_mux_window(previous_workspace)
    wezterm.emit(
      "workspace_manager.workspace_switcher.selected",
      new_mux_window,
      pane,
      previous_workspace
    )
  end)
end

---Returns an action that cycles to the next workspace.
---@return KeyAssignment
function M.next_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local choices = data.get_workspace_cycle_order()

    if #choices <= 1 then
      helpers.notify(window, "Workspace", "No other workspaces available")
      return
    end

    -- Find current workspace in the sorted list
    local current_index = nil
    for i, choice in ipairs(choices) do
      if choice.id == current_workspace then
        current_index = i
        break
      end
    end

    -- If not found, start from first (shouldn't happen but safe)
    if not current_index then current_index = 0 end

    -- Calculate next index with wrapping
    local next_index = (current_index % #choices) + 1
    local next_workspace = choices[next_index].id

    local old_workspace = window:active_workspace()

    -- Save old workspace state before switching
    if
      settings.session_enabled
      and not state.is_excluded_workspace(old_workspace)
    then
      state.save_workspace_state(old_workspace, window)
    end

    -- Emit pre-switch event with old workspace's MuxWindow
    local old_mux_window = data.get_current_mux_window(old_workspace)
    wezterm.emit(
      "workspace_manager.workspace_switcher.switching",
      old_mux_window,
      pane,
      old_workspace,
      next_workspace
    )

    switch_workspace(window, pane, { name = next_workspace })
    history.update_access_time(next_workspace)

    -- Emit post-switch event with new workspace's MuxWindow
    local new_mux_window = data.get_current_mux_window(next_workspace)
    wezterm.emit(
      "workspace_manager.workspace_switcher.selected",
      new_mux_window,
      pane,
      next_workspace
    )
  end)
end

---Returns an action that cycles to the previous workspace.
---@return KeyAssignment
function M.previous_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local choices = data.get_workspace_cycle_order()

    if #choices <= 1 then
      helpers.notify(window, "Workspace", "No other workspaces available")
      return
    end

    -- Find current workspace in the sorted list
    local current_index = nil
    for i, choice in ipairs(choices) do
      if choice.id == current_workspace then
        current_index = i
        break
      end
    end

    -- If not found, start from last
    if not current_index then current_index = 1 end

    -- Calculate previous index with wrapping
    local prev_index = current_index - 1
    if prev_index < 1 then prev_index = #choices end
    local prev_workspace = choices[prev_index].id

    local old_workspace = window:active_workspace()

    -- Save old workspace state before switching
    if
      settings.session_enabled
      and not state.is_excluded_workspace(old_workspace)
    then
      state.save_workspace_state(old_workspace, window)
    end

    -- Emit pre-switch event with old workspace's MuxWindow
    local old_mux_window = data.get_current_mux_window(old_workspace)
    wezterm.emit(
      "workspace_manager.workspace_switcher.switching",
      old_mux_window,
      pane,
      old_workspace,
      prev_workspace
    )

    switch_workspace(window, pane, { name = prev_workspace })
    history.update_access_time(prev_workspace)

    -- Emit post-switch event with new workspace's MuxWindow
    local new_mux_window = data.get_current_mux_window(prev_workspace)
    wezterm.emit(
      "workspace_manager.workspace_switcher.selected",
      new_mux_window,
      pane,
      prev_workspace
    )
  end)
end

---Returns an action that saves and closes the active workspace.
---The previously active live workspace is preferred as the destination.
---@return KeyAssignment
function M.unload_current_workspace()
  return wezterm.action_callback(function(window, pane)
    local current_workspace = window:active_workspace()
    local previous_workspace = wezterm.GLOBAL.previous_workspace
    local target_workspace

    for _, choice in ipairs(data.get_workspace_cycle_order()) do
      if choice.id ~= current_workspace then
        if choice.id == previous_workspace then
          target_workspace = previous_workspace
          break
        end
        target_workspace = target_workspace or choice.id
      end
    end

    if not target_workspace then
      helpers.notify(window, "Workspace", "No other workspace available")
      return
    end

    local unloaded = unload_workspace(current_workspace, window, pane, {
      gui_window = window,
      before_close = function()
        local old_mux_window = data.get_current_mux_window(current_workspace)
        wezterm.emit(
          "workspace_manager.workspace_switcher.switching",
          old_mux_window,
          pane,
          current_workspace,
          target_workspace
        )

        switch_workspace(window, pane, { name = target_workspace })
        history.update_access_time(target_workspace)

        local new_mux_window = data.get_current_mux_window(target_workspace)
        wezterm.emit(
          "workspace_manager.workspace_switcher.selected",
          new_mux_window,
          pane,
          target_workspace
        )
      end,
    })

    if unloaded then wezterm.GLOBAL.previous_workspace = nil end
  end)
end

---Returns an action that prompts to rename the active workspace.
---@return KeyAssignment
function M.rename_current_workspace()
  return wezterm.action_callback(function(window, pane)
    prompt_workspace_rename(window, pane, window:active_workspace())
  end)
end

---Returns an action that saves the active workspace.
---@return KeyAssignment
function M.save_workspace()
  return wezterm.action_callback(function(window, pane)
    if not settings.session_enabled then
      helpers.notify(window, "Workspace", "Session persistence is not enabled")
      return
    end
    local workspace = window:active_workspace()
    if state.is_excluded_workspace(workspace) then
      helpers.notify(
        window,
        "Workspace",
        "Workspace is excluded from session saves"
      )
      return
    end
    local save_ok = state.save_workspace_state(workspace, window)
    if save_ok then
      helpers.notify(
        window,
        "Workspace",
        "Saved: " .. helpers.normalize_workspace_name(workspace)
      )
    else
      helpers.notify(window, "Workspace", "Failed to save workspace", 4000)
    end
  end)
end

return M
