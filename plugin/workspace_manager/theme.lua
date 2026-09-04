local wezterm = require("wezterm") --[[@as Wezterm]]
local settings = require("workspace_manager.settings")

local mod = {}

---@type table<string, WorkspaceManagerThemeStyle>
local DEFAULT_COLORS = {
  prompt_accent = "Lime",
  prompt_heading = { { Attribute = { Intensity = "Bold" } } },
  muted = "Grey",
  -- ANSI palette references follow the active scheme, including overrides.
  workspace_status_live = "Green",
  workspace_status_saved = "Purple",
}

---Returns a configured theme style or its default.
---@param key string
---@return WorkspaceManagerThemeStyle?
function mod.get_color(key)
  if settings.colors and settings.colors[key] ~= nil then return settings.colors[key] end
  return DEFAULT_COLORS[key]
end

---Converts an ANSI name or hex color to a foreground format item.
---@param color_string string
---@return FormatItem
function mod.fg(color_string)
  if color_string:sub(1, 1) == "#" then
    return { Foreground = { Color = color_string } }
  else
    return { Foreground = { AnsiColor = color_string } }
  end
end

---Builds formatted prompt heading text using the configured style.
---@param text string
---@return FormatItem[]
function mod.build_heading(text)
  local items = {}
  mod.append_segment(items, text, mod.get_color("prompt_heading"))
  return items
end

---Resolves the first configured style from the supplied keys.
---@param ... string
---@return WorkspaceManagerThemeStyle?
local function resolve_color(...)
  for i = 1, select("#", ...) do
    local color = mod.get_color(select(i, ...))
    if color then return color end
  end
  return nil
end

---@alias WorkspaceManagerChoiceCategory "workspace"|"saved"|"current"|"entry"

---Resolves a label segment style using category-specific fallbacks.
---@param segment "icon"|"name"|"counts"
---@param category WorkspaceManagerChoiceCategory
---@return WorkspaceManagerThemeStyle?
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

---Appends a styled text segment, skipping empty strings.
---@param items FormatItem[]
---@param text string
---@param style? WorkspaceManagerThemeStyle
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

---@param icon string
---@return string
local function trim_icon(icon) return icon:match("^%s*(.-)%s*$") end

---@return integer
local function icon_column_width()
  local workspace = settings.workspace_icon or "●"
  local current = settings.workspace_icon_current or workspace
  local saved = settings.workspace_icon_saved or "○"
  local entry = settings.entry_icon or "·"
  return math.max(
    wezterm.column_width(trim_icon(workspace)),
    wezterm.column_width(trim_icon(current)),
    wezterm.column_width(trim_icon(saved)),
    wezterm.column_width(trim_icon(entry))
  )
end

---@param status "live"|"saved"|"path"
---@param category WorkspaceManagerChoiceCategory
---@param format WorkspaceManagerStatusFormat
---@return WorkspaceManagerThemeStyle?
local function status_style(status, category, format)
  local key = "workspace_status_" .. status
  local override = settings.colors and settings.colors[key]
  if override ~= nil then return override end
  if format == "icons" then
    local icon_style = resolve_label_color("icon", category)
    if icon_style then return icon_style end
  end
  return mod.get_color(key)
end

---Builds a switcher label with an aligned status column and styled segments.
---@param icon string
---@param name string
---@param counts string
---@param category WorkspaceManagerChoiceCategory
---@return string
function mod.build_switcher_label(icon, name, counts, category)
  local items = {}
  local format = settings.workspace_status_format or "icons"
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
