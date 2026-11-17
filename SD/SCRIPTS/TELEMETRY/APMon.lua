-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/TELEMETRY/APMon.lua
-- Purpose: Render the GX12/Boxer telemetry UI with two pages, menus and saved language choice.
-- Project version: 0.1.0
-- Updated: 2026-11-17
-- Authors: APMon contributors
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- Copyright (c) 2026 APMon contributors
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- GX12 / Boxer: 128x64 telemetry application, classic EdgeTX 2.x LCD API.
local function module(name)
  local path = '/SCRIPTS/APMON/' .. name .. '.lua'
  local chunk, reason = loadScript(path)
  if not chunk then error('APMon: ' .. path .. ': ' .. tostring(reason or 'not loadable')) end
  return chunk()
end
local core, config = module('core'), module('config')
local receiver, i18n = module('pass'), module('i18n')
local monitor = core.new(config, receiver)
local page, language, selection, settings, saveFailed = 1, 1, 1, false, false
local messages = false
local preference = '/SCRIPTS/APMON/mono.cfg'
local function readLanguage()
  if not io or not io.open then return end
  local f = io.open(preference, 'r')
  if not f then return end
  local ok, code = pcall(io.read, f, 16)
  io.close(f)
  if ok then
    for i, entry in ipairs(i18n.languages) do
      if code == entry.code then language = i; return end
    end
  end
end
readLanguage()
local function saveLanguage()
  if not io or not io.open then return false end
  local f = io.open(preference, 'w')
  if not f then return false end
  local ok, result = pcall(io.write, f, i18n.language(language).code)
  io.close(f)
  return ok and result ~= nil
end
local function tr(value) return i18n.text(language, value) end
local function match(event, ...)
  if not event or event == 0 then return false end
  for i = 1, select('#', ...) do
    if event == select(i, ...) then return true end
  end
  return false
end
-- Trim UTF-8 as whole characters; labels are deliberately short on this LCD.
local function fit(value, width)
  local flags = SMLSIZE or 0
  local function size(v)
    if lcd.sizeText then return lcd.sizeText(v, flags) end
    return #v * 5
  end
  while #value > 0 and size(value) > width do
    local start = #value
    while start > 1 and string.byte(value, start) >= 128
        and string.byte(value, start) < 192 do start = start - 1 end
    value = string.sub(value, 1, start - 1)
  end
  return value, size(value)
end
local function background() monitor:sample() end
local function run(event)
  monitor:sample()
  local nextEvent = match(event, EVT_VIRTUAL_NEXT, EVT_PLUS_FIRST, EVT_ROT_RIGHT)
  local prevEvent = match(event, EVT_VIRTUAL_PREV, EVT_MINUS_FIRST, EVT_ROT_LEFT)
  local enterEvent = match(event, EVT_VIRTUAL_ENTER or EVT_ENTER_BREAK or EVT_ENTER_FIRST)
  local exitEvent = match(event, EVT_VIRTUAL_EXIT or EVT_EXIT_BREAK)
  local menuCount = #i18n.languages + 1
  if messages then
    if enterEvent or exitEvent then messages = false end
  elseif settings then
    if nextEvent then selection = selection % menuCount + 1 end
    if prevEvent then selection = (selection - 2) % menuCount + 1 end
    if exitEvent then settings = false end
    if enterEvent then
      if selection == menuCount then
        messages = true
      else
        language = selection
        saveFailed = not saveLanguage()
      end
      settings = false
    end
  elseif enterEvent then
    settings, selection = true, language
  elseif nextEvent then page = page % 2 + 1
  elseif prevEvent then page = (page - 2) % 2 + 1 end
  local width = LCD_W or 128
  lcd.clear()
  local function text(y, value, inverse)
    lcd.drawText(0, y, fit(value, width), (SMLSIZE or 0) + (inverse and (INVERS or 0) or 0))
  end
  if settings then
    text(0, 'APMon / Menu', true)
    local top = math.max(1, selection - 3)
    for i = top, math.min(menuCount, top + 3) do
      text(12 + (i - top) * 10, i == menuCount and tr('FC-Meldungen') or i18n.languages[i].name, selection == i)
    end
    text(54, tr('Enter: waehlen'), false)
    return 0
  end
  local v = monitor.values
  local function fmt(key) return monitor:format(key) end
  local function armed() return v.armed == 1 and 'ARMED' or v.armed == 0 and 'DISARMED' or '--' end
  local function fix()
    local names = {[0]='Kein GPS', 'Nein', 'Ja 2D', 'Ja 3D', 'Ja DGPS', 'Ja RTK flt', 'Ja RTK fix'}
    if monitor.fix ~= nil then return tr(names[monitor.fix] or '--') end
    return v.gpsfix == 1 and tr('Ja') or v.gpsfix == 0 and tr('Nein') or '--'
  end
  local yaw = v.yaw
  local directions = i18n.language(language).directions or i18n.language(1).directions
  local direction = yaw and directions[math.floor(((yaw % 360) + 22.5) / 45) % 8 + 1] or '--'
  if messages then
    text(0, tr('FC-Meldungen'), true)
    local age = receiver.age(receiver.message)
    text(11, age and string.format(tr('FC-Meldung / vor %ds'),age) or '--')
    local value = receiver.message and receiver.message.value or '--'
    for i = 1, 4 do
      local part = fit(value,width)
      text(20 + (i-1)*9,part)
      value = string.sub(value,#part+1)
    end
    return 0
  end
  text(0, 'AP ' .. tr(page == 1 and 'Uebersicht' or 'Flugwerte') .. ' ' .. page .. '/2', true)
  local rows
  if page == 1 then
    -- Same ten values as the GX15 left column, arranged for the small display.
    rows = {{'FM',fmt('mode')},{'Arm',armed()},
      {'V',fmt('voltage')},{'A',fmt('current')},{'Rest',fmt('remaining')},
      {'Verbr.',fmt('used')},{'RC LQ',fmt('lq')},{'Fix',fix()},
      {'Sats',fmt('satellites')},{'EKF*',receiver.ekf and tostring(receiver.ekf.value)
        .. '/' .. tostring(receiver.age(receiver.ekf) or 0) .. 's' or '--'}}
  else
    rows = {{v.altitude ~= nil and 'Alt' or 'GAlt',
      v.altitude ~= nil and fmt('altitude') or fmt('gpsaltitude')},
      {'Roll',fmt('roll')},{'Pitch',fmt('pitch')},{'Yaw',fmt('yaw')},
      {'H-V',fmt('speed')},{'Dir',direction},{'V-V',fmt('climb')}}
  end
  local cellWidth = math.floor(width / 2)
  for i, field in ipairs(rows) do
    local x = i <= 5 and 0 or cellWidth + 2
    local y = 11 + ((i-1) % 5) * 9
    local raw = field[2]
    if string.match(raw, '^%-?%d') then raw = string.gsub(raw, ' ', '') end
    local value, vw = fit(raw,cellWidth - 4)
    local label = fit(tr(field[1]),cellWidth - vw - 6)
    lcd.drawText(x,y,label,SMLSIZE or 0)
    lcd.drawText(x + cellWidth - 2 - vw,y,value,SMLSIZE or 0)
  end
  local _, severity = monitor:status()
  local footer = saveFailed and tr('Sprache nicht gespeichert')
    or severity == 'warn' and tr('FC-Daten fehlen') or tr('Rad: Seite ENTER:Menu')
  text(56,footer,saveFailed or severity == 'warn')
  return 0
end
return { run = run, background = background }
