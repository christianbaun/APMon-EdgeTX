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
    draws[value] = {x=x, y=y}
    op('text', x, y, width, height, color and ink or flags & INVERS ~= 0 and 0 or 0xFFFFFF,
      not color and flags & INVERS ~= 0 and 1 or 0, value)
  end,
  drawFilledRectangle = function(x, y, width, height, flags)
    assert(x >= 0 and y >= 0 and x + width <= LCD_W and y + height <= LCD_H, 'rectangle outside display')
    op('rect', x, y, width, height, color and ink or flags == ERASE and 0 or 0xFFFFFF)
  end,
  drawLine = function(x1, y1, x2, y2, _, flags)
    op('line', x1, y1, x2, y2, flags == ERASE and 0 or 0xFFFFFF)
  end,
  drawBitmap = function(_, x, y) op('logo', x, y) end,
}
Bitmap = {open = function(path) return assert(path == '/WIDGETS/APMon/logo.png') end}
getTime = function() return clock end
getDateTime = function() return {hour=12,min=34} end
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
model = setmetatable({}, {__index=function() error('APMon must not access model settings') end})
loadScript = function(path) return loadfile('SD' .. path) end
io = {
  open = function(path, mode)
    if path == '/SCRIPTS/APMON/VERSION' and mode == 'r' then return assert(hostIO.open('VERSION', 'r')) end
    if path == '/SCRIPTS/APMON/mono.cfg' and mode == 'r' then return {content=lang .. '\n1'} end
    assert(path == reportPath and mode == 'w', 'unexpected SD write: ' .. path)
    return {content=''}
  end,
  read = function(f, n) return type(f) == 'table' and f.content or f:read(n) end,
  write = function(f, text) f.content = f.content .. text; return f end,
  close = function(f)
    if type(f) ~= 'table' then return f:close() end
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
  GPS={{lat=0.123456,lon=-0.654321}}, Yaw={-0.4}, Roll={0.1}, Ptch={0.05}}
tick(20, packet(0x5001,0), packet(0x5002,48), message('Using EKF Source Set 2',6))
expect(color and 'APMon' or 'APMon Overview', color and 'APMon' or 'APMon Übersicht')
frame('Overview and live telemetry', 'Übersicht und Live-Telemetrie')
if not color then
  render(nextEvent)
  expect('APMon Flight','APMon Flugwerte')
  frame('Second telemetry page', 'Zweite Telemetrieseite')
  render(prev)
end
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
if color then tap('Save report','Bericht speichern')
else
  render(nextEvent)
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
for _, secret in ipairs({'0.123456','-0.654321','Battery warning'}) do
  assert(not string.find(sd[reportPath], secret, 1, true), 'sensitive data in default report')
end
frame('Report saved to the simulated SD card', 'Bericht auf der simulierten SD-Karte gespeichert', 2400)
hostIO.write('done\t', count, '\n')
