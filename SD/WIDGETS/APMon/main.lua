-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/WIDGETS/APMon/main.lua
-- Purpose: Render the GX15 color dashboard and handle per-widget language settings.
-- Project version: 0.1.0
-- Updated: 2026-11-17
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
local options = { { 'Language', CHOICE, 1, i18n.choices } }
local function create(zone, opts)
  return { zone = zone, options = opts, monitor = core.new(config, receiver) }
end
local function update(widget, opts) widget.options = opts end
local function background(widget) widget.monitor:sample() end
local function refresh(widget)
  local z, m = widget.zone, widget.monitor
  local language = widget.options and widget.options.Language or 1
  local function tr(value) return i18n.text(language, value) end
  m:sample()
  local bg = lcd.RGB(12, 20, 30)
  local normal = lcd.RGB(225, 234, 243)
  local warn = lcd.RGB(255, 192, 70)
  local info = lcd.RGB(70, 215, 240)
  local function rect(x, y, w, h, color)
    lcd.setColor(CUSTOM_COLOR, color)
    lcd.drawFilledRectangle(x, y, w, h, CUSTOM_COLOR)
  end
  local function text(x, y, value, color, maxWidth)
    value = tr(value)
    lcd.setColor(CUSTOM_COLOR, color)
    local flags = (SMLSIZE or 0) + CUSTOM_COLOR
    -- Use measured width; never draw outside the assigned widget zone.
    while #value > 0 do
      local w = lcd.sizeText(value, flags)
      if w <= maxWidth then break end
      -- Remove a complete UTF-8 character, preserving labels such as Höhe.
      local start = #value
      while start > 1 and string.byte(value, start) >= 128
          and string.byte(value, start) < 192 do start = start - 1 end
      value = string.sub(value, 1, start - 1)
    end
    if #value > 0 then lcd.drawText(x, y, value, flags) end
  end
  rect(z.x, z.y, z.w, z.h, bg)
  if z.w < 440 or z.h < 252 then
    if z.h >= 22 then text(z.x + 3, z.y + 2, 'APMon: grosse Zone waehlen', warn, z.w - 6) end
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
  text(z.x + 8, footer, label, info, z.w - 16)
  if message then text(z.x + 8, footer + 20, message.value, messageColor, z.w - 16) end

end
return { name = 'APMon', options = options, create = create, update = update,
  background = background, refresh = refresh }
