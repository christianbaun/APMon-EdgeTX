-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/diagnostics.lua
-- Purpose: Summarize EdgeTX sensor and FC passthrough status for both displays.
-- Project version: 1.1.0
-- Updated: 2026-11-26
-- Authors: Christian Baun
-- Development assistance: OpenAI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local M = {}
M.stateLabel = { valid = 'Gültig', missing = 'Nicht gefunden', stale = 'Veraltet',
  invalid = 'Ungültig', noapi = 'API fehlt', unknown = 'Unbekannt', unreceived = 'Nicht empfangen',
  unsupported = 'Nicht verfügbar' }

function M.summary(monitor, receiver)
  local sources, valid, issue = monitor.sensorList, 0, nil
  for _, entry in ipairs(sources) do
    if entry.state == 'valid' then
      valid = valid + 1
    elseif not issue and entry.state ~= 'noapi' then
      issue = entry
    end
  end
  local fcState, fcAge = 'unsupported', nil
  if not monitor.betaflight then fcState, fcAge = receiver.status('armed') end
  return {
    link = monitor.sources.lq, valid = valid, total = #sources, issue = issue,
    fcState = fcState, fcAge = fcAge,
    message = receiver.message, messageAge = receiver.age(receiver.message),
  }
end
return M
