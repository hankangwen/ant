-- TODO: should move to scene package

local ecs = ...
local world = ecs.world
local w     = world.w

local viewidmgr = require "viewid_mgr"

local mc 		= import_package "ant.math".constant
local math3d	= require "math3d"
local bgfx		= require "bgfx"
local icamera	= ecs.import.interface "ant.camera|icamera"
local ishadow	= ecs.import.interface "ant.render|ishadow"
local irender	= ecs.import.interface "ant.render|irender"
local iom		= ecs.import.interface "ant.objcontroller|iobj_motion"
local fbmgr		= require "framebuffer_mgr"

local INV_Z<const> = true
-- local function create_crop_matrix(shadow)
-- 	local view_camera = world.main_queue_camera(world)

-- 	local csm = shadow.csm
-- 	local csmindex = csm.index
-- 	local shadowcamera = world[shadow.camera_ref].camera
-- 	local shadow_viewmatrix = mu.view_proj(shadowcamera)

-- 	local bb_LS = get_frustum_points(view_camera, view_camera.frustum, shadow_viewmatrix, shadow.csm.split_ratios)
-- 	local aabb = bb_LS:get "aabb"
-- 	local min, max = aabb.min, aabb.max

-- 	local proj = math3d.projmat(shadowcamera.frustum)
-- 	local minproj, maxproj = math3d.transformH(proj, min) math3d.transformH(proj, max)

-- 	local scalex, scaley = math3d.mul(2, math3d.reciprocal(math3d.sub(maxproj, minproj)))
-- 	if csm.stabilize then
-- 		local quantizer = shadow.shadowmap_size
-- 		scalex = quantizer / math.ceil(quantizer / scalex);
-- 		scaley = quantizer / math.ceil(quantizer / scaley);
-- 	end

-- 	local function calc_offset(a, b, scale)
-- 		return (a + b) * 0.5 * scale
-- 	end

-- 	local offsetx, offsety = 
-- 		calc_offset(maxproj[1], minproj[1], scalex), 
-- 		calc_offset(maxproj[2], minproj[2], scaley)

-- 	if csm.stabilize then
-- 		local half_size = shadow.shadowmap_size * 0.5;
-- 		offsetx = math.ceil(offsetx * half_size) / half_size;
-- 		offsety = math.ceil(offsety * half_size) / half_size;
-- 	end
	
-- 	return {
-- 		scalex, 0, 0, 0,
-- 		0, scaley, 0, 0,
-- 		0, 0, 1, 0,
-- 		offsetx, offsety, 0, 1,
-- 	}
-- end

local function keep_shadowmap_move_one_texel(minextent, maxextent, shadowmap_size)
	local texsize = 1 / shadowmap_size

	local unit_pretexel = math3d.mul(math3d.sub(maxextent, minextent), texsize)
	local invunit_pretexel = math3d.reciprocal(unit_pretexel)

	local function limit_move_in_one_texel(value)
		-- value /= unit_pretexel;
		-- value = floor( value );
		-- value *= unit_pretexel;
		return math3d.tovalue(
			math3d.mul(math3d.floor(math3d.mul(value, invunit_pretexel)), unit_pretexel))
	end

	local newmin = limit_move_in_one_texel(minextent)
	local newmax = limit_move_in_one_texel(maxextent)
	
	minextent[1], minextent[2] = newmin[1], newmin[2]
	maxextent[1], maxextent[2] = newmax[1], newmax[2]
end

local csm_matrices			= {mc.IDENTITY_MAT, mc.IDENTITY_MAT, mc.IDENTITY_MAT, mc.IDENTITY_MAT}
local split_distances_VS	= math3d.ref(math3d.vector(0, 0, 0, 0))

local function update_camera_matrices(camera, lightmat)
	camera.viewmat	= math3d.inverse(lightmat)	--just transpose?
	camera.projmat	= math3d.projmat(camera.frustum, INV_Z)
	camera.viewprojmat = math3d.mul(camera.projmat, camera.viewmat)
end

local function set_worldmat(srt, mat)
	math3d.unmark(srt.worldmat)
	srt.worldmat = math3d.mark(math3d.matrix(mat))
end

