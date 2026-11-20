-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/TELEMETRY/APMon.lua
-- Purpose: Render the GX12/Boxer telemetry UI with two pages, menus and saved language choice.
-- Project version: 0.2.0
-- Updated: 2026-11-20
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
local project = module('project')
local monitor = core.new(config, receiver)
local page, language, menuItem, languageItem, saveFailed = 1, 1, 1, 1, false
local view = 'data'
local radioLanguage = type(getGeneralSettings) == 'function' and getGeneralSettings().language
local nativeUmlauts = not radioLanguage or radioLanguage == 'DE'
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
local small = SMLSIZE or 0
local medium, large = MIDSIZE or small, DBLSIZE or MIDSIZE or small
local function textWidth(value, flags)
  if lcd.sizeText then return (lcd.sizeText(value, flags)) end
  -- EdgeTX 2.x monochrome has no sizeText. Budget glyph advances including
  -- spacing, with exceptions for common wide and narrow SMLSIZE glyphs.
  local _, count = string.gsub(value, '[^\128-\191]', '')
  if flags == small and small ~= 0 then
    local _, wide = string.gsub(value, '[#$+MWmw]', '')
    local _, spaces = string.gsub(value, ' ', '')
    local _, narrow = string.gsub(value, "[.!':|]", '')
    return count * 5 + wide - spaces * 2 - narrow * 3
  end
  local advance = flags == large and large ~= medium and 11 or flags == medium and medium ~= small and 9 or 6
  return count * advance
end
-- Trim UTF-8 as whole characters; labels are deliberately short on this LCD.
local function fit(value, width, flags)
  local size = textWidth(value, flags)
  while #value > 0 and size > width do
    local start = #value
    while start > 1 and string.byte(value, start) >= 128
        and string.byte(value, start) < 192 do start = start - 1 end
    value = string.sub(value, 1, start - 1)
    size = textWidth(value, flags)
  end
  return value, size
end
local function rightText(x, y, value, flags, inverse)
  local style = flags + (inverse and (INVERS or 0) or 0)
  if RIGHT then
    lcd.drawText(x, y, value, style + RIGHT)
  else
    lcd.drawText(x - textWidth(value, flags), y, value, style)
  end
end
local function filled(x, y, w, h)
  lcd.drawFilledRectangle(x, y, w, h, FORCE or 0)
end
local function dataHeader(width, title, counter)
  local right = width - 2
  local counterWidth = textWidth(counter, small)
  local headerStyle = small + (INVERS or 0)
  filled(0, 0, width, 9)
  if not nativeUmlauts and string.sub(title, 1, 2) == 'Ü' then
    -- Monochrome EdgeTX fonts follow the radio language, not APMon's.
    -- Compose the uppercase Ü on firmware that lacks the German font.
    lcd.drawText(2, 2, 'APMon', headerStyle)
    local x = 2 + textWidth('APMon ', small)
    lcd.drawText(x, 2, fit('U' .. string.sub(title, 3), right - counterWidth - x - 2, small), headerStyle)
    lcd.drawFilledRectangle(x, 0, 1, 1, ERASE or 0)
    lcd.drawFilledRectangle(x + 3, 0, 1, 1, ERASE or 0)
  else
    lcd.drawText(2, 2, fit('APMon ' .. title, right - counterWidth - 5, small), headerStyle)
  end
  rightText(right, 2, counter, small, true)
end
local function instrument(x, right, key, alignRight)
  local value = string.match(monitor:format(key), '^%S+')
  local unit, unitWidth = fit(config.sensors[key].unit or '', math.floor((right - x) / 3), small)
  local numberRight = right - (unitWidth > 0 and unitWidth + 2 or 0)
  local available = numberRight - x
  local flags, y = large, 18
  if flags == medium or textWidth(value, flags) > available then flags, y = medium, 22 end
  if flags == small or textWidth(value, flags) > available then flags, y = small, 27 end
  if textWidth(value, flags) > available then value = '--' end
  if alignRight then
    rightText(numberRight, y, value, flags)
    if unitWidth > 0 then rightText(right, 27, unit, small) end
  else
    lcd.drawText(x, y, value, flags)
    if unitWidth > 0 then
      local endX = lcd.getLastRightPos and lcd.getLastRightPos() or x + textWidth(value, flags)
      lcd.drawText(endX + 2, 27, unit, small)
    end
  end
