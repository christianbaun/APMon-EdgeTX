-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/mono_report.lua
-- Purpose: Confirm a one-shot diagnostic report on SW displays.
-- Project version: 1.1.0
-- Updated: 2026-11-26
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local ui = ...
local choice = 1
return function(_, width, _, text, step, enter)
  if not ui.monitor.betaflight and step ~= 0 then choice = 3 - choice end
  if enter then return choice == 2 end
  ui.header(width, ui.tr('Diagnosebericht'))
  text(11, ui.reportPath)
  text(19, ui.tr('Ersetzt alten Bericht'))
  ui.option(width, 37, ui.tr('Ohne FC-Klartext'), choice == 1)
  if not ui.monitor.betaflight then
    text(27, ui.tr('Klartext evtl. mit GPS'))
    ui.option(width, 45, ui.tr('Mit FC-Klartext'), choice == 2)
  end
  text(57, ui.tr('ENT: Speichern'))
end
