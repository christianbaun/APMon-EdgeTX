-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/TELEMETRY/APMon.lua
-- Purpose: Render the GX12/Boxer telemetry UI with two pages, menus and saved language choice.
-- Project version: 0.6.0
-- Updated: 2026-11-21
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- GX12 / Boxer: 128x64 telemetry application, classic EdgeTX 2.x LCD API.
local function reclaim()
  if type(collectgarbage) == 'function' then pcall(collectgarbage, 'collect') end
end
local function module(name, ...)
  -- Reclaim temporary bytecode/compiler objects from the preceding load.
  reclaim()
  local path = '/SCRIPTS/APMON/' .. name .. '.lua'
  local chunk, reason = loadScript(path)
  if not chunk then error('APMon: ' .. path .. ': ' .. tostring(reason or 'not loadable')) end
  return chunk(...)
end
local i18n = module('i18n', 'compact')
local core, config = module('core'), module('config')
local summary = module('armed_summary')
local tracker = summary.new(config.relativeAltitudeSensor)
local receiver = module('pass', 12, tracker)
local project = module('project')
local monitor = core.new(config, receiver, tracker)
local page, language, menuItem, languageItem = 1, 1, 1, 1
local showClock, saveError, selectedMessage, messageDetail = false, nil, nil, nil
local warningsOnly, filterFocus, messageList = false, false, nil
local view = 'data'
local sensorIndex = 1
local toolRenderer, toolError
local radioLanguage = type(getGeneralSettings) == 'function' and getGeneralSettings().language
local nativeUmlauts = not radioLanguage or radioLanguage == 'DE'
local preference = '/SCRIPTS/APMON/mono.cfg'
local function readPreferences()
  if not io or not io.open then return end
  local f = io.open(preference, 'r')
  if not f then return end
  local ok, code = pcall(io.read, f, 16)
  io.close(f)
  if ok and type(code) == 'string' then
    local languageCode, clockFlag = string.match(code, '^(%a+)%s*(1?)%s*$')
    showClock = clockFlag == '1'
    for i, entry in ipairs(i18n.languages) do
      if languageCode == entry.code then language = i; return end
    end
  end
end
readPreferences()
local function savePreferences()
  if not io or not io.open then return false end
  local f = io.open(preference, 'w')
  if not f then return false end
  local ok, result = pcall(io.write, f, i18n.language(language).code .. (showClock and '\n1' or ''))
  io.close(f)
  return ok and result ~= nil
end
local function tr(value) return i18n.text(language, value) end
local function monoText(value)
  value = tr(value)
  if not nativeUmlauts then
    value = string.gsub(value, 'ü', 'ue')
    value = string.gsub(value, 'ä', 'ae')
    value = string.gsub(value, 'ö', 'oe')
  end
  return value
end
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
  local clock = showClock and project.clock()
  local clockRight = right - counterWidth - 4
  local titleRight = clock and clockRight - textWidth(clock, small) - 4 or right - counterWidth - 2
  local headerStyle = small + (INVERS or 0)
  filled(0, 0, width, 9)
  if not nativeUmlauts and string.sub(title, 1, 2) == 'Ü' then
    -- Monochrome EdgeTX fonts follow the radio language, not APMon's.
    -- Compose the uppercase Ü on firmware that lacks the German font.
    lcd.drawText(2, 2, 'APMon', headerStyle)
    local x = 2 + textWidth('APMon ', small)
    lcd.drawText(x, 2, fit('U' .. string.sub(title, 3), titleRight - x, small), headerStyle)
    lcd.drawFilledRectangle(x, 0, 1, 1, ERASE or 0)
    lcd.drawFilledRectangle(x + 3, 0, 1, 1, ERASE or 0)
  else
    lcd.drawText(2, 2, fit('APMon ' .. title, titleRight - 2, small), headerStyle)
  end
  rightText(right, 2, counter, small, true)
  if clock then rightText(clockRight, 2, clock, small, true) end
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
  label = fit(monoText(label), right - x - valueWidth - 1, small)
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
  menuHeader(width, project.title)
  for i, line in ipairs(project.repo) do
    lcd.drawText(2, 10 + (i - 1) * 7, fit(line, width - 4, small), small)
  end
  local version = fit(project.version, width - textWidth(project.repo[2], small) - 8, small)
  rightText(width - 2, 17, version, small)
  filled(2, 23, width - 4, 1)
  local labels = { tr('Sprache') .. ': ' .. i18n.language(language).name, tr('FC-Meldungen'),
    tr('Uhr') .. ': ' .. tr(showClock and 'An' or 'Aus'), tr('Telemetrie-Diagnose'),
    tr('Letzte Armed-Phase'), tr('GPS-Details') }
  local first = math.max(1, menuItem - 4)
  for i = first, first + 4 do menuOption(width, 25 + (i - first) * 8, labels[i], menuItem == i) end