end
local function field(x, right, y, label, value)
  local valueWidth = textWidth(value, small)
  if valueWidth > right - x then value, valueWidth = '--', textWidth('--', small) end
  label = fit(tr(label), right - x - valueWidth - 1, small)
  if label ~= '' then lcd.drawText(x, y, label, small) end
  rightText(right, y, value, small)
end
local function menuOption(width, y, label, selected)
  if selected then
    filled(2, y, width - 4, 7)
    lcd.drawText(4, y, '>', small + (INVERS or 0))
  end
  lcd.drawText(12, y, fit(label, width - 15, small), small + (selected and (INVERS or 0) or 0))
end
-- The same telemetry pulse as the color logo, reduced to a 14-pixel path.
local pulse = {0, 4, 3, 4, 5, 1, 7, 6, 9, 3, 10, 4, 13, 4}
local function menuHeader(width, title)
  local x, y = width - 18, 1
  filled(0, 0, width, 9)
  lcd.drawText(2, y, fit(title, x - 4, small), small + (INVERS or 0))
  for i = 1, #pulse - 2, 2 do
    lcd.drawLine(x + pulse[i], y + pulse[i + 1], x + pulse[i + 2], y + pulse[i + 3], SOLID or 255, ERASE or 0)
  end
end
local function projectMenu(width)
  menuHeader(width, project.title[1])
  for i = 2, #project.title do
    lcd.drawText(2, 10 + (i - 2) * 7, fit(project.title[i], width - 4, small), small)
  end
  for i, line in ipairs(project.repo) do
    lcd.drawText(2, 33 + (i - 1) * 7, fit(line, width - 4, small), small)
  end
  filled(2, 47, width - 4, 1)
  menuOption(width, 49, tr('Sprache') .. ': ' .. i18n.language(language).name, menuItem == 1)
  menuOption(width, 57, tr('FC-Meldungen'), menuItem == 2)
