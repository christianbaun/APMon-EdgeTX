-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/core.lua
-- Purpose: Read and validate EdgeTX sensors and merge optional ArduPilot passthrough data.
-- Project version: 0.5.0
-- Updated: 2026-11-20
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
local function formatValue(key, def, value)
  if value == nil then return '--' end
  if def.gps then return string.format('%.6f, %.6f', value.lat, value.lon) end
  if def.text then
    if key == 'mode' then
      local base = string.match(value, '^(%a+)%*?$')
      local names = { STAB = 'STABILIZE', LOIT = 'LOITER', GUID = 'GUIDED' }
      if base then return names[base] or base end
    end
    return value
  end
  return string.format('%.' .. (def.decimals or 0) .. 'f', value) ..
    (def.unit ~= '' and ' ' .. def.unit or '')
end
local sourceRank = { missing = 0, unknown = 1, stale = 2, invalid = 3 }
function M.new(config, receiver, armedSummary)
  local self = { values = {}, sources = {}, sensorList = {}, last = nil, api = false }
  local keys = {}
  for key in pairs(config.sensors) do
    -- Some SW builds do not have the Lua table library.
    local i = #keys + 1
    while i > 1 and keys[i - 1] > key do keys[i] = keys[i - 1]; i = i - 1 end
    keys[i] = key
  end
  function self:sample(force)
    local now = getTime()
    if receiver then receiver.poll() end
    if not force and self.last and now >= self.last and now - self.last < 20 then return end
    if self.last and now < self.last then self.sources = {} end
    self.last = now
    self.api = type(getSourceValue) == 'function' and type(getFieldInfo) == 'function'
    self.values = {}
    self.fix = nil
    local count = 0
    for _, key in ipairs(keys) do
      local def = config.sensors[key]
      if def.names[1] then
        local entry = self.sources[key] or { key = key }
        self.sources[key] = entry
        entry.name, entry.state = def.names[1], self.api and 'missing' or 'noapi'
        entry.fresh = false
        if self.api then
          for _, name in ipairs(def.names) do
            -- Missing sources can look like valid zero values without this check.
            local info = getFieldInfo(name)
            if info then
              local value, current, fresh = getSourceValue(info.id)
              -- isFresh only covers ~320 ms in EdgeTX 2.12.2. Use isCurrent.
              local valid = current == true and validated(def, value) or nil
              if valid ~= nil then
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
        count = count + 1
        self.sensorList[count] = entry
      else
        self.sources[key] = nil
      end
    end
    for i = count + 1, #self.sensorList do self.sensorList[i] = nil end
    local confirmedArmed = receiver and receiver.value('armed')
    if armedSummary then armedSummary:sample(now, confirmedArmed, self.values, self.sources) end
    if not self.api then return end
    if receiver then
      local fix = receiver.value('fix')
      if self.values.armed == nil then self.values.armed = confirmedArmed end
      self.fix = fix
      if self.values.gpsfix == nil and fix ~= nil then self.values.gpsfix = fix >= 2 and 1 or 0 end
    end
  end
  function self:format(key)
    return formatValue(key, config.sensors[key], self.values[key])
  end
  function self:lastSensorValue(entry)
    if entry.lastName == entry.name then return entry.lastValue end
  end
  function self:formatSensor(entry)
    return formatValue(entry.key, config.sensors[entry.key], self:lastSensorValue(entry))
  end
  function self:rows()
    local v = self.values
    local armed = v.armed == 1 and 'ARMED' or v.armed == 0 and 'DISARMED' or '--'
    local pit = v.pit == 1 and 'AN' or v.pit == 0 and 'AUS' or '--'
    local power = v.pit == 1 and 'PIT: mW unbekannt'
      or v.pit == 0 and self:format('power') or '-- (PIT unbekannt)'
    local gps = v.gps
    return {
      { 'Modus (FC)', self:format('mode') },
      { 'Motoren (FC)', armed, v.armed == 1 and 'warn' or nil },
      { 'Akku', self:format('voltage') },
      { 'Strom', self:format('current') },
      { 'Rest (FC)', self:format('remaining') },
      { 'Verbraucht', self:format('used') },
      { 'Hoehe (Sensor)', self:format('altitude') },
      { 'Steigen', self:format('climb') },
      { 'GPS-Tempo', self:format('speed') },
      { 'Satelliten', self:format('satellites') },
      { 'GPS-Kurs', self:format('heading') },
      { 'RC-Linkqualität', self:format('lq') },
      { 'GPS Breite', gps and string.format('%.6f', gps.lat) or '--' },
      { 'GPS Laenge', gps and string.format('%.6f', gps.lon) or '--' },
      { 'PIT (FC)', pit, v.pit == 1 and 'info' or nil },
      { 'VTX (FC)', power, v.pit == 1 and 'info' or nil },
    }
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
