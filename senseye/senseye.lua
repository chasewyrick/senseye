--
-- Copyright: 2015-2016, Björn Ståhl
-- License: 3-Clause BSD
-- Reference: http://senseye.arcan-fe.com
-- Description: Senseye-ui, built on a stripped version of durden.
--
EVENT_SYNCH = {};

local wnd_create_handler, update_default_font;

local argv_cmds = {};

-- track custom buttons that should be added to each window
local tbar_btns = {
};

-- count initial delay before idle shutdown
local ievcount = 0;

-- replace the normal assert function one that can provide a traceback
local oldass = assert;
function assert(...)
	oldass(..., debug.traceback("assertion failed", 2));
end

function senseye(argv)
	system_load("mouse.lua")(); -- mouse gestures
	system_load("gconf.lua")(); -- configuration management
	system_load("shdrmgmt.lua")(); -- shader format parser, builder
	system_load("uiprim.lua")(); -- ui primitives (buttons!)
	system_load("lbar.lua")(); -- used to navigate menus
	system_load("bbar.lua")(); -- input binding
	system_load("suppl.lua")(); -- convenience functions

	update_default_font();

	system_load("keybindings.lua")(); -- static key configuration
	system_load("tiler.lua")(); -- window management
	system_load("iostatem.lua")(); -- input repeat delay/period
	system_load("extevh.lua")(); -- handlers for external events
	CLIPBOARD = system_load("clipboard.lua")(); -- clipboard filtering / mgmt
	CLIPBOARD:load("clipboard_data.lua");

-- functions exposed to user through menus, binding and scripting

	system_load("fglobal.lua")(); -- tiler- related global functions
	system_load("menus/global/global.lua")(); -- desktop related global
	system_load("menus/target/target.lua")(); -- shared window related global

-- load builtin features and 'extensions'
	local res = glob_resource("builtin/*.lua", APPL_RESOURCE);
	for k,v in ipairs(res) do
		local res = system_load("builtin/" .. v, false);
		if (res) then
			res();
		else
			warning(string.format("couldn't load builtin (%s)", v));
		end
	end

-- can't work without a detected keyboard
	if (not input_capabilities().translated) then
		warning("arcan reported no available translation capable devices "
			.. "(keyboard), cannot continue without one.\n");
		return shutdown("", EXIT_FAILURE);
	end

	SYMTABLE = system_load("symtable.lua")();
	SYMTABLE:load_translation();

	if (gconfig_get("mouse_hardlock")) then
		toggle_mouse_grab(MOUSE_GRABON);
	end

	if (gconfig_get("mouse_mode") == "native") then
		mouse_setup_native(load_image("cursor/default.png"), 0, 0);
	else
-- 65531..5 is a hidden max_image_order range (for cursors, overlays..)
		mouse_setup(load_image("cursor/default.png"), 65535, 1, true, false);
	end

	TILER = tiler_create(VRESW, VRESH, {scalef = VPPCM / 38.4});
	TILER.on_wnd_create = wnd_create_handler;

-- this opens up the 'senseye' external listening point, removing it means
-- only user-input controlled execution through configured database and browse
	local cp = gconfig_get("extcon_path");
	if (cp ~= nil and string.len(cp) > 0 and cp ~= ":disabled") then
		senseye_new_connection();
	end

-- add hooks for changes to all default  font properties
	gconfig_listen("font_def", "deffonth", update_default_font);
	gconfig_listen("font_sz", "deffonth", update_default_font);
	gconfig_listen("font_hint", "font_hint", update_default_font);
	gconfig_listen("font_fb", "font_fb", update_default_font);
	gconfig_listen("lbar_tpad", "padupd", update_default_font);
	gconfig_listen("lbar_bpad", "padupd", update_default_font);

