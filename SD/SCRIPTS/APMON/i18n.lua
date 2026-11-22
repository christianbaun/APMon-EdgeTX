-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/i18n.lua
-- Purpose: Provide the extensible GUI language registry, translations and fallback rules.
-- Project version: 0.6.0
-- Updated: 2026-11-21
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- GUI translations only. Sensor names and incoming FC messages stay unchanged.
-- Compile one string rather than many string constants. SW looks up labels
-- directly in it, without allocating a translation hash table at startup.
local catalogue = [[

Enter: waehlen|ENTER:select RTN:back
Rest|Left
Verbr.|Used
FC-Meldungen|FC messages
Sprache|Language
Zurück|Back
Menü|Menu
Vollbild: Menü|Full screen: menu
Nur für diese Sitzung|For this session only
Rad: Seite|Wheel: page
ENT: Menu|ENT: menu
Übersicht|Overview
Akku|Battery
Flugwerte|Flight
Lage|Attitude
FC-Status|FC status
Spannung|Voltage
Strom|Curr.
Rest (FC)|Left (FC)
Verbrauch|Used
Höhe (GAlt)|Alt. (GAlt)
Breite|Latitude
Laenge|Longitude
Länge|Longitude
GPS-Kurs|GPS course
GPS-Details|GPS details
Nicht live|Not live
Kein Fix|No fix
Bestätigt|Confirmed
Enter: speichern|ENTER: save RTN:cancel
Sprache nicht gespeichert|Language not saved
Uhr nicht gespeichert|Clock not saved
Uhr|Clock
An|On
Aus|Off
ENT: Details|ENT: details
RTN: Liste|RTN: list
Keine FC-Meldungen|No FC messages
Keine Warnungen|No warnings
Filter: Alle|Filter: All
Filter: Warnungen|Filter: Warnings
Filter: Warnungen & Fehler|Filter: Warnings & errors
ENT: Filter|ENT: filter
Armen bestätigt|Arming confirmed
Entarmen bestätigt|Disarming confirmed
Schweregrad %d|Severity %d
Neuere|Newer
Ältere|Older
vor %ds|%ds ago
FC-Daten fehlen|FC data missing
Rad: Ansicht ENTER:Sprache|Wheel: view ENTER:language
RC-Linkqualität|RC link quality
APMon: grosse Zone waehlen|APMon: select a large zone
AKKU / STATUS / GPS|BATTERY / STATUS / GPS
FLUG|FLIGHT
Flugmodus|Flight mode
Motoren|Motors
Akku (Spannung)|Battery (voltage)
Akku (Strom)|Battery (current)
Akku (Rest laut FC)|Battery (left, FC)
Akku (Verbrauch)|Battery (used)
GPS Fix|GPS fix
Satelliten|Satellites
EKF zuletzt|Last EKF set
Höhe|Altitude
Höhe (GPS Altitude)|Height (GPS Altitude)
H-Tempo GPS|GPS horiz. speed
Richtung|Direction
Steigen|Climb rate
Vario|Climb
Ja|Yes
Nein|No
Kein GPS|No GPS
Keins|None
Ja 2D|Yes 2D
Ja 3D|Yes 3D
Ja DGPS|Yes DGPS
Ja RTK flt|Yes RTK flt
Ja RTK fix|Yes RTK fix
API fehlt: getSourceValue|Missing getSourceValue API
Keine aktuellen FC-Daten|No current FC data
FC-Meldung: --|FC message: --
FC-Meldung / vor %ds|FC message / %ds ago
Telemetrie-Diagnose|Telemetry diagnostics
Diagnose|Diagnostics
Datenquellen|Data sources
Sensoren|Sensors
EdgeTX-Sensoren|EdgeTX sensors
RC-Link|RC link
FC-Text|FC text
Letzte FC-Textmeldung|Last FC text message
FC-Status (Passthrough)|FC status (passthrough)
Gültig|Valid
Ungültig|Invalid
Unbekannt|Unknown
Nicht gefunden|Not found
Veraltet|Stale
Nicht empfangen|Not received
API fehlt|API unavailable
%d/%d gültig|%d/%d valid
Keine Sensoren konfiguriert|No sensors configured
Letzter Wert|Last value
Gültige Sensordaten sind keine Flugfreigabe.|Valid sensor data is not flight clearance.
ENT: Sensoren|ENT: sensors
RTN: Menü|RTN: menu
RTN: Diagnose|RTN: diagnostics
Vorige|Previous
Weitere|Next
Letzte Armed-Phase|Last armed period
Armed-Zeit|Time armed
Akku min.|Min. voltage
Strom max.|Peak current
Höhe rel. max.|Max. rel. alt.
Akkuverbrauch|Charge used
Keine Bilanz vorhanden|No summary yet
Aufzeichnung läuft|Recording
Armed-Zeit, nicht Flugzeit|Time armed, not flight time
Vollständig|Complete
Unvollständig|Incomplete
Bilanzdetails|Summary details
Details|Details
RTN: Bilanz|RTN: summary
Start nicht erfasst|Start not observed
Lücke im FC-Status|FC status gap
Messwerte unvollständig|Incomplete readings
mAh-Zähler unterbrochen|mAh counter interrupted
Kein mAh-Verbrauch|Charge used unavailable
Keine rel. Höhenquelle|No rel. altitude source
Keine Datenlücke erkannt|No data gap detected
Speicher knapp|Not enough memory
Werkzeug nicht ladbar|Tool could not be loaded
]]
local lookupEnglish
if ... == 'compact' then
  lookupEnglish = function(value)
    if type(value) ~= 'string' or string.find(value, '[|\n]') then return end
    local _, stop = string.find(catalogue, '\n' .. value .. '|', 1, true)
    if stop then return string.sub(catalogue, stop + 1, string.find(catalogue, '\n', stop + 1, true) - 1) end
  end
else
  local english = {}
  for key, value in string.gmatch(catalogue, '([^\n|]+)|([^\n]+)') do english[key] = value end
  lookupEnglish = function(value) return english[value] end
  catalogue = nil
end
-- Append languages here; keep existing entries in order (EdgeTX stores indices).
-- Missing translations fall back to English. German source labels remain keys.
local languages = {
  { code = 'en', name = 'English',
    directions = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' } },
  { code = 'de', name = 'Deutsch', texts = { ['ENT: Menu'] = 'ENT: Menü' },
    directions = { 'N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW' } },
}
local function language(index)
  return languages[index] or languages[1]
end
local choices = {}
for i, entry in ipairs(languages) do choices[i] = entry.name end
return {
  languages = languages,
  choices = choices,
  language = language,
  text = function(index, value)
    local entry = language(index)
    local translated = entry.texts and entry.texts[value]
    if translated then return translated end
    if entry.code == 'de' then return value end
    return lookupEnglish(value) or value
  end,
}
