-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/config.lua
-- Purpose: Define sensor names, units, conversion factors and value validation limits.
-- Project version: 0.4.0
-- Updated: 2026-11-20
-- Authors: Christian Baun
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

-- Sensor names must match Model > Telemetry. Units must match the labels below.
-- No FC parameters or model settings are written by this application.
return {
  -- Opt in only after confirming the active sensor really gives height above Home.
  -- Example for the standard ELRS MAVLink build: relativeAltitudeSensor = 'GAlt'.
  relativeAltitudeSensor = false,
  sensors = {
    voltage = { names = { 'RxBt' }, unit = 'V', decimals = 2, min = 0.1 },
    current = { names = { 'Curr' }, unit = 'A', decimals = 2, min = 0 },
    remaining = { names = { 'Bat%' }, unit = '%', decimals = 0, min = 0, max = 100 },
    used = { names = { 'Capa' }, unit = 'mAh', decimals = 0, min = 0 },
    altitude = { names = { 'Alt' }, unit = 'm', decimals = 1 },
    gpsaltitude = { names = { 'GAlt' }, unit = 'm', decimals = 1 },
    climb = { names = { 'VSpd' }, unit = 'm/s', decimals = 1 },
    speed = { names = { 'GSpd' }, unit = 'km/h', decimals = 1, min = 0 },
    satellites = { names = { 'Sats' }, unit = '', decimals = 0, min = 0 },
    heading = { names = { 'Hdg' }, unit = 'deg', decimals = 0, min = 0, max = 360 },
    mode = { names = { 'FM' }, text = true },
    lq = { names = { 'RQly' }, unit = '%', decimals = 0, min = 0, max = 100 },
    gps = { names = { 'GPS' }, gps = true },
    -- CRSF attitude sensors use radians; convert the default unit to degrees.
    roll = { names = { 'Roll' }, unit = 'deg', decimals = 1, scale = 180 / math.pi },
    pitch = { names = { 'Ptch' }, unit = 'deg', decimals = 1, scale = 180 / math.pi },
    yaw = { names = { 'Yaw' }, unit = 'deg', decimals = 1, scale = 180 / math.pi },
    -- Assign only verified sensors. GPS position/satellite count do not prove fix.
    ground = { names = {}, unit = 'm', decimals = 1, min = 0 },
    gpsfix = { names = {}, binary = true }, -- confirmed 0=no fix, 1=fix
    vtxfreq = { names = {}, unit = 'MHz', decimals = 0, min = 0 },
    vtxband = { names = {}, text = true },
    vtxchannel = { names = {}, unit = '', decimals = 0, min = 1 },
    ekfsource = { names = {}, unit = '', decimals = 0, min = 1, max = 3 },
    -- Enable only if these are real DOWNLINK sensors with verified semantics.
    -- Never use ch5/ch7: a switch position does not confirm FC/VTX state.
    armed = { names = {}, binary = true }, -- 0=disarmed, 1=armed
    pit = { names = {}, binary = true },   -- 0=off, 1=on
    power = { names = {}, unit = 'mW', decimals = 0, min = 0 },
  }
}
