---@alias WorkspaceManagerCountFormat "compact"|"full"
---@alias WorkspaceManagerSortOrder "recency"|"alphabetical"
---@alias WorkspaceManagerStatusFormat "icons"|"words"
---@alias WorkspaceManagerSwitcherAction "delete"|"unload"|"new"|"new_at_path"|"rename"
---@alias WorkspaceManagerThemeStyle string|FormatItem[]

---@class WorkspaceManagerCustomChoiceInput
---@field name string Workspace name and default display label.
---@field path? string Initial working directory; defaults to the home directory.
---@field label? string Display label used instead of `name`.

---@alias WorkspaceManagerChoiceInput string|WorkspaceManagerCustomChoiceInput
---@alias WorkspaceManagerChoiceProvider fun(): WorkspaceManagerChoiceInput[]

---@class WorkspaceManagerWorkspaceChoice
---@field id string Raw workspace name.
---@field label string Unformatted display label.
---@field normalized string Home-relative normalized name.
---@field is_workspace true
---@field is_saved boolean Whether the workspace exists only on disk.
---@field access_time integer Last access timestamp, or zero when unknown.

---@class WorkspaceManagerCycleChoice
---@field id string Raw workspace name.
---@field label string Unformatted display label.
---@field normalized string Home-relative normalized name.
---@field is_saved false

---@class WorkspaceManagerSuggestionChoice
---@field id string Workspace name or source path.
---@field label string Unformatted display label.
---@field normalized string Home-relative normalized name or path.
---@field is_workspace false
---@field name? string Explicit workspace name from a custom provider.
---@field path? string Initial working directory from a custom provider.
---@field has_path? boolean Whether a custom provider supplied `path`.

---@alias WorkspaceManagerFilterChoice WorkspaceManagerWorkspaceChoice|WorkspaceManagerSuggestionChoice
---@alias WorkspaceManagerChoiceFilter fun(choice: WorkspaceManagerFilterChoice): boolean

---@class WorkspaceManagerKeyBinding
---@field key string Key identifier accepted by WezTerm.
---@field mods? string Modifier expression; defaults to `NONE`.
---@field hint? string Short label shown in switcher help text.

---@class WorkspaceManagerSwitcherKeys
---@field delete? WorkspaceManagerKeyBinding|false Defaults to Ctrl+D; `false` disables it.
---@field unload? WorkspaceManagerKeyBinding|false Defaults to Ctrl+U; `false` disables it.
---@field new? WorkspaceManagerKeyBinding|false Defaults to Ctrl+N; `false` disables it.
---@field new_at_path? WorkspaceManagerKeyBinding|false Defaults to Ctrl+P; `false` disables it.
---@field rename? WorkspaceManagerKeyBinding|false Defaults to Ctrl+R; `false` disables it.

---@class WorkspaceManagerColors
---@field prompt_accent? WorkspaceManagerThemeStyle Workspace/path accents. Defaults to ANSI Lime.
---@field prompt_heading? WorkspaceManagerThemeStyle Prompt labels. Defaults to bold intensity.
---@field muted? WorkspaceManagerThemeStyle Secondary text. Defaults to ANSI Grey.
---@field workspace_status_live? WorkspaceManagerThemeStyle Live prefix. Defaults to ANSI Green.
---@field workspace_status_saved? WorkspaceManagerThemeStyle Saved prefix. Defaults to ANSI Purple.
---@field workspace_status_path? WorkspaceManagerThemeStyle Suggestion prefix. Defaults to the terminal foreground.
---@field workspace_icon? WorkspaceManagerThemeStyle Non-active workspace icon style.
---@field workspace_name? WorkspaceManagerThemeStyle Non-active workspace name style.
---@field workspace_counts? WorkspaceManagerThemeStyle Non-active workspace count style.
---@field workspace_icon_current? WorkspaceManagerThemeStyle Active icon style; falls back to `workspace_icon`.
---@field workspace_name_current? WorkspaceManagerThemeStyle Active name style; falls back to `workspace_name`.
---@field workspace_counts_current? WorkspaceManagerThemeStyle Active count style; falls back to `workspace_counts`.
---@field workspace_current_marker? WorkspaceManagerThemeStyle Current marker style; falls back to `prompt_accent`.
---@field entry_icon? WorkspaceManagerThemeStyle Suggestion icon style; falls back to `workspace_icon`.
---@field entry_name? WorkspaceManagerThemeStyle Suggestion name style; falls back to `workspace_name`.

