-- SPDX-License-Identifier: Apache-2.0
-- Scripted APMon replay using the real Lua entry points and a host EdgeTX API subset.
local profile, lang = assert(os.getenv('APMON_PROFILE')), assert(os.getenv('APMON_LANG'))
local display, w, h = string.match(profile, '^(%a+)%-(%d+)x(%d+)$')
local color, de = display == 'color', lang == 'de'
LCD_W, LCD_H = tonumber(w), tonumber(h)
local clock, data, fifo, used, ops, draws = 100, {}, {}, 0, {}, {}
local sd, reportPath = {}, '/APMon-report.txt'
local hostIO = io
debug.setmetatable('', nil)
local function localize(en, german) return de and german or en end
local function op(...)
  local args = {...}
  for i, v in ipairs(args) do args[i] = string.gsub(tostring(v), '[\t\r\n]', ' ') end
  ops[#ops + 1] = table.concat(args, '\t')
end
local function measure(text, flags)
  local font = flags & 0xF00
  local _, n = string.gsub(text, '[^\128-\191]', '')
  if color then
    if font == 0x100 then return n * 6, 12 end
    if LCD_W >= 800 then
      if font == 0x400 then return n * 23, 48 end
      if font == 0x300 then return n * 16, 36 end
      return n * 10, 24
    end
    if font == 0x400 then return n * 17, 32 end
    if font == 0x300 then return n * 11, 22 end
    return n * 8, 16
  end
  if font == 0x200 then
    local _, wide = string.gsub(text, '[#$+MWmw]', '')
    local _, spaces = string.gsub(text, ' ', '')
    local _, narrow = string.gsub(text, "[.!':|]", '')
    return n * 5 + wide - spaces * 2 - narrow * 3, 7
  end
  if font == 0x300 then return n * 9, 12 end
  if font == 0x400 then return n * 11, 16 end
  return n * 6, 8
end

SMLSIZE, MIDSIZE, DBLSIZE, TINSIZE = 0x200, 0x300, 0x400, 0x100
INVERS, RIGHT, FORCE, ERASE, CUSTOM_COLOR = 2, 4, 2, 4, 0x10000
VALUE, BOOL, CHOICE = 0, 2, 3
EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_EXIT = 10, 11, 12, 13
EVT_TOUCH_TAP = 16
local ink = 0xFFFFFF
lcd = {
  clear = function() end,
  RGB = function(r, g, b) return r * 65536 + g * 256 + b end,
  setColor = function(_, v) ink = v end,
  sizeText = color and function(value, flags) return measure(value, flags or 0) end or nil,
  drawText = function(x, y, value, flags)
    flags = flags or 0
    local width, height = measure(value, flags)
    if not color and flags & RIGHT ~= 0 then x = x - width end
    assert(x >= 0 and y >= 0 and x + width <= LCD_W and y + height <= LCD_H,
      'text outside display: ' .. value)
    draws[value] = {x=x, y=y, flags=flags, h=height}
    op('text', x, y, width, height, color and ink or flags & INVERS ~= 0 and 0 or 0xFFFFFF,
      not color and flags & INVERS ~= 0 and 1 or 0, value)
  end,
  drawFilledRectangle = function(x, y, width, height, flags)
    assert(x >= 0 and y >= 0 and x + width <= LCD_W and y + height <= LCD_H, 'rectangle outside display')
    op('rect', x, y, width, height, color and ink or flags == ERASE and 0 or 0xFFFFFF)
  end,
  drawLine = function(x1, y1, x2, y2, _, flags)
    assert(x1 >= 0 and x1 < LCD_W and x2 >= 0 and x2 < LCD_W
      and y1 >= 0 and y1 < LCD_H and y2 >= 0 and y2 < LCD_H, 'line outside display')
    op('line', x1, y1, x2, y2, color and ink or flags == ERASE and 0 or 0xFFFFFF)
  end,
  drawBitmap = function(_, x, y) op('logo', x, y) end,
}
Bitmap = {open = function(path) return assert(path == '/WIDGETS/APMon/logo.png') end}
getTime = function() return clock end
getDateTime = function() return {year=2026,mon=11,day=23,hour=12,min=34,sec=56} end
getVersion = function() return '2.12.5', 'host-simulator' end
getGeneralSettings = function() return {language='DE'} end
getFieldInfo = function(name) if data[name] then return {id=name} end end
getSourceValue = function(name)
  local sensor = data[name]
  return sensor[1], sensor.current ~= false, sensor.fresh ~= false
end
crossfireTelemetryPop = function()
  used = used + 1
  if fifo[used] then return 0x80, fifo[used] end
end
crossfireTelemetryPush = function() error('APMon must not transmit') end
sportTelemetryPush = crossfireTelemetryPush
local function noModelAccess() error('APMon must not mutate or access other model settings') end
model = setmetatable({getInfo=function() return {filename='model01.yml'} end},
  {__index=noModelAccess, __newindex=noModelAccess})
loadScript = function(path) return loadfile('SD' .. path) end
local profilePath = '/SCRIPTS/APMON/fc-model01.yml.cfg'
io = {
  open = function(path, mode)
    if path == '/SCRIPTS/APMON/VERSION' and mode == 'r' then return assert(hostIO.open('VERSION', 'r')) end
    if path == '/SCRIPTS/APMON/mono.cfg' and mode == 'r' then return {content=lang .. '\n1'} end
    if path == profilePath then
      if mode == 'r' then return sd[path] and {content=sd[path]} end
      return {content='', key=path}
    end
    assert(path == reportPath and mode == 'w', 'unexpected SD write: ' .. path)
    return {content=''}
  end,
  read = function(f, n) return type(f) == 'table' and f.content or f:read(n) end,
  write = function(f, text) f.content = f.content .. text; return f end,
  close = function(f)
    if type(f) ~= 'table' then return f:close() end
    if f.key then sd[f.key] = f.content end
    if string.match(f.content, '^APMon ') then sd[reportPath] = f.content end
  end,
}
fstat = function(path) if sd[path] then return {size=#sd[path]} end end

local app = assert(loadScript(color and '/WIDGETS/APMon/main.lua' or '/SCRIPTS/TELEMETRY/APMon.lua'))()
local widget = color and app.create({x=0,y=0,w=LCD_W,h=LCD_H}, {Language=de and 2 or 1, Clock=1})
local enter, exit, nextEvent, prev = EVT_VIRTUAL_ENTER, EVT_VIRTUAL_EXIT, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV
local touch, input, count = nil, '', 0
local function render(event, point)
  ops, draws, touch = {}, {}, nil
  local names = {[0]='', [enter]='ENTER', [exit]='RTN', [nextEvent]='NEXT', [prev]='PREV',
    [EVT_TOUCH_TAP]=localize('Touch', 'Touch')}
  input = names[event]
  if color then app.refresh(widget, event, point) else assert(app.run(event) == 0) end
end
local function has(en, german)
  return draws[localize(en, german)] or draws['> ' .. localize(en, german)]
end
local function expect(en, german)
  assert(has(en, german or en), 'expected ' .. localize(en, german or en) .. ' on screen')
end
local function frame(en, german, ms)
  count = count + 1
  for _, row in ipairs(ops) do hostIO.write(row, '\n') end
  hostIO.write('frame\t', ms or 1250, '\t', input, '\t', localize(en, german), '\n')
  if touch then hostIO.write('touch\t', touch.x, '\t', touch.y, '\n') end
end
local function tap(en, german)
  local p = assert(has(en, german), 'missing button ' .. en)
  touch, input = p, 'Touch'
  frame('Tap ' .. en, german .. ' antippen', 800)
  render(EVT_TOUCH_TAP, p)
end
local function packet(id, value)
  return {0xF0, id % 256, math.floor(id / 256), value % 256,
    math.floor(value / 256) % 256, 0, 0}
end
local function message(text, severity)
  local p = {0xF1, severity}
  for i = 1, #text do p[#p + 1] = string.byte(text, i) end
  return p
end
local function tick(delta, ...)
  clock, fifo, used = clock + delta, {...}, 0
  render(0)
end
local function openMenu()
  render(enter)
  expect('APMon')
end
local function choose(n, en, german)
  if color and has(en, german) then tap(en, german)
  else
    for _ = 2, n do render(nextEvent) end
    expect(en, german)
    frame('Select ' .. en, german .. ' auswählen', 1000)
    render(enter)
  end
end

data = {RxBt={16.1}, Curr={1}, ['Bat%']={94}, Capa={100}, Alt={24.6}, GAlt={25},
  GSpd={29}, VSpd={2.2}, Sats={12}, Hdg={274}, FM={'LOIT'}, RQly={96},
  GPS={{lat=0.123456,lon=-0.654321}}, Yaw={-0.4}, Roll={math.pi / 6}, Ptch={math.pi / 18}}
tick(20, packet(0x5001,0), packet(0x5002,48), message('Using EKF Source Set 2',6))
expect(color and 'APMon' or 'APMon Overview', color and 'APMon' or 'APMon Übersicht')
frame('Overview and live telemetry', 'Übersicht und Live-Telemetrie')
if not color then
  render(nextEvent)
  expect('APMon Flight','APMon Flugwerte')
  frame('Second telemetry page', 'Zweite Telemetrieseite')
else
  expect('Wheel: HUD','Rad: HUD')
  expect('1/2')
end
render(nextEvent)
expect('HUD')
expect(color and '2/2' or '3/3')
expect('12:34')
expect(color and '16.10 V' or '16.10V')
expect(color and '1.00 A' or '1.00A')
expect('96 %')
expect('2/0s')
if color then expect('3D'); expect('12') else expect('3D/12') end
expect(color and 'Roll: 30.0°' or '30°')
expect(color and 'Pitch: 10.0°' or '10°')
if not color then
  expect('Bat')
  expect('GPS:')
  assert(draws.Bat.x == 2 and draws['16.10V'].y == 40 and draws['1.00A'].y == 40 and draws['96 %'].y == 40)
  assert(draws['3D/12'].y == 49 and draws['2/0s'].y == 49)
else
  local voltage = draws['16.10 V']
  local font = voltage.flags & 0xF00
  if LCD_W >= 480 then assert(font == MIDSIZE or font == DBLSIZE, 'HUD readings should have a larger font') end
  for _, value in ipairs({'1.00 A', '96 %', '3D', '12', '2/0s'}) do
    assert(draws[value].flags & 0xF00 == font, 'HUD readings should use a consistent font')
  end
  assert(voltage.y + voltage.h <= assert(has('Curr.', 'Strom')).y, 'HUD value overlaps next caption')
end
frame('HUD with fresh roll and pitch', 'HUD mit frischen Roll- und Nickdaten')
data.Ptch.fresh = false
tick(20, packet(0x5001,0))
expect(color and 'Pitch: 10.0°' or '10°')
assert(not has('No attitude data','Lagedaten fehlen'))
data.Roll.fresh, data.Ptch.fresh = false, true
tick(20, packet(0x5001,0))
expect(color and 'Roll: 30.0°' or '30°')
assert(not has('No attitude data','Lagedaten fehlen'))
frame('Alternating updates keep the horizon visible', 'Versetzte Updates lassen den Horizont sichtbar')
local function plot()
  local segments = {}
  for _, value in ipairs(ops) do
    if string.sub(value, 1, 5) == 'line\t' then segments[#segments + 1] = value end
  end
  return table.concat(segments, '\n')
end
local previousPlot = plot()
data.Ptch.fresh, data.Roll.fresh, data.Roll[1], data.RxBt[1] = false, true, 0, 15.9
tick(110, packet(0x5001,0))
expect('HOLD')
expect(color and 'Roll: 30.0°' or '30°')
expect(color and 'Pitch: 10.0°' or '10°')
expect(color and '15.90 V' or '15.90V')
assert(plot() == previousPlot, 'the drawn attitude changed during HOLD')
assert(not has('No attitude data','Lagedaten fehlen'))
frame('HOLD keeps the last horizon during a dropout', 'HOLD hält den letzten Horizont bei einem Ausfall fest')
data.Roll.fresh, data.Ptch.fresh = true, true
data.RxBt[1] = 16.1
tick(20, packet(0x5001,0))
expect(color and 'Pitch: 10.0°' or '10°')
assert(not has('HOLD') and plot() ~= previousPlot)
render(enter)
expect('APMon')
render(exit)
expect('HUD') -- menu round trip retains the page
render(prev)
if not color then expect('APMon Flight','APMon Flugwerte'); render(prev) end
expect(color and 'APMon' or 'APMon Overview', color and 'APMon' or 'APMon Übersicht')
if color then expect('1/2') end
tick(100, packet(0x5001,256))
expect('ARMED')
frame('Confirmed arming', 'Bestätigtes Armen')
data.Curr.current, data.RQly[1], data.Capa[1] = false, 82, 110
tick(100, packet(0x5001,256), message('Battery warning',4))
data.Curr.current, data.Curr[1], data.Capa[1], data.RQly[1] = true, 12, 117, 95
tick(100, packet(0x5001,256))
tick(100, packet(0x5001,0), packet(0x5002,48))
expect('DISARMED')
frame('Confirmed disarm', 'Bestätigtes Entarmen')

if color then
  tap('Last FC warning', 'Letzte FC-Warnung')
  expect('Battery warning')
  frame('Read the last FC warning directly', 'Letzte FC-Warnung direkt lesen')
  render(exit)
  expect('APMon')
end

openMenu()
frame('Open the project menu', 'Projektmenü öffnen')
choose(2, 'FC messages', 'FC-Meldungen')
expect('Filter: All', 'Filter: Alle')
frame('FC messages and armed markers', 'FC-Meldungen und Armed-Markierungen')
if color then tap('Filter: All','Filter: Alle')
else
  render(prev)
  frame('Move to the filter', 'Zum Filter wechseln', 1000)
  render(enter)
end
expect(color and 'Filter: Warnings & errors' or 'Filter: Warnings',
  color and 'Filter: Warnungen & Fehler' or 'Filter: Warnungen')
frame('Show warnings and errors', 'Warnungen und Fehler filtern')
render(exit); render(exit)

openMenu()
choose(6, 'GPS details', 'GPS-Details')
expect('Live')
expect('0.123456')
frame('GPS details with a confirmed fix', 'GPS-Details mit bestätigtem Fix')
data.GPS.fresh = false
tick(250)
expect(color and 'Not live  |  2s ago' or 'Not live',
  color and 'Nicht live  |  vor 2s' or 'Nicht live')
expect('0.123456')
frame('Position retained after a gap', 'Letzte Position nach einer Datenlücke')
render(exit); render(exit)

openMenu()
choose(5, 'Last armed period', 'Letzte Armed-Phase')
expect('82 %')
expect('Min. RC LQ', 'RC-LQ min.')
frame('Armed summary with minimum RC link quality', 'Armed-Bilanz mit niedrigster RC-Linkqualität')
if color then tap('Details','Details') else render(enter) end
expect('Current missing', 'Stromsensor fehlt')
expect('1x')
frame('Separate sensor gaps in the details', 'Sensordatenlücken getrennt in den Details')
render(exit); render(exit); render(exit)

openMenu()
choose(4, 'Telemetry diagnostics', 'Telemetrie-Diagnose')
expect('Telemetry diagnostics', 'Telemetrie-Diagnose')
frame('Check the telemetry sources', 'Telemetriequellen prüfen')
if color then tap('Setup check','Einrichtungscheck') else render(prev); render(enter) end
expect('Setup check', 'Einrichtungscheck')
expect('1/9')
expect('Next step', 'Nächster Schritt')
expect('Profile: ArduPilot', 'Profil: ArduPilot')
frame('Start with a next step for the active profile', 'Einstieg mit nächstem Schritt für das aktive Profil')
for _ = 1, 3 do
  if color then tap('Next','Weitere') else render(nextEvent) end
end
expect('GPS coordinates', 'GPS-Koordinaten')
expect('Valid', 'Gültig')
frame('GPS coordinates are available', 'GPS-Koordinaten sind verfügbar')
tick(100, packet(0x5001,0))
if color then tap('Next','Weitere') else render(nextEvent) end
expect('GPS fix type', 'GPS-Fixtyp')
expect('Stale', 'Veraltet')
expect('Check ELRS MAVLink', 'ELRS MAVLink prüfen')
frame('The FC fix type is checked separately', 'Der FC-Fixtyp wird getrennt geprüft')
data.Curr = {-1}
tick(20)
if color then tap('Next','Weitere'); tap('Next','Weitere')
else render(nextEvent); render(nextEvent) end
expect('Current sensor', 'Stromsensor')
expect('Invalid', 'Ungültig')
expect('Configured: Curr', 'Konfiguriert: Curr')
expect('Detected: Curr', 'Erkannt: Curr')
expect('Check source and unit', 'Quelle/Einheit prüfen')
frame('Invalid readings have a setup hint', 'Ungültige Werte mit Einrichtungshinweis')
if color then tap('Next','Weitere'); tap('Next','Weitere')
else render(nextEvent); render(nextEvent) end
expect('Relative altitude', 'Relative Höhe')
expect('Not mapped', 'Nicht zugeordnet')
expect('Map relative altitude', 'Höhe zuordnen')
frame('Relative altitude needs an explicit mapping', 'Relative Höhe braucht eine ausdrückliche Zuordnung')
data.Curr = nil
render(exit)
if color then tap('Save report','Bericht speichern')
else
  render(prev)
  frame('Select Save report', 'Bericht speichern auswählen', 1000)
  render(enter)
end
expect('Diagnostic report','Diagnosebericht')
assert(sd[reportPath] == nil, 'report written before confirmation')
frame('Confirm a local report without FC text', 'Lokalen Bericht ohne FC-Klartext bestätigen')
render(enter)
expect('Report saved','Bericht gespeichert')
expect(reportPath)
assert(string.find(sd[reportPath], 'S4 | ', 1, true))
assert(string.find(sd[reportPath], localize('Radio time:', 'Senderzeit:') .. ' 2026-11-23 12:34:56', 1, true))
for _, secret in ipairs({'0.123456','-0.654321','Battery warning'}) do
  assert(not string.find(sd[reportPath], secret, 1, true), 'sensitive data in default report')
end
frame('Report saved to the simulated SD card', 'Bericht auf der simulierten SD-Karte gespeichert', 2400)

render(exit); render(exit); render(exit)
openMenu()
choose(7, 'Flight Controller', 'Flugcontroller')
expect('ArduPilot *')
expect('Betaflight')
frame('Choose the flight controller profile', 'Flugcontroller-Profil auswählen')
render(nextEvent)
render(enter)
assert(sd[profilePath] == 'bf\n')
render(exit)
data.FM = {'STAB*'}
local savedUsed = used
clock = clock + 20
render(0)
assert(used == savedUsed, 'Betaflight must not read the ArduPilot queue')
expect('ANGLE')
assert(not has('ARMED') and not has('DISARMED'))
frame('Betaflight mode from standard CRSF telemetry', 'Betaflight-Modus aus normaler CRSF-Telemetrie')
openMenu()
choose(4, 'Telemetry diagnostics', 'Telemetrie-Diagnose')
if color then tap('Setup check','Einrichtungscheck') else render(prev); render(enter) end
expect('GPS fix unconfirmed', 'GPS-Fix nicht bestätigt')
expect('Fix source if needed', 'Fixquelle bei Bedarf')
frame('An unconfirmed GPS fix is not a missing RC link', 'Ein unbestätigter GPS-Fix ist kein fehlender RC-Link')
data = {RQly={96}}
tick(20)
expect('No FC sensor readings', 'FC-Sensorwerte fehlen')
expect('Check EdgeTX sensor list', 'EdgeTX-Sensorliste prüfen')
frame('Only link readings: check EdgeTX sensors first', 'Nur Funkwerte: zuerst die EdgeTX-Sensorliste prüfen')
render(nextEvent); render(nextEvent)
expect('Unavailable', 'Nicht verfügbar')
expect('Only with ArduPilot', 'Nur mit ArduPilot')
frame('ArduPilot-specific status is unavailable', 'ArduPilot-spezifischer Status ist nicht verfügbar')
hostIO.write('done\t', count, '\n')