local function calc_shadow_camera_from_corners(corners_WS, lightdir, shadowmap_size, stabilize, shadow_ce)
	local center_WS = math3d.points_center(corners_WS)
	local min_extent, max_extent

	iom.set_rotation(shadow_ce, math3d.torotation(lightdir))
	iom.set_position(shadow_ce, center_WS)
	set_worldmat(shadow_ce.scene, shadow_ce.scene)

	local camera = shadow_ce.camera
	if stabilize then
		local radius = math3d.points_radius(corners_WS, center_WS)
		--radius = math.ceil(radius * 16.0) / 16.0	-- round to 16
		min_extent, max_extent = {-radius, -radius, -radius}, {radius, radius, radius}
		keep_shadowmap_move_one_texel(min_extent, max_extent, shadowmap_size)
	else
		local minv, maxv = math3d.minmax(corners_WS, math3d.inverse(shadow_ce.scene.worldmat))
		min_extent, max_extent = math3d.tovalue(minv), math3d.tovalue(maxv)
	end

	local f = camera.frustum
	f.l, f.b, f.n = min_extent[1], min_extent[2], min_extent[3]
	f.r, f.t, f.f = max_extent[1], max_extent[2], max_extent[3]
	update_camera_matrices(camera, shadow_ce.scene.worldmat)

	do
		-- local ident_projmat = math3d.projmat{
		-- 	ortho=true,
		-- 	l=-1, r=1, b=-1, t=1, n=-100, f=100,
		-- }

		-- local minv, maxv = math3d.minmax(corners_WS, camera_rc.viewmat)
		-- local minv_proj, maxv_proj = math3d.transformH(ident_projmat, minv, 1), math3d.transformH(ident_projmat, maxv, 1)
		-- -- scale = 2 / (maxv_proj-minv_proj)
		-- local scale = math3d.mul(2, math3d.reciprocal(math3d.sub(maxv_proj, minv_proj)))
		-- -- offset = 0.5 * (minv_proj+maxv_proj) * scale
		-- local offset = math3d.mul(scale, math3d.mul(0.5, math3d.add(minv_proj, maxv_proj)))
		-- local scalex, scaley = math3d.index(scale, 1, 2)
		-- local offsetx, offsety = math3d.index(offset, 1, 2)
		-- local lightproj = math3d.mul(math3d.matrix(
		-- scalex, 0.0, 	0.0, 0.0,
		-- 0.0,	scaley,	0.0, 0.0,
		-- 0.0,	0.0,	1.0, 0.0,
		-- offsetx,offsety,0.0, 1.0
		-- ), ident_projmat)

		-- camera_rc.projmat = lightproj
		-- camera_rc.viewprojmat = math3d.mul(camera_rc.projmat, camera_rc.viewmat)
	end
end

local function calc_shadow_camera(viewmat, frustum, lightdir, shadowmap_size, stabilize, shadow_ce)
	local vp = math3d.mul(math3d.projmat(frustum, INV_Z), viewmat)

	local corners_WS = math3d.frustum_points(vp)
	calc_shadow_camera_from_corners(corners_WS, lightdir, shadowmap_size, stabilize, shadow_ce)
end

-- local function calc_split_distance(frustum)
-- 	local corners_VS = math3d.frustum_points(math3d.projmat(frustum))
-- 	local minv, maxv = math3d.minmax(corners_VS)
-- 	return math3d.index(maxv, 3)
-- end

local function calc_csm_matrix_attrib(csmidx, vp)
	return math3d.mul(ishadow.crop_matrix(csmidx), vp)
end

local function update_shadow_camera(dl, maincamera)
	local lightdir = iom.get_direction(dl)
	local setting = ishadow.setting()
	local viewmat = maincamera.viewmat
	for qe in w:select "csm_queue camera_ref:in csm:in" do
		local csm = qe.csm
		local vf = csm.view_frustum
		local shadow_ce = world:entity(qe.camera_ref)
		calc_shadow_camera(viewmat, vf, lightdir, setting.shadowmap_size, setting.stabilize, shadow_ce)
		csm_matrices[csm.index] = calc_csm_matrix_attrib(csm.index, shadow_ce.camera.viewprojmat)
		--split_distances_VS[csm.index] = vf.f
	end
end

local sm = ecs.system "shadow_system"

local function create_clear_shadowmap_queue(fbidx)
	local rb = fbmgr.get_rb(fbidx, 1)
	local ww, hh = rb.w, rb.h
	ecs.create_entity{
		policy = {
			"ant.render|postprocess_queue",
			"ant.general|name",
		},
		data = {
			render_target = {
				clear_state = {
					color = 0xffffffff,
					depth = 0,
					clear = "D",
				},
				fb_idx = fbidx,
				viewid = viewidmgr.get "csm_fb",
				view_rect = {x=0, y=0, w=ww, h=hh},
			},
			queue_name = "clear_sm",
			name = "clear_sm",
		}
	}
end

