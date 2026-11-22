-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/WIDGETS/APMon/main.lua
-- Purpose: Render the color dashboard, full-screen project menu and language selection.
-- Project version: 0.6.0
-- Updated: 2026-11-21
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- Color widget, classic EdgeTX LCD API (2.x).
local function module(name, ...)
  local path = '/SCRIPTS/APMON/' .. name .. '.lua'
  local chunk, reason = loadScript(path)
  if not chunk then error('APMon: ' .. path .. ': ' .. tostring(reason or 'nicht ladbar')) end
  return chunk(...)
end
local core = module('core')
local config = module('config')
local summary = module('armed_summary')
local tracker = summary.new(config.relativeAltitudeSensor)
local receiver = module('pass', 32, tracker)
local i18n = module('i18n')
local project = module('project')
local diagnostics = module('diagnostics')
local options = { { 'Language', CHOICE, 1, i18n.choices }, { 'Clock', BOOL, 0 } }
local logo
local function drawLogo(zone, headerHeight)
  if not (Bitmap and Bitmap.open and lcd.drawBitmap) then return end
  -- Load once across instances. EdgeTX draws nothing for a missing or
  -- invalid bitmap, so older SD installs still work.
  if logo == nil then logo = Bitmap.open('/WIDGETS/APMon/logo.png') or false end
  if logo then lcd.drawBitmap(logo, zone.x + zone.w - 44, zone.y + math.floor((headerHeight - 32) / 2)) end
end
local function create(zone, opts)
  return { zone = zone, options = opts, monitor = core.new(config, receiver, tracker) }
end
local function update(widget, opts)
  widget.options, widget.sessionLanguage, widget.sessionClock = opts, nil, nil
end
local function background(widget) widget.monitor:sample() end
local function languageOf(widget)
  local index = widget.sessionLanguage or (widget.options and widget.options.Language)
  return i18n.languages[index] and index or 1
end
local function clockEnabled(widget)
  if widget.sessionClock ~= nil then return widget.sessionClock end
  return widget.options and widget.options.Clock == 1
end
local function setView(widget, view, focus)
  widget.view, widget.focus = view, focus