end
local function loadTools(isDiagnostics)
  return module(isDiagnostics and 'mono_tools' or view == 'gps' and 'mono_gps' or 'mono_summary', {
    tr = tr, monoText = monoText, header = menuHeader, field = field,
    rightText = rightText, small = small, filled = filled, fit = fit, textWidth = textWidth,
    monitor = monitor, receiver = receiver, tracker = tracker, summary = summary,
    diagnostics = isDiagnostics and module('diagnostics') or nil,
  })
end
local function background() monitor:sample() end
local function run(event)
  monitor:sample()
  local nextEvent = match(event, EVT_VIRTUAL_NEXT, EVT_PLUS_FIRST, EVT_ROT_RIGHT)
  local prevEvent = match(event, EVT_VIRTUAL_PREV, EVT_MINUS_FIRST, EVT_ROT_LEFT)
  local enterEvent = match(event, EVT_VIRTUAL_ENTER or EVT_ENTER_BREAK or EVT_ENTER_FIRST)
  local exitEvent = match(event, EVT_VIRTUAL_EXIT or EVT_EXIT_BREAK)
  local step = nextEvent and 1 or prevEvent and -1 or 0
  if view == 'summary' then
    if exitEvent then view = 'menu'
    elseif enterEvent and tracker.last and toolRenderer then view = 'summaryDetail' end
  elseif view == 'summaryDetail' then
    if enterEvent or exitEvent then view = 'summary' end
  elseif view == 'gps' then
    if exitEvent then view = 'menu' end
  elseif view == 'diagnostics' then
    if exitEvent then view = 'menu'
    elseif enterEvent and toolRenderer then view, sensorIndex = 'sensors', 1 end
  elseif view == 'sensors' then
    local count = #monitor.sensorList
    if count > 0 then sensorIndex = (sensorIndex - 1 + step) % count + 1 end
    if enterEvent or exitEvent then view = 'diagnostics' end
  elseif view == 'messageDetail' then
    if enterEvent or exitEvent then view, messageDetail = 'messages', nil end
  elseif view == 'messages' then
    if exitEvent then
      view, selectedMessage, messageList = 'menu', nil, nil
    else
      messageList = receiver.timeline(messageList, warningsOnly)
      local index = receiver.timelineIndex(messageList, selectedMessage)
      if index == 0 then filterFocus = true end
      if filterFocus then
        if nextEvent and index > 0 then filterFocus, selectedMessage = false, nil end
        if enterEvent then warningsOnly, selectedMessage = not warningsOnly, nil end
      elseif prevEvent and index == 1 then
        filterFocus = true
      else
        index = math.max(1, math.min(#messageList, index + step))
        local message = messageList[index]
        selectedMessage = index > 1 and message or nil
        if enterEvent then view, messageDetail, selectedMessage = 'messageDetail', message, message end
      end
    end
  elseif view == 'language' then
    local count = #i18n.languages
    if nextEvent then languageItem = languageItem % count + 1 end
    if prevEvent then languageItem = (languageItem - 2) % count + 1 end
    if exitEvent then view = 'menu' end
    if enterEvent then
      language = languageItem
      saveError = not savePreferences() and 'Sprache nicht gespeichert' or nil
      view = 'menu'
    end
  elseif view == 'menu' then
    if step ~= 0 then menuItem = (menuItem - 1 + step) % 6 + 1 end
    if exitEvent then view = 'data' end
    if enterEvent then
      if menuItem == 1 then view, languageItem = 'language', language
      elseif menuItem == 2 then view, selectedMessage, filterFocus = 'messages', nil, false
      elseif menuItem == 3 then
        showClock = not showClock
        saveError = not savePreferences() and 'Uhr nicht gespeichert' or nil
      elseif menuItem == 4 then
        view = 'diagnostics'
      elseif menuItem == 5 then
        view = 'summary'
      else
        view = 'gps'
      end
    end
  elseif enterEvent then
    view, menuItem = 'menu', 1
  elseif nextEvent then page = page % 2 + 1
  elseif prevEvent then page = (page - 2) % 2 + 1 end
  local width = LCD_W or 128
  lcd.clear()
  local function text(y, value, inverse)
    lcd.drawText(0, y, fit(value, width, small), small + (inverse and (INVERS or 0) or 0))
  end
  local diagnosticsPage = view == 'diagnostics' or view == 'sensors'
  if diagnosticsPage or view == 'summary' or view == 'summaryDetail' or view == 'gps' then
    if toolRenderer == nil then
      local ok, render = pcall(loadTools, diagnosticsPage)
      toolRenderer = ok and render or false
      if not ok then
        toolError = string.find(string.lower(tostring(render)), 'memory', 1, true)
          and 'Speicher knapp' or 'Werkzeug nicht ladbar'
      end
    end
    if toolRenderer then
      toolRenderer(view, width, sensorIndex, text)
    else
      menuHeader(width, tr(diagnosticsPage and 'Telemetrie-Diagnose'
        or view == 'gps' and 'GPS-Details' or 'Letzte Armed-Phase'))
      text(11, tr(toolError))
      text(57, monoText('RTN: Menü'))
    end
    return 0
  end
  toolRenderer, toolError = nil, nil
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
  if view == 'messages' or view == 'messageDetail' then
    menuHeader(width, tr('FC-Meldungen'))
    if view == 'messages' then
      messageList = receiver.timeline(messageList, warningsOnly)
      local index, count = receiver.timelineIndex(messageList, selectedMessage), #messageList
      local filter = filterFocus or index == 0
      menuOption(width, 10, tr(warningsOnly and 'Filter: Warnungen' or 'Filter: Alle'), filter)
      if count == 0 then text(21, tr(warningsOnly and 'Keine Warnungen' or 'Keine FC-Meldungen')) end
      local first = math.max(1, index - 3)
      for i = first, math.min(count, first + 3) do
        local entry = messageList[i]
        local label
        if entry.armed ~= nil then
          local age = receiver.age(entry)
          label = (entry.armed == 1 and '[ARMED]' or '[DISARMED]') .. (age and ' ' .. age .. 's' or '')
        else
          label = 'S' .. entry.severity .. ' ' .. entry.value
        end
        if textWidth(label, small) > width - 15 then
          label = fit(label, width - 15 - textWidth('...', small), small) .. '...'
        end
        menuOption(width, 19 + (i - first) * 9, label, not filter and i == index)
      end
      text(57, tr(filter and 'ENT: Filter' or 'ENT: Details'))
      if count > 0 then rightText(width - 2, 57, index .. '/' .. count, small) end
      return 0
    end
    local message = messageDetail
    local age = receiver.age(message)
    if message.armed ~= nil then
      text(11, message.armed == 1 and 'ARMED' or 'DISARMED')
      text(20, monoText(message.armed == 1 and 'Armen bestätigt' or 'Entarmen bestätigt'))
      if age then text(29, string.format(tr('vor %ds'), age)) end
      text(57, tr('RTN: Liste'))
      return 0
    end
    local repeats = message.repeats > 1 and ' x' .. message.repeats or ''
    text(11, string.format('S%d%s %s', message.severity, repeats, age and age .. 's' or '--'))
    local value = message.value
    for i = 1, 4 do
      if value == '' then break end
      local part = fit(value, width, small)
      text(20 + (i-1)*9,part)
      value = string.sub(value,#part+1)
    end
    text(57, tr('RTN: Liste'))
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
  local footer = saveError and tr(saveError)
    or severity == 'warn' and tr('FC-Daten fehlen')
  if footer then
    text(57, footer, true)
  else
    lcd.drawText(2, 57, tr('Rad: Seite'), small)
    local menu = tr('ENT: Menu')
    if not nativeUmlauts and menu == 'ENT: Menü' then menu = 'ENT: Menue' end
    rightText(right, 57, menu, small)
    if receiver.message then
      local badge = receiver.message.severity <= 4 and 'FC!' or 'FC'
      local x = math.floor((width - textWidth(badge, small)) / 2)
      if x > 2 + textWidth(tr('Rad: Seite'), small) and x + textWidth(badge, small) < right - textWidth(menu, small) then
        lcd.drawText(x, 57, badge, small)
      end
    end
  end
  return 0
end
return { run = run, background = background }
