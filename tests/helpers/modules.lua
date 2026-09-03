local M = {}

local plugin_modules = {
  "actions",
  "config",
  "data",
  "helpers",
  "history",
  "init",
  "state",
  "theme",
}

function M.reset()
  for _, name in ipairs(plugin_modules) do
    package.loaded[name] = nil
  end
  for name in pairs(package.loaded) do
    if name:match("^session%.") then package.loaded[name] = nil end
  end
  package.loaded.wezterm = nil
end

function M.load(path)
  local chunk, err = loadfile(path)
  assert(chunk, err)
  return chunk()
end

return M
