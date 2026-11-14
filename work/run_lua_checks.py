"""Run standalone Lua boundary harnesses with Lua 5.4 (not the game VM).

The interpreter library is resolved in this order:
  1. $GQUEST_LUA_LIB
  2. <repo>/work/toolchains/lua/lib/liblua5.4.so.0   (locally built, see BUILD.md)
  3. the system liblua5.4

Nothing here touches the game's own liblua_shared.so; these harnesses only exercise
the Lua sources in isolation.
"""
import ctypes
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANDIDATES = [
    os.environ.get("GQUEST_LUA_LIB"),
    str(ROOT / "work/toolchains/lua/lib/liblua5.4.so.0"),
    "liblua5.4.so.0",
    "liblua5.4.so",
]


def load_lua():
    tried = []
    for candidate in CANDIDATES:
        if not candidate:
            continue
        tried.append(candidate)
        try:
            return ctypes.CDLL(candidate), candidate
        except OSError:
            continue
    print(
        "Lua 5.4 shared library not found. Tried:\n  "
        + "\n  ".join(tried)
        + "\nInstall liblua5.4, or build it locally:\n"
        "  curl -O https://www.lua.org/ftp/lua-5.4.7.tar.gz\n"
        "  tar xzf lua-5.4.7.tar.gz && cd lua-5.4.7 && make linux MYCFLAGS=-fPIC\n"
        "  cd src && gcc -shared -fPIC -o ../../lib/liblua5.4.so.0 "
        "$(ls *.o | grep -vE '^(lua|luac)\\.o$') -lm\n"
        "  (place it at work/toolchains/lua/lib/liblua5.4.so.0)\n"
        "Or point GQUEST_LUA_LIB at an existing liblua5.4.",
        file=sys.stderr,
    )
    # Exit code 2 means "no interpreter": callers report this as skipped, not failed.
    raise SystemExit(2)


lib, origin = load_lua()
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                           ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]

failures = 0
for arg in sys.argv[1:]:
    path = Path(arg)
    if not path.is_file():
        print(f"MISSING {arg}")
        failures += 1
        continue
    state = lib.luaL_newstate()
    lib.luaL_openlibs(state)
    try:
        code = lib.luaL_loadfilex(state, str(path).encode(), None)
        # Harness files named test_* are executed; shared files are only loaded.
        if not code and "test_" in path.name:
            code = lib.lua_pcallk(state, 0, 0, 0, 0, None)
        if code:
            message = lib.lua_tolstring(state, -1, None)
            print(f"FAIL {arg}: {(message or b'?').decode(errors='replace')}")
            failures += 1
        else:
            print(f"PASS {arg}")
    finally:
        lib.lua_close(state)

if failures:
    print(f"\n{failures} Lua-Harness(es) fehlgeschlagen.")
    raise SystemExit(1)
print(f"\n{len(sys.argv) - 1} Lua-Harness(es) bestanden (Lua aus {origin}).")
