-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/core.lua
-- Purpose: Read and validate EdgeTX sensors and merge optional ArduPilot passthrough data.
-- Project version: 1.3.2
-- Updated: 2026-11-26
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- Read-only EdgeTX sensor adapter, optionally augmented by a shared receiver.
local M = {}
local function finite(v)
  return type(v) == 'number' and v == v and v > -math.huge and v < math.huge
end
local function validated(def, value)
  if def.text then
    if type(value) == 'string' then
      local clean = string.sub(string.gsub(value, '[%c]', ''), 1, 24)
      if #clean > 0 then return clean end
    end
  elseif def.gps then
    if type(value) == 'table' and finite(value.lat) and finite(value.lon)
        and math.abs(value.lat) <= 90 and math.abs(value.lon) <= 180 then
      return { lat = value.lat, lon = value.lon }
    end
  elseif finite(value) then
    if def.scale then value = value * def.scale end
    if finite(value) and (not def.min or value >= def.min) and (not def.max or value <= def.max)
        and (not def.binary or value == 0 or value == 1) then return value end
  end
end
local function formatValue(key, def, value, betaflight)
  if value == nil then return '--' end
  if def.gps then return string.format('%.6f, %.6f', value.lat, value.lon) end
  if def.text then
    if key == 'mode' then
      if betaflight then
        local base = string.match(value, '^(%a+)[*!?]?$')
        if base == 'STAB' or base == 'ANGL' then return 'ANGLE' end
        if base == 'HOR' then return 'HORIZON' end
        if base == 'WAIT' then return 'GPS WAIT' end
        if value == '!FS!' or value == '!FS!*' then return 'FAILSAFE' end
        return base or value
      end
      local base = string.match(value, '^(%a+)%*?$')
      local names = { STAB = 'STABILIZE', LOIT = 'LOITER', GUID = 'GUIDED' }
      if base then return names[base] or base end
    end
    return value
  end
  local decimals = def.decimals or 0
  if math.abs(value) < 0.5 * 10 ^ -decimals then value = 0 end
  return string.format('%.' .. decimals .. 'f', value) ..
    (def.unit ~= '' and ' ' .. def.unit or '')
end
local sourceRank = { missing = 0, unknown = 1, stale = 2, invalid = 3 }
local gpsFixLabels = { [0] = 'Kein GPS', 'Kein Fix', '2D', '3D', 'DGPS', 'RTK float', 'RTK fix' }
local function showFlightGPS(monitor)
  return not monitor.betaflight or monitor.gpsFixLabel == 'Bestätigt'
