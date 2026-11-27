-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/mono_sensors.lua
-- Purpose: Draw detailed sensor status on SW displays.
-- Project version: 1.2.0
-- Updated: 2026-11-22
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local ui = ...
local monitor, tr, small = ui.monitor, ui.tr, ui.small
return function(_, width, sensorIndex, text)
  ui.header(width, tr('Sensoren'))
  local count = #monitor.sensorList
  local entry = monitor.sensorList[sensorIndex]
  if entry then
    local position = sensorIndex .. '/' .. count
    lcd.drawText(2, 11, ui.fit(entry.name, width - 6 - ui.textWidth(position, small), small), small)
    ui.rightText(width - 2, 11, position, small)
    text(21, ui.monoText(ui.diagnostics.stateLabel[entry.state]))
    text(33, tr('Letzter Wert') .. ':')
    local value = monitor:lastSensorValue(entry)
    if entry.key == 'gps' and value then
      text(41, string.format('Lat %.6f', value.lat))
      text(49, string.format('Lon %.6f', value.lon))
    else
      text(43, monitor:formatSensor(entry))
    end
  else
    text(11, tr('Keine Sensoren konfiguriert'))
  end
  text(57, tr('RTN: Diagnose'))
end
