local M = {}

function M.reset()
  for name in pairs(package.loaded) do
    if name:match("^workspace_manager%.") then package.loaded[name] = nil end
  end
  package.loaded.wezterm = nil
end

function M.load(path)
  local chunk, err = loadfile(path)
  assert(chunk, err)
  return chunk()
end

return M