end
function M.new(config, receiver, armedSummary, profile)
  -- 1.5 s bridges ordinary gaps between GPS updates.
  local self = { values = {}, sources = {}, sensorList = {}, api = false, gpsGrace = 150 }
  local keys = {}
  for key in pairs(config.sensors) do
    -- Some SW builds do not have the Lua table library.
    local i = #keys + 1
    while i > 1 and keys[i - 1] > key do keys[i] = keys[i - 1]; i = i - 1 end
    keys[i] = key
  end
  function self:sample(force)
    local now = getTime()
    local betaflight = profile ~= nil and profile.get(now) == 'Betaflight'
    if self.betaflight ~= betaflight then
      self.betaflight, force = betaflight, true
      self.sources, self.gpsPosition, self.gpsBinaryTime = {}, nil, nil
      self.gpsLive, self.gpsTime, self.gpsBinaryFix = nil, nil, nil
      self.hudRoll, self.hudPitch = nil, nil
    end
    if receiver then
      if profile then receiver.enable(not betaflight) end
      if not betaflight then receiver.poll() end
    end
    if not force and self.last and now >= self.last and now - self.last < 20 then return end
    if self.last and now < self.last then
      self.sources, self.gpsPosition, self.gpsBinaryTime = {}, nil, nil
      self.hudRoll, self.hudPitch = nil, nil
    end
    self.last = now
    self.api = type(getSourceValue) == 'function' and type(getFieldInfo) == 'function'
    self.values = {}
    self.fix = nil
    local count = 0
    for _, key in ipairs(keys) do
      local def = config.sensors[key]
      if def.names[1] and not (betaflight and key == 'armed') then
        local entry = self.sources[key] or { key = key }
        local previousName = entry.name
        self.sources[key] = entry
        entry.name, entry.state = def.names[1], self.api and 'missing' or 'noapi'
        entry.fresh = false
        if self.api then
          for _, name in ipairs(def.names) do
            -- Missing sources can look like valid zero values without this check.
            local info = getFieldInfo(name)
            if info then
              local value, current, fresh = getSourceValue(info.id)
              -- Keep current values for the dashboard. The GPS detail page
              -- separately uses isFresh (a short window, not a packet timestamp).
              local valid = current == true and validated(def, value) or nil
              if valid ~= nil then
                if betaflight and def.betaflightScale and type(valid) == 'number' then
                  valid = valid * def.betaflightScale
                end
                self.values[key] = valid
                entry.name, entry.state, entry.lastName, entry.lastValue = name, 'valid', name, valid
                entry.fresh = fresh == true
                break
              end
              local state = current == true and 'invalid' or current == false and 'stale' or 'unknown'
              if sourceRank[state] > sourceRank[entry.state] then
                entry.name, entry.state = name, state
              end
            elseif entry.state == 'missing' and name == entry.lastName then
              entry.name = name
            end
          end
        end
        if key == 'satellites' or key == 'heading' or key == 'roll' or key == 'pitch' then
          if entry.state ~= 'valid' or (key == 'pitch' and math.abs(entry.lastValue) > 90) then
            entry.freshAt = nil
          elseif entry.fresh then
            entry.freshAt, entry.freshValue = now, entry.lastValue
          elseif entry.name ~= previousName then
            entry.freshAt = nil
          end
        end
        count = count + 1
        self.sensorList[count] = entry
      else
        self.sources[key] = nil
      end
    end
    for i = count + 1, #self.sensorList do self.sensorList[i] = nil end
    local confirmedArmed = not betaflight and receiver and receiver.value('armed') or nil
    if armedSummary and not betaflight then armedSummary:sample(now, confirmedArmed, self.values, self.sources) end
    local wasLive = self.gpsLive
    self.gpsLive, self.gpsFixLabel = false, nil
    if not self.api then self.gpsBinaryTime = nil; return end
    local binaryFix = self.values.gpsfix
    if binaryFix ~= nil and self.sources.gpsfix.fresh then
      self.gpsBinaryFix, self.gpsBinaryTime = binaryFix, now
    elseif binaryFix ~= self.gpsBinaryFix then
      self.gpsBinaryTime = nil
    end
    if not self.gpsBinaryTime or now - self.gpsBinaryTime > self.gpsGrace then binaryFix = nil end
    if receiver and not betaflight then
      local fix = receiver.value('fix')
      if self.values.armed == nil then self.values.armed = confirmedArmed end
      self.fix = fix
      if self.values.gpsfix == nil and fix ~= nil then self.values.gpsfix = fix >= 2 and 1 or 0 end
    end
    -- Use passthrough for the fix type. A recent explicit no-fix from
    -- either source vetoes a position, even if the other source claims a fix.
    local fix = self.fix
    local hasFix = binaryFix ~= 0 and (fix and fix >= 2 or fix == nil and binaryFix == 1)
    self.gpsFixLabel = binaryFix == 0 and (fix == 0 and 'Kein GPS' or 'Kein Fix')
      or gpsFixLabels[fix] or (binaryFix == 1 and 'Bestätigt' or nil)
    local pos = self.values.gps
    if hasFix and pos then
      if self.sources.gps.fresh then
        self.gpsLive, self.gpsPosition, self.gpsTime = true, pos, now
      elseif wasLive and self.gpsPosition and now - self.gpsTime <= self.gpsGrace then
        -- Keep the displayed position and timestamp unchanged during the gap.
        self.gpsLive = true
      end
    end
  end
  function self:flightAltitude()
    if self.values.altitude ~= nil then return 'altitude', true end
    -- Keep GAlt in source diagnostics, but do not display unchecked Betaflight
    -- GPS altitude as a flight reading. ArduPilot MAVLink also uses GAlt for
    -- heights that are not GNSS-derived, so its existing fallback is unchanged.
    return 'gpsaltitude', showFlightGPS(self)
  end
  function self:flightSpeed()
    -- Leave the accepted sensor value available to source diagnostics.
    return showFlightGPS(self) and self:format('speed') or '--'
  end
  function self:format(key, value)
    return formatValue(key, config.sensors[key], value == nil and self.values[key] or value, self.betaflight)
  end
  function self:lastSensorValue(entry)
    if entry.lastName == entry.name then return entry.lastValue end
  end
  function self:formatSensor(entry)
    return formatValue(entry.key, config.sensors[entry.key], self:lastSensorValue(entry), self.betaflight)
  end
  function self:status()
    if not self.api then return 'API fehlt: getSourceValue', 'warn' end
    if self.values.voltage ~= nil or self.values.mode ~= nil or self.values.gps ~= nil then
      return 'Sensordaten / keine Flugfreigabe', 'normal'
    end
    return 'Keine aktuellen FC-Daten', 'warn'
  end
  return self
end
return M
