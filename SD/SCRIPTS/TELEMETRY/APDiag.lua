-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/TELEMETRY/APDiag.lua
-- Purpose: Display raw EdgeTX sensor values and API validity flags for troubleshooting.
-- Project version: 1.1.0
-- Updated: 2026-11-20
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- Independent read-only probe: compare EdgeTX APIs without APMon filtering.
local names = { 'RxBt', 'Curr', 'Capa', 'Bat%', 'Alt', 'VSpd',
  'GPS', 'GSpd', 'Hdg', 'Sats', 'FM', 'RQly' }
local page = 1
local function show(value)
  if type(value) == 'number' then return string.format('%.2f', value) end
  if type(value) == 'table' then return 'table (GPS)' end
  return string.sub(tostring(value), 1, 15)
end
local function run(event)
  if event and ((EVT_VIRTUAL_NEXT and event == EVT_VIRTUAL_NEXT)
      or (EVT_PLUS_FIRST and event == EVT_PLUS_FIRST)) then
    page = page % #names + 1
  elseif event and ((EVT_VIRTUAL_PREV and event == EVT_VIRTUAL_PREV)
      or (EVT_MINUS_FIRST and event == EVT_MINUS_FIRST)) then
    page = (page - 2) % #names + 1
  end
  local name = names[page]
  local info = getFieldInfo(name)
  local function text(y, value)
    lcd.drawText(0, y, string.sub(value, 1, 25), SMLSIZE or 0)
  end
  lcd.clear()
  text(0, 'DIAG ' .. name .. ' ' .. page .. '/' .. #names)
  if not info then
    text(12, 'Sensorname fehlt')
  elseif type(getSourceValue) ~= 'function' then
    text(12, 'getSourceValue fehlt')
  else
    local value, current, fresh = getSourceValue(info.id)
    text(10, 'ID ' .. tostring(info.id) .. ' ' .. type(value))
    text(22, 'API: ' .. show(value))
    text(32, 'C=' .. tostring(current) .. ' F=' .. tostring(fresh))
    text(42, 'getValue: ' .. show(getValue(info.id)))
  end
  text(54, '+/- Sensor wechseln')
  return 0
end
return { run = run }
