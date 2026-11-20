-- =============================================================================
-- APMon - EdgeTX Monitor for ArduPilot
-- File: SD/SCRIPTS/APMON/project.lua
-- Purpose: Share the project title and repository address across both displays.
-- Project version: 0.2.0
-- Updated: 2026-11-20
-- Authors: APMon contributors
-- Development assistance: OpenAI Codex CLI (code, tests and documentation)
-- Copyright (c) 2026 APMon contributors
-- SPDX-License-Identifier: Apache-2.0
-- License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
-- See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
-- =============================================================================

return {
  -- These line breaks fit the 128-pixel monochrome display.
  title = { 'APMon - ArduPilot', 'telemetry monitor for', 'EdgeTX monochrome and', 'color radios' },
  repo = { 'github.com/christianbaun/', 'APMon-EdgeTX' },
}
