-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/pass.lua
-- Purpose: Decode ELRS ArduPilot passthrough frames, status text and data freshness.
-- Project version: 0.2.0
-- Updated: 2026-11-20
-- Authors: APMon contributors
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- Copyright (c) 2026 APMon contributors
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- ELRS 4.1.0 ArduPilot response frames (0x80), little-endian payload.
-- One shared receiver per loaded widget script; never transmits requests.
local M = { data = {}, message = nil, ekf = nil }
local function le(p, start, count)
  local v = 0
  for i = 0, count - 1 do v = v + p[start + i] * 256 ^ i end
  return v
end
local function item(id, p, start, now)
  -- Extract from individual bytes: reconstructing all 32 bits through powers
  -- creates a float and can round away fix bits on embedded 32-bit Lua builds.
  if id == 0x5001 then
    M.data.armed = { value = p[start + 1] % 2, time = now }
  elseif id == 0x5002 then
    local base = math.floor(p[start] / 16) % 4
    local fix = base == 3 and 3 + math.floor(p[start + 1] / 64) % 4 or base
    M.data.fix = { value = fix, time = now }
  end
end
function M.decode(command, p, now)
  if command ~= 0x80 or type(p) ~= 'table' or #p > 64 then return end
  for i = 1, #p do
    local b = p[i]
    if type(b) ~= 'number' or b < 0 or b > 255 or b % 1 ~= 0 then return end
  end
  if p[1] == 0xF0 and #p >= 7 then
    item(le(p, 2, 2), p, 4, now)
  elseif p[1] == 0xF2 and p[2] and p[2] >= 1 and p[2] <= 9
      and #p >= 2 + p[2] * 6 then
    for i = 0, p[2] - 1 do item(le(p, 3 + i * 6, 2), p, 5 + i * 6, now) end
  elseif p[1] == 0xF1 and #p >= 3 and p[2] <= 7 then
    -- The table library is absent in some monochrome telemetry Lua builds.
    -- Text is bounded to 50 bytes, so direct concatenation stays inexpensive.
    local value = ''
    for i = 3, math.min(#p, 52) do
      if p[i] == 0 then break end
      if p[i] >= 32 and p[i] <= 126 then value = value .. string.char(p[i]) end
    end
    if #value > 0 then
      M.message = { value = value, time = now, severity = p[2] }
      local source = string.match(value, '^Using EKF Source Set ([123])$')
      if source then M.ekf = { value = tonumber(source), time = now } end
    end
  end
end
function M.poll()
  if type(crossfireTelemetryPop) ~= 'function' then return end
  local now = getTime()
  if M.last == now then return end
  if M.last and now < M.last then M.data, M.message, M.ekf = {}, nil, nil end
  M.last = now
  for i = 1, 12 do
    local command, payload = crossfireTelemetryPop()
    if not command then break end
    M.decode(command, payload, now)
  end
end
function M.value(key)
  local entry, now = M.data[key], getTime()
  if entry and now >= entry.time and now - entry.time <= 300 then return entry.value end
end
function M.age(entry)
  if entry and getTime() >= entry.time then return math.floor((getTime() - entry.time) / 100) end
end
return M
