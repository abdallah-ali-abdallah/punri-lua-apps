/* Host-only runner; compile against PUNRI's vendored Lua configuration. */
#include <stdio.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    lua_State *state = luaL_newstate();
    if (!state) return 3;
    luaL_openlibs(state);
    lua_createtable(state, argc - 1, 0);
    for (int i = 1; i < argc; ++i) {
        lua_pushstring(state, argv[i]);
        lua_rawseti(state, -2, i - 1);
    }
    lua_setglobal(state, "arg");
    int status = luaL_dofile(state, argv[1]);
    if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(state, -1));
    lua_close(state);
    return status == LUA_OK ? 0 : 1;
}
