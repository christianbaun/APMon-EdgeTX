-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: tests/check.lua
-- Purpose: Test sensor handling, passthrough decoding and both UIs with simulated EdgeTX APIs.
-- Project version: 0.2.0
-- Updated: 2026-11-20
-- Authors: APMon contributors
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- Copyright (c) 2026 APMon contributors
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- Exercise the restricted string environment used by embedded Lua builds.
debug.setmetatable('', nil)
local root = 'SD'
local now, data, calls, colorDisplay = 100, {}, {}, false
local draws, rectangles = {}, {}
local lines, bitmaps, bitmapLoads = {}, {}, 0
getTime = function() return now end
getFieldInfo = function(name) if data[name] then return { id = name } end end
getSourceValue = function(id)
  local item = data[id]
  return item.value, item.current ~= false, item.fresh ~= false
end
loadScript = function(path) return assert(loadfile(root .. path)) end
SMLSIZE, MIDSIZE, DBLSIZE, INVERS, RIGHT = 0x200, 0x300, 0x400, 2, 4
FORCE, ERASE = 2, 4
VALUE, CUSTOM_COLOR, BOOL, CHOICE = 0, 256, 2, 3
EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV = 10, 11
EVT_VIRTUAL_ENTER, EVT_VIRTUAL_EXIT, EVT_ROT_RIGHT, EVT_ROT_LEFT = 12,13,14,15
EVT_TOUCH_TAP = 16
local function measure(text, flags)
  if colorDisplay then return #text * 8, 16 end
  local _, glyphs = string.gsub(text, '[^\128-\191]', '')
  local font = (flags or 0) & 0xF00
  if font == SMLSIZE then
    local _, wide = string.gsub(text, '[#$+MWmw]', '')
    local _, spaces = string.gsub(text, ' ', '')
    local _, narrow = string.gsub(text, "[.!':|]", '')
    return glyphs * 5 + wide - spaces * 2 - narrow * 3, 7
  end
  if font == MIDSIZE then return glyphs * 9, 12 end
  if font == DBLSIZE then return glyphs * 11, 16 end
  return glyphs * 6, 8