end
local menuW = 148
local menuCount = 7
local regularFont = SMLSIZE or 0
local headingFont = MIDSIZE or regularFont
local menuSubtitle = project.subtitle[1] .. ' ' .. project.subtitle[2]
local repoAddress = project.repo[1] .. project.repo[2]
local versionLabel = 'APMon ' .. project.version
local function layoutFor(widget, z)
  local layout = widget.menuLayout
  if layout and layout.width == z.w and layout.height == z.h then return layout end

  local regularFlags = regularFont + CUSTOM_COLOR
  local headingFlags = headingFont + CUSTOM_COLOR
  local _, smallHeight = lcd.sizeText('Ag', regularFlags)
  local _, largeHeight = lcd.sizeText('Ag', headingFlags)
  local inner = z.w - 24
  local subtitles = lcd.sizeText(menuSubtitle, regularFlags) <= inner and {menuSubtitle} or project.subtitle
  local repo = lcd.sizeText(repoAddress, regularFlags) <= inner and {repoAddress} or project.repo
  -- EdgeTX devices can use different pixel sizes for the same font flag.
  -- Keep the full font box on the colored bar, with padding above and below.
  local header = math.max(38, largeHeight + 16)
  local clockFont = DBLSIZE or headingFont
  local clockWidth, clockHeight = lcd.sizeText('88:88', clockFont + CUSTOM_COLOR)
  local titleWidth = lcd.sizeText(project.title, headingFlags)
  local clockMaxWidth = z.w - 2 * (math.max(12 + titleWidth, 44) + 8)
  -- Allow a few extra header pixels, but prefer a smaller font over moving the telemetry rows down further.
  if clockHeight > header or clockWidth > clockMaxWidth then
    clockFont = headingFont
    _, clockHeight = lcd.sizeText('88:88', headingFlags)
  end
  header = math.max(header, clockHeight + 6)
  local subtitleY, step = header + 6, smallHeight + 4
  local repoY = math.max(108, subtitleY + #subtitles * step + 4)
  local versionWidth = lcd.sizeText(versionLabel, regularFlags)
  local versionInline = lcd.sizeText(repo[#repo], regularFlags) + versionWidth + 12 <= inner
  local versionY = repoY + (#repo - (versionInline and 1 or 0)) * step
  local divider = math.max(132, versionY + step + 4)
  local rowHeight = math.max(28, smallHeight + 9)
  local menuTop = divider + 10
  local menuRowHeight = math.max(smallHeight + 5, math.min(rowHeight, math.floor((z.h - menuTop + 3) / menuCount)))
  local languageTop = header + 14
  local messageStep = math.max(20, smallHeight + 2)
  layout = {
    width = z.w, height = z.h, header = header,
    clockFont = clockFont,
    subtitles = subtitles, subtitleY = subtitleY, repo = repo, repoY = repoY,
    versionY = versionY, versionWidth = versionWidth,
    divider = divider, menuTop = menuTop, languageTop = languageTop,
    smallHeight = smallHeight, step = step, rowHeight = rowHeight,
    menuRowHeight = menuRowHeight,
    menuRows = math.max(1, math.min(menuCount, math.floor((z.h - menuTop + 3) / menuRowHeight))),
    languageRows = math.max(1, math.min(5, math.floor((z.h - smallHeight - 16 - languageTop) / rowHeight))),
    footerY = z.h - messageStep - smallHeight - 6, messageStep = messageStep,
    buttonHeight = math.max(24, smallHeight + 6),
  }
  widget.menuLayout = layout
  return layout
end
local function rows(widget, layout)
  if widget.view == 'menu' then
    return layout.menuTop, math.max(1, widget.focus - layout.menuRows + 1), menuCount, layout.menuRows
  end
  local count = #i18n.languages + 1
  return layout.languageTop, math.max(1, widget.focus - layout.languageRows + 1), count, layout.languageRows
end
local function messagePage(widget)
  return widget.view == 'messages' or widget.view == 'messageDetail'
end
local function diagnosticPage(widget)
  return widget.view == 'diagnostics' or widget.view == 'sensors'
end
local function summaryPage(widget)
  return widget.view == 'summary' or widget.view == 'summaryDetail'
end
local function diagnosticWindow(widget, z, layout)
  local top, back = layout.header + 8, z.h - layout.rowHeight - 12
  local listTop = top + layout.smallHeight + 6
  local visible = math.max(1, math.floor((back - layout.rowHeight - listTop) / layout.rowHeight))
  local count = #widget.monitor.sensorList
  local last = math.max(1, count - visible + 1)
  local first = math.min(widget.sensorFirst or 1, last)
  return top, back, listTop, visible, count, first, last
end
local function messageWindow(widget, z, layout)
  local top, back = layout.header + 9 + layout.rowHeight, z.h - layout.rowHeight - 16
  local visible = math.max(1, math.floor((back - layout.rowHeight - top) / layout.rowHeight))
  widget.messageList = receiver.timeline(widget.messageList, widget.warningsOnly == true)
  local index, count = receiver.timelineIndex(widget.messageList, widget.selectedMessage), #widget.messageList
  local first = math.max(1, index - visible + 1)
  return top, back, first, index, count, math.min(visible, count - first + 1)
end
local function handleInput(widget, z, layout, event, touch)
  if event == nil then
    setView(widget)
    widget.messageDetail, widget.selectedMessage, widget.messageList = nil, nil, nil
    return
  end
  if event == 0 then return end
  local enter = event == EVT_VIRTUAL_ENTER
  local exit = event == EVT_VIRTUAL_EXIT
  local tap = event == EVT_TOUCH_TAP and touch
  local function inButton(top, height)
    return tap and tap.x >= 12 and tap.x < z.w - 12 and tap.y >= top and tap.y < top + height
  end
  if not widget.view then
    local top = layout.footerY - 5
    if enter or (inButton(top, layout.buttonHeight) and tap.x >= z.w - 12 - menuW) then
      setView(widget, 'menu', 1)
    end
    return
  end
  local rowHeight = layout.rowHeight
  if widget.view == 'gps' then
    if exit or enter or inButton(z.h - rowHeight - 12, rowHeight - 3) then setView(widget, 'menu', 6) end
    return
  end
  if summaryPage(widget) then
    local back = z.h - rowHeight - 12
    local button = inButton(back, rowHeight - 3)
    if widget.view == 'summaryDetail' then
      if exit or enter or button then setView(widget, 'summary', tracker.last and 1 or 2) end
    else
      if not tracker.last then widget.focus = 2
      elseif event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_PREV then widget.focus = 3 - widget.focus end
      if exit or (enter and widget.focus == 2) or (button and (not tracker.last or tap.x >= z.w / 2)) then
        setView(widget, 'menu', 5)
      elseif tracker.last and (enter or button) then
        setView(widget, 'summaryDetail', 1)
      end
    end
    return
  end
  if diagnosticPage(widget) then
    local _, back, _, visible, _, first, last = diagnosticWindow(widget, z, layout)
    if widget.view == 'sensors' then
      if exit or enter or inButton(back, rowHeight - 3) then
        setView(widget, 'diagnostics', 1)
      else
        local step = event == EVT_VIRTUAL_NEXT and 1 or event == EVT_VIRTUAL_PREV and -1 or 0
        if inButton(back - rowHeight, rowHeight - 3) then
          step = tap.x < z.w / 2 and -visible or visible
        end
        widget.sensorFirst = math.max(1, math.min(last, first + step))
      end
    else
      if event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_PREV then widget.focus = 3 - widget.focus end
      if exit or (enter and widget.focus == 2) or (inButton(back, rowHeight - 3) and tap.x >= z.w / 2) then
        setView(widget, 'menu', 4)
      elseif enter or inButton(back, rowHeight - 3) then
        widget.sensorFirst = 1
        setView(widget, 'sensors', 1)
      end
    end
    return
  end
  if messagePage(widget) then
    local top, back, first, index, count, visible = messageWindow(widget, z, layout)
    if widget.view == 'messageDetail' then
      if enter or exit or inButton(back, rowHeight - 3) then
        widget.messageDetail = nil
        setView(widget, 'messages', 1)
      end
      return
    end
    if exit or inButton(back, rowHeight - 3) then
      setView(widget, 'menu', 2)
      widget.selectedMessage, widget.messageList = nil, nil
      return
    end
    local filter = widget.filterFocus or index == 0
    if inButton(top - rowHeight, rowHeight - 3) or (enter and filter) then
      widget.warningsOnly, widget.filterFocus, widget.selectedMessage = not widget.warningsOnly, true, nil
      return
    end
    local step = 0
    if event == EVT_VIRTUAL_NEXT then step = 1
    elseif event == EVT_VIRTUAL_PREV then step = -1
    elseif not filter and inButton(back - rowHeight, rowHeight - 3) then
      step = tap.x < z.w / 2 and -1 or 1
    end
    if inButton(top, visible * rowHeight) then
      local row = tap.y - top
      if row % rowHeight < rowHeight - 3 then
        index = first + math.floor(row / rowHeight)
        widget.filterFocus, enter = false, true
      end
    elseif filter then
      if step > 0 and count > 0 then widget.filterFocus, widget.selectedMessage = false, nil end
      return
    elseif event == EVT_VIRTUAL_PREV and index == 1 then
      widget.filterFocus = true
      return
    else
      index = math.max(1, math.min(count, index + step))
    end
    local message = widget.messageList[index]
    widget.selectedMessage = index > 1 and message or nil
    if enter and message then
      widget.messageDetail, widget.selectedMessage = message, message
      setView(widget, 'messageDetail', 1)
    end
    return
  end
  if exit then
    if widget.view == 'menu' then setView(widget)
    else setView(widget, 'menu', 1) end
    return
  end
  local top, first, count, visibleChoices = rows(widget, layout)
  if widget.view == 'menu' then rowHeight = layout.menuRowHeight end
  if event == EVT_VIRTUAL_NEXT then widget.focus = widget.focus % count + 1
  elseif event == EVT_VIRTUAL_PREV then widget.focus = (widget.focus - 2) % count + 1 end
  if tap then
    if not inButton(top, math.min(visibleChoices, count - first + 1) * rowHeight) then return end
    local row = tap.y - top
    if row % rowHeight >= rowHeight - 3 then return end
    widget.focus, enter = first + math.floor(row / rowHeight), true
  end
  if not enter then return end
  if widget.view == 'menu' then
    if widget.focus == 1 then setView(widget, 'language', languageOf(widget))
    elseif widget.focus == 2 then
      widget.selectedMessage, widget.filterFocus = nil, false
      setView(widget, 'messages', 1)
    elseif widget.focus == 3 then
      -- Like the language menu, this overrides the saved widget setting for this session.
      widget.sessionClock = not clockEnabled(widget)
    elseif widget.focus == 4 then
      setView(widget, 'diagnostics', 1)
    elseif widget.focus == 5 then
      setView(widget, 'summary', tracker.last and 1 or 2)
    elseif widget.focus == 6 then
      setView(widget, 'gps', 1)
    else setView(widget) end
  elseif widget.view == 'language' then
    -- EdgeTX persists widget options only via its own settings screen.
    if widget.focus <= #i18n.languages then widget.sessionLanguage = widget.focus end
    setView(widget, 'menu', 1)
  end
end
local function refresh(widget, event, touch)
  local z, m = widget.zone, widget.monitor
  if event ~= nil then z = { x = 0, y = 0, w = LCD_W, h = LCD_H } end
  local bg = lcd.RGB(12, 20, 30)
  local normal = lcd.RGB(225, 234, 243)
  local warn = lcd.RGB(255, 192, 70)
  local info = lcd.RGB(70, 215, 240)
  local panel = lcd.RGB(27, 43, 60)
  local language = languageOf(widget)
  local function tr(value) return i18n.text(language, value) end
  local function rect(x, y, w, h, color)
    lcd.setColor(CUSTOM_COLOR, color)
    lcd.drawFilledRectangle(x, y, w, h, CUSTOM_COLOR)
  end
  local function fit(value, maxWidth, flags)
    while #value > 0 do
      local w = lcd.sizeText(value, flags)
      if w <= maxWidth then break end
      -- Remove a complete UTF-8 character, preserving labels such as Höhe.
      local start = #value
      while start > 1 and string.byte(value, start) >= 128
          and string.byte(value, start) < 192 do start = start - 1 end
      value = string.sub(value, 1, start - 1)
    end
    return value
  end
  local function literal(x, y, value, color, maxWidth, font)
    lcd.setColor(CUSTOM_COLOR, color)
    local flags = (font or SMLSIZE or 0) + CUSTOM_COLOR
    value = fit(value, maxWidth, flags)
    if #value > 0 then lcd.drawText(x, y, value, flags) end
  end
  local function text(x, y, value, color, maxWidth, font)
    literal(x, y, tr(value), color, maxWidth, font)
  end
  m:sample()
  rect(z.x, z.y, z.w, z.h, bg)
  if z.w < 440 or z.h < 252 then
    if event == nil then setView(widget) end
    if z.h >= 22 then text(z.x + 3, z.y + 2, 'APMon: grosse Zone waehlen', warn, z.w - 6) end
    return
  end
  local layout = layoutFor(widget, z)
  handleInput(widget, z, layout, event, touch)
  language = languageOf(widget)
  local left, inner = z.x + 12, z.w - 24
  rect(z.x, z.y, z.w, layout.header, info)
  local heading = widget.view == 'language' and 'Sprache'
    or messagePage(widget) and 'FC-Meldungen'
    or widget.view == 'diagnostics' and 'Telemetrie-Diagnose'
    or widget.view == 'summary' and 'Letzte Armed-Phase'
    or widget.view == 'summaryDetail' and 'Bilanzdetails'
    or widget.view == 'gps' and 'GPS-Details'
    or widget.view == 'sensors' and 'Sensoren' or project.title
  text(left, z.y + 8, heading, bg, inner - 40, headingFont)
  if not widget.view and clockEnabled(widget) then
    local clock = project.clock()
    local w, h = lcd.sizeText(clock, layout.clockFont + CUSTOM_COLOR)
    text(z.x + math.floor((z.w - w) / 2), z.y + math.floor((layout.header - h) / 2),
      clock, bg, w, layout.clockFont)
  end
  drawLogo(z, layout.header)
  if widget.view == 'gps' then
    local details, live, age = m:gpsDetails()
    local top, back = layout.header + 8, z.h - layout.rowHeight - 12
    local status = tr(live and 'Live' or 'Nicht live')
    if age then status = status .. '  |  ' .. string.format(tr('vor %ds'), age) end
    literal(left, top, status, live and info or warn, inner)
    local step = math.min(layout.rowHeight, math.floor((back - top - 4) / 6))
    for i, row in ipairs(details) do
      local y = top + i * step
      rect(left, y, inner, step - 2, panel)
      text(left + 8, y + 1, row[1], info, math.floor(inner / 2) - 8)
      text(left + math.floor(inner / 2), y + 1, row[2], normal, math.floor(inner / 2) - 8)
    end
    rect(left, back, inner, layout.rowHeight - 3, info)
    text(left + 8, back + 4, 'Zurück', bg, inner - 16)
    return
  end
  if summaryPage(widget) then
    local phase, back = tracker.last, z.h - layout.rowHeight - 12
    local top, half = layout.header + 8, math.floor(inner / 2)
    local function button(x, w, label, selected)
      rect(x, back, w, layout.rowHeight - 3, selected and info or panel)
      text(x + 8, back + 4, label, selected and bg or info, w - 16)
    end
    if not phase then
      text(left, top, 'Keine Bilanz vorhanden', info, inner)
      if tracker.active then text(left, top + layout.step, 'Aufzeichnung läuft', normal, inner) end
    elseif widget.view == 'summaryDetail' then
      local notes = summary.notes(phase)
      if #notes == 0 then notes[1] = 'Keine Datenlücke erkannt' end
      for i, note in ipairs(notes) do text(left, top + (i - 1) * layout.step, note, normal, inner) end
      text(left, back - layout.step, 'Armed-Zeit, nicht Flugzeit', info, inner)
    else
      text(left, top, phase.partial and 'Unvollständig' or 'Vollständig', phase.partial and warn or info, inner)
      local caption = tr('Armed-Zeit, nicht Flugzeit')
      local captionWidth = lcd.sizeText(caption, regularFont + CUSTOM_COLOR)
      literal(left + inner - captionWidth, top, caption, info, captionWidth)
      local cardTop = top + layout.step
      local stride = math.floor((back - cardTop - 3) / 3)
      local cardHeight = stride - 4
      local _, bigHeight = lcd.sizeText('Ag', headingFont + CUSTOM_COLOR)
      local valueFont = cardHeight >= layout.smallHeight + bigHeight + 7 and headingFont or regularFont
      for i, row in ipairs(summary.rows(phase)) do
        local col, y, w = 0, cardTop, inner
        if i > 1 then
          col = (i - 2) % 2
          y = cardTop + (1 + math.floor((i - 2) / 2)) * stride
          w = col == 0 and half - 2 or inner - half - 2
        end
        local x = left + (col == 0 and 0 or half + 2)
        rect(x, y, w, cardHeight, panel)
        text(x + 8, y + 3, row[1], info, w - 16)
        literal(x + 8, y + 4 + layout.smallHeight, row[2], normal, w - 16, valueFont)
      end
    end
    if phase and widget.view == 'summary' then
      button(left, half - 2, 'Details', widget.focus == 1)
      button(left + half + 2, inner - half - 2, 'Zurück', widget.focus == 2)
    else
      button(left, inner, 'Zurück', true)
    end
    return
  end
  if diagnosticPage(widget) then
    local top, back, listTop, visible, count, first, last = diagnosticWindow(widget, z, layout)
    local height, half = layout.rowHeight, math.floor(inner / 2)
    local function button(x, y, w, label, selected)
      rect(x, y, w, height - 3, selected and info or panel)
      text(x + 8, y + 4, label, selected and bg or info, w - 16)
    end
    local function rightText(right, y, label, color, limit, font)
      local w = math.min(lcd.sizeText(label, font + CUSTOM_COLOR), limit)
      literal(right - w, y, label, color, w, font)
    end
    local state = diagnostics.stateLabel
    if widget.view == 'diagnostics' then
      local data = diagnostics.summary(m, receiver)
      local link = data.link
      local linkValue = link and (link.state == 'valid' and m:formatSensor(link) or tr(state[link.state])) or '--'
      local counts = m.api and string.format(tr('%d/%d gültig'), data.valid, data.total) or tr(state.noapi)
      local issue = data.issue
      local age = data.fcAge and string.format(tr('vor %ds'), data.fcAge) or ''
      local message, messageAge = data.message, data.messageAge
      local rows = {
        { 'RC-Link', linkValue, link and link.name, link and link.state ~= 'valid' },
        { 'EdgeTX-Sensoren', counts, issue and (issue.name .. ': ' .. tr(state[issue.state])), not m.api or issue },
        { 'FC-Status (Passthrough)', tr(state[data.fcState]), age, data.fcState ~= 'valid' },
        { 'Letzte FC-Textmeldung', messageAge and string.format(tr('vor %ds'), messageAge)
          or tr(data.fcState == 'noapi' and state.noapi or state.unreceived),
          message and message.value, message and message.severity <= 4 },
      }
      text(left, top, 'Datenquellen', info, inner)
      local noteY = back - layout.smallHeight - 4
      local stride = math.floor((noteY - listTop) / #rows)
      local font = stride < layout.smallHeight * 2 + 7 and (TINSIZE or regularFont) or regularFont
      local _, line = lcd.sizeText('Ag', font + CUSTOM_COLOR)
      for i, row in ipairs(rows) do
        local y = listTop + (i - 1) * stride
        local statusWidth = math.min(lcd.sizeText(row[2], font + CUSTOM_COLOR), math.floor(inner * 0.42))
        rect(left, y, inner, stride - 3, panel)
        local rowY = y + math.max(2, math.floor((stride - 3 - 2 * line) / 2))
        text(left + 8, rowY, row[1], normal, inner - statusWidth - 24, font)
        rightText(left + inner - 8, rowY, row[2], row[4] and warn or normal, statusWidth, font)
        if row[3] then literal(left + 8, rowY + line, row[3], row[4] and warn or info, inner - 16, font) end
      end
      text(left, noteY, 'Gültige Sensordaten sind keine Flugfreigabe.', info, inner)
      button(left, back, half - 2, 'Sensoren', widget.focus == 1)
      button(left + half + 2, back, inner - half - 2, 'Zurück', widget.focus == 2)
    else
      local nameWidth, valueWidth = math.floor(inner * 0.25), math.floor(inner * 0.43)
      text(left + 8, top, 'Sensor', info, nameWidth - 8)
      text(left + nameWidth, top, 'Letzter Wert', info, valueWidth - 8)
      if count == 0 then text(left + 8, listTop, 'Keine Sensoren konfiguriert', info, inner - 16) end
      for i = first, math.min(count, first + visible - 1) do
        local entry = m.sensorList[i]
        local y = listTop + (i - first) * height
        rect(left, y, inner, height - 3, panel)
        literal(left + 8, y + 4, entry.name, normal, nameWidth - 16)
        literal(left + nameWidth, y + 4, m:formatSensor(entry), normal, valueWidth - 8)
        rightText(left + inner - 8, y + 4, tr(state[entry.state]), entry.state == 'valid' and info or warn,
          inner - nameWidth - valueWidth - 8, regularFont)
      end
      if first > 1 then button(left, back - height, half - 2, 'Vorige') end
      if first < last then button(left + half + 2, back - height, inner - half - 2, 'Weitere') end
      button(left, back, inner, 'Zurück')
      if count > 0 then
        local range = string.format('%d–%d / %d', first, math.min(count, first + visible - 1), count)
        rightText(left + inner - 8, back + 4, range, info, half - 16, regularFont)
      end
    end
    return
  end
  if messagePage(widget) then
    local top, back, first, index, total, visible = messageWindow(widget, z, layout)
    local height = layout.rowHeight
    local flags = regularFont + CUSTOM_COLOR
    local function messageText(x, y, value, color)
      lcd.setColor(CUSTOM_COLOR, color)
      lcd.drawText(x, y, value, flags)
    end
    local function button(x, y, w, label, selected)
      rect(x, y, w, height - 3, selected and info or panel)
      text(x + 8, y + 4, label, selected and bg or info, w - 16)
    end
    if widget.view == 'messageDetail' then
      local message = widget.messageDetail
      local age = receiver.age(message)
      top = top - height
      if message.armed ~= nil then
        text(left, top, message.armed == 1 and 'Armen bestätigt' or 'Entarmen bestätigt', info, inner)
        if age then text(left, top + layout.step, string.format(tr('vor %ds'), age), normal, inner) end
        button(left, back, inner, 'Zurück')
        return
      end
      local label = string.format(tr('Schweregrad %d'), message.severity)
      if age then label = label .. '  |  ' .. string.format(tr('vor %ds'), age) end
      if message.repeats > 1 then label = label .. '  |  x' .. message.repeats end
      text(left, top, label, message.severity <= 4 and warn or info, inner)
      local value = message.value
      for y = top + layout.smallHeight + 9, back - layout.smallHeight - 8, layout.step do
        if value == '' then break end
        local part = fit(value, inner, flags)
        messageText(left, y, part, message.severity <= 4 and warn or normal)
        value = string.sub(value, #part + 1)
      end
    else
      local filter = widget.filterFocus or index == 0
      button(left, top - height, inner, widget.warningsOnly and 'Filter: Warnungen & Fehler' or 'Filter: Alle', filter)
      if total == 0 then text(left, top, widget.warningsOnly and 'Keine Warnungen' or 'Keine FC-Meldungen', info, inner) end
      for i = first, first + visible - 1 do
        local entry = widget.messageList[i]
        local marker = entry.armed ~= nil
        local y, selected = top + (i - first) * height, not filter and i == index
        local age = receiver.age(entry)
        local meta = marker and (age and age .. 's' or '')
          or ('S' .. entry.severity .. (entry.repeats > 1 and ' x' .. entry.repeats or '')
            .. (age and ' ' .. age .. 's' or ''))
        local metaWidth = math.min(lcd.sizeText(meta, flags), math.floor(inner / 2))
        rect(left, y, inner, height - 3, selected and info or panel)
        local fg = selected and bg or marker and info or entry.severity <= 4 and warn or normal
        local value = marker and (entry.armed == 1 and '[ARMED]' or '[DISARMED]') or entry.value
        local preview, available = (selected and '> ' or '') .. value, inner - metaWidth - 24
        if lcd.sizeText(preview, flags) > available then
          preview = fit(preview, available - lcd.sizeText('...', flags), flags) .. '...'
        end
        messageText(left + 8, y + 4, preview, fg)
        text(left + inner - metaWidth - 8, y + 4, meta, fg, metaWidth)
      end
      local half, nav = math.floor(inner / 2), back - height
      if not filter and index > 1 then button(left, nav, half - 2, 'Neuere') end
      if not filter and index < total then button(left + half + 2, nav, inner - half - 2, 'Ältere') end
    end
    button(left, back, inner, 'Zurück')
    if widget.view == 'messages' and total > 0 then
      local position = index .. '/' .. total
      local w = lcd.sizeText(position, flags)
      text(left + inner - w - 8, back + 4, position, info, w)
    end
    return
  end
  if widget.view then
    if widget.view == 'menu' then
      for i, line in ipairs(layout.subtitles) do
        text(left, layout.subtitleY + (i - 1) * layout.step, line, normal, inner)
      end
      for i, line in ipairs(layout.repo) do
        text(left, layout.repoY + (i - 1) * layout.step, line, info, inner)
      end
      text(left + inner - layout.versionWidth, layout.versionY, versionLabel, normal, layout.versionWidth)
      rect(left, layout.divider, inner, 1, info)
    end
    local top, first, count, visibleChoices = rows(widget, layout)
    local rowHeight = widget.view == 'menu' and layout.menuRowHeight or layout.rowHeight
    if widget.view == 'language' then
      text(left, z.h - layout.smallHeight - 8, 'Nur für diese Sitzung', info, inner)
    end
    for i = first, math.min(count, first + visibleChoices - 1) do
      local label
      if widget.view == 'menu' then
        label = i == 1 and tr('Sprache') .. ': ' .. i18n.language(language).name
          or i == 2 and 'FC-Meldungen'
          or i == 3 and tr('Uhr') .. ': ' .. tr(clockEnabled(widget) and 'An' or 'Aus')
          or i == 4 and 'Telemetrie-Diagnose'
          or i == 5 and 'Letzte Armed-Phase'
          or i == 6 and 'GPS-Details'
          or 'Zurück'
      else
        label = widget.view == 'language' and i <= #i18n.languages and i18n.languages[i].name or 'Zurück'
      end
      local y, selected = top + (i - first) * rowHeight, i == widget.focus
      rect(left, y, inner, rowHeight - 3, selected and info or panel)
      local inset = math.min(4, math.floor((rowHeight - 3 - layout.smallHeight) / 2))
      text(left + 8, y + inset, (selected and '> ' or '') .. tr(label), selected and bg or normal, inner - 16)
    end
    return
  end
  local function yesno(key)
    local v = m.values[key]
    return v == 1 and 'Ja' or v == 0 and 'Nein' or '--'
  end
  local yaw = m.values.yaw
  local directions = i18n.language(language).directions or i18n.language(1).directions
  local direction = yaw and directions[math.floor(((yaw % 360) + 22.5) / 45) % 8 + 1] or '--'
  local groups = {
    {
      { 'AKKU / STATUS / GPS' },
      { 'Flugmodus', m:format('mode') },
      { 'Motoren', m.values.armed == 1 and 'ARMED' or m.values.armed == 0 and 'DISARMED' or '--' },
      { 'Akku (Spannung)', m:format('voltage') },
      { 'Akku (Strom)', m:format('current') },
      { 'Akku (Rest laut FC)', m:format('remaining') },
      { 'Akku (Verbrauch)', m:format('used') },
      { 'RC-Linkqualität', m:format('lq') },
      { 'GPS Fix', m.fix ~= nil and ({ [0]='Kein GPS', 'Nein', 'Ja 2D', 'Ja 3D', 'Ja DGPS', 'Ja RTK flt', 'Ja RTK fix' })[m.fix] or yesno('gpsfix') },
      { 'Satelliten', m:format('satellites') },
      { 'EKF zuletzt', receiver.ekf and tostring(receiver.ekf.value) .. ' / ' .. tostring(receiver.age(receiver.ekf) or 0) .. 's' or '--' },
    },
    {
      { 'FLUG' },
      { m.values.altitude ~= nil and 'Höhe' or 'Höhe (GPS Altitude)',
        m.values.altitude ~= nil and m:format('altitude') or m:format('gpsaltitude') },
      { 'Roll', m:format('roll') },
      { 'Pitch', m:format('pitch') },
      { 'Yaw', m:format('yaw') },
      { 'H-Tempo GPS', m:format('speed') },
      { 'Richtung', direction },
      { 'Steigen', m:format('climb') },
    },
  }
  local cellWidth = math.floor(z.w / 2)
  local firstY, footer = z.y + layout.header + 4, z.y + layout.footerY
  local rowHeight = math.floor((footer - firstY - 2) / #groups[1])
  -- At the minimum widget size, keep all rows readable under the shared header.
  local bodyFont = rowHeight < layout.smallHeight and (TINSIZE or regularFont) or regularFont
  local bodyFlags = bodyFont + CUSTOM_COLOR
  for col, rows in ipairs(groups) do
    local x = z.x + (col - 1) * cellWidth + 8
    for slot, field in ipairs(rows) do
      local y = firstY + (slot - 1) * rowHeight
      if not field[2] then
        text(x, y, field[1], info, cellWidth - 16, bodyFont)
      else
        local value = tr(field[2])
        local valueWidth = math.min(lcd.sizeText(value, bodyFlags), cellWidth - 80)
        text(x, y, field[1], normal, cellWidth - 24 - valueWidth, bodyFont)
        text(x + cellWidth - 16 - valueWidth, y, value,
          string.find(value, '--', 1, true) and warn or normal, valueWidth, bodyFont)
      end
    end
  end
  local status, severity = m:status()
  if severity == 'warn' then
    text(z.x + cellWidth + 8, firstY + #groups[2] * rowHeight, status, warn, cellWidth - 12, bodyFont)
  end
  local message, age = receiver.message, receiver.age(receiver.message)
  local messageColor = message and message.severity <= 4 and warn or normal
  local label = message and string.format(tr('FC-Meldung / vor %ds'), age or 0) or tr('FC-Meldung: --')
  local buttonX = z.x + z.w - 12 - menuW
  text(z.x + 8, footer, label, info, z.w - menuW - 24)
  if event ~= nil then
    rect(buttonX, footer - 5, menuW, layout.buttonHeight, panel)
    text(buttonX + 8, footer - 2, 'Menü', info, menuW - 16)
  else
    text(buttonX, footer, 'Vollbild: Menü', info, menuW)
  end
  if message then text(z.x + 8, footer + layout.messageStep, message.value, messageColor, z.w - 16) end

end
return { name = 'APMon', options = options, create = create, update = update,
  background = background, refresh = refresh }
