local wezterm = require("wezterm") --[[@as Wezterm]]
local pane_tree_mod = require("workspace_manager.session.pane_tree")
local pub = {}

---@class WorkspaceManagerTabState
---@field title string
---@field is_zoomed boolean
---@field is_active? boolean
---@field pane_tree WorkspaceManagerPaneTree

---@class WorkspaceManagerPaneRestoreAccumulator
---@field active_pane? Pane
---@field is_zoomed boolean

---Builds the fold callback that recreates saved pane splits.
---@param opts WorkspaceManagerRestoreOptions
---@return fun(acc: WorkspaceManagerPaneRestoreAccumulator, pane_tree: WorkspaceManagerPaneTree): WorkspaceManagerPaneRestoreAccumulator
local function make_splits(opts)
  if opts == nil then opts = {} end

  return function(acc, pane_tree)
    local pane = pane_tree.pane

    if opts.on_pane_restore then opts.on_pane_restore(pane_tree) end

    local bottom = pane_tree.bottom
    if bottom then
      local split_args = { direction = "Bottom", cwd = bottom.cwd }
      if opts.relative then
        split_args.size = pane_tree_mod.subtree_height(bottom)
          / (pane_tree.height + 1 + pane_tree_mod.subtree_height(bottom))
      elseif opts.absolute then
        -- note: absolute mode assumes the same terminal geometry (DPI/font size)
        split_args.size = bottom.height
      end

      bottom.pane = pane:split(split_args)
    end

    local right = pane_tree.right
    if right then
      local split_args = { direction = "Right", cwd = right.cwd }
      if opts.relative then
        split_args.size = pane_tree_mod.subtree_width(right)
          / (pane_tree.width + 1 + pane_tree_mod.subtree_width(right))
      elseif opts.absolute then
        -- note: absolute mode assumes the same terminal geometry (DPI/font size)
        split_args.size = right.width
      end

      right.pane = pane:split(split_args)
    end

    if pane_tree.is_active then acc.active_pane = pane_tree.pane end

    if pane_tree.is_zoomed then acc.is_zoomed = true end

    return acc
  end
end

---Captures the state of a tab.
---@param tab MuxTab
---@return WorkspaceManagerTabState
function pub.get_tab_state(tab)
  local panes = tab:panes_with_info()

  local function is_zoomed()
    for _, pane in ipairs(panes) do
      if pane.is_zoomed then return true end
    end
    return false
  end

  local tab_state = {
    title = tab:get_title(),
    is_zoomed = is_zoomed(),
    pane_tree = pane_tree_mod.create_pane_tree(panes),
  }

  return tab_state
end

---Closes every pane in a tab except the selected pane.
---@param tab MuxTab
---@param pane_to_keep Pane
local function close_all_other_panes(tab, pane_to_keep)
  for _, pane in ipairs(tab:panes()) do
    if pane:pane_id() ~= pane_to_keep:pane_id() then
      pane:activate()
      tab:window():gui_window():perform_action(
        wezterm.action.CloseCurrentPane({ confirm = false }),
        pane
      )
    end
  end
end

---Restores a tab from saved state.
---@param tab MuxTab
---@param tab_state WorkspaceManagerTabState
---@param opts WorkspaceManagerRestoreOptions
function pub.restore_tab(tab, tab_state, opts)
  if opts.pane then
    tab_state.pane_tree.pane = opts.pane
  else
    local split_args = { cwd = tab_state.pane_tree.cwd }
    if tab_state.pane_tree.domain then
      split_args.domain = { DomainName = tab_state.pane_tree.domain }
    end
    local new_pane = tab:active_pane():split(split_args)
    tab_state.pane_tree.pane = new_pane
  end

  if opts.close_open_panes then
    close_all_other_panes(tab, tab_state.pane_tree.pane)
  end

  if tab_state.title then tab:set_title(tab_state.title) end

  local acc = pane_tree_mod.fold(
    tab_state.pane_tree,
    { is_zoomed = false },
    make_splits(opts)
  )
  if acc.active_pane then acc.active_pane:activate() end
end

---Waits for a newly created pane's geometry and shell output to settle.
---@param pane_tree WorkspaceManagerPaneTree
---@param on_pane_restore fun(pane_tree: WorkspaceManagerPaneTree)
function pub.restore_pane_when_stable(pane_tree, on_pane_restore)
  local previous, stable_count, checks = nil, 0, 0

  local function sample()
    checks = checks + 1
    local ok, err = pcall(function()
      local pane = pane_tree.pane
      local dims = pane:get_dimensions()
      local cursor = pane:get_cursor_position()
      local screen = pane:get_lines_as_text()
      local current = table.concat({
        dims.cols,
        dims.viewport_rows,
        cursor.x,
        cursor.y - dims.physical_top,
        screen,
      }, "\n")
      if current == previous and screen:find("%S") then
        stable_count = stable_count + 1
      else
        stable_count = 0
      end
      previous = current

      -- Blank panes may still be waiting for PowerShell/ConPTY to initialize.
      -- Bound the wait for shells that don't print a prompt or keep updating it.
      if stable_count >= 5 or checks >= 50 then
        on_pane_restore(pane_tree)
      else
        wezterm.time.call_after(0.1, sample)
      end
    end)
    if not ok then
      wezterm.log_warn(
        "workspace_manager: deferred pane restore failed: " .. tostring(err)
      )
    end
  end

  wezterm.time.call_after(0.1, sample)
end

---Restores saved scrollback without sending commands to the new shell.
---@param pane_tree WorkspaceManagerPaneTree
function pub.default_on_pane_restore(pane_tree)
  local pane = pane_tree.pane

  if pane_tree.text then
    local text = pane_tree.text:gsub("%s+$", "")
    if text == "" then return end

    local rows = pane:get_dimensions().viewport_rows
    local screen = pane:get_lines_as_escapes(rows):gsub("%s+$", "")

    -- Output injection bypasses the shell (and ConPTY on Windows). Keep
    -- its live screen and cursor intact so the next prompt redraw cannot
    -- overwrite restored history. ESC 7/8 also preserve cursor attributes.
    pane:inject_output(
      "\x1b7\x1b[H\x1b[0m\x1b[2J"
        .. text
        -- Push every restored line above the live viewport, then repaint it.
        .. "\x1b[0m"
        .. string.rep("\r\n", rows)
        .. "\x1b[H"
        .. screen
        .. "\x1b8"
    )
  end
end

return pub
