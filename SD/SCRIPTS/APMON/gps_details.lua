-- SPDX-License-Identifier: Apache-2.0
-- APMon: format GPS rows only when the detail page is in use.
-- Project version: 1.0.0
return function(monitor)
  local pos, live, now = monitor.gpsPosition, monitor.gpsLive, getTime()
  local function liveValue(key)
    local entry = monitor.sources[key]
    if live and entry and entry.freshAt and now - entry.freshAt <= monitor.gpsGrace then
      return monitor:format(key, entry.freshValue)
    end
    return '--'
  end
  return {
    { 'Breite', pos and string.format('%.6f', pos.lat) or '--' },
    { 'Länge', pos and string.format('%.6f', pos.lon) or '--' },
    { 'GPS Fix', monitor.gpsFixLabel or '--' },
    { 'Satelliten', liveValue('satellites') },
    { 'GPS-Kurs', liveValue('heading') },
  }, live, not live and pos and math.floor((now - monitor.gpsTime) / 100) or nil
end
