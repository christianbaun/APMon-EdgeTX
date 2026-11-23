-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/armed_summary.lua
-- Purpose: Keep the last observed armed interval and its sampled measurements.
-- Project version: 0.9.0
-- Updated: 2026-11-21
-- Authors: Christian Baun
-- Development assistance: OpenAI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local M = {}
local counterWindow = 300 -- maximum distance of a fresh capacity sample from an edge
local altitudeKeys = {'altitude', 'gpsaltitude'}

-- A negative count is an open gap. Consecutive missing samples count once.
local function gap(phase, key, missing)
  local gaps = phase.gaps
  local count = gaps and gaps[key] or 0
  if missing and count >= 0 then
    if not gaps then gaps = {}; phase.gaps = gaps end
    gaps[key] = -(count + 1)
  elseif not missing and count < 0 then
    gaps[key] = -count
  end
end

function M.new(relativeSource)
  local self = { relativeSource = relativeSource }
  local previous, seenAt, sampledAt

  function self:reset()
    self.active, self.last = nil, nil
    previous, seenAt, sampledAt = nil, nil, nil
  end

  function self:observe(armed, now, statusTimeout)
    local phase = self.active
    local continuous = seenAt ~= nil and now >= seenAt and now - seenAt <= statusTimeout
    if phase then
      if not continuous then gap(phase, 1, true) end
      gap(phase, 1, false)
    end
    if armed == 1 and not phase then
      local start = continuous and previous == 0 and now or nil
      self.active = { started = start, relativeSource = relativeSource }
      sampledAt = nil
    elseif armed == 0 and phase then
      if phase.started and not (phase.gaps and phase.gaps[1]) then
        phase.duration = math.floor((now - phase.started) / 100)
        if not phase.counterProblem and phase.counterStartAt and phase.counterAt > phase.counterStartAt
            and now - phase.counterAt <= counterWindow then
          phase.used = phase.counterEnd - phase.counterStart
        end
      end
      phase.missing = phase.voltage == nil or phase.current == nil
        or (relativeSource and phase.altitude == nil) or phase.used == nil
      phase.partial = phase.duration == nil or phase.gaps ~= nil or phase.missing
      self.active, self.last = nil, phase
    end
    previous, seenAt = armed, now
  end

  function self:sample(now, armed, values, sources)
    local phase = self.active
    if not phase then return end
    -- Without confirmed armed status, do not attribute the outage to sensors.
    if armed ~= 1 then gap(phase, 1, true); return end
    -- Multiple COLOR widget instances share a tracker and must not duplicate samples.
    if sampledAt and now - sampledAt < 20 then return end
    sampledAt = now
    local function fresh(key)
      local source = sources[key]
      if source and source.fresh then return values[key], source.name end
    end
    local volts, amps = fresh('voltage'), fresh('current')
    if volts and (not phase.voltage or volts < phase.voltage) then phase.voltage = volts end
    if amps and (not phase.current or amps > phase.current) then phase.current = amps end
    -- RQly is an independent, optional observation, never a proxy for FC gaps.
    local lq = fresh('lq')
    if lq and (not phase.lq or lq < phase.lq) then phase.lq = lq end
    local relativeKey
    if relativeSource then
      for _, key in ipairs(altitudeKeys) do
        if sources[key] and sources[key].name == relativeSource and values[key] ~= nil then
          relativeKey = key
          local altitude = fresh(key)
          if altitude and (not phase.altitude or altitude > phase.altitude) then phase.altitude = altitude end
          break
        end
      end
    end
    gap(phase, 2, values.voltage == nil)
    gap(phase, 3, values.current == nil)
    gap(phase, 4, relativeSource and not relativeKey)
    gap(phase, 5, values.used == nil)
    local used, name = fresh('used')
    if used and phase.started then
      if not phase.counterStart and now - phase.started <= counterWindow then
        phase.counterStart, phase.counterName, phase.counterStartAt = used, name, now
      end
      if phase.counterStart then
        if name ~= phase.counterName or (phase.counterEnd and used < phase.counterEnd) then
          phase.counterProblem = true
        end
        phase.counterEnd, phase.counterAt = used, now
      end
    elseif phase.counterStart and values.used == nil then
      phase.counterProblem = true
    end
  end
  return self
end

return M
