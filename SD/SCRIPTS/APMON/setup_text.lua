-- SPDX-License-Identifier: Apache-2.0
-- Setup-only translations. Compile this catalogue separately on SW.
-- Project version: 1.3.2
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
Nicht bestätigt|Unconfirmed
Kein bestätigter Fix|No verified GPS fix
Erkannt:|Detected:
Höhe zuordnen|Map relative altitude
Relative Höhe|Relative altitude
Nicht zugeordnet|Not mapped
Nicht ausgewählt|Not selected
Andere Quelle:|Other source:
Zuordnung prüfen|Check mapping
Alias-Reihenfolge prüfen|Check alias order
Nächster Schritt|Next step
Profil:|Profile:
Keine aktuellen Werte|No current readings
Modell und Link prüfen|Check model and link
FC-Sensorwerte fehlen|No FC sensor readings
EdgeTX-Sensorliste prüfen|Check EdgeTX sensor list
RC-Linkwert fehlt|No RC link reading
RC-Linkquelle prüfen|Check RC link source
Passthrough-API fehlt|Passthrough API missing
FC-Status veraltet|FC status stale
Passthrough prüfen|Check passthrough
Akkuspannung fehlt|No battery voltage
Akkuquelle prüfen|Check battery source
HUD-Lagedaten fehlen|No HUD attitude data
Roll und Nick prüfen|Check roll and pitch
GPS-Fix nicht bestätigt|GPS fix unconfirmed
Fix für Live-GPS prüfen|Check fix for live GPS
GPS-Passthrough prüfen|Check GPS passthrough
Basiswerte vorhanden|Basic readings available
Details bei Bedarf prüfen|Check details as needed
]]
return function(key, tr, en)
  if en then
    local _, e = string.find(english, '\n' .. key .. '|', 1, true)
    if e then return string.sub(english, e + 1, string.find(english, '\n', e + 1, true) - 1) end
  end
  return tr(key)
end
