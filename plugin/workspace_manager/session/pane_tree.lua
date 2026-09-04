local wezterm = require("wezterm") --[[@as Wezterm]]
local utils = require("workspace_manager.session.utils")

---@class WorkspaceManagerPaneTreeModule
---@field max_nlines integer
local pub = {}
pub.max_nlines = 3500

---@class WorkspaceManagerPaneInformation
---@field pane Pane
---@field left integer
---@field top integer
---@field height integer
---@field width integer
---@field is_active boolean
---@field is_zoomed boolean

---@class WorkspaceManagerProcessState
---@field name string
---@field argv string[]
---@field cwd string
---@field executable string

---@class WorkspaceManagerPaneTree
---@field left integer
---@field top integer
---@field height integer
---@field width integer
---@field bottom? WorkspaceManagerPaneTree
---@field right? WorkspaceManagerPaneTree
---@field text? string
---@field cwd string
---@field domain? string
---@field process? WorkspaceManagerProcessState
---@field pane? Pane
---@field is_active boolean
---@field is_zoomed boolean
---@field alt_screen_active? boolean

---Returns whether the first pane is positioned before the second pane.
---@param a WorkspaceManagerPaneInformation
---@param b WorkspaceManagerPaneInformation
---@return boolean
local function compare_pane_by_coord(a, b)
  if a.left == b.left then
    return a.top < b.top
  else
    return a.left < b.left
  end
end

---@param root WorkspaceManagerPaneInformation
---@param pane WorkspaceManagerPaneInformation
---@return boolean
local function is_right(root, pane)
  if root.left + root.width < pane.left then return true end
  return false
end

---@param root WorkspaceManagerPaneInformation
---@param pane WorkspaceManagerPaneInformation
---@return boolean
local function is_bottom(root, pane)
  if root.top + root.height < pane.top then return true end
  return false
end

---@param root WorkspaceManagerPaneTree
---@param panes WorkspaceManagerPaneInformation[]
---@return WorkspaceManagerPaneInformation?
local function pop_connected_bottom(root, panes)
  for i, pane in ipairs(panes) do
    if root.left == pane.left and root.top + root.height + 1 == pane.top then
      table.remove(panes, i)
      return pane
    end
  end
end

---@param root WorkspaceManagerPaneTree
---@param panes WorkspaceManagerPaneInformation[]
---@return WorkspaceManagerPaneInformation?
local function pop_connected_right(root, panes)
  for i, pane in ipairs(panes) do
    if root.top == pane.top and root.left + root.width + 1 == pane.left then
      table.remove(panes, i)
      return pane
    end
  end
end

---@param node WorkspaceManagerPaneTree?
---@return integer
local function subtree_height(node)
  if node == nil then return 0 end
  if node.bottom then return node.height + 1 + subtree_height(node.bottom) end
  return node.height
end

---@param node WorkspaceManagerPaneTree?
---@return integer
local function subtree_width(node)
  if node == nil then return 0 end
  if node.right then return node.width + 1 + subtree_width(node.right) end
  return node.width
end

---@param root WorkspaceManagerPaneTree?
---@param panes WorkspaceManagerPaneInformation[]
---@return WorkspaceManagerPaneTree?
local function insert_panes(root, panes)
  if root == nil then return nil end

  local domain = root.pane:get_domain_name()
  if not wezterm.mux.get_domain(domain):is_spawnable() then
    wezterm.log_warn("Domain " .. domain .. " is not spawnable")
    wezterm.emit("session.error", "Domain " .. domain .. " is not spawnable")
  else
    root.domain = domain

    if not root.pane:get_current_working_dir() then
      root.cwd = ""
    else
      root.cwd = root.pane:get_current_working_dir().file_path
      if utils.is_windows then
        root.cwd = root.cwd:gsub("^/([a-zA-Z]):", "%1:")
      end
    end

    if domain == "local" then
      -- pane:inject_output() is unavailable for non-local domains,
      -- only saving local scrollback because it would slow down the process
      -- See: https://github.com/MLFlexer/resurrect.wezterm/issues/41
      root.alt_screen_active = root.pane:is_alt_screen_active()
      if not root.alt_screen_active then
        local nlines = root.pane:get_dimensions().scrollback_rows
        if nlines > pub.max_nlines then nlines = pub.max_nlines end
        root.text = root.pane:get_lines_as_escapes(nlines)
      end
    end
  end

  root.pane = nil

  if #panes == 0 then return root end

  local right, bottom = {}, {}
  for _, pane in ipairs(panes) do
    if is_right(root, pane) then
      table.insert(right, pane)
    elseif is_bottom(root, pane) then
      table.insert(bottom, pane)
    else
      wezterm.log_warn(
        "pane_tree: pane at ("
          .. pane.left
          .. ","
          .. pane.top
          .. ") not classified as right or bottom of root at ("
          .. root.left
          .. ","
          .. root.top
          .. "); adding to bottom bucket"
      )
      table.insert(bottom, pane)
    end
  end

  if #right > 0 then
    local right_child = pop_connected_right(root, right)
    if right_child == nil then
      wezterm.log_warn(
        "pane_tree: no exact right-adjacent pane for root at ("
          .. root.left
          .. ","
          .. root.top
          .. "); using fallback selection"
      )
      right_child = table.remove(right, 1)
    end
    root.right = insert_panes(right_child, right)
  end

  if #bottom > 0 then
    local bottom_child = pop_connected_bottom(root, bottom)
    if bottom_child == nil then
      wezterm.log_warn(
        "pane_tree: no exact bottom-adjacent pane for root at ("
          .. root.left
          .. ","
          .. root.top
          .. "); using fallback selection"
      )
      bottom_child = table.remove(bottom, 1)
    end
    root.bottom = insert_panes(bottom_child, bottom)
  end

  return root
end

pub.subtree_height = subtree_height
pub.subtree_width = subtree_width

---Creates a pane tree from an ordered list of pane information.
---@param panes WorkspaceManagerPaneInformation[]
---@return WorkspaceManagerPaneTree?
function pub.create_pane_tree(panes)
  table.sort(panes, compare_pane_by_coord)
  local root = table.remove(panes, 1)
  return insert_panes(root, panes)
end

---Maps a function over every node in a pane tree.
---@param pane_tree WorkspaceManagerPaneTree?
---@param f fun(pane_tree: WorkspaceManagerPaneTree): WorkspaceManagerPaneTree
---@return WorkspaceManagerPaneTree?
function pub.map(pane_tree, f)
  if pane_tree == nil then return nil end

  pane_tree = f(pane_tree)
  if pane_tree.right then pub.map(pane_tree.right, f) end
  if pane_tree.bottom then pub.map(pane_tree.bottom, f) end

  return pane_tree
end

---Folds every node in a pane tree into an accumulator.
---@generic T
---@param pane_tree WorkspaceManagerPaneTree?
---@param acc T
---@param f fun(acc: T, pane_tree: WorkspaceManagerPaneTree): T
---@return T
function pub.fold(pane_tree, acc, f)
  if pane_tree == nil then return acc end

  acc = f(acc, pane_tree)
  if pane_tree.right then acc = pub.fold(pane_tree.right, acc, f) end
  if pane_tree.bottom then acc = pub.fold(pane_tree.bottom, acc, f) end

  return acc
end

return pub