local function create_csm_entity(index, vr, fbidx)
	local csmname = "csm" .. index
	local queuename = "csm_queue" .. index
	local camera_ref = icamera.create {
			updir 	= mc.YAXIS,
			viewdir = mc.ZAXIS,
			eyepos 	= mc.ZERO_PT,
			frustum = {
				l = -1, r = 1, t = -1, b = 1,
				n = 1, f = 100, ortho = true,
			},
			name = csmname
		}

	w:register {name = queuename}
	ecs.create_entity {
		policy = {
			"ant.render|render_queue",
			"ant.render|cull",
			"ant.render|csm_queue",
			"ant.general|name",
		},
		data = {
			csm = {
				index = index,
			},
			camera_ref = camera_ref,
			render_target = {
				viewid = viewidmgr.get(csmname),
				view_mode = "s",
				view_rect = {x=vr.x, y=vr.y, w=vr.w, h=vr.h},
				clear_state = {
					clear = "",
				},
				fb_idx = fbidx,
			},
			primitive_filter = {
				filter_type = "cast_shadow",
				"opacity",
			},
			cull_tag = {},
			visible = false,
			queue_name = queuename,
			csm_queue = true,
			name = "csm" .. index,
		},
	}
end

local shadow_material
local gpu_skinning_material
local imaterial = ecs.import.interface "ant.asset|imaterial"
function sm:init()
	local fbidx = ishadow.fb_index()
	local s = ishadow.shadowmap_size()
	create_clear_shadowmap_queue(fbidx)
	local originmatrial = "/pkg/ant.resources/materials/depth.material"
	shadow_material = imaterial.load(originmatrial)
	gpu_skinning_material = imaterial.load(originmatrial, {skinning="GPU"})
	for ii=1, ishadow.split_num() do
		local vr = {x=(ii-1)*s, y=0, w=s, h=s}
		create_csm_entity(ii, vr, fbidx)
	end
end

local shadow_camera_rebuild = false
local mq_camera_mb = world:sub{"main_queue", "camera_changed"}
local camera_scene_mb
local camera_changed_mb
local function update_camera_changed_mailbox(camera_ref)
	camera_scene_mb = world:sub{"scene_changed", camera_ref}
	camera_changed_mb = world:sub{"camera_changed", camera_ref}
end

local function main_camera_changed(ceid)
	local mc = world:entity(ceid)
	local mccamera = mc.camera
	local viewfrustum = mccamera.frustum
	local csmfrustums = ishadow.calc_split_frustums(viewfrustum)
	for cqe in w:select "csm:in" do
		local csm = cqe.csm
		local idx = csm.index
		local cf = csmfrustums[csm.index]
		csm.view_frustum = cf
		split_distances_VS[idx] = cf.f
	end
	update_camera_changed_mailbox(ceid)
end

local function set_csm_visible(enable)
	for v in w:select "csm_queue visible?out" do
		v.visible = enable
	end
end

function sm:entity_init()
	for e in w:select "INIT main_queue camera_ref:in" do
		main_camera_changed(e.camera_ref)
		shadow_camera_rebuild = true
	end

	for msg in mq_camera_mb:each() do
		main_camera_changed(msg[3])
		shadow_camera_rebuild = true
	end

	for e in w:select "INIT make_shadow directional_light light:in" do
		local csm_dl = w:singleton("csm_directional_light", "light:in")
		if csm_dl == nil then
			e.csm_directional_light = true
			w:sync("csm_directional_light?out", e)
			set_csm_visible(true)

			shadow_camera_rebuild = true
		else
			error("already have 'make_shadow' directional light")
		end
	end
end

function sm:entity_remove()
	for _ in w:select "REMOVED csm_directional_light" do
		set_csm_visible(false)
	end
end

function sm:data_changed()
	local dl = w:singleton("csm_directional_light", "light:in")
	if dl then
		for _ in camera_scene_mb:each() do
			shadow_camera_rebuild = true
		end

		for _ in camera_changed_mb:each() do
			shadow_camera_rebuild = true
		end
	end
end

local function commit_csm_matrices_attribs()
	local sa = imaterial.system_attribs()
	sa:update("u_csm_matrix", csm_matrices)
	sa:update("u_csm_split_distances", split_distances_VS)
end

function sm:init_world()
	local sa = imaterial.system_attribs()
	sa:update("s_shadowmap", fbmgr.get_rb(ishadow.fb_index(), 1).handle)

	sa:update("u_shadow_param1", math3d.vector(ishadow.shadow_param()))
	sa:update("u_shadow_param2", ishadow.color())
end

function sm:update_camera()
	local dl = w:singleton("csm_directional_light", "light:in scene:in")
	if dl then
		if shadow_camera_rebuild then
			local mq = w:singleton("main_queue", "camera_ref:in")
			local camera = world:entity(mq.camera_ref)
			update_shadow_camera(dl, camera.camera)
			shadow_camera_rebuild = false
		else
			for qe in w:select "csm_queue csm:in camera_ref:in" do
				local cref = qe.camera_ref
				local ce = world:entity(cref)
				local camera = ce.camera
				update_camera_matrices(camera, ce.scene.worldmat)
				local idx = qe.csm.index
				csm_matrices[idx] = calc_csm_matrix_attrib(idx, camera.viewprojmat)
			end
		end

		commit_csm_matrices_attribs()
	end
