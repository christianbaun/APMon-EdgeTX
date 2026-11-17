# =============================================================================
# APMon - EdgeTX Monitor for ArduPilot
# File: tests/run.py
# Purpose: Execute the Lua regression suite through a local Lua 5.3/5.4 shared library.
# Project version: 0.1.0
# Updated: 2026-11-17
# Authors: APMon contributors
# Development assistance: OpenAI Codex CLI (code, tests and documentation)
# Copyright (c) 2026 APMon contributors
# SPDX-License-Identifier: Apache-2.0
# License: Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
# See LICENSE in the repository or SCRIPTS/APMON/LICENSE.txt in SD packages.
# =============================================================================

"""Run the Lua checks using a local Lua 5.3/5.4 shared library (no packages needed)."""
import ctypes as C
import ctypes.util
import os
from pathlib import Path

os.chdir(Path(__file__).resolve().parents[1])
name = ctypes.util.find_library('lua5.3') or ctypes.util.find_library('lua5.4')
if not name:
    raise SystemExit('Install Lua 5.3/5.4, then run: lua tests/check.lua')
lua = C.CDLL(name)
lua.luaL_newstate.restype = C.c_void_p
lua.luaL_openlibs.argtypes = [C.c_void_p]
lua.luaL_loadfilex.argtypes = [C.c_void_p, C.c_char_p, C.c_char_p]
lua.lua_pcallk.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_ssize_t, C.c_void_p]
lua.lua_tolstring.argtypes = [C.c_void_p, C.c_int, C.c_void_p]
lua.lua_tolstring.restype = C.c_char_p
lua.lua_close.argtypes = [C.c_void_p]
state = lua.luaL_newstate()
if not state:
    raise SystemExit('Could not create Lua state')
try:
    lua.luaL_openlibs(state)
    result = lua.luaL_loadfilex(state, b'tests/check.lua', None)
    if not result:
        result = lua.lua_pcallk(state, 0, 0, 0, 0, None)
    if result:
        raise SystemExit(lua.lua_tolstring(state, -1, None).decode())
finally:
    lua.lua_close(state)
