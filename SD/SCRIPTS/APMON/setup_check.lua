-- SPDX-License-Identifier: Apache-2.0
-- APMon: read-only setup checks for telemetry features, shared by SW and COLOR.
-- Project version: 0.9.0
local checks = {
  {'lq', 'RC-Link'}, {'armed', 'FC-Status'}, {'gps', 'GPS-Koordinaten'},
  {'fix', 'GPS-Fixtyp'}, {'voltage', 'Akkuspannung'},
  {'current', 'Stromsensor'}, {'used', 'mAh-Zähler'},
}
local labels = {valid='Gültig', missing='Nicht gefunden', stale='Veraltet',
  invalid='Ungültig', noapi='API fehlt', unknown='Unbekannt',
  unreceived='Nicht empfangen', disabled='Nicht konfiguriert'}
local tips = {missing='Sensoren neu suchen', stale='Auf neue Werte warten',
  invalid='Quelle/Einheit prüfen', unknown='EdgeTX-Version prüfen',
  noapi='EdgeTX-Version prüfen', disabled='config.lua prüfen'}
local fixes = {[0]='Kein GPS', 'Kein Fix', '2D', '3D', 'DGPS', 'RTK float', 'RTK fix'}
-- Keep setup-only strings out of the always-loaded SW catalogue.
local english = {
  ['GPS-Koordinaten']='GPS coordinates', ['GPS-Fixtyp']='GPS fix type',
  Akkuspannung='Battery voltage', Stromsensor='Current sensor', ['mAh-Zähler']='mAh counter',
  ['Nicht konfiguriert']='Not configured', ['Sensoren neu suchen']='Discover sensors',
  ['Auf neue Werte warten']='Wait for new data', ['Quelle/Einheit prüfen']='Check source and unit',
  ['EdgeTX-Version prüfen']='Check EdgeTX version', ['config.lua prüfen']='Check config.lua',
  ['ELRS MAVLink prüfen']='Check ELRS MAVLink', ['GPS am FC prüfen']='Check GPS on the FC',
  ['Auf GPS-Fix warten']='Wait for GPS fix',
  ['Konfiguriert:']='Configured:', ['Fixtyp fehlt noch']='Fix type not received',
}

return {
  count = #checks,
  text = function(key, tr, en)
    return en and english[key] or tr(key)
  end,
  check = function(index, monitor, receiver)
    local key, title = checks[index][1], checks[index][2]
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
      return title, status, 'ELRS MAVLink', tip
    end
    local sensor = monitor.sources[key]
    local state = sensor and sensor.state or 'disabled'
    local sourceLabel = (state == 'missing' or state == 'noapi') and 'Konfiguriert:' or 'Quelle:'
    local tip = key == 'gps' and state == 'valid' and receiver.status('fix') == 'unreceived'
      and 'Fixtyp fehlt noch' or tips[state]
    return title, labels[state], sensor and sensor.name, tip, sourceLabel
  end,
}