end
local function background() monitor:sample() end
local function run(event)
  monitor:sample()
  local nextEvent = match(event, EVT_VIRTUAL_NEXT, EVT_PLUS_FIRST, EVT_ROT_RIGHT)
  local prevEvent = match(event, EVT_VIRTUAL_PREV, EVT_MINUS_FIRST, EVT_ROT_LEFT)
  local enterEvent = match(event, EVT_VIRTUAL_ENTER or EVT_ENTER_BREAK or EVT_ENTER_FIRST)
  local exitEvent = match(event, EVT_VIRTUAL_EXIT or EVT_EXIT_BREAK)
  if view == 'messages' then
    if enterEvent or exitEvent then view = 'menu' end
  elseif view == 'language' then
    local count = #i18n.languages
    if nextEvent then languageItem = languageItem % count + 1 end
    if prevEvent then languageItem = (languageItem - 2) % count + 1 end
    if exitEvent then view = 'menu' end
    if enterEvent then
      language = languageItem
      saveFailed = not saveLanguage()
      view = 'menu'
    end
  elseif view == 'menu' then
    if nextEvent or prevEvent then menuItem = 3 - menuItem end
    if exitEvent then view = 'data' end
    if enterEvent then view, languageItem = menuItem == 1 and 'language' or 'messages', language end
  elseif enterEvent then
    view, menuItem = 'menu', 1
  elseif nextEvent then page = page % 2 + 1
  elseif prevEvent then page = (page - 2) % 2 + 1 end
  local width = LCD_W or 128
  lcd.clear()
  local function text(y, value, inverse)
    lcd.drawText(0, y, fit(value, width, small), small + (inverse and (INVERS or 0) or 0))
  end
  if view == 'menu' then
    projectMenu(width)
    return 0
  end
  if view == 'language' then
    menuHeader(width, 'APMon / ' .. tr('Sprache'))
    local top = math.max(1, languageItem - 3)
    for i = top, math.min(#i18n.languages, top + 3) do
      menuOption(width, 12 + (i - top) * 10, i18n.languages[i].name, languageItem == i)
    end
    text(54, tr('Enter: waehlen'), false)
    return 0
  end
  local v = monitor.values
  local function fmt(key) return monitor:format(key) end
  if view == 'messages' then
    menuHeader(width, tr('FC-Meldungen'))
    local age = receiver.age(receiver.message)
    text(11, age and string.format(tr('FC-Meldung / vor %ds'),age) or '--')
    local value = receiver.message and receiver.message.value or '--'
    for i = 1, 4 do
      local part = fit(value, width, small)
      text(20 + (i-1)*9,part)
      value = string.sub(value,#part+1)
    end
    return 0
  end

  local right, split = width - 2, math.floor(width / 2)
  dataHeader(width, tr(page == 1 and 'Übersicht' or 'Flugwerte'), page .. '/2')

  -- The voltage card keeps the same position and size on both data pages.
  local boxLeft, legendX = split - 2, split + 4
  local legend, legendWidth = fit(tr('Akku'), right - legendX - 3, small)
  local topRight = legendX + legendWidth + 2
  filled(boxLeft, 13, legendX - boxLeft - 2, 1)
  filled(topRight, 13, width - topRight, 1)
  filled(boxLeft, 14, 1, 20)
  filled(width - 1, 14, 1, 20)
  filled(2, 34, width - 2, 1)
  lcd.drawText(legendX, 10, legend, small)
  instrument(boxLeft + 2, right, 'voltage', true)

  local leftRight, rightX = split - 3, split - 1
  local function compact(key) return (string.gsub(fmt(key), ' ', '')) end
  if page == 1 then
    lcd.drawText(2, 10, fit(tr('Flugmodus'), leftRight - 2, small), small)
    local mode = fmt('mode')
    local modeFont = textWidth(mode, 0) <= leftRight - 2 and 0 or small
    lcd.drawText(2, 18, fit(mode, leftRight - 2, modeFont), modeFont)
    lcd.drawText(2, 27, v.armed == 1 and 'ARMED' or v.armed == 0 and 'DISARMED' or '--', small)
    local fixes = {[0]='Keins', 'Nein', '2D', '3D', 'DGPS', 'RTKflt', 'RTKfix'}
    local fix = monitor.fix ~= nil and tr(fixes[monitor.fix] or '--')
      or v.gpsfix == 1 and tr('Ja') or v.gpsfix == 0 and tr('Nein') or '--'
    local ekf = receiver.ekf and tostring(receiver.ekf.value) .. '/'
      .. tostring(receiver.age(receiver.ekf) or 0) .. 's' or '--'
    field(2, leftRight, 35, 'Strom', compact('current'))
    field(2, leftRight, 42, 'Rest', compact('remaining'))
    field(2, leftRight, 49, 'Verbr.', compact('used'))
    field(rightX, right, 35, 'LQ', compact('lq'))
    field(rightX, right, 42, 'GPS', fix .. '/' .. fmt('satellites'))
    field(rightX, right, 49, 'EKF', ekf)
  else
    local altitude = tr('Höhe')
    if not nativeUmlauts and altitude == 'Höhe' then altitude = 'Hoehe' end
    lcd.drawText(2, 10, v.altitude == nil and v.gpsaltitude ~= nil and 'GAlt' or altitude, small)
    instrument(2, leftRight, v.altitude ~= nil and 'altitude' or 'gpsaltitude', false)
    local function angle(key) return (string.gsub(compact(key), 'deg$', '°')) end
    field(2, leftRight, 35, 'GPS', compact('speed'))
    field(2, leftRight, 42, 'Vario', compact('climb'))
    field(rightX, right, 35, 'Roll', angle('roll'))
    field(rightX, right, 42, 'Pitch', angle('pitch'))
    local yaw = angle('yaw')
    if v.yaw then
      local directions = i18n.language(language).directions or i18n.language(1).directions
      local direction = directions[math.floor(((v.yaw % 360) + 22.5) / 45) % 8 + 1]
      local combined = yaw .. ' ' .. direction
      if textWidth('Yaw', small) + textWidth(combined, small) + 1 <= right - rightX then
        yaw = combined
      else
        field(2, leftRight, 49, 'Dir', direction)
      end
    end
    field(rightX, right, 49, 'Yaw', yaw)
  end
  local _, severity = monitor:status()
  local footer = saveFailed and tr('Sprache nicht gespeichert')
    or severity == 'warn' and tr('FC-Daten fehlen')
  if footer then
    text(57, footer, true)
  else
    lcd.drawText(2, 57, tr('Rad: Seite'), small)
    local menu = tr('ENT: Menu')
    rightText(right, 57, not nativeUmlauts and menu == 'ENT: Menü' and 'ENT: Menue' or menu, small)
  end
  return 0
end
return { run = run, background = background }
