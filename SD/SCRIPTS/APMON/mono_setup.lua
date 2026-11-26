-- SPDX-License-Identifier: Apache-2.0
-- APMon: draw one telemetry setup check at a time on the SW screen.
-- Project version: 1.1.0
local ui = ...
local index, check = 1, ui.check
local function label(key) return ui.monoText(check.text(key, ui.tr, ui.english)) end
return function(_, width, _, text, step)
  index = (index - 1 + step) % check.count + 1
  local title, status, source, tip, sourceLabel, configured =
    check.check(index, ui.monitor, ui.receiver, ui.config)
  ui.header(width, ui.tr('Einrichtungscheck'))
  ui.field(2, width - 2, 11, label(title), index .. '/' .. check.count)
  text(20, label(status))
  if configured then
    local prefix = label('Konfiguriert:') .. ' '
    if ui.textWidth(prefix .. configured, ui.small) > width then
      configured = ui.fit(configured, width - ui.textWidth(prefix .. '...', ui.small), ui.small) .. '...'
    end
    text(29, prefix .. configured)
  end
  if source then text(38, label(sourceLabel) .. ' ' .. source) end
  if tip then text(47, label(tip)) end
  text(57, ui.tr('Rad: Seite'))
  ui.rightText(width - 2, 57, ui.tr('RTN: Diagnose'), ui.small)
end
