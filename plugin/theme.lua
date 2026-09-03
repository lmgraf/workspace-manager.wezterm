local wezterm = require("wezterm")

local M_ref -- reference to plugin config table (set via setup)

local mod = {}

local DEFAULT_COLORS = {
  prompt_accent = "Lime",
  prompt_heading = { { Attribute = { Intensity = "Bold" } } },
  muted = "Grey",
  -- ANSI palette references follow the active scheme, including overrides.
  workspace_status_live = "Green",
  workspace_status_saved = "Purple",
}

function mod.setup(plugin) M_ref = plugin end

function mod.get_color(key)
  if M_ref.colors and M_ref.colors[key] ~= nil then return M_ref.colors[key] end
  return DEFAULT_COLORS[key]
end

-- Converts a color string (AnsiColor name or "#hex") to a Foreground FormatItem.
function mod.fg(color_string)
  if color_string:sub(1, 1) == "#" then
    return { Foreground = { Color = color_string } }
  else
    return { Foreground = { AnsiColor = color_string } }
  end
end

-- Builds a FormatItem list for prompt heading text using the configured prompt_heading style.
function mod.build_heading(text)
  local items = {}
  mod.append_segment(items, text, mod.get_color("prompt_heading"))
  return items
end

-- Resolves the first non-nil color from the given keys (in order).
local function resolve_color(...)
  for i = 1, select("#", ...) do
    local color = mod.get_color(select(i, ...))
    if color then return color end
  end
  return nil
end

-- Resolves a label segment color for a given category.
-- category: "workspace" | "saved" | "current" | "entry"
-- Fallback chains:
--   current:   workspace_<seg>_current -> workspace_<seg>
--   entry:     entry_<seg>             -> workspace_<seg>
--   workspace: workspace_<seg>
--   saved:     workspace_<seg>
local function resolve_label_color(segment, category)
  if category == "current" then
    return resolve_color(
      "workspace_" .. segment .. "_current",
      "workspace_" .. segment
    )
  elseif category == "entry" then
    return resolve_color("entry_" .. segment, "workspace_" .. segment)
  else
    return resolve_color("workspace_" .. segment)
  end
end

-- Appends a styled text segment to a FormatItems list. Skips empty strings.
-- style can be nil (no styling), a color string (treated as foreground), or
-- a list of FormatItems (e.g. { { Attribute = { Intensity = "Half" } } }).
function mod.append_segment(items, text, style)
  if text == "" then return end
  table.insert(items, "ResetAttributes")
  if type(style) == "string" then
    table.insert(items, mod.fg(style))
  elseif type(style) == "table" then
    for _, item in ipairs(style) do
      table.insert(items, item)
    end
  end
  table.insert(items, { Text = text })
end

local function trim_icon(icon) return icon:match("^%s*(.-)%s*$") end

local function icon_column_width()
  local workspace = M_ref.workspace_icon or "●"
  local current = M_ref.workspace_icon_current or workspace
  local saved = M_ref.workspace_icon_saved or "○"
  local entry = M_ref.entry_icon or "·"
  return math.max(
    wezterm.column_width(trim_icon(workspace)),
    wezterm.column_width(trim_icon(current)),
    wezterm.column_width(trim_icon(saved)),
    wezterm.column_width(trim_icon(entry))
  )
end

local function status_style(status, category, format)
  local key = "workspace_status_" .. status
  local override = M_ref.colors and M_ref.colors[key]
  if override ~= nil then return override end
  if format == "icons" then
    local icon_style = resolve_label_color("icon", category)
    if icon_style then return icon_style end
  end
  return mod.get_color(key)
end

-- Builds a fully formatted switcher label with independently styled segments.
-- Both formats use one aligned status column before the name and counts.
-- category: "workspace" (live) | "saved" | "current" | "entry" (suggestion)
function mod.build_switcher_label(icon, name, counts, category)
  local items = {}
  local format = M_ref.workspace_status_format or "icons"
  assert(
    format == "icons" or format == "words",
    'workspace_status_format must be "icons" or "words"'
  )
  local status = category == "saved" and "saved"
    or category == "entry" and "path"
    or "live"
  local words = { live = "[live]", saved = "[disk]", path = "[path]" }
  local prefix = format == "words" and words[status] or trim_icon(icon)
  local width = format == "words" and 6 or icon_column_width()
  local style = status_style(status, category, format)
  mod.append_segment(items, prefix, style)
  local padding = width - wezterm.column_width(prefix) + 1
  if width > 0 then mod.append_segment(items, string.rep(" ", padding)) end
  mod.append_segment(items, name, resolve_label_color("name", category))
  mod.append_segment(items, counts, resolve_label_color("counts", category))
  if category == "current" then
    mod.append_segment(items, " ")
    mod.append_segment(
      items,
      " current",
      resolve_color("workspace_current_marker", "prompt_accent")
    )
  end
  table.insert(items, "ResetAttributes")
  return wezterm.format(items)
end

return mod
