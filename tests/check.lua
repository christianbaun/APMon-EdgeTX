-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: tests/check.lua
-- Purpose: Test sensor handling, passthrough decoding and both UIs with simulated EdgeTX APIs.
-- Project version: 0.4.0
-- Updated: 2026-11-21
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
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
local versionLabel
getTime = function() return now end
getFieldInfo = function(name) if data[name] then return { id = name } end end
getSourceValue = function(id)
  local item = data[id]
  return item.value, item.current ~= false, item.fresh ~= false
end
loadScript = function(path) return assert(loadfile(root .. path)) end
SMLSIZE, MIDSIZE, DBLSIZE, INVERS, RIGHT = 0x200, 0x300, 0x400, 2, 4
TINSIZE = 0x100
FORCE, ERASE = 2, 4
VALUE, CUSTOM_COLOR, BOOL, CHOICE = 0, 0x10000, 2, 3
EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV = 10, 11
EVT_VIRTUAL_ENTER, EVT_VIRTUAL_EXIT, EVT_ROT_RIGHT, EVT_ROT_LEFT = 12,13,14,15
EVT_TOUCH_TAP = 16
local function measure(text, flags)
  if colorDisplay then
    local font = (flags or 0) & 0xF00
    if font == TINSIZE then return #text * 6, 12 end
    if font == DBLSIZE then
      if LCD_W == 800 then return #text * 23, 48 end
      if LCD_W == 440 then return #text * 17, 48 end -- oversized font on a compact display
      return #text * 17, 32
    end
    local medium = font == MIDSIZE
    -- Simulate the larger fonts on the 800x480 TX16S MK3.
    if LCD_W == 800 then return medium and #text * 16 or #text * 10, medium and 36 or 24 end
    return medium and #text * 11 or #text * 8, medium and 22 or 16
  end
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
    assert(colorDisplay and bitmap == 'APMon logo' and x >= 0 and x + 32 <= LCD_W and y >= 0 and y + 32 <= LCD_H)
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
  assert(calls[1] == 'APMon')
  assert(drawOf('ArduPilot Telemetry', 10) and drawOf('Monitor for EdgeTX radios', 17))
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
  assert(drawOf('github.com/christianbaun/', 24) and drawOf('APMon-EdgeTX', 31))
  assert(drawOf(language, 41) and drawOf(messages, 49))
  assert(drawOf(language == 'Sprache: Deutsch' and 'Uhr: Aus' or 'Clock: Off', 57))
  local repo, version = drawOf('APMon-EdgeTX', 31), assert(drawOf(versionLabel, 31))
  assert(repo.x + repo.w < version.x)
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
local versionFile = assert(realIO.open('VERSION', 'r'))
versionLabel = 'v' .. versionFile:read('*l')
versionFile:close()
local sdIO = {
  open = function(path, mode)
    if path == '/SCRIPTS/APMON/VERSION' then return realIO.open('VERSION', mode) end
  end,
  read = function(f, n) return f:read(n) end,
  close = function(f) return f:close() end,
}
io = {
  open = function(path, mode)
    if path == '/SCRIPTS/APMON/VERSION' then return sdIO.open(path, mode) end
    assert(path == '/SCRIPTS/APMON/mono.cfg')
    if mode == 'w' and writeFailure then return nil end
    if mode == 'r' and not savedLanguage then return nil end
    return { mode = mode }
  end,
  read = function(f, n)
    if type(f) == 'userdata' then return sdIO.read(f, n) end
    return savedLanguage
  end,
  write = function(f, value) savedLanguage = value; return f end,
  close = function(f) if type(f) == 'userdata' then return sdIO.close(f) end end,
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
assert(drawOf('Language: English', 41).flags & INVERS ~= 0)
mono.run(EVT_VIRTUAL_ENTER)
assert(calls[1] == 'APMon / Language')
assertMonoLogo()
assert(drawOf('English') and drawOf('Deutsch'))
mono.run(EVT_ROT_RIGHT); mono.run(EVT_VIRTUAL_ENTER)
assert(savedLanguage == 'de')
assertMonoMenu('Sprache: Deutsch', 'FC-Meldungen')
mono.run(EVT_ROT_RIGHT)
assert(drawOf('FC-Meldungen', 49).flags & INVERS ~= 0)
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
writeFailure = false
local rtc = { year = 2026, mon = 11, day = 21, hour = 7, min = 5 }
getDateTime = function() return rtc end
reloaded.run(EVT_VIRTUAL_ENTER); reloaded.run(EVT_ROT_RIGHT); reloaded.run(EVT_ROT_RIGHT)
assert(drawOf('Clock: Off', 57).flags & INVERS ~= 0)
assert(drawOf('Language: English', 41) and drawOf('FC messages', 49))
reloaded.run(EVT_VIRTUAL_ENTER)
assert(drawOf('Clock: On', 57) and savedLanguage == 'en\n1')
reloaded.run(EVT_VIRTUAL_EXIT)
assertPage('Overview', '1/2')
local clock = assert(drawOf('07:05', 2))
assert(draws[1].x + draws[1].w < clock.x and clock.x + clock.w < draws[2].x)
local clockReload = loadScript('/SCRIPTS/TELEMETRY/APMon.lua')()
clockReload.run(EVT_ROT_RIGHT)
assertPage('Flight', '2/2')
assert(drawOf('07:05', 2))
rtc.year = 2000
clockReload.run(0)
assert(drawOf('07:05', 2)) -- valid time with an unset calendar
rtc.hour, rtc.min = 0, 0
clockReload.run(0)
assert(drawOf('00:00', 2)) -- midnight is a valid time
rtc.hour = 24
clockReload.run(0)
assert(drawOf('--:--', 2))
getDateTime = nil
clockReload.run(0)
assert(drawOf('--:--', 2))
clockReload.run(EVT_VIRTUAL_ENTER); clockReload.run(EVT_ROT_RIGHT); clockReload.run(EVT_ROT_RIGHT)
clockReload.run(EVT_VIRTUAL_ENTER); clockReload.run(EVT_VIRTUAL_EXIT)
assert(savedLanguage == 'en' and not drawOf('--:--', 2))
io = sdIO
-- Color lifecycle at target resolution, zones and every configured page.
colorDisplay, LCD_W, LCD_H = true, 480, 320
lcd.sizeText = measure
local widget = loadScript('/WIDGETS/APMon/main.lua')()
assert(#widget.options == 2 and widget.options[1][1] == 'Language')
assert(widget.options[1][2] == CHOICE and widget.options[1][3] == 1)
assert(widget.options[1][4][1] == 'English' and widget.options[1][4][2] == 'Deutsch')
assert(widget.options[2][1] == 'Clock' and widget.options[2][2] == BOOL and widget.options[2][3] == 0)
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
local function assertColorClock(time, font)
  local title, shown, logo = assert(drawOf('APMon')), assert(drawOf(time)), assert(bitmaps[1])
  local header = rectangles[2]
  assert(shown.flags & 0xF00 == font)
  assert(shown.x == header.x + math.floor((header.w - shown.w) / 2))
  assert(shown.y == header.y + math.floor((header.h - shown.h) / 2))
  assert(shown.y > header.y and shown.y + shown.h < header.y + header.h)
  assert(title.x + title.w < shown.x and shown.x + shown.w < logo.x)
  local n = 0
  for _, draw in ipairs(draws) do if draw.text == time then n = n + 1 end end
  assert(n == 1)
end
rtc = { hour = 7, min = 5 } -- no date required
getDateTime = function() return rtc end
colorFrame(full)
assert(not drawOf('07:05'))
widget.update(full, { Language = 2, Clock = 1 })
colorFrame(full)
assertColorClock('07:05', DBLSIZE)
assert(drawOf('FLUG').y >= rectangles[2].h)
rtc.min = 60
colorFrame(full)
assertColorClock('--:--', DBLSIZE)
rtc.min = 5
colorFrame(full, EVT_VIRTUAL_ENTER)
local colorClock = assert(drawOf('Uhr: An'))
assert(not drawOf('07:05')) -- dashboard clock does not appear in the menu
colorFrame(full, EVT_TOUCH_TAP, colorClock.x, colorClock.y)
assert(drawOf('> Uhr: Aus') and full.options.Clock == 1)
colorFrame(full, EVT_VIRTUAL_EXIT)
assert(not drawOf('07:05'))
colorFrame(full)
assert(not drawOf('07:05')) -- session override also applies outside full screen
widget.update(full, { Language = 2, Clock = 1 })
colorFrame(full)
assert(drawOf('07:05')) -- reapplying widget settings restores the saved default
widget.update(full, { Language = 2, Clock = 0 })
colorFrame(full, EVT_VIRTUAL_ENTER)
colorFrame(full, EVT_VIRTUAL_NEXT)
colorFrame(full, EVT_VIRTUAL_NEXT)
assert(drawOf('> Uhr: Aus'))
colorFrame(full, EVT_VIRTUAL_ENTER)
assert(drawOf('> Uhr: An') and full.options.Clock == 0)
colorFrame(full, EVT_VIRTUAL_EXIT)
assert(drawOf('07:05'))
local otherClock = widget.create({x=0,y=0,w=480,h=272}, { Clock = 0 })
colorFrame(otherClock)
assert(not drawOf('07:05')) -- the menu changes only this widget
widget.update(full, { Language = 2, Clock = 0 })
getDateTime = nil
local colorTitle = 'APMon'
local function assertColorHeader(x, y, width)
  x, y, width = x or 0, y or 0, width or LCD_W
  local title = assert(drawOf(colorTitle), 'Expected color title was not drawn')
  assert(not drawOf('APMon - ArduPilot Telemetry Monitor'))
  local header, logo = rectangles[2], bitmaps[1]
  assert(header.x == x and header.y == y and header.w == width)
  assert(title.x == x + 12 and title.y == y + 8 and title.y + title.h < y + header.h)
  assert(#bitmaps == 1 and logo.x == x + width - 44 and logo.y == y + math.floor((header.h - 32) / 2))
  assert(logo.y >= y and logo.y + 32 <= y + header.h and title.x + title.w < logo.x)
  return header, logo
end
local function assertColorMenu(language, messages)
  local header, logo = assertColorHeader()
  local subtitle = assert(drawOf('ArduPilot Telemetry Monitor for EdgeTX radios'))
  local repo = assert(drawOf('github.com/christianbaun/APMon-EdgeTX'))
  assert(subtitle.y > header.h and subtitle.y + subtitle.h <= repo.y)
  local version = assert(drawOf('APMon ' .. versionLabel))
  assert(repo.y + repo.h <= version.y or (repo.y == version.y and repo.x + repo.w < version.x))
  assert(drawOf(language) and drawOf(messages))
  return header, logo
end
colorFrame(full, EVT_TOUCH_TAP, 30, 275)
local dashboardHeader, dashboardLogo = assertColorHeader()
assert(drawOf('Flugmodus') and not drawOf('Sprache: Deutsch')) -- tap outside the button
assert(bitmapLoads == 1)
colorFrame(full, EVT_TOUCH_TAP, 460, 275)
local menuHeader, menuLogo = assertColorMenu('> Sprache: Deutsch', 'FC-Meldungen')
assert(dashboardHeader.h == menuHeader.h and dashboardLogo.x == menuLogo.x and dashboardLogo.y == menuLogo.y)
colorFrame(full, EVT_VIRTUAL_ENTER)
assert(drawOf('Sprache') and drawOf('Nur für diese Sitzung'))
assert(bitmapLoads == 1 and #bitmaps == 1)
colorFrame(full, EVT_TOUCH_TAP, 30, 55)
assertColorMenu('> Language: English', 'FC messages')
assert(full.options.Language == 2)
colorFrame(full, EVT_VIRTUAL_NEXT)
assertColorMenu('Language: English', '> FC messages')
colorFrame(full, EVT_VIRTUAL_ENTER)
assert(drawOf('FC messages') and drawOf('No FC messages'))
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
assert(drawOf('Flugmodus') and not drawOf('> Sprache: Deutsch'))
assertColorHeader()
local offset = widget.create({x=8,y=20,w=464,h=280}, { Language = 2 })
colorFrame(offset)
assertColorHeader(8, 20, 464)
getDateTime = function() return rtc end
widget.update(offset, { Language = 2, Clock = 1 })
colorFrame(offset)
assertColorClock('07:05', DBLSIZE)
getDateTime = nil
widget.update(full, { Language = 2 })
colorFrame(full, EVT_VIRTUAL_ENTER)
assertColorMenu('> Sprache: Deutsch', 'FC-Meldungen')
local back = assert(drawOf('Zurück'))
colorFrame(full, EVT_TOUCH_TAP, back.x, back.y)
assert(drawOf('Flugmodus'))
-- Small normal zones still show the dashboard warning; full screen uses LCD dimensions.
LCD_W, LCD_H = 440, 252
local smallZone = widget.create({x=10,y=10,w=90,h=50}, { Language = 0 })
colorFrame(smallZone)
assert(not drawOf(colorTitle) and #bitmaps == 0)
colorFrame(smallZone, 0)
assert(drawOf(colorTitle).flags & 0xF00 == MIDSIZE)
assertColorHeader()
local compactClock = widget.create({x=0,y=0,w=440,h=252}, {Clock=1})
getDateTime = function() return rtc end
colorFrame(compactClock)
assertColorClock('07:05', MIDSIZE)
getDateTime = nil
colorFrame(smallZone, 0)
local lastRow = assert(drawOf('Last EKF set'))
assert(lastRow.flags & 0xF00 == TINSIZE and lastRow.y + lastRow.h < assert(drawOf('FC message: --')).y)
getSourceValue = nil
local noFC = widget.create({x=0,y=0,w=440,h=252}, {})
colorFrame(noFC)
local warning = assert(drawOf('Missing getSourceValue API'))
assert(warning.y > rectangles[2].h and warning.y + warning.h < assert(drawOf('FC message: --')).y)
getSourceValue = saved
colorFrame(smallZone, EVT_VIRTUAL_ENTER)
assertColorMenu('> Language: English', 'FC messages')
assert(drawOf('Clock: Off') and drawOf('Last armed period')) -- primary options fit the minimum full screen
colorFrame(smallZone, EVT_VIRTUAL_PREV)
assert(drawOf('> Back')) -- Back is reachable when the menu scrolls
assert(drawOf('APMon').flags & 0xF00 == MIDSIZE)
assert(bitmapLoads == 1) -- menu refreshes and widget instances share the bitmap
-- Same menu on the TX16S MK3: large glyphs fit; touch follows moved rows.
LCD_W, LCD_H = 800, 480
local mk3 = widget.create({x=0,y=0,w=800,h=440}, { Language = 1, Clock = 1 })
colorFrame(mk3, 0)
assertColorClock('--:--', DBLSIZE)
local mk3DashboardHeader, mk3DashboardLogo = assertColorHeader()
colorFrame(mk3, EVT_VIRTUAL_ENTER)
local mk3MenuHeader, mk3MenuLogo = assertColorMenu('> Language: English', 'FC messages')
assert(mk3DashboardHeader.h == mk3MenuHeader.h and mk3DashboardLogo.y == mk3MenuLogo.y)
assert(rectangles[2].h > 38 and drawOf('APMon').flags & 0xF00 == MIDSIZE)
local messages = assert(drawOf('FC messages'))
colorFrame(mk3, EVT_TOUCH_TAP, messages.x + 1, messages.y + 1)
local messageTitle = assert(drawOf('FC messages', 8))
assert(messageTitle.y + messageTitle.h < rectangles[2].h)
colorFrame(mk3, EVT_VIRTUAL_EXIT)
local language = assert(drawOf('Language: English'))
colorFrame(mk3, EVT_TOUCH_TAP, language.x + 1, language.y + 1)
local german = assert(drawOf('Deutsch'))
colorFrame(mk3, EVT_TOUCH_TAP, german.x + 1, german.y + 1)
assertColorMenu('> Sprache: Deutsch', 'FC-Meldungen')
LCD_W, LCD_H = 480, 320
-- An unavailable bitmap must not interfere with the menu.
local openBitmap, failedLoads = Bitmap.open, 0
Bitmap.open = function() failedLoads = failedLoads + 1 end
local logoMissing = loadScript('/WIDGETS/APMon/main.lua')()
local withoutLogo = logoMissing.create({x=0,y=0,w=480,h=272}, {})
bitmaps, calls = {}, {}
logoMissing.refresh(withoutLogo, EVT_VIRTUAL_ENTER)
assert(drawOf('APMon'))
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
local function message(value, severity)
  local p = {0xF1, severity or 6}
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
assert(select(3, pass.browse()) == 0)
for _, limit in ipairs({12, 32}) do
  local history = loadScript('/SCRIPTS/APMON/pass.lua')(limit)
  local function add(value, severity, time)
    history.decode(0x80, message(value, severity), time or now)
  end
  for n = 1, limit + 2 do add('Message ' .. n) end
  local oldest, index, count = history.browse(nil, limit)
  assert(index == limit and count == limit and oldest.value == 'Message 3')
  local latest = history.browse()
  add(latest.value, 6, now + 100)
  assert(history.browse() == latest and latest.repeats == 2 and latest.time == now + 100)
  add(latest.value, 4)
  assert(history.message.severity == 4 and history.message.repeats == 1)
  assert(history.browse(latest) == latest and select(2, history.browse(latest)) == 2)
  add('Another')
  assert(history.browse(latest) == latest and select(2, history.browse(latest)) == 3)
  assert(history.browse(oldest).value == 'Message 5') -- evicted selection clamps
  add(latest.value, 6)
  assert(history.message ~= latest and history.message.repeats == 1) -- not adjacent
end
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
assert(drawOf('FC messages', 8) and drawOf('> Using EKF Source Set 3'))
incoming = {message('New FC warning', 4), message('New FC warning', 4)}
now = now + 100
calls, draws, rectangles = {}, {}, {}
liveWidget.refresh(live, 0)
assert(drawOf('1/2') and drawOf('> New FC warning') and drawOf('S4 x2 0s'))
assert(drawOf('Using EKF Source Set 3').y > drawOf('> New FC warning').y)
local older = assert(drawOf('Older'))
calls, draws, rectangles = {}, {}, {}
liveWidget.refresh(live, EVT_TOUCH_TAP, {x=older.x,y=older.y})
assert(drawOf('2/2') and drawOf('> Using EKF Source Set 3') and drawOf('S6 1s'))
incoming = {message('Newest FC text')}
now = now + 100
calls, draws, rectangles = {}, {}, {}
liveWidget.refresh(live, 0)
assert(drawOf('3/3') and drawOf('> Using EKF Source Set 3')) -- selection does not jump
calls, draws, rectangles = {}, {}, {}
liveWidget.refresh(live, EVT_VIRTUAL_PREV)
local warningRow = assert(drawOf('> New FC warning'))
calls, draws, rectangles = {}, {}, {}
liveWidget.refresh(live, EVT_TOUCH_TAP, {x=warningRow.x,y=warningRow.y})
assert(drawOf('Severity 4  |  1s ago  |  x2') and drawOf('New FC warning'))
assert(not drawOf('Newest FC text'))
calls, draws, rectangles = {}, {}, {}
liveWidget.refresh(live, EVT_VIRTUAL_EXIT)
assert(drawOf('> New FC warning') and drawOf('Newest FC text'))
incoming = {}
for i = 1, 10 do incoming[i] = message('Extra ' .. i) end
now = now + 100
for i = 1, 11 do
  calls, draws, rectangles = {}, {}, {}
  liveWidget.refresh(live, EVT_VIRTUAL_PREV)
end
assert(drawOf('1/13') and drawOf('> Extra 10') and not drawOf('Using EKF Source Set 3'))
for i = 1, 12 do
  calls, draws, rectangles = {}, {}, {}
  liveWidget.refresh(live, EVT_VIRTUAL_NEXT)
end
assert(drawOf('13/13') and drawOf('> Using EKF Source Set 3') and not drawOf('Extra 10'))
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
small.run(EVT_VIRTUAL_ENTER)
assert(string.find(table.concat(calls,'|'),'Using EKF Source Set 2',1,true))
assertMonoLogo()
small.run(EVT_VIRTUAL_EXIT)
incoming = {message('A warning that wraps onto more than one line', 4),
  message('A warning that wraps onto more than one line', 4)}
now = now + 100
small.background()
small.run(0)
small.run(EVT_ROT_LEFT) -- focus the newest entry
assert(drawOf('1/2', 57) and drawOf('ENT: details', 57))
assert(string.find(table.concat(calls,'|'),'S4 A warning',1,true))
assert(string.find(table.concat(calls,'|'),'S6 Using EKF',1,true))
small.run(EVT_VIRTUAL_ENTER)
assert(drawOf('S4 x2 0s', 11) and drawOf('RTN: list', 57))
assert(draws[4].y == 29) -- second line of the wrapped message
small.run(EVT_VIRTUAL_EXIT)
small.run(EVT_ROT_RIGHT)
assert(drawOf('2/2', 57))
small.run(EVT_VIRTUAL_ENTER)
assert(drawOf('S6 1s', 11) and drawOf('Using EKF Source Set 2'))
small.run(EVT_VIRTUAL_EXIT)
small.run(EVT_ROT_LEFT)
assert(drawOf('1/2', 57))
incoming = {}
for i = 1, 6 do incoming[i] = message('Extra ' .. i) end
now = now + 100
small.run(0)
assert(drawOf('S6 Extra 6', 10) and not drawOf('S6 Extra 1'))
for i = 1, 5 do small.run(EVT_ROT_RIGHT) end
assert(drawOf('S6 Extra 1', 46) and drawOf('6/8', 57) and not drawOf('S6 Extra 6'))
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
restrictedMono.run(EVT_VIRTUAL_ENTER)
assert(string.find(table.concat(calls,'|'),'Using EKF Source Set 1',1,true))

-- Shared diagnostics: an invalid alias must not hide a valid fallback. A cached
-- value is shown only for its own sensor name and never becomes a live reading.
local aliases = core.new({sensors = {voltage = {names = {'A', 'B'}, unit = 'V', min = 0.1}}})
data = {A = {value = 0}, B = {value = 14}}
aliases:sample(true)
local a = aliases.sensorList[1]
assert(a.name == 'B' and a.state == 'valid' and aliases:formatSensor(a) == '14 V')
data.A, data.B.current = nil, false
aliases:sample(true)
assert(a.name == 'B' and a.state == 'stale' and aliases:formatSensor(a) == '14 V')
assert(aliases.values.voltage == nil)
data.A = {value = 0}
aliases:sample(true)
assert(a.name == 'A' and a.state == 'invalid' and aliases:formatSensor(a) == '--')
local originalSource = getSourceValue
getSourceValue = function() return 15 end -- older API does not supply a current flag
aliases:sample(true)
assert(a.name == 'A' and a.state == 'unknown' and aliases.values.voltage == nil)
getSourceValue = originalSource
data.A, data.B = nil, nil
aliases:sample(true)
assert(a.name == 'B' and a.state == 'missing' and aliases:formatSensor(a) == '14 V')

-- Exercise both displays against real decoder/sampler logic, not mock summaries.
data = {
  Alt = {value = 7.5}, GPS = {value = {lat = 49.1, lon = 8.1}},
  RQly = {value = 98}, Curr = {value = 0},
}
incoming = {single(0x5001, 0), message('Sensoren')}
now = now + 20
restricted.crossfireTelemetryPop = nil
local monoDiag = restricted.loadScript('/SCRIPTS/TELEMETRY/APMon.lua')()
monoDiag.run(EVT_VIRTUAL_ENTER); monoDiag.run(EVT_ROT_LEFT); monoDiag.run(EVT_ROT_LEFT)
assert(drawOf('Telemetry diagnostics', 57).flags & INVERS ~= 0)
monoDiag.run(EVT_VIRTUAL_ENTER)
assert(drawOf('Telemetry diagnostics', 1) and drawOf('98 %', 11) and drawOf('4/16 valid', 19))
assert(drawOf('Valid 0s', 27) and drawOf('Not found: VSpd', 43))
monoDiag.run(EVT_VIRTUAL_ENTER)
assert(drawOf('Sensors', 1) and drawOf('Alt', 11) and drawOf('7.5 m', 43))
data.Alt.current = false
now = now + 20
monoDiag.run(0)
assert(drawOf('Stale', 21) and drawOf('Last value:', 33) and drawOf('7.5 m', 43))
for i = 1, 3 do monoDiag.run(EVT_ROT_RIGHT) end
assert(drawOf('GPS', 11) and drawOf('Lat 49.100000', 41) and drawOf('Lon 8.100000', 49))
incoming = {single(0x5002, 48), message('Fresh FC text')}
now = now + 500
monoDiag.run(EVT_VIRTUAL_EXIT)
assert(drawOf('Stale 5s', 27) and drawOf('0s ago', 35)) -- GPS/text are not an AP_STATUS heartbeat
monoDiag.run(EVT_VIRTUAL_EXIT)
assert(drawOf('Telemetry diagnostics', 57) and drawOf('Clock: Off', 49))
getGeneralSettings = function() return { language = 'EN' } end
io = {open = function(path)
  if path == '/SCRIPTS/APMON/mono.cfg' then return {} end
  return sdIO.open(path, 'r')
end, close = function(f) if type(f) == 'userdata' then sdIO.close(f) end end,
read = function(f, n) return type(f) == 'userdata' and sdIO.read(f, n) or 'de' end}
local monoDE = loadScript('/SCRIPTS/TELEMETRY/APMon.lua')()
crossfireTelemetryPop = nil
monoDE.run(EVT_VIRTUAL_ENTER); monoDE.run(EVT_ROT_LEFT); monoDE.run(EVT_ROT_LEFT); monoDE.run(EVT_VIRTUAL_ENTER)
assert(drawOf('Telemetrie-Diagnose', 1) and drawOf('3/16 gueltig', 19) and drawOf('API fehlt', 27))
assert(drawOf('RTN: Menue', 57))
getGeneralSettings, io = nil, sdIO

local diagWidget = loadScript('/WIDGETS/APMon/main.lua')()
local function diagFrame(w, event, x, y)
  calls, draws, rectangles, bitmaps = {}, {}, {}, {}
  diagWidget.refresh(w, event, x and {x=x,y=y})
end
local function diagTap(w, label)
  for i = #draws, 1, -1 do
    local d = draws[i]
    if d.text == label then diagFrame(w, EVT_TOUCH_TAP, d.x, d.y); return end
  end
  error('Missing button: ' .. label)
end
colorDisplay, LCD_W, LCD_H, lcd.sizeText = true, 480, 320, measure
local z = {x=0,y=0,w=480,h=272}
incoming = {single(0x5001, 0), message('Sensoren')}
crossfireTelemetryPop = function()
  local p = table.remove(incoming, 1)
  if p then return 0x80, p end
end
local diagColor = diagWidget.create(z, {Language = 1})
data.Alt.current = true
diagFrame(diagColor, EVT_VIRTUAL_ENTER)
data.Alt.current = false
now = now + 20
diagTap(diagColor, 'Telemetry diagnostics')
assert(drawOf('Telemetry diagnostics', 8) and drawOf('98 %') and drawOf('3/16 valid'))
assert(drawOf('Valid') and drawOf('Sensoren')) -- incoming text stays unchanged
diagTap(diagColor, 'Sensors')
assert(drawOf('Sensors', 8) and drawOf('Alt') and drawOf('7.5 m'))
assert(drawOf('Stale') and drawOf('Not found'))
local oldRange = assert(drawOf('1–6 / 16'))
diagTap(diagColor, 'Next')
assert(not drawOf(oldRange.text) and drawOf('Previous'))
diagTap(diagColor, 'Back')
assert(drawOf('Telemetry diagnostics', 8))
now = now + 301
diagFrame(diagColor, 0)
assert(drawOf('Stale') and drawOf('3s ago'))
diagFrame(diagColor, EVT_VIRTUAL_EXIT)
assert(drawOf('> Telemetry diagnostics'))
getSourceValue = nil
for _, dims in ipairs({{440,252}, {800,480}}) do
  LCD_W, LCD_H = dims[1], dims[2]
  local germanDiag = diagWidget.create(z, {Language = 2})
  diagFrame(germanDiag, EVT_VIRTUAL_ENTER)
  for i = 1, 3 do diagFrame(germanDiag, EVT_VIRTUAL_NEXT) end
  diagFrame(germanDiag, EVT_VIRTUAL_ENTER)
  assert(drawOf('Telemetrie-Diagnose', 8) and drawOf('API fehlt') and drawOf('Veraltet'))
  diagTap(germanDiag, 'Sensoren')
  assert(drawOf('Sensoren', 8) and drawOf('Letzter Wert') and drawOf('API fehlt'), table.concat(calls, ' | '))
  diagFrame(germanDiag, EVT_VIRTUAL_EXIT)
  diagTap(germanDiag, 'Zurück')
  assert(drawOf('> Telemetrie-Diagnose'))
end
getSourceValue = originalSource

-- Armed summaries use confirmed status edges, only fresh measurements, and a
-- verified relative-altitude source. Neither an RC switch nor stale values count.
local armedSummary = loadScript('/SCRIPTS/APMON/armed_summary.lua')()
local summaryTracker = armedSummary.new('GAlt')
local function observe(tracker, value, tick) tracker:observe(value, tick, 300) end
local readings = {voltage = 15.8, current = 2, used = 100, altitude = 430, gpsaltitude = -2}
local sources = {
  voltage={name='RxBt', fresh=true}, current={name='Curr', fresh=true},
  used={name='Capa', fresh=true}, altitude={name='Alt', fresh=true}, gpsaltitude={name='GAlt', fresh=true},
}
observe(summaryTracker, 0, 0)
observe(summaryTracker, 1, 100)
summaryTracker:sample(100, 1, readings, sources)
readings.voltage, readings.current, readings.used, readings.gpsaltitude = 14.5, 22, 120, -1
summaryTracker:sample(100, 1, readings, sources) -- duplicate widget callback; not another sample
assert(summaryTracker.active.voltage == 15.8)
observe(summaryTracker, 1, 200)
summaryTracker:sample(200, 1, readings, sources)
readings.voltage, readings.current, readings.used, readings.gpsaltitude = 1, 99, 140, 99
for _, source in pairs(sources) do source.fresh = false end
summaryTracker:sample(250, 1, readings, sources) -- still current, but held in EdgeTX
observe(summaryTracker, 0, 300)
local phase = assert(summaryTracker.last)
assert(phase.duration == 2 and phase.voltage == 14.5 and phase.current == 22 and phase.used == 20)
assert(phase.altitude == -1 and not phase.partial)
observe(summaryTracker, 1, 320)
assert(summaryTracker.last == phase) -- previous summary stays available during the next run
summaryTracker:reset()
observe(summaryTracker, 1, 400)
summaryTracker:sample(400, 1, readings, sources)
observe(summaryTracker, 0, 500)
assert(summaryTracker.last.partial and summaryTracker.last.duration == nil and summaryTracker.last.started == nil)
for _, source in pairs(sources) do source.fresh = true end
summaryTracker:reset()
observe(summaryTracker, 0, 500)
observe(summaryTracker, 1, 600)
summaryTracker:sample(600, 1, readings, sources)
summaryTracker:sample(901, nil, readings, sources)
assert(summaryTracker.active.statusGap and not summaryTracker.last)
observe(summaryTracker, 0, 1000)
assert(summaryTracker.last.partial and summaryTracker.last.duration == nil and summaryTracker.last.used == nil)
summaryTracker:reset()
observe(summaryTracker, 0, 0)
observe(summaryTracker, 1, 500) -- disarmed baseline was already stale when armed first arrived
observe(summaryTracker, 0, 600)
assert(summaryTracker.last.partial and not summaryTracker.last.duration)
summaryTracker:reset()
observe(summaryTracker, 0, 0)
observe(summaryTracker, 1, 100)
summaryTracker:sample(100, 1, readings, sources)
readings.used = 0
summaryTracker:sample(200, 1, readings, sources)
observe(summaryTracker, 0, 300)
assert(summaryTracker.last.counterProblem and not summaryTracker.last.used and summaryTracker.last.duration == 2)
summaryTracker:reset()
observe(summaryTracker, 0, 0)
observe(summaryTracker, 1, 100)
summaryTracker:sample(100, 1, readings, sources)
observe(summaryTracker, 0, 200)
assert(summaryTracker.last.duration == 1 and not summaryTracker.last.used) -- no end sample

-- Sweep a real disarm sequence through the SW and COLOR entry points.
local function reportStatus(value)
  now = now + 100
  incoming = {single(0x5001, value == 1 and 256 or 0)}
end
local function prepareFlight()
  data = {RxBt={value=15.8}, Curr={value=2}, Capa={value=0}, GAlt={value=25}}
end
local function changeFlight()
  data.RxBt.value, data.Curr.value, data.Capa.value = 14.5, 22, 20
end
prepareFlight()
colorDisplay, LCD_W, LCD_H, lcd.sizeText = false, 128, 64, nil
local summarySW = restricted.loadScript('/SCRIPTS/TELEMETRY/APMon.lua')()
summarySW.run(EVT_VIRTUAL_ENTER); summarySW.run(EVT_ROT_LEFT); summarySW.run(EVT_VIRTUAL_ENTER)
assert(drawOf('Last armed period', 1) and drawOf('No summary yet'))
summarySW.run(EVT_VIRTUAL_EXIT); summarySW.run(EVT_VIRTUAL_EXIT)
reportStatus(0); summarySW.background()
reportStatus(1); summarySW.background()
changeFlight(); reportStatus(1); summarySW.background()
reportStatus(0); summarySW.run(0)
assert(drawOf('APMon Overview', 2) and drawOf('DISARMED', 27)) -- never opens the menu automatically
summarySW.run(EVT_VIRTUAL_ENTER); summarySW.run(EVT_ROT_LEFT); summarySW.run(EVT_VIRTUAL_ENTER)
assert(drawOf('Last armed period') and drawOf('Time armed', 10) and drawOf('00:02', 10))
assert(drawOf('14.50 V', 18) and drawOf('22.0 A', 26) and drawOf('--', 34) and drawOf('20 mAh', 42))
assert(drawOf('Complete', 50)) -- height is optional and unverified GAlt is not shown
summarySW.run(EVT_VIRTUAL_ENTER)
assert(drawOf('Summary details') and drawOf('No rel. altitude source'))
summarySW.run(EVT_VIRTUAL_EXIT); summarySW.run(EVT_VIRTUAL_EXIT)
summarySW.run(EVT_ROT_RIGHT); summarySW.run(EVT_VIRTUAL_ENTER)
summarySW.run(EVT_ROT_RIGHT); summarySW.run(EVT_VIRTUAL_ENTER) -- select German
summarySW.run(EVT_ROT_LEFT); summarySW.run(EVT_VIRTUAL_ENTER)
assert(drawOf('Letzte Armed-Phase') and drawOf('Armed-Zeit', 10) and drawOf('Vollständig', 50))

for _, spec in ipairs({{440,252,1}, {480,320,2}, {800,480,2}}) do
  colorDisplay, LCD_W, LCD_H, lcd.sizeText = true, spec[1], spec[2], measure
  local summaryWidget = loadScript('/WIDGETS/APMon/main.lua')()
  local w = summaryWidget.create({x=0,y=0,w=LCD_W,h=LCD_H}, {Language=spec[3]})
  local other = summaryWidget.create({x=0,y=0,w=LCD_W,h=LCD_H}, {Language=spec[3]})
  local function frame(event, touch)
    calls, draws, rectangles, bitmaps = {}, {}, {}, {}
    summaryWidget.refresh(w, event, touch)
  end
  prepareFlight()
  if spec[3] == 1 then reportStatus(0); summaryWidget.background(w) end
  reportStatus(1); summaryWidget.background(other)
  changeFlight(); reportStatus(1); summaryWidget.background(w)
  reportStatus(0); frame(0)
  assert(drawOf('APMon', 8) and drawOf('DISARMED'))
  frame(EVT_VIRTUAL_ENTER)
  local title = spec[3] == 1 and 'Last armed period' or 'Letzte Armed-Phase'
  local option = assert(drawOf(title))
  frame(EVT_TOUCH_TAP, {x=option.x,y=option.y})
  assert(drawOf(title, 8) and drawOf('14.50 V') and drawOf('22.0 A'))
  if spec[3] == 1 then
    assert(drawOf('Complete') and drawOf('00:02') and drawOf('20 mAh'))
  else
    assert(drawOf('Unvollständig') and drawOf('Armed-Zeit') and not drawOf('00:02'))
  end
  local details = assert(drawOf('Details'))
  frame(EVT_TOUCH_TAP, {x=details.x,y=details.y})
  assert(drawOf(spec[3] == 1 and 'Summary details' or 'Bilanzdetails', 8))
  if spec[3] == 2 then assert(drawOf('Start nicht erfasst')) end
  frame(EVT_VIRTUAL_EXIT)
  assert(drawOf(title, 8))
  frame(EVT_VIRTUAL_EXIT)
  assert(drawOf('> ' .. title))
end
-- SW must reach the dashboard without loading either optional view module.
-- If the allocator rejects a tool, RTN still returns and a later attempt can succeed.
colorDisplay, LCD_W, LCD_H, lcd.sizeText = false, 128, 64, nil
local attempted, blockTools = {}, true
local lowMemory = setmetatable({}, {__index = restricted})
lowMemory.loadScript = function(path)
  local name = string.match(path, '/([^/]+)%.lua$')
  attempted[name] = (attempted[name] or 0) + 1
  if name == 'mono_tools' and blockTools then return nil, 'not enough memory' end
  return assert(loadfile(root .. path, 't', lowMemory))
end
local lowSW = lowMemory.loadScript('/SCRIPTS/TELEMETRY/APMon.lua')()
lowSW.run(0)
assert(drawOf('APMon Overview', 2) and not attempted.diagnostics and not attempted.mono_tools)
lowSW.run(EVT_VIRTUAL_ENTER); lowSW.run(EVT_ROT_LEFT); lowSW.run(EVT_VIRTUAL_ENTER)
assert(drawOf('Not enough memory') and attempted.mono_tools == 1 and not attempted.diagnostics)
lowSW.run(0)
assert(attempted.mono_tools == 1) -- do not retry every frame
lowSW.run(EVT_VIRTUAL_EXIT)
assert(drawOf('Last armed period', 57))
blockTools = false
lowSW.run(EVT_VIRTUAL_ENTER)
assert(drawOf('No summary yet') and attempted.mono_tools == 2)
lowSW.run(EVT_VIRTUAL_EXIT); lowSW.run(EVT_ROT_LEFT); lowSW.run(EVT_VIRTUAL_ENTER)
assert(drawOf('Telemetry diagnostics', 1) and attempted.mono_tools == 3 and attempted.diagnostics == 1)
print('OK: sensor validity, stale data, read-only, layouts, bilingual menus, diagnostics, passthrough, restricted mono Lua')