end

function sm:refine_camera()
	-- local setting = ishadow.setting()
	-- for se in w:select "csm_queue primitive_filter:in"
	-- 	local se = world[eid]
	-- assert(false && "should move code new ecs")
	-- 		local filter = se.primitive_filter.result
	-- 		local sceneaabb = math3d.aabb()
	
	-- 		local function merge_scene_aabb(sceneaabb, filtertarget)
	-- 			for _, item in ipf.iter_target(filtertarget) do
	-- 				if item.aabb then
	-- 					sceneaabb = math3d.aabb_merge(sceneaabb, item.aabb)
	-- 				end
	-- 			end
	-- 			return sceneaabb
	-- 		end
	
	-- 		sceneaabb = merge_scene_aabb(sceneaabb, filter.opacity)
	-- 		sceneaabb = merge_scene_aabb(sceneaabb, filter.translucent)
	
	-- 		if math3d.aabb_isvalid(sceneaabb) then
	-- 			local camera_rc = world[se.camera_ref]._rendercache
	
	-- 			local function calc_refine_frustum_corners(rc)
	-- 				local frustm_points_WS = math3d.frustum_points(rc.viewprojmat)
	-- 				local frustum_aabb_WS = math3d.points_aabb(frustm_points_WS)
		
	-- 				local scene_frustum_aabb_WS = math3d.aabb_intersection(sceneaabb, frustum_aabb_WS)
	-- 				local max_frustum_aabb_WS = math3d.aabb_merge(sceneaabb, frustum_aabb_WS)
	-- 				local _, extents = math3d.aabb_center_extents(scene_frustum_aabb_WS)
	-- 				extents = math3d.mul(0.1, extents)
	-- 				scene_frustum_aabb_WS = math3d.aabb_expand(scene_frustum_aabb_WS, extents)
					
	-- 				local max_frustum_aabb_VS = math3d.aabb_transform(rc.viewmat, max_frustum_aabb_WS)
	-- 				local max_n, max_f = math3d.index(math3d.index(max_frustum_aabb_VS, 1), 3), math3d.index(math3d.index(max_frustum_aabb_VS, 2), 3)
	
	-- 				local scene_frustum_aabb_VS = math3d.aabb_transform(rc.viewmat, scene_frustum_aabb_WS)
	
	-- 				local minv, maxv = math3d.index(scene_frustum_aabb_VS, 1), math3d.index(scene_frustum_aabb_VS, 2)
	-- 				minv, maxv = math3d.set_index(minv, 3, max_n), math3d.set_index(maxv, 3, max_f)
	-- 				scene_frustum_aabb_VS = math3d.aabb(minv, maxv)
					
	-- 				scene_frustum_aabb_WS = math3d.aabb_transform(rc.worldmat, scene_frustum_aabb_VS)
	-- 				return math3d.aabb_points(scene_frustum_aabb_WS)
	-- 			end
	
	-- 			local aabb_corners_WS = calc_refine_frustum_corners(camera_rc)
	
	-- 			local lightdir = math3d.index(camera_rc.worldmat, 3)
	-- 			calc_shadow_camera_from_corners(aabb_corners_WS, lightdir, setting.shadowmap_size, setting.stabilize, camera_rc)
	-- 		end
	-- end
end

function sm:render_submit()
	local viewid = viewidmgr.get "csm_fb"
	bgfx.touch(viewid)
end

local function which_material(skinning)
	return skinning and gpu_skinning_material or shadow_material
end

local omni_stencils = {
	[0] = bgfx.make_stencil{
		TEST="EQUAL",
		FUNC_REF = 0,
	},
	[1] = bgfx.make_stencil{
		TEST="EQUAL",
		FUNC_REF = 1,
	},
}

local s = ecs.system "shadow_primitive_system"

local material_cache = {__mode="k"}

function s:end_filter()
    for e in w:select "filter_result:in render_object:in skinning?in filter_material:in" do
        local ro = e.render_object
		local m = which_material(e.skinning)
		local dst_mi, fx = m.material, m.fx
		local newstate = irender.check_set_state(dst_mi, ro.material)
		local new_matobj = irender.create_material_from_template(dst_mi:get_material(), newstate, material_cache)
		local fm = e.filter_material
		local fr = e.filter_result
		for qe in w:select "csm_queue primitive_filter:in" do
			for _, fn in ipairs(qe.primitive_filter) do
				if fr[fn] then
					fm[fn] = {
						material = new_matobj:instance(),
						fx = fx,
					}
				end
			end
		end
	end
end
