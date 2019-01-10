-- luacheck: globals log bullet
local log = log and log(...) or print
local ecs = require "ecs"

--local elog = require "editor.log"
--local db = require "debugger"

-- --windows dir
-- asset.insert_searchdir(1, "D:/Engine/ant/assets")
-- --mac dir
-- asset.insert_searchdir(2, "/Users/ejoy/Desktop/Engine/ant/assets")


local util = {}
util.__index = util

local world = nil

local bullet_world = import_package "ant.bullet"

function util.start_new_world(input_queue, fbw, fbh, packages, systems)
	if input_queue == nil then
		log("input queue is not privided, no input event will be received!")
	end

	world = ecs.new_world {
		packages = packages,
		systems = systems,
		update_order = {"timesystem", "message_system"},
		args = { 
			mq = input_queue, 
			fb_size={w=fbw, h=fbh},			
			Physics = bullet_world.new(),
		},
    }
    return world
end

return util
