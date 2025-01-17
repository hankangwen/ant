local ecs = ...

local platform = require "bee.platform"
local ImGui = import_package "ant.imgui"
local rhwi = import_package "ant.hwi"
local assetmgr = import_package "ant.asset"
local inputmgr = import_package "ant.inputmgr"
local PM = require "programan.client"

local ltask = require "ltask"
local ServiceWindow = ltask.queryservice "ant.window|window"

local m = ecs.system 'imgui_system'

function m:init_system()
	ImGui.CreateContext()
	ImGui.io.ConfigFlags = ImGui.Flags.Config {
		"NavEnableKeyboard",
		"DockingEnable",
		"NavNoCaptureKeyboard",
		"DpiEnableScaleViewports",
		"DpiEnableScaleFonts",
		"NoMouseCursorChange",
	}
	ImGui.InitPlatform(rhwi.native_window())

	local imgui_font = assetmgr.load_material "/pkg/ant.imgui/materials/font.material"
	local imgui_image = assetmgr.load_material "/pkg/ant.imgui/materials/image.material"
	assetmgr.material_mark(imgui_font.fx.prog)
	assetmgr.material_mark(imgui_image.fx.prog)
	local viewId = rhwi.viewid_generate("imgui_eidtor" .. 1, "uiruntime")
	ImGui.InitRender {
		fontProg = PM.program_get(imgui_font.fx.prog),
		imageProg = PM.program_get(imgui_image.fx.prog),
		fontUniform = imgui_font.fx.uniforms.s_tex.handle,
		imageUniform = imgui_image.fx.uniforms.s_tex.handle,
		viewIdPool = { viewId },
	}
	if platform.os == "windows" then
		ImGui.FontAtlasAddFont {
			SystemFont = "Segoe UI Emoji",
			SizePixels = 18,
			GlyphRanges = { 0x23E0, 0x329F, 0x1F000, 0x1FA9F }
		}
		ImGui.FontAtlasAddFont {
			SystemFont = "黑体",
			SizePixels = 18,
			GlyphRanges = { 0x0020, 0xFFFF }
		}
	elseif platform.os == "macos" then
		ImGui.FontAtlasAddFont {
			SystemFont = "苹方-简",
			SizePixels = 18,
			GlyphRanges = { 0x0020, 0xFFFF }
		}
	else -- iOS
		ImGui.FontAtlasAddFont {
			SystemFont = "Heiti SC",
			SizePixels = 18,
			GlyphRanges = { 0x0020, 0xFFFF }
		}
	end
	inputmgr:enable_imgui()
end

function m:init_world()
	ImGui.FontAtlasBuild()
end

function m:exit()
	ImGui.DestroyRenderer()
	ImGui.DestroyPlatform()
	ImGui.DestroyContext()
end

local last_cursor = 0

function m:start_frame()
	local cursor = ImGui.GetMouseCursor()
	if last_cursor ~= cursor then
		last_cursor = cursor
		ltask.call(ServiceWindow, "setcursor", cursor)
	end
	ImGui.NewFrame()
end

function m:end_frame()
	ImGui.Render()
end
