-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/mono_tools.lua
-- Purpose: Draw the optional SW diagnostic screens on demand.
-- Project version: 1.3.2
-- Updated: 2026-11-26
-- Authors: Christian Baun
-- Development assistance: OpenAI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local ui = ...
local tr, monoText, header = ui.tr, ui.monoText, ui.header
local field = ui.field
local monitor, receiver = ui.monitor, ui.receiver

return function(_, width, sensorIndex, text)
  local right = width - 2
  header(width, tr('Telemetrie-Diagnose'))
  local data = ui.diagnostics.summary(monitor, receiver)
  local state = ui.diagnostics.stateLabel
  local link = data.link
  local linkLabel = link and (link.state == 'valid' and monitor:formatSensor(link) or monoText(state[link.state]))
    or '--'
  field(2, right, 11, 'RC-Link', linkLabel)
  field(2, right, 19, 'Sensoren', monitor.api and string.format(monoText('%d/%d gültig'), data.valid, data.total)
    or monoText(state.noapi))
  if monitor.betaflight then
    text(27, tr('FC-Status und -Text'))
    text(35, tr('Nur mit ArduPilot'))
  else
    local fc = monoText(state[data.fcState])
    if data.fcAge then fc = fc .. ' ' .. data.fcAge .. 's' end
    field(2, right, 27, 'FC-Status', fc)
    field(2, right, 35, 'FC-Text', data.messageAge and string.format(tr('vor %ds'), data.messageAge) or '--')
  end
  ui.option(width, 43, tr('Sensoren'), sensorIndex == 1)
  ui.option(width, 50, tr('Bericht speichern'), sensorIndex == 2)
  ui.option(width, 57, tr('Einrichtungscheck'), sensorIndex == 3)
end
