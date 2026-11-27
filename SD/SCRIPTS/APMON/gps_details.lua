-- SPDX-License-Identifier: Apache-2.0
-- APMon: format GPS rows only when the detail page is in use.
-- Project version: 1.3.2
return function(monitor)
  local pos, live, now = monitor.gpsPosition, monitor.gpsLive, getTime()
  local function liveValue(key, allowWithoutFix)
    local entry = monitor.sources[key]
    if (live or allowWithoutFix) and entry and entry.freshAt and now - entry.freshAt <= monitor.gpsGrace then
      return monitor:format(key, entry.freshValue)
    end
    return '--'
  end
  return {
    { 'Breite', pos and string.format('%.6f', pos.lat) or '--' },
    { 'Länge', pos and string.format('%.6f', pos.lon) or '--' },
    { 'GPS Fix', monitor.gpsFixLabel or '--' },
    -- Satellite count is independent of fix confirmation in the Betaflight profile.
    { 'Satelliten', liveValue('satellites', monitor.betaflight) },
    { 'GPS-Kurs', liveValue('heading') },
  }, live, not live and pos and math.floor((now - monitor.gpsTime) / 100) or nil
end
