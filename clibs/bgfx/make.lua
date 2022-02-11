local lm = require "luamake"

dofile "../common.lua"

lm:source_set "source_bgfx" {
    deps = "bx",
    includes = {
        LuaInclude,
        BgfxInclude,
    },
    sources = {
        "*.c",
        "*.cpp"
    },
    defines = lm.mode == "debug" and "BX_CONFIG_DEBUG=1",
    msvc = {
        flags = {
            "-wd4244",
            "-wd4267",
        },
        ldflags = {
            "-export:luaopen_bgfx_util",
        },
    },
}

lm:lua_dll "bgfx" {
    deps = "source_bgfx",
}