---@class WorkspaceManager
---@field zoxide_path string Path to the zoxide binary. Defaults to `zoxide`.
---@field get_choices? WorkspaceManagerChoiceProvider|false Custom suggestions; defaults to built-in zoxide, while `false` disables suggestions.
---@field filter_choices? string[]|WorkspaceManagerChoiceFilter Path allowlist for suggestions or predicate for every choice; defaults to no filtering.
---@field wezterm_path? string WezTerm executable override; defaults to automatic detection.
---@field show_current_workspace_in_switcher boolean Whether the active workspace appears in the switcher. Defaults to `false`.
---@field show_current_workspace_hint boolean Whether descriptions include the active workspace. Defaults to `true`.
---@field start_in_fuzzy_mode boolean Whether the switcher initially uses fuzzy search. Defaults to `true`.
---@field notifications_enabled boolean Whether actions show toast notifications. Defaults to `false`.
---@field workspace_count_format? WorkspaceManagerCountFormat Count display format; defaults to `compact`, while `nil` disables counts.
---@field use_basename_for_workspace_names boolean Whether paths use their basename as the workspace name. Defaults to `false`.
---@field workspace_switcher_sort WorkspaceManagerSortOrder Workspace ordering strategy. Defaults to `recency`.
---@field switcher_keys? WorkspaceManagerSwitcherKeys In-switcher action overrides. Defaults to the built-in bindings.
---@field show_switcher_hints boolean Whether descriptions include action hints. Defaults to `true`.
---@field workspace_status_format WorkspaceManagerStatusFormat Status prefix format. Defaults to `icons`.
---@field workspace_icon? string Live-workspace status glyph. Defaults to `●`.
---@field workspace_icon_current? string Active-workspace status glyph. Defaults to `workspace_icon`.
---@field workspace_icon_saved? string Saved-workspace status glyph. Defaults to `○`.
---@field entry_icon? string Suggested-entry status glyph. Defaults to `·`.
---@field colors? WorkspaceManagerColors Theme style overrides. Defaults to the built-in palette.
---@field session_enabled boolean Whether session persistence is enabled. Defaults to `false`.
---@field session_periodic_save_interval? number Seconds between periodic saves; defaults to 600, while `nil` disables them.
---@field session_periodic_save_all boolean Whether periodic saves include every live workspace. Defaults to `false`.
---@field session_max_scrollback_lines integer Maximum scrollback lines saved per pane. Defaults to 3500.
---@field session_exclude_workspaces string[] Workspace names excluded from persistence. Defaults to `{ "default" }`.
---@field session_state_dir? string Directory containing saved workspace state. Defaults beneath WezTerm's data directory.
---@field session_on_pane_restore? fun(pane_tree: WorkspaceManagerPaneTree) Custom pane restoration callback. Defaults to scrollback restoration.
---@field session_restore_on_startup boolean Whether the newest saved workspace is restored at startup. Defaults to `false`.
---@field workspace_switcher fun(): KeyAssignment
---@field switch_to_previous_workspace fun(): KeyAssignment
---@field next_workspace fun(): KeyAssignment
---@field previous_workspace fun(): KeyAssignment
---@field unload_current_workspace fun(): KeyAssignment
---@field save_workspace fun(): KeyAssignment
---@field apply_to_config fun(config: Config)
---@field get_switcher_legend fun(): string
---@field get_zoxide_paths fun(limit?: integer): string[]

---@type WorkspaceManager
local M = {}

M.zoxide_path = "zoxide"
M.get_choices = nil
M.filter_choices = nil
M.wezterm_path = nil
M.show_current_workspace_in_switcher = false
M.show_current_workspace_hint = true
M.start_in_fuzzy_mode = true
M.notifications_enabled = false
M.workspace_count_format = "compact"
M.use_basename_for_workspace_names = false
M.workspace_switcher_sort = "recency"
M.switcher_keys = nil
M.show_switcher_hints = true
M.workspace_status_format = "icons"
M.workspace_icon = nil
M.workspace_icon_current = nil
M.workspace_icon_saved = nil
M.entry_icon = nil
M.colors = nil

M.session_enabled = false
M.session_periodic_save_interval = 600
M.session_periodic_save_all = false
M.session_max_scrollback_lines = 3500
M.session_exclude_workspaces = { "default" }
M.session_state_dir = nil
M.session_on_pane_restore = nil
M.session_restore_on_startup = false

return M
