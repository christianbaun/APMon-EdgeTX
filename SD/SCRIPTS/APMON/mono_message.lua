-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/mono_message.lua
-- Purpose: Draw the full text of a selected FC message on SW displays.
-- Project version: 1.1.0
-- Updated: 2026-11-22
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local ui = ...
return function(_, width, _, text)
  ui.header(width, ui.tr('FC-Meldungen'))
  local message = ui.message
  local age = ui.receiver.age(message)
  if message.armed ~= nil then
    text(11, message.armed == 1 and 'ARMED' or 'DISARMED')
    text(20, ui.monoText(message.armed == 1 and 'Armen bestätigt' or 'Entarmen bestätigt'))
    if age then text(29, string.format(ui.tr('vor %ds'), age)) end
  else
    local repeats = message.repeats > 1 and ' x' .. message.repeats or ''
    text(11, string.format('S%d%s %s', message.severity, repeats, age and age .. 's' or '--'))
    local value = message.value
    for i = 1, 4 do
      if value == '' then break end
      local part = ui.fit(value, width, ui.small)
      text(20 + (i - 1) * 9, part)
      value = string.sub(value, #part + 1)
    end
  end
  text(57, ui.tr('RTN: Liste'))
end
