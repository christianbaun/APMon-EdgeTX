-- SPDX-License-Identifier: Apache-2.0
-- APMon: draw one telemetry setup check at a time on the SW screen.
-- Project version: 0.9.0
local ui = ...
local index, check = 1, ui.check
local function label(key) return ui.monoText(check.text(key, ui.tr, ui.english)) end
return function(_, width, _, text, step)
  index = (index - 1 + step) % check.count + 1
  local title, status, source, tip, sourceLabel = check.check(index, ui.monitor, ui.receiver)
  ui.header(width, ui.tr('Einrichtungscheck'))
  ui.field(2, width - 2, 11, label(title), index .. '/' .. check.count)
  text(20, label(status))
  if source then text(29, label(sourceLabel or 'Quelle:') .. ' ' .. source) end
  if tip then text(38, label(tip)) end
  text(57, ui.tr('Rad: Seite'))
  ui.rightText(width - 2, 57, ui.tr('RTN: Diagnose'), ui.small)
end
