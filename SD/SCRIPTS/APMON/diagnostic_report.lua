-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/diagnostic_report.lua
-- Purpose: Write a one-shot diagnostic snapshot to the radio's SD card.
-- Project version: 1.1.0
-- Updated: 2026-11-26
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

local path, version, config, monitor, receiver, tr, includeText, senderTime = ...
if not (io and io.open and io.write and io.close) then return false end

local function clean(value)
  return type(value) == 'string' and string.gsub(value, '%c', ' ') or '--'
end

local function writeReport(file)
  local bytes = 0
  local function line(text)
    assert(io.write(file, text .. '\n'), 'write failed')
    bytes = bytes + #text + 1
  end
  local function age(seconds)
    return seconds and string.format(tr('vor %ds'), seconds) or '--'
  end
  local states = {valid='Gültig', missing='Nicht gefunden', stale='Veraltet',
    invalid='Ungültig', noapi='API fehlt', unknown='Unbekannt', unreceived='Nicht empfangen'}
  local firmware, radio
  if type(getVersion) == 'function' then
    local ok, sw, hw = pcall(getVersion)
    if ok then firmware, radio = sw, hw end
  end
  line('APMon ' .. version .. ' | ' .. tr('Diagnosebericht'))
  line(tr('Flugcontroller') .. ': ' .. (monitor.betaflight and 'Betaflight' or 'ArduPilot'))
  line('EdgeTX: ' .. clean(firmware) .. ' (' .. clean(radio) .. ')')
  line(tr('Senderzeit') .. ': ' .. (senderTime or tr('Nicht verfügbar')))
  if monitor.betaflight then
    line(tr('FC-Status (Passthrough)') .. ': ' .. tr('Nicht verfügbar'))
  else
    local fc, fcAge = receiver.status('armed')
    line(tr('FC-Status (Passthrough)') .. ': ' .. tr(states[fc]) .. ' / ' .. age(fcAge))
  end
  line('')
  line(tr('Sensoren') .. ': ' .. tr('Zuordnung / Erkannt / Status'))
  for _, entry in ipairs(monitor.sensorList) do
    local names = ''
    for i, name in ipairs(config.sensors[entry.key].names) do
      names = names .. (i == 1 and '' or ', ') .. clean(name)
    end
    local detected = entry.state ~= 'missing' and entry.state ~= 'noapi' and entry.name
    line(entry.key .. ': ' .. names .. ' / ' .. clean(detected) .. ' / ' .. tr(states[entry.state]))
  end
  line('')
  if monitor.betaflight then
    line(tr('FC-Meldungen') .. ': ' .. tr('Nicht verfügbar'))
    return bytes
  end
  line(tr('FC-Meldungen') .. ' (' .. tr(includeText and 'Mit FC-Klartext' or 'Ohne FC-Klartext') .. ')')
  local count = 0
  for _, entry in ipairs(receiver.timeline(nil, false)) do
    if entry.armed == nil then
      local meta = 'S' .. entry.severity .. ' | ' .. age(receiver.age(entry)) .. ' | x' .. entry.repeats
      line(includeText and meta .. ' | ' .. clean(entry.value) or meta)
      count = count + 1
      if count == 8 then break end
    end
  end
  if count == 0 then line(tr('Keine FC-Meldungen')) end
  return bytes
end

local opened, file = pcall(io.open, path, 'w')
if not opened or not file then return false end
local wrote, bytes = pcall(writeReport, file)
-- EdgeTX io.close returns no values. If available, check the saved size too.
local closed, result, reason = pcall(io.close, file)
if not wrote or not closed or result == false or (result == nil and reason ~= nil) then return false end
if type(fstat) == 'function' then
  local ok, info = pcall(fstat, path)
  return ok and info ~= nil and info.size == bytes
end
return true
