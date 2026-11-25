-- TNS|APMon|TNE
-- SPDX-License-Identifier: Apache-2.0
-- EdgeTX Tools run in a separate session from the model's screen or widget.
local color = type(lcd.RGB) == 'function'
local path = color and '/WIDGETS/APMon/main.lua' or '/SCRIPTS/TELEMETRY/APMon.lua'
local script, reason = loadScript(path)
if not script then
  error('APMon: install the complete package for this display: ' .. tostring(reason or path))
end
if not color then return script(true) end

local app = script()
local instance = app.create({ x = 0, y = 0, w = LCD_W, h = LCD_H }, { Language = 1, Clock = 0 })
local function run(event, touch)
  if event == EVT_VIRTUAL_EXIT and not instance.view and not instance.hud then return 1 end
  app.refresh(instance, event or 0, touch)
  return 0
end
return { run = run }