-- preload cursor states
	mouse_add_cursor("drag", load_image("cursor/drag.png"), 0, 0); -- 7, 5);
	mouse_add_cursor("grabhint", load_image("cursor/grabhint.png"), 0, 0); --, 7, 10);
	mouse_add_cursor("rz_diag_l", load_image("cursor/rz_diag_l.png"), 0, 0); --, 6, 5);
	mouse_add_cursor("rz_diag_r", load_image("cursor/rz_diag_r.png"), 0, 0); -- , 6, 6);
	mouse_add_cursor("rz_down", load_image("cursor/rz_down.png"), 0, 0); -- 5, 13);
	mouse_add_cursor("rz_left", load_image("cursor/rz_left.png"), 0, 0); -- 0, 5);
	mouse_add_cursor("rz_right", load_image("cursor/rz_right.png"), 0, 0); -- 13, 5);
	mouse_add_cursor("rz_up", load_image("cursor/rz_up.png"), 0, 0); -- 5, 0);
	switch_default_texfilter(FILTER_NONE);

	audio_gain(BADID, gconfig_get("global_gain"));

-- load saved keybindings
	dispatch_load();
	iostatem_init();

-- hook some API functions for debugging purposes
	if (DEBUGLEVEL > 0) then
		local oti = target_input;
		target_input = function(dst, tbl)
			if (active_display().debug_console) then
				active_display().debug_console:add_input(tbl, dst);
			end
			oti(dst, tbl);
		end
	end

	for i,v in ipairs(argv) do
		if (argv_cmds[v]) then
			argv_cmds[v]();
		end
	end

-- process user- configuration commands
	local cmd = system_load("autorun.lua", 0);
	if (type(cmd) == "function") then
		cmd();
	end
end

function active_display()
	return TILER;
end

update_default_font = function(key, val)
	local font = (key and key == "font_def") and val or gconfig_get("font_def");
	local sz = (key and key == "font_sz") and val or gconfig_get("font_sz");
	local hint = (key and key == "font_hint") and val or gconfig_get("font_hint");
	local fbf = (key and key == "font_fb") and val or gconfig_get("font_fb");

	system_defaultfont(font, sz, hint);

-- with the default font reset, also load a fallback one
	if (fbf and resource(fbf, SYS_FONT_RESOURCE)) then
		system_defaultfont(fbf, sz, hint, 1);
	end

-- centering vertically on fonth will look poor on fonts that has a
-- pronounced ascent / descent and with scale factors etc. it is a lot of tedium
-- to try and probe the metrics. Go with user-definable top and bottom padding.
	local vid, lines, w, fonth, asc = render_text("\\f,0\\#ffffff gijy1!`");
	local rfh = fonth;
	local props = image_surface_properties(vid);
	delete_image(vid);

	gconfig_set("sbar_sz", fonth + gconfig_get("sbar_tpad") + gconfig_get("sbar_bpad"));
	gconfig_set("tbar_sz", fonth + gconfig_get("tbar_tpad") + gconfig_get("tbar_bpad"));
	gconfig_set("lbar_sz", fonth + gconfig_get("lbar_tpad") + gconfig_get("lbar_bpad"));
	gconfig_set("lbar_caret_h", fonth);

	if (not all_tilers_iter) then
		return;
	end

	for disp in all_tilers_iter() do
		disp.font_sf = rfhf;
		disp:update_scalef(disp.scalef);
	end

-- also propagate to each window so that it may push descriptors and
-- size information to any external connections
	for wnd in all_windows() do
		wnd:update_font(sz, hint, font);
		wnd:set_title(wnd.title_text and wnd.title_text or "");
		wnd:resize(wnd.width, wnd.height);
	end
end

-- need these event handlers here since it ties together modules that should
-- be separated code-wise, as we want tiler- and other modules to be reusable
-- in less complex projects
local function tile_changed(wnd, neww, newh, efw, efh)
	if (not neww or not newh) then
		return;
	end

	if (neww > 0 and newh > 0) then
		if (valid_vid(wnd.external, TYPE_FRAMESERVER)) then
			local props = image_storage_properties(wnd.external);

