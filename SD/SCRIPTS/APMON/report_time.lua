-- SPDX-License-Identifier: Apache-2.0
-- APMon: sample the sender's RTC at confirmation, not on the dashboard.
-- Project version: 1.0.0
if type(getDateTime) ~= 'function' then return end
local t = getDateTime()
if type(t) ~= 'table' then return end
local function valid(n, first, last)
  return type(n) == 'number' and n >= first and n <= last and n % 1 == 0
end
-- EdgeTX's RTC API uses a four-digit year and a one-based month.
local y, m = t.year, t.mon
if not valid(y, 2020, 2099) or not valid(m, 1, 12) then return end
local days = ({31, y % 4 == 0 and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31})[m]
if valid(t.day, 1, days) and valid(t.hour, 0, 23) and valid(t.min, 0, 59) and valid(t.sec, 0, 59) then
  return string.format('%04d-%02d-%02d %02d:%02d:%02d', y, m, t.day, t.hour, t.min, t.sec)
end
