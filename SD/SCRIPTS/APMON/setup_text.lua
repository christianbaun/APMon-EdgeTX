-- SPDX-License-Identifier: Apache-2.0
-- Setup-only translations. Compile this catalogue separately on SW.
-- Project version: 1.0.0
local english = [[

GPS-Koordinaten|GPS coordinates
GPS-Fixtyp|GPS fix type
Akkuspannung|Battery voltage
Stromsensor|Current sensor
mAh-Zähler|mAh counter
Nicht konfiguriert|Not configured
Sensoren neu suchen|Discover sensors
Auf neue Werte warten|Wait for new data
Quelle/Einheit prüfen|Check source and unit
EdgeTX-Version prüfen|Check EdgeTX version
config.lua prüfen|Check config.lua
ELRS MAVLink prüfen|Check ELRS MAVLink
GPS am FC prüfen|Check GPS on the FC
Auf GPS-Fix warten|Wait for GPS fix
Konfiguriert:|Configured:
Fixtyp fehlt noch|Fix type not received
Erkannt:|Detected:
Höhe zuordnen|Map relative altitude
Relative Höhe|Relative altitude
Nicht zugeordnet|Not mapped
Nicht ausgewählt|Not selected
Andere Quelle:|Other source:
Zuordnung prüfen|Check mapping
Alias-Reihenfolge prüfen|Check alias order
]]
return function(key, tr, en)
  if en then
    local _, e = string.find(english, '\n' .. key .. '|', 1, true)
    if e then return string.sub(english, e + 1, string.find(english, '\n', e + 1, true) - 1) end
  end
  return tr(key)
end
