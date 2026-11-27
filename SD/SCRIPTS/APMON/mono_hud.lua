-- SPDX-License-Identifier: Apache-2.0
-- APMon: attitude HUD for the 128 × 64 monochrome telemetry screen.
-- Project version: 1.3.2
local monitor, receiver, header, field, tr, rightText, small, draw, readings = ...

local function line(x1, y1, x2, y2, kind)
  lcd.drawLine(x1, y1, x2, y2, kind == 'ladder' and (DOTTED or 0x55) or (SOLID or 255), FORCE or 0)
end
local function angle(value)
  if value and math.abs(value) < 0.5 then value = 0 end
  return value and string.format('%.0f°', value) or '--'
end
local function compact(key)
  return (string.gsub(monitor:format(key), ' ', ''))
end

return function(_, width, _, text)
  header(width, 'HUD', '3/3')
  local side = math.floor(width / 4)
  local roll, pitch, frozen
  if draw then roll, pitch, frozen = readings.horizon(monitor)
  else roll, pitch = readings.attitude(monitor) end
  if draw and roll and pitch then draw(roll, pitch, side, 11, width - 2 * side, 25, line) end
  lcd.drawText(2, 11, 'Roll', small)
  rightText(width - 2, 11, 'Pitch', small)
  lcd.drawText(2, 19, angle(roll), small)
  rightText(width - 2, 19, angle(pitch), small)
  if not (draw and roll and pitch) then
    text(27, tr(draw and 'Lagedaten fehlen' or 'Werkzeug nicht ladbar'))
  elseif frozen then
    lcd.drawText(2, 27, 'HOLD', small + (INVERS or 0))
  end
  -- Reserve two full-width rows for the sensor readings instead of flank columns.
  line(2, 37, width - 3, 37)
  local bat, lq, half = math.floor(width * 0.4), math.floor(width * 0.68), math.floor(width / 2)
  field(2, bat - 1, 40, 'Bat', compact('voltage'))
  field(bat + 2, lq - 2, 40, '', compact('current'))
  field(lq + 1, width - 2, 40, 'LQ', monitor:format('lq'))
  field(2, half - 3, 49, 'GPS:', readings.gpsFix(monitor, tr, true) .. '/' .. monitor:format('satellites'))
  if not monitor.betaflight then field(half + 1, width - 2, 49, 'EKF', readings.ekf(receiver)) end
  lcd.drawText(2, 57, tr('Rad: Seite'), small)
  rightText(width - 2, 57, tr('ENT: Menu'), small)
end