-- ignore resize- step limit (terminal) if we are not in drag resize
			if (not mouse_state().drag or not wnd.sz_delta or
				(math.abs(props.width - efw) > wnd.sz_delta[1] or
			   math.abs(props.height - newh) > wnd.sz_delta[2])) then
				target_displayhint(wnd.external, efw, efh, wnd.dispmask);
			end
		end

		if (valid_vid(wnd.titlebar_id)) then
			target_displayhint(wnd.titlebar_id,
				wnd.width - wnd.border_w * 2, gconfig_get("tbar_sz"));
		end
	end
end

function senseye_tbar_buttons(dir, cmd, lbl)
	if (not dir) then
		tbar_btns = {};
	else
		table.insert(tbar_btns, {
			dir = dir, cmd = cmd, lbl = lbl
		});
	end
end

-- tiler does not automatically add any buttons to the statusbar, or take
-- other tracking actions based on window creation so we do that here
wnd_create_handler = function(wm, wnd)
	for k,v in ipairs(tbar_btns) do
		wnd.titlebar:add_button(v.dir, "titlebar_iconbg",
			"titlebar_icon", v.lbl, gconfig_get("sbar_tpad") * wm.scalef,
			wm.font_resfn, nil, nil, {
-- many complications hidden here as tons of properties can be changed between
-- dispatch_symbol and "restore old state"
				click = function(btn)
					local old_sel = wm.selected;
					wnd:select();
					dispatch_symbol(v.cmd);
					if (old_sel and old_sel.select) then
						old_sel:select();
					end
				end,
				over = function(btn)
					btn:switch_state("alert");
				end,
				out = function(btn)
					btn:switch_state(wm.selected == wnd and "active" or "inactive");
				end
			}
		);
	end
end

-- there is a ton of "per window" input state when it comes to everything from
-- active translation tables, to diacretic traversals, to repeat-rate and
-- active analog/digital devices.
local function sel_input(wnd)
	local cnt = 0;
	SYMTABLE:translation_overlay(wnd.u8_translation);
	iostatem_restore(wnd.iostatem);
end

local function desel_input(wnd)
	SYMTABLE:translation_overlay({});
	wnd.iostatem = iostatem_save();
	mouse_switch_cursor("default");
end

-- useful for terminal where we can possibly avoid a resize and
-- the added initial delay by setting the size in beforehand
function durden_prelaunch()
	local nsurf = null_surface(32, 32);
	return active_display():add_window(nsurf);
end

