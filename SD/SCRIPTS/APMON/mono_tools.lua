-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/mono_tools.lua
-- Purpose: Draw the optional SW diagnostic screens on demand.
-- Project version: 0.6.0
-- Updated: 2026-11-21
-- Authors: Christian Baun
-- Development assistance: OpenAI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local ui = ...
local tr, monoText, header = ui.tr, ui.monoText, ui.header
local field, rightText, small = ui.field, ui.rightText, ui.small
local monitor, receiver = ui.monitor, ui.receiver

return function(view, width, sensorIndex, text)
  local right = width - 2
  if view == 'diagnostics' then
    header(width, tr('Telemetrie-Diagnose'))
    local data = ui.diagnostics.summary(monitor, receiver)
    local state = ui.diagnostics.stateLabel
    local link = data.link
    local linkLabel = link and (link.state == 'valid' and monitor:formatSensor(link) or monoText(state[link.state]))
      or '--'
    field(2, right, 11, 'RC-Link', linkLabel)
    field(2, right, 19, 'Sensoren', monitor.api and string.format(monoText('%d/%d gültig'), data.valid, data.total)
      or monoText(state.noapi))
    local fc = monoText(state[data.fcState])
    if data.fcAge then fc = fc .. ' ' .. data.fcAge .. 's' end
    field(2, right, 27, 'FC-Status', fc)
    field(2, right, 35, 'FC-Text', data.messageAge and string.format(tr('vor %ds'), data.messageAge) or '--')
    if data.issue then text(43, monoText(state[data.issue.state]) .. ': ' .. data.issue.name) end
    ui.filled(2, 51, width - 4, 1)
    text(57, tr('ENT: Sensoren'))
    rightText(right, 57, monoText('RTN: Menü'), small)
  else
    header(width, tr('Sensoren'))
    local count = #monitor.sensorList
    local entry = monitor.sensorList[sensorIndex]
    if entry then
      local position = sensorIndex .. '/' .. count
      lcd.drawText(2, 11, ui.fit(entry.name, width - 6 - ui.textWidth(position, small), small), small)
      rightText(right, 11, position, small)
      text(21, monoText(ui.diagnostics.stateLabel[entry.state]))
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
end
