local M = {}

-- Configuration
M.zoxide_path = "zoxide"
M.get_choices = nil -- Custom entry provider function. Replaces zoxide when set.
-- Return a list of path strings or tables:
--   { name = "ws-name", path = "~/optional/cwd", label = "Optional Display" }
-- Set to false to disable extra entries entirely.
M.filter_choices = nil -- Filter switcher entries. Accepts a table (path allowlist) or a function (predicate).
-- Table: list of exact path strings; only matching custom/zoxide entries are kept.
--   Workspaces (live + saved) always pass through.
-- Function: function(choice) -> bool; return true to keep the entry.
--   Choice fields — workspace: id, label, normalized, is_workspace (true), is_saved, access_time
--                   custom:    id, label, normalized, is_workspace (false), name, path, has_path
M.wezterm_path = nil -- Optional: auto-detected from wezterm.executable_dir (only needed if auto-detection fails)
M.show_current_workspace_in_switcher = false -- Show current workspace in the switcher list
M.show_current_workspace_hint = true -- Show current workspace name in the switcher description
M.start_in_fuzzy_mode = true -- Start switcher in fuzzy search mode (false = use positional shortcuts)
M.notifications_enabled = false -- Enable toast notifications (requires code-signed wezterm on macOS)
M.workspace_count_format = "compact" -- nil (disabled), "compact" (2w 3t 5p), or "full" (2 wins, 3 tabs, 5 panes)
M.use_basename_for_workspace_names = false -- Use basename only (default: false for backward compatibility)
M.workspace_switcher_sort = "recency" -- "recency" (most recently used first, default) or "alphabetical" (sorted alphabetically)
M.switcher_keys = nil -- Override in-switcher action key bindings. Table mapping action name to { key, mods }.
-- Actions: "delete", "unload", "new", "new_at_path", "rename"
-- Set an action to false to disable it. Unspecified actions use defaults.
-- e.g. { unload = { key = "x", mods = "CTRL" }, rename = false }
M.show_switcher_hints = true -- Show action key hints in the switcher description bar (both fuzzy and non-fuzzy modes).
-- Set to false to hide hints from the description (use get_switcher_legend() instead).
M.workspace_status_format = "icons" -- "icons" (● / ○ / ·) or "words" ([live] / [disk] / [path])
M.workspace_icon = nil -- Live workspace status icon (default: "●")
M.workspace_icon_current = nil -- Icon glyph for the active workspace (default: falls back to workspace_icon)
M.workspace_icon_saved = nil -- Saved workspace status icon (default: "○")
M.entry_icon = nil -- Status icon for custom/zoxide entries (default: "·")
M.colors = nil -- Override theme colors.
-- All keys accept a color string (AnsiColor name or "#hex") as a foreground color,
-- or a FormatItem list for full control over fg, bg, intensity, etc.
-- e.g. { { Foreground = { Color = "#cdd6f4" } }, { Attribute = { Intensity = "Bold" } } }
--
--   Prompt styling:
--   prompt_accent:  workspace name/path text in descriptions, e.g. "~/ws" in the switcher and "Renaming: ~/ws" (default: "Lime")
--   prompt_heading: label text in prompts, e.g. "Renaming:", "Directory does not exist:" (default: Bold)
--   muted:          secondary text like the switcher legend and shortcut hints (default: ANSI Grey)
--
--   Non-active workspace entries:
--   workspace_icon:   icon color override in icons mode (default: nil)
--   workspace_name:   workspace name (default: nil = terminal default)
--   workspace_counts: count suffix, e.g. "(2w 3t 5p)" (default: nil = terminal default)
--
--   Status colors apply only to the icon or word prefix in both formats.
--   workspace_status_live:  ● or [live] (default: scheme's ANSI Green)
--   workspace_status_saved: ○ or [disk] (default: scheme's ANSI Purple/magenta)
--   workspace_status_path:  · or [path] (default: terminal foreground)
--
--   Active (current) workspace — falls back to workspace_*:
--   workspace_icon_current:   icon glyph
--   workspace_name_current:   workspace name
--   workspace_counts_current: count suffix
--   workspace_current_marker: "current" text after the name (falls back to prompt_accent)
--
--   Custom/zoxide entries — falls back to workspace_*:
--   entry_icon: icon glyph
--   entry_name: entry name

-- Session persistence (session integration)
M.session_enabled = false -- Enable automatic workspace state save/restore
M.session_periodic_save_interval = 600 -- Seconds between periodic saves (nil to disable)
M.session_periodic_save_all = false -- Periodic save: true=all in-memory workspaces, false=active workspace only
M.session_max_scrollback_lines = 3500 -- Max scrollback lines to capture per pane
M.session_exclude_workspaces = { "default" } -- Workspace names to never save/restore
M.session_state_dir = nil -- Override state directory (default: ~/.local/share/wezterm/workspace_state/)
M.session_on_pane_restore = nil -- Custom per-pane restore callback (default: default_on_pane_restore)
M.session_restore_on_startup = false -- Restore most recently used workspace on gui-startup

return M
