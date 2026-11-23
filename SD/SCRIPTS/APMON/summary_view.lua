-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/summary_view.lua
-- Purpose: Format the armed summary and its data-gap notes for both displays.
-- Project version: 1.0.0
-- Updated: 2026-11-22
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local M = {}
local function number(value, format)
  return value == nil and '--' or string.format(format, value)
end

function M.rows(phase)
  local seconds = phase.duration
  local time = '--'
  if seconds then
    if seconds >= 3600 then
      time = string.format('%d:%02d:%02d', math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    else
      time = string.format('%02d:%02d', math.floor(seconds / 60), seconds % 60)
    end
  end
  return {
    {'Armed-Zeit', time}, {'RC-LQ min.', number(phase.lq, '%.0f %%')},
    {'Akku min.', number(phase.voltage, '%.2f V')},
    {'Strom max.', number(phase.current, '%.1f A')},
    {'Höhe rel. max.', number(phase.altitude, '%.1f m')},
    {'Akkuverbrauch', number(phase.used, '%.0f mAh')},
  }
end

function M.notes(phase)
  local notes = {}
  if phase.gaps then
    -- Same order as the counters in armed_summary.lua.
    local labels = {'FC-Status fehlt', 'Spannung fehlt', 'Stromsensor fehlt', 'Höhensensor fehlt', 'mAh-Sensor fehlt'}
    for i, label in ipairs(labels) do
      local count = phase.gaps[i]
      if count then
        count = math.abs(count)
        notes[#notes + 1] = {label, count > 999 and '999+' or count .. 'x'}
      end
    end
  end
  if not phase.started then notes[#notes + 1] = 'Start nicht erfasst' end
  if phase.voltage == nil or phase.current == nil or (phase.relativeSource and phase.altitude == nil) then
    notes[#notes + 1] = 'Messwerte unvollständig'
  end
  if phase.counterProblem then notes[#notes + 1] = 'mAh-Zähler unterbrochen'
  elseif phase.used == nil then notes[#notes + 1] = 'Kein mAh-Verbrauch' end
  if not phase.relativeSource then notes[#notes + 1] = 'Keine rel. Höhenquelle' end
  return notes
end
return M