end
lcd = {
  clear = function() calls, draws, rectangles, lines = {}, {}, {}, {} end,
  RGB = function(r, g, b) return r * 65536 + g * 256 + b end,
  setColor = function() end,
  drawText = function(x, y, text, flags)
    flags = flags or 0
    local w, h = measure(text, flags)
    if not colorDisplay and flags & RIGHT ~= 0 then x = x - w end
    assert(x >= 0 and y >= 0 and x + w <= LCD_W and y + h <= LCD_H,
      'Text outside screen: ' .. text)
    calls[#calls + 1] = text
    draws[#draws + 1] = {x=x, y=y, w=w, h=h, flags=flags, text=text}
  end,
  drawFilledRectangle = function(x, y, w, h, flags)
    assert(x >= 0 and y >= 0 and x + w <= LCD_W and y + h <= LCD_H)
    rectangles[#rectangles + 1] = {x=x, y=y, w=w, h=h, flags=flags}
  end,
  drawLine = function(x1, y1, x2, y2, pattern, flags)
    assert(not colorDisplay and x1 >= 0 and x2 < LCD_W and y1 >= 0 and y2 >= 0 and y1 < LCD_H and y2 < LCD_H)
    lines[#lines + 1] = { x1=x1, y1=y1, x2=x2, y2=y2, pattern=pattern, flags=flags }
  end,
  drawBitmap = function(bitmap, x, y)
    assert(colorDisplay and bitmap == 'APMon logo' and x >= 0 and x + 32 <= LCD_W and y >= 0 and y + 32 <= 38)
    bitmaps[#bitmaps + 1] = {x=x, y=y}
  end,
}
Bitmap = { open = function(path)
  assert(colorDisplay and path == '/WIDGETS/APMon/logo.png')
  bitmapLoads = bitmapLoads + 1
  return 'APMon logo'
end }
local function drawOf(text, y)
  for _, draw in ipairs(draws) do
    if draw.text == text and (y == nil or y == draw.y) then return draw end
  end
end
local function assertPage(title, counter)
  assert(calls[1] == 'APMon ' .. title and calls[2] == counter, 'Expected page: ' .. title)
  assert(rectangles[1].x == 0 and rectangles[1].w == LCD_W)
  assert(draws[1].flags & INVERS ~= 0 and draws[2].flags & INVERS ~= 0)
  assert(draws[2].x + draws[2].w == LCD_W - 2)
  assert(#lines == 0) -- menus only
end
local function assertProjectTitle()
  local title = table.concat(calls, ' ', 1, 4)
  assert(title == 'APMon - ArduPilot telemetry monitor for EdgeTX monochrome and color radios', title)
end
local function assertMonoLogo()
  assert(#lines == 6 and lines[1].x1 == 110 and lines[6].x2 == 123)
  for _, line in ipairs(lines) do
    assert(line.x1 >= 110 and line.x2 <= 123 and line.y1 >= 1 and line.y1 <= 8
      and line.y2 >= 1 and line.y2 <= 8 and line.pattern == 255 and line.flags == ERASE)
  end
  assert(draws[1].x + draws[1].w < lines[1].x1)
end
local function assertMonoMenu(language, messages)
  assertProjectTitle()
  assert(drawOf('github.com/christianbaun/', 33) and drawOf('APMon-EdgeTX', 40))
  assert(drawOf(language, 49) and drawOf(messages, 57))
  assertMonoLogo()
end
-- Any attempt to write or transmit fails the test.
model = setmetatable({}, { __index = function() error('Model mutation/access not allowed') end })
crossfireTelemetryPush = function() error('No transmissions allowed') end
sportTelemetryPush = crossfireTelemetryPush
local config = loadScript('/SCRIPTS/APMON/config.lua')()
local core = loadScript('/SCRIPTS/APMON/core.lua')()
local m = core.new(config)
m:sample(true)
assert(m:format('voltage') == '--') -- no source is not a zero battery
assert(m:status() == 'Keine aktuellen FC-Daten')
data.RxBt = { value = 15.5 }
data.Curr = { value = 0 }
data.FM = { value = 'STABILIZE' }
data.GPS = { value = { lat = 49.1, lon = 8.1 } }
m:sample(true)
assert(m:format('voltage') == '15.50 V')
assert(m:format('current') == '0.00 A')
assert(m:format('mode') == 'STABILIZE')
for short, fullName in pairs({ STAB = 'STABILIZE', LOIT = 'LOITER', GUID = 'GUIDED' }) do
  data.FM.value = short .. '*'; m:sample(true)
  assert(m:format('mode') == fullName)
end
data.FM.value = 'STABILIZE'; m:sample(true)
assert(m:rows()[2][2] == '--') -- never infer disarmed from mode/switch
data.RxBt.fresh = false
m:sample(true)
assert(m:format('voltage') == '15.50 V') -- slow sensor remains current
assert(m:status() == 'Sensordaten / keine Flugfreigabe')
data.RxBt.fresh, data.RxBt.current = true, false
m:sample(true)
assert(m:format('voltage') == '--')
data.Curr.value = 0/0
m:sample(true)
assert(m:format('current') == '--')
config.sensors.pit.names, config.sensors.power.names = { 'Pit' }, { 'Pwr' }
data.Pit, data.Pwr = { value = 1 }, { value = 25 }
m:sample(true)
assert(m:rows()[15][2] == 'AN')
assert(m:rows()[16][2] == 'PIT: mW unbekannt')
data.Pit.value = 0
m:sample(true)
assert(m:rows()[16][2] == '25 mW')
data.Pit.current = false
m:sample(true)
assert(m:rows()[16][2] == '-- (PIT unbekannt)')
local saved = getSourceValue
getSourceValue = nil
m:sample(true)
assert(m:format('voltage') == '--')
assert(m:status() == 'API fehlt: getSourceValue')
getSourceValue = saved
-- GX12 and Boxer share a 128x64 UI; test rotation, manual-only views and language.
LCD_W, LCD_H = 128, 64
local realIO, savedLanguage, writeFailure = io, nil, false
io = {
  open = function(path, mode)
    assert(path == '/SCRIPTS/APMON/mono.cfg')
    if mode == 'w' and writeFailure then return nil end
    if mode == 'r' and not savedLanguage then return nil end
    return { mode = mode }
  end,
  read = function() return savedLanguage end,
  write = function(f, value) savedLanguage = value; return f end,
  close = function() end,
}
data.RxBt, data.GAlt = { value = 15.5 }, { value = 24.6 }
data.Yaw, data.Sats = { value = 0 }, { value = 12 }
local mono = loadScript('/SCRIPTS/TELEMETRY/APMon.lua')()
mono.run(0)
assertPage('Overview', '1/2')
assert(drawOf('STABILIZE') and drawOf('Battery'))
local voltage, volts = assert(drawOf('15.50', 18)), assert(drawOf('V', 27))
assert(voltage.flags & 0xF00 == DBLSIZE and volts.x > voltage.x)
mono.run(EVT_ROT_RIGHT)
assertPage('Flight', '2/2')
local flightVoltage, flightVolts = assert(drawOf('15.50', 18)), assert(drawOf('V', 27))
assert(flightVoltage.x == voltage.x and flightVoltage.flags == voltage.flags and flightVolts.x == volts.x)
assert(drawOf('GAlt', 10) and drawOf('24.6', 18) and drawOf('0.0° N', 49))
mono.run(EVT_ROT_LEFT)
assertPage('Overview', '1/2')
mono.run(EVT_VIRTUAL_PREV)
assertPage('Flight', '2/2')
data.Yaw.value = -118 * math.pi / 180
now = now + 20
mono.run(0)
assert(drawOf('-118.0° SW', 49))
data.Alt = { value = -1234.5 }
data.Yaw.value = -1198 * math.pi / 180
data.RxBt.current = false
now = now + 20
mono.run(0)
assert(not drawOf('15.50') and drawOf('--', 18) and drawOf('V', 27))
assert(drawOf('Altitude', 10) and drawOf('-1234.5', 27) and drawOf('m', 27))
assert(drawOf('-1198.0°', 49) and drawOf('SW', 49)) -- direction keeps its own slot when needed
mono.run(EVT_ROT_LEFT)
assert(drawOf('--', 18) and not drawOf('15.50'))
data.Alt = nil
for i = 1, 2 do mono.background(); assert(mono.run(EVT_VIRTUAL_NEXT) == 0) end
local selected = calls[1]
now = 1000; mono.run(0); assert(calls[1] == selected)
now = 5000; mono.run(0); assert(calls[1] == selected)
mono.run(EVT_VIRTUAL_ENTER)
assertMonoMenu('Language: English', 'FC messages')
assert(drawOf('Language: English', 49).flags & INVERS ~= 0)
mono.run(EVT_VIRTUAL_ENTER)
assert(calls[1] == 'APMon / Language')
assertMonoLogo()
assert(drawOf('English') and drawOf('Deutsch'))
mono.run(EVT_ROT_RIGHT); mono.run(EVT_VIRTUAL_ENTER)
assert(savedLanguage == 'de')
assertMonoMenu('Sprache: Deutsch', 'FC-Meldungen')
mono.run(EVT_ROT_RIGHT)
assert(drawOf('FC-Meldungen', 57).flags & INVERS ~= 0)
mono.run(EVT_ROT_LEFT); mono.run(EVT_VIRTUAL_ENTER)
mono.run(EVT_ROT_LEFT); mono.run(EVT_VIRTUAL_EXIT)
assert(savedLanguage == 'de')
assertMonoMenu('Sprache: Deutsch', 'FC-Meldungen')
local reloaded = loadScript('/SCRIPTS/TELEMETRY/APMon.lua')()
reloaded.run(0); assertPage('Übersicht', '1/2')
assert(drawOf('Akku') and drawOf('ENT: Menü'))
reloaded.run(EVT_VIRTUAL_ENTER); reloaded.run(EVT_ROT_LEFT)
reloaded.run(EVT_VIRTUAL_EXIT); reloaded.run(0)
assertPage('Übersicht', '1/2'); assert(savedLanguage == 'de')
reloaded.run(EVT_ROT_RIGHT)
assertPage('Flugwerte', '2/2')
assert(drawOf('Akku') and drawOf('V', 27))
reloaded.run(EVT_ROT_LEFT)
getGeneralSettings = function() return { language = 'EN' } end
local nonGermanRadio = loadScript('/SCRIPTS/TELEMETRY/APMon.lua')()
nonGermanRadio.run(0)
local umlautBase = assert(drawOf('Ubersicht', 2))
assert(calls[3] == '1/2' and drawOf('ENT: Menue'))
assert(rectangles[2].flags == ERASE and rectangles[2].x == umlautBase.x and rectangles[2].y == 0)
assert(rectangles[3].flags == ERASE and rectangles[3].x == umlautBase.x + 3 and rectangles[3].y == 0)
getGeneralSettings = nil
writeFailure = true
reloaded.run(EVT_VIRTUAL_ENTER); reloaded.run(EVT_VIRTUAL_ENTER); reloaded.run(EVT_ROT_LEFT)
reloaded.run(EVT_VIRTUAL_ENTER)
assertMonoMenu('Language: English', 'FC messages')
reloaded.run(EVT_VIRTUAL_EXIT)
assertPage('Overview', '1/2')
assert(calls[#calls] == 'Language not saved')
io = realIO
-- Color lifecycle at target resolution, zones and every configured page.
colorDisplay, LCD_W, LCD_H = true, 480, 320
lcd.sizeText = measure
local widget = loadScript('/WIDGETS/APMon/main.lua')()
assert(#widget.options == 1 and widget.options[1][1] == 'Language')
assert(widget.options[1][2] == CHOICE and widget.options[1][3] == 1)
assert(widget.options[1][4][1] == 'English' and widget.options[1][4][2] == 'Deutsch')
data.RxBt, data.Curr = { value = 15.5 }, { value = 0 }
data['Bat%'], data.Capa, data.RQly = { value = 75 }, { value = 123 }, { value = 99 }
data.Roll, data.Ptch, data.Yaw = { value = math.pi / 2 }, { value = 0 }, { value = -math.pi / 2 }
local full = widget.create({x=0,y=0,w=480,h=272}, { Language = 2 })
calls = {}; widget.refresh(full)
local visible = table.concat(calls, '|')
assert(string.find(visible, '15.50 V', 1, true))
assert(string.find(visible, '90.0 deg', 1, true))
assert(string.find(visible, '|W|', 1, true))
assert(string.find(visible, '0.00 A', 1, true))
assert(string.find(visible, '75 %', 1, true))
assert(string.find(visible, '123 mAh', 1, true))
assert(string.find(visible, '99 %', 1, true))
assert(string.find(visible, 'STABILIZE', 1, true))
assert(string.find(visible, 'GPS Fix', 1, true))
assert(string.find(visible, 'EKF zuletzt', 1, true))
data.GAlt = { value = 123 }
now = now + 20
calls = {}; widget.refresh(full)
assert(string.find(table.concat(calls, '|'), '123.0 m', 1, true))
data.Alt = { value = 5 }
now = now + 20
calls = {}; widget.refresh(full)
visible = table.concat(calls, '|')
assert(string.find(visible, '5.0 m', 1, true))
assert(not string.find(visible, '123.0 m', 1, true))
-- Switching language updates the same instance without changing sensor values.
data.Yaw.value = math.pi / 2
now = now + 20
widget.update(full, { Language = 1 })
calls = {}; widget.refresh(full)
visible = table.concat(calls, '|')
assert(string.find(visible, 'Flight mode', 1, true))
assert(string.find(visible, 'Battery (voltage)', 1, true))
assert(string.find(visible, 'Satellites', 1, true))
assert(string.find(visible, '|E|', 1, true))
assert(string.find(visible, '15.50 V', 1, true))
assert(not string.find(visible, 'Flugmodus', 1, true))
widget.update(full, { Language = 2 })
calls = {}; widget.refresh(full)
visible = table.concat(calls, '|')
assert(string.find(visible, 'Flugmodus', 1, true))
assert(string.find(visible, '|O|', 1, true))
local function colorFrame(w, event, x, y)
  calls, draws, rectangles, bitmaps = {}, {}, {}, {}
  widget.refresh(w, event, x and {x=x,y=y})
end
local function assertColorMenu(language, messages)
  assertProjectTitle()
  assert(drawOf('github.com/christianbaun/APMon-EdgeTX', 108))
  assert(drawOf(language, 146) and drawOf(messages, 174))
  assert(#bitmaps == 1 and bitmaps[1].x == LCD_W - 44 and bitmaps[1].y == 3)
end
colorFrame(full, EVT_TOUCH_TAP, 30, 275)
assert(drawOf('ARDUPILOT MONITOR')) -- unrelated touches do not open the menu
assert(bitmapLoads == 0 and #bitmaps == 0)
colorFrame(full, EVT_TOUCH_TAP, 460, 275)
assertColorMenu('> Sprache: Deutsch', 'FC-Meldungen')
colorFrame(full, EVT_VIRTUAL_ENTER)
assert(drawOf('Sprache') and drawOf('Nur für diese Sitzung'))
assert(bitmapLoads == 1 and #bitmaps == 1)
colorFrame(full, EVT_TOUCH_TAP, 30, 55)
assertColorMenu('> Language: English', 'FC messages')
assert(full.options.Language == 2)
colorFrame(full, EVT_VIRTUAL_NEXT)
assertColorMenu('Language: English', '> FC messages')
colorFrame(full, EVT_VIRTUAL_ENTER)
assert(drawOf('FC messages') and drawOf('FC message: --'))
assert(bitmapLoads == 1 and #bitmaps == 1)
colorFrame(full, EVT_VIRTUAL_EXIT)
assertColorMenu('Language: English', '> FC messages')
colorFrame(full, EVT_VIRTUAL_EXIT)
assert(drawOf('Flight mode') and drawOf('Menu'))
colorFrame(full)
assert(drawOf('Flight mode')) -- session language applies in the normal widget too
local isolated = widget.create({x=0,y=0,w=480,h=272}, { Language = 2 })
colorFrame(isolated, EVT_VIRTUAL_ENTER)
assertColorMenu('> Sprache: Deutsch', 'FC-Meldungen')
colorFrame(isolated)
assert(drawOf('Flugmodus') and not drawOf('APMon - ArduPilot'))
widget.update(full, { Language = 2 })
colorFrame(full, EVT_VIRTUAL_ENTER)
assertColorMenu('> Sprache: Deutsch', 'FC-Meldungen')
colorFrame(full, EVT_TOUCH_TAP, 100, 204)
assert(drawOf('Flugmodus'))
-- Small normal zones still show the dashboard warning; full screen uses LCD dimensions.
LCD_W, LCD_H = 440, 252
local smallZone = widget.create({x=10,y=10,w=90,h=50}, { Language = 0 })
colorFrame(smallZone)
assert(not drawOf('ARDUPILOT MONITOR'))
colorFrame(smallZone, EVT_VIRTUAL_ENTER)
assertColorMenu('> Language: English', 'FC messages')
assert(bitmapLoads == 1) -- menu refreshes and widget instances share the bitmap
LCD_W, LCD_H = 480, 320
-- An unavailable bitmap must not interfere with the menu.
local openBitmap, failedLoads = Bitmap.open, 0
Bitmap.open = function() failedLoads = failedLoads + 1 end
local logoMissing = loadScript('/WIDGETS/APMon/main.lua')()
local withoutLogo = logoMissing.create({x=0,y=0,w=480,h=272}, {})
bitmaps, calls = {}, {}
logoMissing.refresh(withoutLogo, EVT_VIRTUAL_ENTER)
assertProjectTitle()
logoMissing.refresh(withoutLogo, 0)
assert(#bitmaps == 0 and failedLoads == 1)
Bitmap.open = openBitmap
local translated = loadScript('/SCRIPTS/APMON/i18n.lua')()
assert(translated.text(1, 'Ja DGPS') == 'Yes DGPS')
assert(translated.text(1, 'Keine aktuellen FC-Daten') == 'No current FC data')
assert(translated.text(2, 'Ja DGPS') == 'Ja DGPS')
assert(translated.text(2, 'RC-Linkqualität') == 'RC-Linkqualität')
assert(translated.text(1, 'RC-Linkqualität') == 'RC link quality')
assert(translated.text(nil, 'Flugmodus') == 'Flight mode')
assert(translated.text(0, 'Flugmodus') == 'Flight mode') -- old unchecked boolean
assert(translated.text(999, 'Flugmodus') == 'Flight mode')
translated.languages[3] = { code = 'test', name = 'Test', texts = { ['Flugmodus'] = 'Mode test' } }
assert(translated.text(3, 'Flugmodus') == 'Mode test')
assert(translated.text(3, 'Ja DGPS') == 'Yes DGPS') -- incomplete language uses English
local defaultWidget = widget.create({x=0,y=0,w=480,h=272}, {})
calls = {}; widget.refresh(defaultWidget)
assert(string.find(table.concat(calls, '|'), 'Flight mode', 1, true))
for _, zone in ipairs({{x=0,y=0,w=480,h=272}, {x=10,y=10,w=220,h=180},
    {x=0,y=0,w=180,h=110}, {x=0,y=0,w=120,h=60}}) do
  local w = widget.create(zone, { Seite = 1 })
  for page = 1, 16 do
    widget.update(w, { Seite = page }); widget.background(w); widget.refresh(w)
  end
end
for _, item in pairs(data) do item.current = false end
m:sample(true)
assert(m:status() == 'Keine aktuellen FC-Daten')
assert(m:rows()[2][2] == '--')
-- Independent diagnostics exposes raw API values even when APMon rejects them.
colorDisplay, LCD_W, LCD_H = false, 128, 64
lcd.sizeText = nil
getValue = function(id) return data[id].value end
local diag = loadScript('/SCRIPTS/TELEMETRY/APDiag.lua')()
data.RxBt = { value = 15.5, current = false, fresh = false }
diag.run(0)
assert(calls[3] == 'API: 15.50')
assert(calls[4] == 'C=false F=false')
assert(calls[5] == 'getValue: 15.50')
data.RxBt = nil
diag.run(0)
assert(calls[2] == 'Sensorname fehlt')
for i = 1, 12 do diag.run(EVT_VIRTUAL_NEXT) end
assert(calls[1] == 'DIAG RxBt 1/12')
-- ELRS 4.1.0 F0 single, F2 multi and F1 text payloads, not raw MAVLink.
local pass = loadScript('/SCRIPTS/APMON/pass.lua')()
local function tuple(id, value)
  return {id % 256, math.floor(id / 256), value % 256,
    math.floor(value / 256) % 256, math.floor(value / 65536) % 256,
    math.floor(value / 16777216) % 256}
end
local function single(id, value)
  local p = {0xF0}
  for _, byte in ipairs(tuple(id, value)) do p[#p+1] = byte end
  return p
end
local function message(value)
  local p = {0xF1, 6}
  for i=1,#value do p[#p+1] = string.byte(value,i) end
  p[#p+1] = 0
  return p
end
pass.decode(0x80, single(0x5001, 256), now)
assert(pass.value('armed') == 1)
pass.decode(0x80, single(0x5001, 0), now)
assert(pass.value('armed') == 0)
for fix=0,6 do
  local encoded = math.min(fix,3)*16 + math.max(fix-3,0)*16384
  pass.decode(0x80, single(0x5002, encoded), now)
  assert(pass.value('fix') == fix)
end
-- High altitude bits expose float32 rounding hidden by small test values.
local rounded = string.unpack('f', string.pack('f', 0xFC00403F))
assert(math.floor(rounded / 16) % 4 == 0) -- old decoder falsely reported no GPS
pass.decode(0x80, {0xF0,0x02,0x50,0x3F,0x40,0x00,0xFC}, now)
assert(pass.value('fix') == 4) -- actual low bytes encode DGPS
local multi = {0xF2,2}
for _, t in ipairs({tuple(0x5001,256),tuple(0x5002,48)}) do
  for _, byte in ipairs(t) do multi[#multi+1]=byte end
end
pass.decode(0x80,multi,now)
assert(pass.value('armed') == 1 and pass.value('fix') == 3)
pass.decode(0x80,message('Using EKF Source Set 2'),now)
assert(pass.ekf.value == 2)
pass.decode(0x80,message('PreArm: check GPS'),now)
assert(pass.message.value == 'PreArm: check GPS' and pass.ekf.value == 2)
pass.decode(0x80,message('Using EKF Source Set 9'),now)
assert(pass.ekf.value == 2)
for _, bad in ipairs({{}, {0xF0}, {0xF2,2,1}, {0xF1,9,65}, {0xF0,0,80,0,0,0,999}}) do
  pass.decode(0x80,bad,now)
end
pass.decode(0x14,single(0x5001,0),now)
assert(pass.value('armed') == 1)
local receiverMonitor = core.new(config,pass)
receiverMonitor:sample(true)
assert(receiverMonitor.values.armed == 1 and receiverMonitor.values.gpsfix == 1)
local popped = 0
crossfireTelemetryPop = function() popped = popped + 1; return 0x14, {} end
pass.poll(); pass.poll()
assert(popped == 12) -- bounded work, shared poll only once per clock tick
now = now + 301
crossfireTelemetryPop = function() end
receiverMonitor:sample(true)
assert(pass.value('armed') == nil and pass.value('fix') == nil)
assert(receiverMonitor.values.armed == nil and receiverMonitor.values.gpsfix == nil)
assert(pass.age(pass.ekf) == 3) -- history remains explicitly aged
now = 1; pass.poll()
assert(pass.ekf == nil and pass.message == nil) -- timer reset clears history
-- Exercise the actual widget's receiver, merging, and final rendering together.
colorDisplay, LCD_W, LCD_H = true, 480, 320
lcd.sizeText = measure
local incoming = {multi, {0xF0,0x02,0x50,0x3F,0x40,0x00,0xFC}, message('Using EKF Source Set 3')}
crossfireTelemetryPop = function()
  local payload = table.remove(incoming,1)
  if payload then return 0x80,payload end
end
local liveWidget = loadScript('/WIDGETS/APMon/main.lua')()
local live = liveWidget.create({x=0,y=0,w=480,h=272},{ Language = 2 })
calls = {}; liveWidget.refresh(live)
visible = table.concat(calls,'|')
assert(string.find(visible,'ARMED',1,true))
assert(string.find(visible,'Ja DGPS',1,true))
assert(string.find(visible,'Akku (Spannung)',1,true))
assert(string.find(visible,'Akku (Strom)',1,true))
assert(string.find(visible,'Flugmodus',1,true))
assert(string.find(visible,'Akku (Rest laut FC)',1,true))
assert(string.find(visible,'Akku (Verbrauch)',1,true))
assert(string.find(visible,'EKF zuletzt',1,true))
assert(not string.find(visible,'VTX',1,true))
assert(not string.find(visible,'Bodenabst.',1,true))
assert(string.find(visible,'Ja',1,true))
liveWidget.update(live, { Language = 1 })
calls = {}; liveWidget.refresh(live)
visible = table.concat(calls,'|')
assert(string.find(visible,'Yes DGPS',1,true))
assert(string.find(visible,'FC message / 0s ago',1,true))
assert(string.find(visible,'Using EKF Source Set 3',1,true)) -- original FC text
calls, draws, rectangles = {}, {}, {}
liveWidget.refresh(live, EVT_VIRTUAL_ENTER)
liveWidget.refresh(live, EVT_TOUCH_TAP, {x=30,y=174})
assert(drawOf('FC messages', 8) and drawOf('Using EKF Source Set 3', 72))
now = now + 301
calls = {}; liveWidget.refresh(live)
visible = table.concat(calls,'|')
assert(not string.find(visible,'ARMED',1,true))
-- Mono integration receives exactly the same confirmed FC data as the GX15.
LCD_W, LCD_H, colorDisplay = 128,64,false
lcd.sizeText = nil
incoming = { {0xF0,0x02,0x50,0x3F,0x40,0x00,0xFC}, single(0x5001,256),
  message('Using EKF Source Set 2') }
local small = loadScript('/SCRIPTS/TELEMETRY/APMon.lua')()
small.run(0)
assert(string.find(table.concat(calls,'|'),'ARMED',1,true))
assertPage('Overview', '1/2')
assert(drawOf('DGPS/--', 42))
small.run(EVT_VIRTUAL_ENTER)
small.run(EVT_ROT_RIGHT); small.run(EVT_VIRTUAL_ENTER)
assert(string.find(table.concat(calls,'|'),'Using EKF Source Set 2',1,true))
assertMonoLogo()
small.run(EVT_VIRTUAL_EXIT)
assertMonoMenu('Language: English', 'FC messages')
small.run(EVT_VIRTUAL_EXIT)
now = now + 301
small.run(0)
assert(not drawOf('DGPS/--', 42))
-- Run the complete mono application and every loaded module without table.*.
local restricted = setmetatable({}, {__index = function(_, key)
  if key == 'table' then return nil end
  return _G[key]
end})
restricted.loadScript = function(path) return assert(loadfile(root .. path, 't', restricted)) end
local packets = {message('Using EKF Source Set 1'), single(0x5001,256),
  {0xF0,0x02,0x50,0x3F,0x40,0x00,0xFC}}
restricted.crossfireTelemetryPop = function()
  local p = table.remove(packets,1)
  if p then return 0x80,p end
end
local restrictedMono = restricted.loadScript('/SCRIPTS/TELEMETRY/APMon.lua')()
assert(restrictedMono.run(0) == 0)
visible = table.concat(calls,'|')
assert(string.find(visible,'ARMED',1,true))
assert(drawOf('DGPS/--', 42))
restrictedMono.run(EVT_VIRTUAL_ENTER)
assertMonoMenu('Language: English', 'FC messages')
restrictedMono.run(EVT_ROT_RIGHT)
restrictedMono.run(EVT_VIRTUAL_ENTER)
assert(string.find(table.concat(calls,'|'),'Using EKF Source Set 1',1,true))
print('OK: sensor validity, stale data, read-only, layouts, bilingual menus, diagnostics, passthrough, restricted mono Lua')
