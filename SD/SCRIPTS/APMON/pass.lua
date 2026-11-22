-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/pass.lua
-- Purpose: Decode ELRS ArduPilot passthrough frames, status text and data freshness.
-- Project version: 0.5.0
-- Updated: 2026-11-21
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- ELRS 4.1.0 ArduPilot response frames (0x80), little-endian payload.
-- One shared receiver per loaded widget script; never transmits requests.
local M = { data = {}, message = nil, ekf = nil }
local capacity, armedSummary = ...
capacity = capacity or 12
local log, head, count = {}, 0, 0
local markers, markerHead, markerCount = {}, 0, 0
local markerCapacity, order = capacity <= 12 and 4 or 8, 0
local statusTimeout = 300
local function at(index)
  return log[(head - index) % capacity + 1]
end
local function mark(armed, now)
  order = order + 1
  markerHead = markerHead % markerCapacity + 1
  markerCount = math.min(markerCount + 1, markerCapacity)
  markers[markerHead] = { armed = armed, time = now, order = order }
end
-- Merge references, not copies. Markers do not consume any of the FC text slots.
function M.timeline(list, warnings)
  list = list or {}
  if list.order == order and list.warnings == warnings then return list end
  local i, j, n = 1, 1, 0
  while i <= count or j <= markerCount do
    local message = i <= count and at(i)
    local marker = j <= markerCount and markers[(markerHead - j) % markerCapacity + 1]
    if marker and (not message or marker.order > message.order) then
      n, j = n + 1, j + 1
      list[n] = marker
    else
      if not warnings or message.severity <= 4 then
        n = n + 1
        list[n] = message
      end
      i = i + 1
    end
  end
  for k = n + 1, #list do list[k] = nil end
  list.order, list.warnings = order, warnings
  return list
end
function M.timelineIndex(list, selected)
  -- nil follows the newest entry; keep an older selection until it is evicted.
  if #list == 0 then return 0 end
  if not selected then return 1 end
  for i, entry in ipairs(list) do if entry == selected then return i end end
  return #list
end
local function remember(value, severity, now)
  local latest = M.message
  if latest and latest.order == order and latest.value == value and latest.severity == severity then
    latest.time, latest.repeats = now, latest.repeats + 1
  else
    head = head % capacity + 1
    count = math.min(count + 1, capacity)
    order = order + 1
    M.message = { value = value, time = now, severity = severity, repeats = 1, order = order }
    log[head] = M.message
  end
end
local function le(p, start, count)
  local v = 0
  for i = 0, count - 1 do v = v + p[start + i] * 256 ^ i end
  return v
end
local function item(id, p, start, now)
  -- Extract from individual bytes: reconstructing all 32 bits through powers
  -- creates a float and can round away fix bits on embedded 32-bit Lua builds.
  if id == 0x5001 then
    local armed = p[start + 1] % 2
    local previous = M.data.armed
    if previous and armed ~= previous.value and now >= previous.time and now - previous.time <= statusTimeout then
      mark(armed, now)
    end
    M.data.armed = { value = armed, time = now }
    if armedSummary then armedSummary:observe(armed, now, statusTimeout) end
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
      remember(value, p[2], now)
      local source = string.match(value, '^Using EKF Source Set ([123])$')
      if source then M.ekf = { value = tonumber(source), time = now } end
    end
  end
end
function M.poll()
  local now = getTime()
  if M.last == now then return end
  if M.last and now < M.last then
    M.data, M.message, M.ekf, log, head, count = {}, nil, nil, {}, 0, 0
    markers, markerHead, markerCount, order = {}, 0, 0, order + 1
    M.last = nil
    if armedSummary then armedSummary:reset() end
  end
  if type(crossfireTelemetryPop) ~= 'function' then return end
  M.last = now
  for i = 1, 12 do
    local command, payload = crossfireTelemetryPop()
    if not command then break end
    M.decode(command, payload, now)
  end
end
local function status(key)
  local entry, now = M.data[key], getTime()
  if entry and now >= entry.time then
    local elapsed = now - entry.time
    return elapsed <= statusTimeout and 'valid' or 'stale', entry, math.floor(elapsed / 100)
  end
  return type(crossfireTelemetryPop) == 'function' and 'unreceived' or 'noapi'
end
function M.value(key)
  local state, entry = status(key)
  if state == 'valid' then return entry.value end
end
function M.status(key)
  local state, _, age = status(key)
  return state, age
end
function M.age(entry)
  if entry and getTime() >= entry.time then return math.floor((getTime() - entry.time) / 100) end
end
return M
