-- SPDX-License-Identifier: Apache-2.0
-- APMon: project recent attitude onto a clipped wireframe horizon.
-- Project version: 1.0.0
local function clip(lo, hi, point, direction, first, last)
  if math.abs(direction) < 0.00001 then
    if point >= first and point <= last then return lo, hi end
    return 1, 0
  end
  local a, b = (first - point) / direction, (last - point) / direction
  return math.max(lo, math.min(a, b)), math.min(hi, math.max(a, b))
end

local function point(v) return math.floor(v + 0.5) end

return function(roll, pitch, x, y, w, h, line)
  local cx, cy = x + (w - 1) / 2, y + (h - 1) / 2
  local radians = (roll % 360) * math.pi / 180
  local dx, dy = math.cos(radians), -math.sin(radians)
  local scale = h / 55
  for mark = -80, 80, 10 do
    local delta = pitch - mark
    if math.abs(delta) <= (mark == 0 and 55 or 30) then
      local half = mark == 0 and math.max(h * 0.8, w * 0.42) or h * (mark % 20 == 0 and 0.25 or 0.16)
      -- Positive pitch puts the zero rung below the fixed aircraft.
      local px, py = cx - dy * delta * scale, cy + dx * delta * scale
      local lo, hi = clip(-half, half, px, dx, x, x + w - 1)
      lo, hi = clip(lo, hi, py, dy, y, y + h - 1)
      if lo <= hi then
        line(point(px + lo * dx), point(py + lo * dy),
          point(px + hi * dx), point(py + hi * dy), mark == 0 and 'horizon' or 'ladder')
      end
    end
  end
  local span, gap = math.max(7, math.floor(h / 6)), math.max(3, math.floor(h / 16))
  local ix, iy = point(cx), point(cy)
  line(ix - span, iy, ix - gap, iy, 'aircraft')
  line(ix - gap, iy, ix, iy + gap, 'aircraft')
  line(ix, iy + gap, ix + gap, iy, 'aircraft')
  line(ix + gap, iy, ix + span, iy, 'aircraft')
end
