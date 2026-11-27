-- SPDX-License-Identifier: Apache-2.0
-- APMon: prepare HUD readings, including independently timed attitude samples.
-- Project version: 1.3.2
local function gpsFix(monitor, tr, compact)
  local fix = monitor.gpsFixLabel
  if not fix then return '--' end
  if compact then
    if fix == 'Kein GPS' or fix == 'Kein Fix' then return tr('Nein') end
    if fix == 'Bestätigt' then return tr('Ja') end
    if fix == 'RTK float' then return 'RTKf' end
    if fix == 'RTK fix' then return 'RTK' end
  end
  return tr(fix)
end

local function ekf(receiver)
  local age = receiver.age(receiver.ekf)
  return age and receiver.ekf.value .. '/' .. age .. 's' or '--'
end

local hold = 100 -- one second at 10 ms per tick
local function recent(entry, now)
  local at = entry and entry.freshAt
  if at and now >= at and now - at <= hold then return entry.freshValue end
end

local function attitude(monitor)
  -- Redraws use the sample's timestamp, not the time of this draw.
  local now = getTime()
  local roll, pitch = recent(monitor.sources.roll, now), recent(monitor.sources.pitch, now)
  return roll and (roll + 180) % 360 - 180, pitch
end

local function horizon(monitor)
  local roll, pitch = attitude(monitor)
  if roll and pitch then
    monitor.hudRoll, monitor.hudPitch = roll, pitch
  elseif monitor.hudRoll then
    -- Keep the last complete pose, not a mix of old and newly arrived axes.
    return monitor.hudRoll, monitor.hudPitch, true
  end
  return roll, pitch, false
end

return {gpsFix = gpsFix, ekf = ekf, attitude = attitude, horizon = horizon}
