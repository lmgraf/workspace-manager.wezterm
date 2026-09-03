local M = {}

local function action_table()
  return setmetatable({}, {
    __index = function(_, kind)
      return function(opts) return { kind = kind, opts = opts } end
    end,
  })
end

local function column_width(value)
  local width = 0
  for _, codepoint in utf8.codes(value) do
    if codepoint == 0x754C then
      width = width + 2
    elseif codepoint >= 0x20 then
      width = width + 1
    end
  end
  return width
end

function M.new(overrides)
  local calls = {}
  local function record(kind, ...)
    table.insert(calls, { kind = kind, args = table.pack(...) })
  end

  local fake = {
    home_dir = "/home/test",
    GLOBAL = {},
    action = action_table(),
    action_callback = function(callback) return callback end,
    add_to_config_reload_watch_list = function() end,
    emit = function(name, ...) record(name, ...) end,
    column_width = column_width,
    format = function(parts)
      local text = {}
      for _, part in ipairs(parts) do
        if part.Text then table.insert(text, part.Text) end
      end
      return table.concat(text)
    end,
    log_error = function() end,
    log_info = function() end,
    log_warn = function() end,
  }
  for key, value in pairs(overrides or {}) do
    fake[key] = value
  end

  return {
    wezterm = fake,
    calls = calls,
    record = record,
    recorded = function(kind)
      local result = {}
      for _, call in ipairs(calls) do
        if call.kind == kind then table.insert(result, call.args) end
      end
      return result
    end,
  }
end

return M
