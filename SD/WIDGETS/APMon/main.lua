-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/WIDGETS/APMon/main.lua
-- Purpose: Render the GX15 dashboard, full-screen project menu and language selection.
-- Project version: 0.2.0
-- Updated: 2026-11-20
-- Authors: APMon contributors
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- Copyright (c) 2026 APMon contributors
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- GX15 color widget, classic EdgeTX LCD API (2.x).
local function module(name)
  local path = '/SCRIPTS/APMON/' .. name .. '.lua'
  local chunk, reason = loadScript(path)
  if not chunk then error('APMon: ' .. path .. ': ' .. tostring(reason or 'nicht ladbar')) end
  return chunk()
end
local core = module('core')
local config = module('config')
local receiver = module('pass')
local i18n = module('i18n')
local project = module('project')
local options = { { 'Language', CHOICE, 1, i18n.choices } }
local logo
local function drawMenuLogo(width)
  if not (Bitmap and Bitmap.open and lcd.drawBitmap) then return end
  -- Load once across instances, only when a menu is opened. EdgeTX draws
  -- nothing for a missing/invalid bitmap, so older SD installs still work.
  if logo == nil then logo = Bitmap.open('/WIDGETS/APMon/logo.png') or false end
  if logo then lcd.drawBitmap(logo, width - 44, 3) end
end
local function create(zone, opts)
  return { zone = zone, options = opts, monitor = core.new(config, receiver) }
end
local function update(widget, opts)
  widget.options, widget.sessionLanguage = opts, nil
end
local function background(widget) widget.monitor:sample() end
local function languageOf(widget)
  local index = widget.sessionLanguage or (widget.options and widget.options.Language)
  return i18n.languages[index] and index or 1
end
local function setView(widget, view, focus)
  widget.view, widget.focus = view, focus
end
local menuW, menuH = 148, 24
local rowHeight, visibleChoices = 28, 5
local function rows(widget, z)
  if widget.view == 'menu' then return 142, 1, 3 end
  if widget.view == 'messages' then return z.h - 44, 1, 1 end
  local count = #i18n.languages + 1
  return 52, math.max(1, widget.focus - visibleChoices + 1), count
