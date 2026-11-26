-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/project.lua
-- Purpose: Share project metadata and sender-clock formatting across both displays.
-- Project version: 1.1.0
-- Updated: 2026-11-21
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local function version()
  if not io or not io.open or not io.read or not io.close then return end
  local f = io.open('/SCRIPTS/APMON/VERSION', 'r')
  if not f then return end
  local ok, value = pcall(io.read, f, 32)
  io.close(f)
  if ok and type(value) == 'string' then
    return string.match(value, '^%s*(%d+%.%d+%.%d+[%w%.%-+]*)%s*$')
  end
end

local function clock()
  if type(getDateTime) ~= 'function' then return '--:--' end
  local t = getDateTime()
  local function inRange(n, low, high)
    return type(n) == 'number' and n >= low and n <= high and n % 1 == 0
  end
  -- A radio can report a valid time even when its calendar is still unset.
  if type(t) ~= 'table'
      or not inRange(t.hour, 0, 23) or not inRange(t.min, 0, 59) then return '--:--' end
  return string.format('%02d:%02d', t.hour, t.min)
end

return {
  title = 'APMon',
  repo = { 'github.com/christianbaun/', 'APMon-EdgeTX' },
  version = 'v' .. (version() or '--'),
  reportPath = '/APMon-report.txt',
  clock = clock,
}
