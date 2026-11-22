-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/mono_summary.lua
-- Purpose: Draw the optional SW armed-summary screens on demand.
-- Project version: 0.6.0
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

return function(view, width, _, text)
  local right = width - 2
  local detail, phase = view == 'summaryDetail', ui.tracker.last
  header(width, tr(detail and 'Bilanzdetails' or 'Letzte Armed-Phase'))
  if not phase then
    text(11, tr('Keine Bilanz vorhanden'))
    if ui.tracker.active then text(22, monoText('Aufzeichnung läuft')) end
  elseif detail then
    local notes = ui.summary.notes(phase)
    if #notes == 0 then notes[1] = 'Keine Datenlücke erkannt' end
    for i, note in ipairs(notes) do text(11 + (i - 1) * 8, monoText(note)) end
  else
    for i, row in ipairs(ui.summary.rows(phase)) do field(2, right, 10 + (i - 1) * 8, row[1], row[2]) end
    text(50, monoText(phase.partial and 'Unvollständig' or 'Vollständig'))
  end
  if detail then
    text(57, tr('RTN: Bilanz'))
  else
    if phase then text(57, tr('ENT: Details')) end
    rightText(right, 57, monoText('RTN: Menü'), small)
  end
end
