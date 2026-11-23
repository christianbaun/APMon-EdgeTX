-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/mono_gps.lua
-- Purpose: Draw the SW GPS detail page on demand.
-- Project version: 0.9.0
-- Updated: 2026-11-22
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local ui = ...
return function(_, width, _, text)
  local right = width - 2
  local rows, live, age = ui.gpsDetails(ui.monitor)
  ui.header(width, ui.tr('GPS-Details'))
  text(10, live and 'Live' or ui.tr('Nicht live'), not live)
  if age then ui.rightText(right, 10, string.format(ui.tr('vor %ds'), age), ui.small) end
  for i, row in ipairs(rows) do ui.field(2, right, 10 + i * 8, row[1], ui.monoText(row[2])) end
  text(57, ui.monoText('RTN: Menü'))
end