end
local function handleInput(widget, z, event, touch)
  if event == nil then setView(widget); return end
  if event == 0 then return end
  local enter = event == EVT_VIRTUAL_ENTER
  local exit = event == EVT_VIRTUAL_EXIT
  local tap = event == EVT_TOUCH_TAP and touch
  local function inButton(top, height)
    return tap and tap.x >= 12 and tap.x < z.w - 12 and tap.y >= top and tap.y < top + height
  end
  if not widget.view then
    local top = z.h - 47
    if enter or (inButton(top, menuH) and tap.x >= z.w - 12 - menuW) then
      setView(widget, 'menu', 1)
    end
    return
  end
  if exit then
    if widget.view == 'menu' then setView(widget)
    else setView(widget, 'menu', widget.view == 'messages' and 2 or 1) end
    return
  end
  local top, first, count = rows(widget, z)
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
    elseif widget.focus == 2 then setView(widget, 'messages', 1)
    else setView(widget) end
  elseif widget.view == 'language' then
    -- EdgeTX persists widget options only via its own settings screen.
    if widget.focus <= #i18n.languages then widget.sessionLanguage = widget.focus end
    setView(widget, 'menu', 1)
  else
    setView(widget, 'menu', 2)
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
  local function text(x, y, value, color, maxWidth, font)
    lcd.setColor(CUSTOM_COLOR, color)
    local flags = (font or SMLSIZE or 0) + CUSTOM_COLOR
    value = fit(tr(value), maxWidth, flags)
    if #value > 0 then lcd.drawText(x, y, value, flags) end
  end
  m:sample()
  rect(z.x, z.y, z.w, z.h, bg)
  if z.w < 440 or z.h < 252 then
    if event == nil then setView(widget) end
    if z.h >= 22 then text(z.x + 3, z.y + 2, 'APMon: grosse Zone waehlen', warn, z.w - 6) end
    return
  end
  handleInput(widget, z, event, touch)
  language = languageOf(widget)
  if widget.view then
    local left, inner = 12, z.w - 24
    rect(0, 0, z.w, 38, info)
    local heading = widget.view == 'menu' and project.title[1]
      or widget.view == 'language' and 'Sprache' or 'FC-Meldungen'
    text(left, 8, heading, bg, inner - 40, MIDSIZE)
    drawMenuLogo(z.w)
    if widget.view == 'menu' then
      for i = 2, #project.title do
        text(left, 44 + (i - 2) * 20, project.title[i], normal, inner)
      end
      text(left, 108, project.repo[1] .. project.repo[2], info, inner)
      rect(left, 132, inner, 1, info)
    elseif widget.view == 'language' then
      text(left, z.h - 24, 'Nur für diese Sitzung', info, inner)
    else
      local message, age = receiver.message, receiver.age(receiver.message)
      local label = message and string.format(tr('FC-Meldung / vor %ds'), age or 0) or tr('FC-Meldung: --')
      text(left, 47, label, info, inner)
      local value = message and message.value or ''
      local flags = (SMLSIZE or 0) + CUSTOM_COLOR
      for y = 72, z.h - 67, 20 do
        if #value == 0 then break end
        local part = fit(value, inner, flags)
        lcd.setColor(CUSTOM_COLOR, message.severity <= 4 and warn or normal)
        lcd.drawText(left, y, part, flags)
        value = string.sub(value, #part + 1)
      end
    end
    local top, first, count = rows(widget, z)
    for i = first, math.min(count, first + visibleChoices - 1) do
      local label
      if widget.view == 'menu' then
        label = i == 1 and tr('Sprache') .. ': ' .. i18n.language(language).name
          or i == 2 and 'FC-Meldungen' or 'Zurück'
      else
        label = widget.view == 'language' and i <= #i18n.languages and i18n.languages[i].name or 'Zurück'
      end
      local y, selected = top + (i - first) * rowHeight, i == widget.focus
      rect(left, y, inner, rowHeight - 3, selected and info or panel)
      text(left + 8, y + 4, (selected and '> ' or '') .. tr(label), selected and bg or normal, inner - 16)
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
  text(z.x + 8, z.y + 3, 'ARDUPILOT MONITOR', info, z.w - 16)
  local status, severity = m:status()
  if severity == 'warn' then
    text(z.x + math.floor(z.w / 2), z.y + 3, status, warn, math.floor(z.w / 2) - 8)
  end
  local cellWidth = math.floor(z.w / 2)
  -- Reserve two full-width lines for the most recent FC message.
  local rowHeight = math.floor((z.h - 76) / 11)
  for col, rows in ipairs(groups) do
    local x = z.x + (col - 1) * cellWidth + 8
    for slot, field in ipairs(rows) do
      local y = z.y + 28 + (slot - 1) * rowHeight
      if not field[2] then
        text(x, y, field[1], info, cellWidth - 16)
      else
        local value = tr(field[2])
        local flags = (SMLSIZE or 0) + CUSTOM_COLOR
        local valueWidth = math.min(lcd.sizeText(value, flags), cellWidth - 80)
        text(x, y, field[1], normal, cellWidth - 24 - valueWidth)
        text(x + cellWidth - 16 - valueWidth, y, value,
          string.find(value, '--', 1, true) and warn or normal, valueWidth)
      end
    end
  end
  local message, age = receiver.message, receiver.age(receiver.message)
  local footer = z.y + z.h - 42
  local messageColor = message and message.severity <= 4 and warn or normal
  local label = message and string.format(tr('FC-Meldung / vor %ds'), age or 0) or tr('FC-Meldung: --')
  local buttonX = z.x + z.w - 12 - menuW
  text(z.x + 8, footer, label, info, z.w - menuW - 24)
  if event ~= nil then
    -- The button ends above the message body, which starts 20 pixels below the label.
    rect(buttonX, footer - 5, menuW, menuH, panel)
    text(buttonX + 8, footer - 2, 'Menü', info, menuW - 16)
  else
    text(buttonX, footer, 'Vollbild: Menü', info, menuW)
  end
  if message then text(z.x + 8, footer + 20, message.value, messageColor, z.w - 16) end

end
return { name = 'APMon', options = options, create = create, update = update,
  background = background, refresh = refresh }
