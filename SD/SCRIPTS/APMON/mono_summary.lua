-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/mono_summary.lua
-- Purpose: Draw the optional SW armed-summary screens on demand.
-- Project version: 1.3.2
-- Updated: 2026-11-22
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local ui = ...
local tr, monoText, header = ui.tr, ui.monoText, ui.header
local field, rightText, small = ui.field, ui.rightText, ui.small

return function(view, width, page, text)
  local right = width - 2
  local detail, phase = view == 'summaryDetail', ui.tracker.last
  header(width, tr(detail and 'Bilanzdetails' or 'Letzte Armed-Phase'))
  if not phase then
    text(11, tr('Keine Bilanz vorhanden'))
    if ui.tracker.active then text(22, monoText('Aufzeichnung läuft')) end
  elseif detail then
    local notes = ui.notes
    if #notes == 0 then notes[1] = 'Keine Datenlücke erkannt' end
    local first = #notes > 5 and (page - 1) * 5 + 1 or 1
    for i = first, math.min(#notes, first + 4) do
      local note, y = notes[i], 10 + (i - first) * 8
      if type(note) == 'table' then field(2, right, y, note[1], note[2])
      else text(y, monoText(note)) end
    end
    if phase.gaps then text(50, monoText('Kein Beleg für RC-Ausfall')) end
    if #notes > 5 then rightText(right, 57, page .. '/2', small) end
  else
    for i, row in ipairs(ui.rows) do field(2, right, 10 + (i - 1) * 7, row[1], row[2]) end
  end
  if detail then
    text(57, tr('RTN: Bilanz'))
  elseif phase then
    text(57, tr('ENT: Details'))
    rightText(right, 57, monoText(phase.partial and 'Unvollständig' or 'Vollständig'), small)
  else
    rightText(right, 57, monoText('RTN: Menü'), small)
  end
end
