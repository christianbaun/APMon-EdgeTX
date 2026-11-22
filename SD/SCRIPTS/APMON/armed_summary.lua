-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/armed_summary.lua
-- Purpose: Keep the last observed armed interval and its sampled measurements.
-- Project version: 0.5.0
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
    if phase and not continuous then phase.statusGap = true end
    if armed == 1 and not phase then
      local start = continuous and previous == 0 and now or nil
      self.active = { started = start, relativeSource = relativeSource }
      sampledAt = nil
    elseif armed == 0 and phase then
      if phase.started and not phase.statusGap then
        phase.duration = math.floor((now - phase.started) / 100)
        if not phase.counterProblem and phase.counterStartAt and phase.counterAt > phase.counterStartAt
            and now - phase.counterAt <= counterWindow then
          phase.used = phase.counterEnd - phase.counterStart
        end
      end
      phase.missing = phase.sensorGap or phase.voltage == nil or phase.current == nil
        or (relativeSource and phase.altitude == nil) or phase.used == nil
      phase.partial = phase.duration == nil or phase.missing
      self.active, self.last = nil, phase
    end
    previous, seenAt = armed, now
  end

  function self:sample(now, armed, values, sources)
    local phase = self.active
    if not phase then return end
    if armed ~= 1 then phase.statusGap = true; return end
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
    if values.voltage == nil or values.current == nil or (relativeSource and not relativeKey) then
      phase.sensorGap = true
    end
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

local function number(value, format)
  return value == nil and '--' or string.format(format, value)
end

function M.rows(phase)
  local seconds = phase.duration
  local time = '--'
  if seconds then
    if seconds >= 3600 then
      time = string.format('%d:%02d:%02d', math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
    else
      time = string.format('%02d:%02d', math.floor(seconds / 60), seconds % 60)
    end
  end
  return {
    {'Armed-Zeit', time}, {'Akku min.', number(phase.voltage, '%.2f V')},
    {'Strom max.', number(phase.current, '%.1f A')},
    {'Höhe rel. max.', number(phase.altitude, '%.1f m')},
    {'Akkuverbrauch', number(phase.used, '%.0f mAh')},
  }
end

function M.notes(phase)
  local notes = {}
  if not phase.started then notes[#notes + 1] = 'Start nicht erfasst' end
  if phase.statusGap then notes[#notes + 1] = 'Lücke im FC-Status' end
  if phase.missing then notes[#notes + 1] = 'Messwerte unvollständig' end
  if phase.counterProblem then notes[#notes + 1] = 'mAh-Zähler unterbrochen'
  elseif phase.used == nil then notes[#notes + 1] = 'Kein mAh-Verbrauch' end
  if not phase.relativeSource then notes[#notes + 1] = 'Keine rel. Höhenquelle' end
  return notes
end
return M
