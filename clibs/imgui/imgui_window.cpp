#include <stdio.h>
#include <lua.hpp>
#include <stdint.h>
#include "imgui_window.h"
#include "imgui_platform.h"
#include "virtual_keys.h"
#ifdef _WIN32
#include <windows.h>
#include <WinNT.h>
#endif //_WIN32

struct window_callback {
	lua_State *callback;
	lua_State *functions;
	int top;
};

static bool event_push(struct window_callback* context, int id) {
	if (!context) {
		return false;
	}
	lua_State* from = context->functions;
	lua_State* to = context->callback;
	lua_pushvalue(from, 1);
	lua_pushvalue(from, id + 1);
	lua_xmove(from, to, 2);
	bool ok = lua_type(to, -1) == LUA_TSTRING;
	if (!ok) {
		lua_pop(to, 2);
	}
	context->top = lua_gettop(to);
	return ok;
}

static bool event_emit(struct window_callback* context, int nresults = 0) {
	lua_State* L = context->callback;
	int nargs = 1 + lua_gettop(L) - context->top;
	if (lua_pcall(L, nargs, nresults, 1) != LUA_OK) {
		printf("Error: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
		return false;
	}
	return true;
}

void window_event_update(struct window_callback* cb) {
	if (!event_push(cb, ANT_WINDOW_UPDATE)) {
		return;
	}
	event_emit(cb);
}

void window_event_init(struct window_callback* cb, void* window, void* context, int w, int h) {
	if (!event_push(cb, ANT_WINDOW_INIT)) {
		return;
	}
	lua_State* L = ((struct window_callback*)cb)->callback;
	lua_pushlightuserdata(L, window);
	lua_pushlightuserdata(L, context);
	lua_pushinteger(L, w);
	lua_pushinteger(L, h);
	event_emit(cb);
}

void window_event_exit(struct window_callback* cb) {
	if (!event_push(cb, ANT_WINDOW_EXIT)) {
		return;
	}
	event_emit(cb);
}

void window_event_keyboard(struct window_callback* cb, int key, uint8_t state, uint8_t press) {
	if (!event_push(cb, ANT_WINDOW_KEYBOARD)) {
		return;
	}
	lua_State* L = ((struct window_callback*)cb)->callback;
	lua_pushinteger(L, key);
	lua_pushinteger(L, press);
	lua_pushinteger(L, state);
	event_emit(cb);
}

void window_event_mouse(struct window_callback* cb, int x, int y, uint8_t type, uint8_t state) {
	if (!event_push(cb, ANT_WINDOW_MOUSE)) {
		return;
	}
	lua_State* L = ((struct window_callback*)cb)->callback;
	lua_pushinteger(L, x);
	lua_pushinteger(L, y);
	lua_pushinteger(L, type);
	lua_pushinteger(L, state);
	event_emit(cb);
}

void window_event_mouse_wheel(struct window_callback* cb, int x, int y, float delta) {
	if (!event_push(cb, ANT_WINDOW_MOUSE_WHEEL)) {
		return;
	}
	lua_State* L = ((struct window_callback*)cb)->callback;
	lua_pushinteger(L, x);
	lua_pushinteger(L, y);
	lua_pushnumber(L, delta);
	event_emit(cb);
}

void window_event_size(struct window_callback* cb, int w, int h, int type) {
	if (!event_push(cb, ANT_WINDOW_SIZE)) {
		return;
	}
	lua_State* L = ((struct window_callback*)cb)->callback;
	lua_pushinteger(L, w);
	lua_pushinteger(L, h);
	lua_pushinteger(L, type);
	event_emit(cb);
}

void window_event_dropfiles(struct window_callback* cb, int count, char** paths, int* path_counts) {
	if (!event_push(cb, ANT_WINDOW_DROPFILES)) {
		return;
	}
	lua_State* L = ((struct window_callback*)cb)->callback;
	lua_createtable(L, count, 0);
	for (int i = 0; i < count; i++)
	{
		lua_pushinteger(L, i + 1);
		lua_pushlstring(L, paths[i], path_counts[i]);
		lua_settable(L, -3);
	}
	event_emit(cb);
}

int window_event_viewid(struct window_callback* cb) {
	if (!event_push(cb, ANT_WINDOW_VIEWID)) {
		return -1;
	}
	if (!event_emit(cb, 1)) {
		return -1;
	}
	lua_State* L = ((struct window_callback*)cb)->callback;
	int ret = (int)luaL_checkinteger(L, -1);
	lua_pop(L, 1);
	return ret;
}

static void
register_function(lua_State *L, const char *name, lua_State *fL, int id) {
	lua_pushstring(L, name);
	lua_xmove(L, fL, 1);
	lua_replace(fL, id + 1);
}

static void
register_functions(lua_State *L, int index, lua_State *fL) {
	lua_pushvalue(L, index);
	lua_xmove(L, fL, 1);

	luaL_checkstack(fL, ANT_WINDOW_COUNT+3, NULL);	// 3 for temp
	for (int i = 0; i < ANT_WINDOW_COUNT; ++i) {
		lua_pushnil(fL);
	}
	register_function(L, "update", fL, ANT_WINDOW_UPDATE);
	register_function(L, "init", fL, ANT_WINDOW_INIT);
	register_function(L, "exit", fL, ANT_WINDOW_EXIT);
	register_function(L, "keyboard", fL, ANT_WINDOW_KEYBOARD);
	register_function(L, "mouse_wheel", fL, ANT_WINDOW_MOUSE_WHEEL);
	register_function(L, "mouse", fL, ANT_WINDOW_MOUSE);
	register_function(L, "size", fL, ANT_WINDOW_SIZE);
	register_function(L, "dropfiles", fL, ANT_WINDOW_DROPFILES);
	register_function(L, "viewid", fL, ANT_WINDOW_VIEWID);
}

static int
ltraceback(lua_State *L) {
	const char *msg = lua_tostring(L, 1);
	if (msg == NULL && !lua_isnoneornil(L, 1)) {
		lua_pushvalue(L, 1);
	} else {
		luaL_traceback(L, L, msg, 2);
	}
	return 1;
}

struct window_callback* window_get_callback(lua_State* L) {
	if (lua_getfield(L, LUA_REGISTRYINDEX, WINDOW_CALLBACK) != LUA_TUSERDATA) {
		luaL_error(L, "Can't find window_callback.");
		return 0;
	}
	struct window_callback* cb = (struct window_callback*)lua_touserdata(L, -1);
	lua_pop(L, 1);
	return cb;
}

void window_register(lua_State *L, int idx) {
	luaL_checktype(L, idx, LUA_TFUNCTION);
	struct window_callback * context = (struct window_callback*)lua_newuserdatauv(L, sizeof(*context), 2);
	context->callback = lua_newthread(L);
	lua_setiuservalue(L, -2, 1);
	context->functions = lua_newthread(L);
	lua_setiuservalue(L, -2, 2);
	lua_setfield(L, LUA_REGISTRYINDEX, WINDOW_CALLBACK);

	lua_pushcfunction(context->callback, ltraceback);	// push traceback function
	register_functions(L, 1, context->functions);
}
