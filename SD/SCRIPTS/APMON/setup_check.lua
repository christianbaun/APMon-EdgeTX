-- SPDX-License-Identifier: Apache-2.0
-- APMon: read-only setup checks for telemetry features, shared by SW and COLOR.
-- Project version: 1.0.0
local load = ...
local defs = load('setup_defs')
local checks, labels, tips, fixes = defs.checks, defs.labels, defs.tips, defs.fixes

local function sensorCheck(entry, state)
  local detected = entry and state ~= 'missing' and state ~= 'noapi'
  return labels[state], detected and entry.name or nil, tips[state],
    detected and (state == 'valid' and 'Quelle:' or 'Erkannt:') or nil
end

local relative
local function relativeCheck(monitor, config, title)
  local name = config.relativeAltitudeSensor
  if not name then return title, 'Nicht zugeordnet', nil, 'Höhe zuordnen' end
  if relative == nil then
    local ok, result = pcall(load, 'setup_relative')
    relative = ok and result or false
  end
  if not relative then return title, 'Werkzeug nicht ladbar', nil, nil, nil, name end
  local state, source = relative(monitor, config, name)
  if state == 'unmapped' then return title, 'Nicht zugeordnet', nil, 'Zuordnung prüfen', nil, name end
  if state == 'unselected' then
    return title, 'Nicht ausgewählt', source, source and 'Alias-Reihenfolge prüfen' or 'Zuordnung prüfen',
      source and 'Andere Quelle:' or nil, name
  end
  return title, labels[state], source, tips[state],
    source and (state == 'valid' and 'Quelle:' or 'Erkannt:') or nil, name
end

return {
  count = math.floor(#checks / 2),
  text = load('setup_text'),
  check = function(index, monitor, receiver, config)
    local key, title = checks[2 * index - 1], checks[2 * index]
    if key == 'relative' then return relativeCheck(monitor, config, title) end
    if key == 'armed' or key == 'fix' then
      local state = receiver.status(key)
      local status, tip = labels[state], state == 'noapi' and tips.noapi or 'ELRS MAVLink prüfen'
      if state == 'valid' then
        tip = nil
        if key == 'fix' then
          local fix = receiver.value('fix')
          status = fixes[fix] or labels.unknown
          tip = fix == 0 and 'GPS am FC prüfen' or fix == 1 and 'Auf GPS-Fix warten' or nil
        end
      end
      if state == 'valid' or state == 'stale' then
        return title, status, 'ELRS MAVLink', tip, state == 'valid' and 'Quelle:' or 'Erkannt:'
      end
      return title, status, nil, tip, nil, 'ELRS MAVLink'
    end
    local sensor = monitor.sources[key]
    local state = sensor and sensor.state or 'disabled'
    local status, source, tip, sourceLabel = sensorCheck(sensor, state)
    if key == 'gps' and state == 'valid' and receiver.status('fix') == 'unreceived' then tip = 'Fixtyp fehlt noch' end
    local def = config.sensors[key]
    local names = def and def.names
    local configured = names and names[1]
    if configured then
      for i = 2, #names do configured = configured .. ', ' .. names[i] end
    end
    return title, status, source, tip, sourceLabel, configured
  end,
}
