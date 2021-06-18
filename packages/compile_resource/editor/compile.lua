local fs = require "filesystem"
local lfs = require "filesystem.local"
local sha1 = require "hash".sha1
local stringify = require "stringify"
local serialize = import_package "ant.serialize".stringify
local datalist = require "datalist"
local config = require "config"

local function split(str)
    local r = {}
    str:gsub('[^|]*', function (w) r[#r+1] = w end)
    return r
end

local function split_path(pathstring)
    local pathlst = split(pathstring)
    local res = {}
    for i = 1, #pathlst - 1 do
        local path = pathlst[i]
        local ext = path:match "[^/]%.([%w*?_%-]*)$"
        local cfg = config.get(ext)
        res[#res+1] = path .. "?" .. cfg.arguments
    end
    res[#res+1] = pathlst[#pathlst]
    return res
end

local ResourceCompiler = {
    glb = "editor.model.convert",
    texture = "editor.texture.convert",
    png = "editor.png.convert",
    sc = "editor.fx.convert",
}

for ext, compiler in pairs(ResourceCompiler) do
    local cfg = config.get(ext)
    cfg.binpath = fs.path "":localpath() / ".build" / ext
    cfg.compiler = compiler
end

local function get_filename(pathname)
    pathname = pathname:lower()
    local filename = pathname:match "[/]?([^/]*)$"
    return filename.."_"..sha1(pathname)
end

local function writefile(filename, data)
	local f = assert(lfs.open(filename, "wb"))
	f:write(data)
	f:close()
end

local function readfile(filename)
	local f = assert(lfs.open(filename))
	local data = f:read "a"
	f:close()
	return data
end

local function readconfig(filename)
    return datalist.parse(readfile(filename))
end

local function do_build(output)
    local depfile = output / ".dep"
    if not lfs.exists(depfile) then
        return
    end
	for _, dep in ipairs(readconfig(depfile)) do
        local timestamp, filename = dep[1], lfs.path(dep[2])
        if timestamp == 0 then
            if lfs.exists(filename) then
                return
            end
        else
            if not lfs.exists(filename) or timestamp ~= lfs.last_write_time(filename) then
                return
            end
        end
	end
	return true
end

local function create_depfile(filename, deps)
    local w = {}
    for _, file in ipairs(deps) do
        local path = lfs.path(file)
        if lfs.exists(path) then
            w[#w+1] = ("{%d, %q}"):format(lfs.last_write_time(path), lfs.absolute(path):string())
        else
            w[#w+1] = ("{0, %q}"):format(lfs.absolute(path):string())
        end
    end
    writefile(filename, table.concat(w, "\n"))
end

local function absolute_path(base, path)
	if path:sub(1,1) == "/" then
		return fs.path(path):localpath()
	end
	return lfs.absolute(base:parent_path() / (path:match "^%./(.+)$" or path))
end

local function do_compile(cfg, setting, input, output)
    lfs.create_directories(output)
    local ok, deps = require(cfg.compiler)(input, output, setting, function (path)
        return absolute_path(input, path)
    end)
    if not ok then
        local err = deps
        error("compile failed: " .. input:string() .. "\n" .. err)
    end
    create_depfile(output / ".dep", deps or {})
end

local function parseUrl(url)
    local path, arguments = url:match "^([^?]*)%?(.*)$"
    local setting = {}
    arguments:gsub("([^=&]*)=([^=&]*)", function(k ,v)
        setting[k] = v
    end)
    return path, setting, arguments
end

local function compile_url(url)
    local path, setting, arguments = parseUrl(url)
    local hash = sha1(arguments):sub(1,7)
    local ext = path:match "[^/]%.([%w*?_%-]*)$"
    local cfg = config.get(ext)
    local input = fs.path(path):localpath()
    local keystring = lfs.absolute(input):string():lower()
    local output = cfg.binpath / get_filename(keystring) / hash
    if not lfs.exists(output) or not do_build(output) then
        do_compile(cfg, setting, input, output)
        writefile(output / ".setting", serialize(setting))
        writefile(output / ".arguments", arguments)
    end
    return output
end

local function compile_dir(urllst)
    local url = urllst[1]
    if #urllst == 1 then
        return fs.path(url):localpath()
    end
    for i = 2, #urllst do
        url = (compile_url(url) / urllst[i]):string()
    end
    return lfs.path(url)
end

local function compile(pathstring)
    return compile_dir(split_path(pathstring))
end

return {
    compile_url = compile_url,
    compile_dir = compile_dir,
    compile = compile,
}