function rebalance_space(space)
	if (#space.children == 1) then
		return;
	end

	if (#space.children == 2) then
		space.children[1].weight = 0.5;
		space.children[2].weight = 2.0;
	else
		space.children[1].weight = 0.5;
		space.children[2].weight = 2.0;
		space.children[3].weight = 0.5;
		local rec = nil;
		rec = function(node)
			node:merge();
			if (node.children[1]) then
				rec(node.children[1]);
			end
		end
		rec(space.children[3]);
		space:resize();
	end

	space:set_label(title and title or "");
	space:activate();
end

-- we have received both a sensor and it's parent window --
-- assign a space and begin setting up.
function senseye_launch(wnd, subvid)
	for i=1,10 do
		if (not TILER.spaces[i] or not TILER.spaces[i].sensor) then
			TILER:switch_ws(i);
			TILER.spaces[i].sensor = subvid;
			stepframe_target(subvid, 1);
			wnd.hide_titlebar = true;
			wnd.scalemode = "stretch";
			wnd.autocrop = false;
			wnd:resize(wnd.width, wnd.height);
			wnd:assign_ws(i);
			wnd.delete_protect = true;
-- make sure the navigation window is the leftmost one
			if (TILER.spaces[i].children[1] ~= wnd) then
				wnd:swap(TILER.spaces[i].children[1]);
			end

			wnd:select();
			TILER.spaces[i].insert = "h";
			local neww = TILER:add_window(subvid);
			neww.delete_protect = true;
			neww:set_title(title and title or "");
			neww.scalemode = "stretch";

-- divide the ration [20% 60% 20% or 20% 80% 0%] depending on
-- the number of windows, then we start stacking vertical.
			rebalance_space(TILER.spaces[i]);
			return;
		end
	end
	wnd:destroy();

-- out of workspaces
	if (valid_vid(subvid)) then
		delete_image(subvid);
	end
end

function durden_launch(vid, prefix, title, wnd)
	if (not valid_vid(vid)) then
		return;
	end
	if (not wnd) then
		wnd = active_display():add_window(vid);
	end

-- local keybinding->utf8 overrides, we map this to SYMTABLE
	wnd.u8_translation = {};

-- window aesthetics
	wnd:set_prefix(prefix);
	wnd:set_title(title and title or "?");
	wnd:add_handler("resize", tile_changed);
	wnd:add_handler("select", sel_input);
	wnd:add_handler("deselect", desel_input);
	show_image(wnd.canvas);

-- may use this function to launch / create some internal window
-- that don't need all the external dispatch stuff, so make sure
	if (valid_vid(vid, TYPE_FRAMESERVER)) then
		wnd.dispatch = shared_dispatch();
		wnd.external = vid;
		extevh_register_window(vid, wnd);
		EVENT_SYNCH[wnd.canvas] = {
			queue = {},
			target = vid
		};
	end

	rebalance_space(TILER.spaces[TILER.space_ind]);
	return wnd;
end

function senseye_new_connection(source, status)
	if (status == nil or status.kind == "connected") then
		INCOMING_ENDPOINT = target_alloc(
			gconfig_get("extcon_path"), senseye_new_connection);
		if (valid_vid(INCOMING_ENDPOINT)) then
			image_tracetag(INCOMING_ENDPOINT, "nonauth_connection");
		end
		if (status) then
			for k,v in pairs(status) do print(k, v); end
			durden_launch(source, "", "external");
		end
	end
end

local mid_c = 0;
local mid_v = {0, 0};

local function mousemotion(iotbl)
-- we prefer relative mouse coordinates for proper warping etc.
-- but not all platforms can deliver on that promise and these are
-- split BY AXIS but delivered in pairs (stupid legacy) so we have to
-- merge.
	if (iotbl.relative) then
		if (iotbl.subid == 0) then
			mouse_input(iotbl.samples[2], 0);
		else
			mouse_input(0, iotbl.samples[2]);
		end
	else
		mid_v[iotbl.subid+1] = iotbl.samples[1];
		mid_c = mid_c + 1;

		if (mid_c == 2) then
			mouse_absinput(mid_v[1], mid_v[2]);
			mid_c = 0;
		end
	end
end

-- shared between the other input forms (normal, locked, ...)
function senseye_iostatus_handler(iotbl)
	active_display():message(string.format("%d:%d %s",
		iotbl.devid, iotbl.subid, iotbl.action));

	if (iotbl.action == "added") then
		iostatem_added(iotbl);
	elseif (iotbl.action == "removed") then
		iostatem_removed(iotbl);
	end
end

function VRES_AUTORES(w, h, vppcm, flags, source)
	resize_video_canvas(w, h);
	TILER:resize(w, h, true);
end

function senseye_normal_input(iotbl, fromim)
-- we track all iotbl events in full debug mode
	if (DEBUGLEVEL > 2 and active_display().debug_console) then
		active_display().debug_console:add_input(iotbl);
	end

	if (iotbl.kind == "status") then
		senseye_iostatus_handler(iotbl);
		return;
	end

	ievcount = ievcount + 1;

-- iostate manager takes care of mapping or translating 'game' devices,
-- stateful "per window" tracking and "autofire" or "repeat" injections
-- but tries to ignore mouse devices.
	if (not fromim) then
		if (iostatem_input(iotbl)) then
			return;
		end
	end

-- then we forward keyboard events into the dispatch function, this applies
-- translations, bindings and symtable mapping. Returns information if the
-- event was consumed by some UI features (ok true) or what the internal string
-- representation is (m1_m2_LEFT) and the patched iotbl. It will also apply any
-- per-display hook active at the moment (lbar, bbar uses those). It also runs
-- the meta-guard evaluation to try and figure out if the user seems unaware of
-- his keybindings.
	local ok, outsym, iotbl = dispatch_translate(iotbl);
	if (iotbl.digital) then
		if (ok) then
			return;
		end
	end

-- after that we have special handling for mouse motion and presses,
-- any forwarded input there is based on event reception in listeners
-- attached to mouse motion or presses.
	if (iotbl.mouse) then
		if (iotbl.digital) then
			mouse_button_input(iotbl.subid, iotbl.active);
		else
			mousemotion(iotbl);
		end
		return;
	end

-- still a window alived but no input has consumed it? then we forward
-- to the external- handler
	local sel = active_display().selected;
	if (not sel or not valid_vid(sel.external, TYPE_FRAMESERVER)) then
		return;
	end

-- there may be per-window label tabel for custom input labels,
-- those need to be applied still.
	target_input(sel.external, iotbl);
end

-- special case: (UP, DOWN, LEFT, RIGHT + mouse motion is mapped to
-- manipulate the mouse_select_begin() mouse_select_end() region,
-- ESCAPE cancels the mode, end runs whatever trigger we set (global).
-- see 'select_region_*' global functions + some button to align
-- with selected window (if any, like m1 and m2)
function senseye_regionsel_input(iotbl)
	if (iotbl.kind == "status") then
		senseye_iostatus_handler(iotbl);
		return;
	end

	if (iotbl.translated and iotbl.active) then
		local sym, lutsym = SYMTABLE:patch(iotbl);

		if (SYSTEM_KEYS["cancel"] == sym) then
			mouse_select_end();
			iostatem_restore();
			senseye_input = senseye_normal_input;
		elseif (SYSTEM_KEYS["accept"] == sym) then
			mouse_select_end(senseye_REGIONSEL_TRIGGER);
			iostatem_restore();
			senseye_input = senseye_normal_input;
		elseif (SYSTEM_KEYS["meta_1"] == sym) then
			mouse_select_set();
		elseif (SYSTEM_KEYS["meta_2"] == sym) then
			local rt = active_display(true);
			local mx, my = mouse_xy();
			local items = pick_items(mx, my, 1, true, rt);
			if (#items > 0) then
				mouse_select_set(items[1]);
			end
		end

	elseif (iotbl.mouse) then
		if (iotbl.digital) then
			mouse_select_end(senseye_REGIONSEL_TRIGGER);
			iostatem_restore();
			senseye_input = senseye_normal_input;
		else
			mousemotion(iotbl);
		end
	end
end

senseye_input = senseye_normal_input;

function senseye_shutdown()
	SYMTABLE:store_translation();
	CLIPBOARD:save("clipboard_data.lua");
	gconfig_shutdown();
end

local function flush_pending()
	for k,v in pairs(EVENT_SYNCH) do
		if (valid_vid(v.target)) then
			if (v.queue) then
				for i,j in ipairs(v.queue) do
					target_input(v.target, j);
				end
				v.queue = {};
			end
			if (v.pending and #v.pending > 0) then
				for i,j in ipairs(v.pending) do
					target_input(v.target, j);
				end
				v.pending = nil;
			end
		end
	end
end

function senseye_clock_pulse(n, nt)
-- if we experience stalls that give us multiple batched ticks
-- we don't want to forward this to the iostatem_ as that can
-- generate storms of repeats
	if (nt == 1) then
		local tt = iostatem_tick();
		if (tt) then
			for k,v in ipairs(tt) do
				senseye_input(v, true);
			end
		end
	end

	flush_pending();
	mouse_tick(1);
end
