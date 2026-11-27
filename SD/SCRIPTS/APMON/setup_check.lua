-- SPDX-License-Identifier: Apache-2.0
-- APMon: read-only setup checks for telemetry features, shared by SW and COLOR.
-- Project version: 1.3.2
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

local function check(index, monitor, receiver, config)
    local key, title = checks[2 * index - 1], checks[2 * index]
    if monitor.betaflight and (key == 'armed' or key == 'relative' or key == 'fix') then
      if key == 'fix' and monitor.gpsFixLabel then return title, monitor.gpsFixLabel, monitor.sources.gpsfix.name, nil, 'Quelle:' end
      return title, 'Nicht verfügbar', nil, key ~= 'fix' and 'Nur mit ArduPilot' or nil
    end
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
    if key == 'gps' and state == 'valid' then
      if monitor.betaflight then
        if monitor.gpsFixLabel ~= 'Bestätigt' then
          status, tip, sourceLabel = 'Nicht bestätigt', 'Kein bestätigter Fix', 'Erkannt:'
        end
      elseif receiver.status('fix') == 'unreceived' then tip = 'Fixtyp fehlt noch' end
    end
    local def = config.sensors[key]
    local names = def and def.names
    local configured = names and names[1]
    if configured then
      for i = 2, #names do configured = configured .. ', ' .. names[i] end
    end
    return title, status, source, tip, sourceLabel, configured
end

-- Only an accepted sensor value is evidence here. Optional sensors are not
-- a checklist for flight readiness and no cause is inferred from a missing one.
local fcSensors = {'voltage','current','remaining','used','mode','roll','pitch',
  'yaw','altitude','gpsaltitude','climb','gps','heading','speed','satellites'}
local function valid(sources, key)
  local entry = sources[key]
  return entry and entry.state == 'valid'
end
local function overview(monitor, receiver)
  if not monitor.api then return 'API fehlt', 'EdgeTX-Version prüfen' end
  local sources = monitor.sources
  local anyFC
  for _, key in ipairs(fcSensors) do
    if valid(sources, key) then anyFC = true; break end
  end
  local link = valid(sources, 'lq')
  if not anyFC then
    if not link then return 'Keine aktuellen Werte', 'Modell und Link prüfen' end
    return 'FC-Sensorwerte fehlen', 'EdgeTX-Sensorliste prüfen'
  end
  if not link then return 'RC-Linkwert fehlt', 'RC-Linkquelle prüfen' end
  if not monitor.betaflight then
    local state = receiver.status('armed')
    if state == 'noapi' then return 'Passthrough-API fehlt', 'EdgeTX-Version prüfen' end
    if state == 'stale' then return 'FC-Status veraltet', 'Passthrough prüfen' end
    if state ~= 'valid' then return 'FC-Status fehlt', 'Passthrough prüfen' end
  end
  if not valid(sources, 'voltage') then return 'Akkuspannung fehlt', 'Akkuquelle prüfen' end
  if not valid(sources, 'roll') or not valid(sources, 'pitch') then
    return 'HUD-Lagedaten fehlen', 'Roll und Nick prüfen'
  end
  local gps, fix = valid(sources, 'gps'), monitor.gpsFixLabel
  if monitor.betaflight then
    if fix ~= 'Bestätigt' and (gps or valid(sources, 'gpsaltitude') and not valid(sources, 'altitude')) then
      return 'Basiswerte vorhanden', 'Fix für Live-GPS prüfen'
    end
  elseif gps then
    if fix == 'Kein GPS' then return 'Kein GPS', 'GPS am FC prüfen' end
    if fix == 'Kein Fix' then return 'Kein Fix', 'Auf GPS-Fix warten' end
    if not fix then return 'GPS-Fix nicht bestätigt', 'GPS-Passthrough prüfen' end
  end
  return 'Basiswerte vorhanden', 'Details bei Bedarf prüfen'
end

local count = math.floor(#checks / 2)
return {
  count = count,
  pages = count + 1,
  text = load('setup_text'),
  check = check,
  page = function(index, monitor, receiver, config)
    if index ~= 1 then return check(index - 1, monitor, receiver, config) end
    local status, tip = overview(monitor, receiver)
    return 'Nächster Schritt', status, monitor.betaflight and 'Betaflight' or 'ArduPilot', tip, 'Profil:'
  end,
}
