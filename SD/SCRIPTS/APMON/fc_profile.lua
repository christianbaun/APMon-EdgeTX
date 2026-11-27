-- SPDX-License-Identifier: Apache-2.0
-- Local APMon preference, keyed by the EdgeTX model file, not its display name.
-- Project version: 1.2.0
local current, checked = 'ArduPilot', nil
local function path()
  if not model or type(model.getInfo) ~= 'function' then return end
  local info = model.getInfo()
  local name = type(info) == 'table' and info.filename
  if type(name) ~= 'string' or #name == 0 or #name > 64 then return end
  name = string.gsub(name, '[^%w_.-]', function(c) return string.format('~%02x', string.byte(c)) end)
  return '/SCRIPTS/APMON/fc-' .. name .. '.cfg'
end
local function read(filePath)
  if not filePath or not io or not io.open then return end
  local file = io.open(filePath, 'r')
  if not file then return end
  local ok, value = pcall(io.read, file, 8)
  io.close(file)
  if ok then return value end
end
local function get(now)
  -- Share changes between Tools and already loaded COLOR widgets without
  -- reading the SD card on every telemetry sample.
  if not checked or now < checked or now - checked >= 200 then
    checked = now
    current = read(path()) == 'bf\n' and 'Betaflight' or 'ArduPilot'
  end
  return current
end
local function set(name, now)
  if name ~= 'ArduPilot' and name ~= 'Betaflight' then return false end
  local filePath = path()
  if not filePath or not io or not io.open then return false end
  local value = name == 'Betaflight' and 'bf\n' or 'ap\n'
  if read(filePath) ~= value then
    local file = io.open(filePath, 'w')
    if not file then return false end
    local ok, result = pcall(io.write, file, value)
    local closed, closing, reason = pcall(io.close, file)
    if not ok or not result or not closed or closing == false or reason or read(filePath) ~= value then
      return false
    end
  end
  current, checked = name, now
  return true
end
return { get = get, set = set }
