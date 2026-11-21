-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/i18n.lua
-- Purpose: Provide the extensible GUI language registry, translations and fallback rules.
-- Project version: 0.3.0
-- Updated: 2026-11-21
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- GUI translations only. Sensor names and incoming FC messages stay unchanged.
local english = {
  ['Enter: waehlen'] = 'ENTER:select RTN:back',
  ['Rest'] = 'Left', ['Verbr.'] = 'Used',
  ['FC-Meldungen'] = 'FC messages',
  ['Sprache'] = 'Language', ['Zurück'] = 'Back', ['Menü'] = 'Menu',
  ['Vollbild: Menü'] = 'Full screen: menu',
  ['Nur für diese Sitzung'] = 'For this session only',
  ['Rad: Seite'] = 'Wheel: page', ['ENT: Menu'] = 'ENT: menu',
  ['Übersicht'] = 'Overview', ['Akku'] = 'Battery',
  ['Flugwerte'] = 'Flight', ['Lage'] = 'Attitude', ['FC-Status'] = 'FC status',
  ['Spannung'] = 'Voltage', ['Strom'] = 'Curr.', ['Rest (FC)'] = 'Left (FC)',
  ['Verbrauch'] = 'Used', ['Höhe (GAlt)'] = 'Alt. (GAlt)',
  ['Breite'] = 'Latitude', ['Laenge'] = 'Longitude', ['GPS-Kurs'] = 'GPS course',
  ['Enter: speichern'] = 'ENTER: save RTN:cancel',
  ['Sprache nicht gespeichert'] = 'Language not saved',
  ['Uhr nicht gespeichert'] = 'Clock not saved',
  ['Uhr'] = 'Clock', ['An'] = 'On', ['Aus'] = 'Off',
  ['ENT: Details'] = 'ENT: details', ['RTN: Liste'] = 'RTN: list',
  ['Keine FC-Meldungen'] = 'No FC messages',
  ['Schweregrad %d'] = 'Severity %d',
  ['Neuere'] = 'Newer', ['Ältere'] = 'Older',
  ['vor %ds'] = '%ds ago',
  ['FC-Daten fehlen'] = 'FC data missing',
  ['Rad: Ansicht ENTER:Sprache'] = 'Wheel: view ENTER:language',
  ['RC-Linkqualität'] = 'RC link quality',
  ['APMon: grosse Zone waehlen'] = 'APMon: select a large zone',
  ['AKKU / STATUS / GPS'] = 'BATTERY / STATUS / GPS',
  ['FLUG'] = 'FLIGHT',
  ['Flugmodus'] = 'Flight mode',
  ['Motoren'] = 'Motors',
  ['Akku (Spannung)'] = 'Battery (voltage)',
  ['Akku (Strom)'] = 'Battery (current)',
  ['Akku (Rest laut FC)'] = 'Battery (left, FC)',
  ['Akku (Verbrauch)'] = 'Battery (used)',
  ['GPS Fix'] = 'GPS fix',
  ['Satelliten'] = 'Satellites',
  ['EKF zuletzt'] = 'Last EKF set',
  ['Höhe'] = 'Altitude',
  ['Höhe (GPS Altitude)'] = 'Height (GPS Altitude)',
  ['H-Tempo GPS'] = 'GPS horiz. speed',
  ['Richtung'] = 'Direction',
  ['Steigen'] = 'Climb rate', ['Vario'] = 'Climb',
  ['Ja'] = 'Yes', ['Nein'] = 'No', ['Kein GPS'] = 'No GPS',
  ['Keins'] = 'None',
  ['Ja 2D'] = 'Yes 2D', ['Ja 3D'] = 'Yes 3D', ['Ja DGPS'] = 'Yes DGPS',
  ['Ja RTK flt'] = 'Yes RTK flt', ['Ja RTK fix'] = 'Yes RTK fix',
  ['API fehlt: getSourceValue'] = 'Missing getSourceValue API',
  ['Keine aktuellen FC-Daten'] = 'No current FC data',
  ['FC-Meldung: --'] = 'FC message: --',
  ['FC-Meldung / vor %ds'] = 'FC message / %ds ago',
}
-- Append languages here; keep existing entries in order (EdgeTX stores indices).
-- Missing translations fall back to English. German source labels remain keys.
local german = {}
for key in pairs(english) do german[key] = key end
german['ENT: Menu'] = 'ENT: Menü'
local languages = {
  { code = 'en', name = 'English', texts = english,
    directions = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' } },
  { code = 'de', name = 'Deutsch', texts = german,
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
    return language(index).texts[value] or english[value] or value
  end,
}
