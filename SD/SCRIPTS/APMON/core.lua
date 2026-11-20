-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/core.lua
-- Purpose: Read and validate EdgeTX sensors and merge optional ArduPilot passthrough data.
-- Project version: 0.2.1
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
function M.new(config, receiver)
  local self = { values = {}, last = nil, api = false }
  function self:sample(force)
    local now = getTime()
    if receiver then receiver.poll() end
    if not force and self.last and now >= self.last and now - self.last < 20 then return end
    self.last = now
    self.api = type(getSourceValue) == 'function'
    self.values = {}
    self.fix = nil
    if not self.api then return end
    for key, def in pairs(config.sensors) do
      for _, name in ipairs(def.names) do
        -- Missing sources can look like valid zero values without this check.
        local info = getFieldInfo(name)
        if info then
          local value, current = getSourceValue(info.id)
          -- isFresh only covers ~320 ms in EdgeTX 2.12.2. isCurrent stays
          -- true until EdgeTX marks the sensor old (about 20 s).
          if current == true then
            local valid = false
            if def.text then
              valid = type(value) == 'string' and #value > 0
              if valid then value = string.sub(string.gsub(value, '[%c]', ''), 1, 24) end
            elseif def.gps then
              valid = type(value) == 'table' and finite(value.lat) and finite(value.lon)
                and math.abs(value.lat) <= 90 and math.abs(value.lon) <= 180
              if valid then value = { lat = value.lat, lon = value.lon } end
            else
              valid = finite(value)
              if valid then value = value * (def.scale or 1) end
              valid = valid and (not def.min or value >= def.min)
                and (not def.max or value <= def.max)
              if def.binary then valid = valid and (value == 0 or value == 1) end
            end
            if valid then self.values[key] = value; break end
          end
        end
      end
    end
    if receiver then
      local armed, fix = receiver.value('armed'), receiver.value('fix')
      if self.values.armed == nil then self.values.armed = armed end
      self.fix = fix
      if self.values.gpsfix == nil and fix ~= nil then self.values.gpsfix = fix >= 2 and 1 or 0 end
    end
  end
  function self:format(key)
    local value, def = self.values[key], config.sensors[key]
    if value == nil then return '--' end
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
