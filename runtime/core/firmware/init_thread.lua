-- Step 1. init c searcher
local searcher_preload = package.searchers[1]
local searcher_C = package.searchers[3]

package.searchers[1] = searcher_preload
package.searchers[2] = searcher_C
package.searchers[3] = nil
package.loadlib = nil

-- Step 2. init vfs
local thread = require "thread"
local threadid = thread.id
-- main thread id is 0
if threadid ~= 0 then
    thread.newchannel ("IOresp" .. threadid)
end
local io_req = thread.channel "IOreq"
local io_resp = thread.channel ("IOresp" .. threadid)

local vfs = {}

local function npath(path)
	return path:match "^/?(.-)/?$"
end

function vfs.list(path)
	io_req:push("LIST", threadid, npath(path))
	return io_resp:bpop()
end

function vfs.realpath(path)
	io_req:push("GET", threadid, npath(path))
	return io_resp:bpop()
end

function vfs.prefetch(path)
	io_req:push("PREFETCH", npath(path))
end

package.loaded.vfs = vfs

-- Step 3. init io
local nio = io
local io = {
    read = nio.read,
    write = nio.write,
    type = nio.type,
    flush = nio.flush,
    close = nio.close,
    popen = nio.popen,
    tmpfile = nio.tmpfile,
    input = nil, -- TODO
    output = nil,
    lines = nil,
}

function io.open(filename, mode)
    if mode ~= nil and mode ~= 'r' and mode ~= 'rb' then
        return nil, ('%s:Permission denied.'):format(filename)
    end
    local real_filename = vfs.realpath(filename)
    if not real_filename then
        return nil, ('%s:No such file or directory.'):format(filename)
    end
    local f, err, ec = nio.open(real_filename, mode)
    if not f then
        local first, last = err:find(real_filename, 1, true)
        if not first then
            return nil, err, ec
        end
        err = err:sub(1, first-1) .. filename .. err:sub(last+1)
        return nil, err, ec
    end
    return f
end

package.loaded.nativeio = nio
package.loaded.vfsio = io
package.loaded.io = io
_G.io = io

-- Step 4. init dofile and loadfile
local io_open = io.open
local function hasfile(path)
    local f = io_open(path, 'rb')
    if not f then
        return false
    end
    f:close()
    return true
end

local function loadfile(path)
    local f, err = io_open(path, 'rb')
    if not f then
        return nil, err
    end
    local str = f:read 'a'
    f:close()
    return load(str, '@vfs://' .. path)
end

local function dofile(path)
    local f, err = loadfile(path)
    if not f then
        error(err)
    end
    return f()
end

_G.loadfile = loadfile
_G.dofile = dofile

-- Step 5. init lua searcher
package.path = "engine/libs/?.lua;engine/libs/?/?.lua"

local config = {}
package.config:gsub('[^\n]+', function (w) config[#config+1] = w end)

local LUA_DIRSEP    = config[1] -- '/'
local LUA_PATH_SEP  = config[2] -- ';'
local LUA_PATH_MARK = config[3] -- '?'
local LUA_EXEC_DIR  = config[4] -- '!'
local LUA_IGMARK    = config[5] -- '-'

local function searchpath(name, path)
    local err = ''
    name = string.gsub(name, '%.', '/')
    for c in string.gmatch(path, '[^;]+') do
        local filename = string.gsub(c, '%?', name)
        if hasfile(filename) then
            return filename
        end
        err = err .. ("\n\tno file '%s'"):format(filename)
    end
    return nil, err
end

local function searcher_Lua(name)
    assert(type(package.path) == "string", "'package.path' must be a string")
    local filename, err = searchpath(name, package.path)
    if not filename then
        return err
    end
    local f, err = loadfile(filename)
    if not f then
        error(("error loading module '%s' from file '%s':\n\t%s"):format(name, filename, err))
    end
    return f, filename
end

package.searchers[1] = searcher_preload
package.searchers[2] = searcher_Lua
package.searchers[3] = searcher_C
package.searchers[4] = nil
package.searchpath = searchpath
