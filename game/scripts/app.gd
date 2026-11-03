extends Node
## App — điều phối toàn bộ vòng đời: UI, world, kết nối phòng.
## Được đăng ký như autoload để mọi hệ thống có thể gọi App.toast(), App.open_computer()…

signal world_loaded(world: Nightclub)
signal world_unloaded()

var ui: CanvasLayer
var world: Nightclub
var booted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AppConfig.is_dedicated:
		_boot_dedicated_server()
		return
	for arg in AppConfig.launch_args:
		if arg == "--smoke":
			_run_smoke_test()
			return
		if arg == "--screenshot":
			_run_screenshots()
			return
		if arg.begins_with("--tv-test="):
			_run_tv_web_test(arg.trim_prefix("--tv-test="))
			return
		if arg == "--fs-test":
			_run_tv_fullscreen_test()
			return
		if arg == "--yt-fs-test" or arg.begins_with("--yt-fs-test="):
			var fs_url := "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
			if arg.begins_with("--yt-fs-test="):
				fs_url = arg.trim_prefix("--yt-fs-test=")
			_run_youtube_fullscreen_test(fs_url)
			return
		if arg == "--aim-test":
			_run_tv_aim_test()
			return
		if arg == "--computer-test":
			_run_computer_test()
			return
		if arg == "--click-test":
			_run_click_test()
			return
		if arg == "--embed-test" or arg.begins_with("--embed-test="):
			var embed_url := "https://www.youtube.com/watch?v=aqz-KE-bpKQ"
			if arg.begins_with("--embed-test="):
				embed_url = arg.trim_prefix("--embed-test=")
			_run_embed_test(embed_url)
			return
		if arg == "--perf-test":
			_run_perf_test()
			return
		if arg == "--hud-test":
			_run_hud_test()
			return
		if arg == "--character-test":
			_run_character_test()
			return
		if arg.begins_with("--net-smoke="):
			_run_net_smoke(arg.split("=")[1])
			return
	_boot_client()


func _boot_client() -> void:
	ui = preload("res://scripts/ui/ui_root.gd").new()
	ui.name = "UIRoot"
	add_child(ui)
	booted = true
	ui.call("boot")


func _boot_dedicated_server() -> void:
	print("[QBO] Khởi động dedicated server tại cổng %d" % AppConfig.game_port)
	_load_world({
		"code": OS.get_environment("QBO_ROOM_CODE"),
		"name": "Dedicated Nightclub",
		"map": "the_chrome_lotus",
		"maxPlayers": AppConfig.MAX_ROOM_PLAYERS,
	}, true)
	var ok := Net.start_server(AppConfig.game_port, AppConfig.MAX_ROOM_PLAYERS)
	if not ok:
		push_error("Không thể khởi động dedicated server.")
		get_tree().quit(1)


func _load_world(room_info: Dictionary, server_mode := false) -> Nightclub:
	unload_world()
	var instance: Nightclub = preload("res://scripts/world/nightclub.gd").new()
	instance.room_info = room_info
	instance.server_mode = server_mode
	add_child(instance)
	world = instance
	Net.server_world = instance if server_mode else null
	world_loaded.emit(instance)
	return instance


func unload_world() -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
	world = null
	Net.server_world = null
	world_unloaded.emit()


# ------------------------------------------------------------------ room lifecycle

func start_solo() -> void:
	var room := {
		"code": "SOLO",
		"name": "The Chrome Lotus — phòng offline",
		"map": "the_chrome_lotus",
		"maxPlayers": 1,
		"isPublic": false,
		"ownerId": "local",
	}
	GameState.set_room(room)
	_load_world(room, false)
	Net.start_solo(room)
	if ui != null:
		ui.call("enter_game")


func start_room(room: Dictionary, ticket: String, host: String, port: int) -> void:
	GameState.set_room(room)
	GameState.ticket = ticket
	_load_world(room, false)
	if ui != null:
		ui.call("enter_game")
	var ok := Net.connect_to_room(host, port, ticket)
	if not ok:
		toast("Không thể kết nối game server.", "error")
		await get_tree().create_timer(1.5).timeout
		leave_room()


func leave_room() -> void:
	if GameState.room.has("code") and GameState.is_logged_in() and str(GameState.room.get("code", "SOLO")) != "SOLO":
		Api.leave_room(str(GameState.room["code"]))
	Net.stop()
	GameState.clear_room()
	GameState.ticket = ""
	unload_world()
	if ui != null:
		ui.call("exit_game")


func return_to_menu() -> void:
	leave_room()


# ------------------------------------------------------------------ UI helpers

func toast(message: String, level := "info") -> void:
	GameState.toast_requested.emit(message, level)


func open_computer(tab := "browser") -> void:
	if ui != null:
		ui.call("open_overlay", "computer", {"tab": tab})


func open_dj_panel() -> void:
	if ui != null:
		ui.call("open_overlay", "dj", {})


func open_lighting_panel() -> void:
	if ui != null:
		ui.call("open_overlay", "lighting", {})


func open_tv_panel() -> void:
	if ui != null:
		ui.call("open_overlay", "computer", {"tab": "tv"})


func local_player() -> Node3D:
	if world == null:
		return null
	return world.players.get(Net.local_peer_id)


# ------------------------------------------------------------------ smoke tests (headless)

func _run_smoke_test() -> void:
	print("[SMOKE] Bắt đầu kiểm tra offline client")
	var failures: Array = []
	var started := Time.get_ticks_msec()
	start_solo()
	await get_tree().create_timer(0.8).timeout
	if world == null:
		failures.append("world không được tạo")
	else:
		print("[SMOKE] interactables=%d players=%d lights=%d" % [world.interactables.size(), world.players.size(), world.lighting._groups.get("moving_head", []).size()])
		if world.interactables.size() < 20:
			failures.append("quá ít interactable (%d)" % world.interactables.size())
		if world.players.size() != 1:
			failures.append("local player không spawn")
		if world.lighting == null:
			failures.append("thiếu LightingController")
		if world.dj == null:
			failures.append("thiếu DJSystem")
		if world.tv == null:
			failures.append("thiếu TVSystem")
	if world != null:
		world.lighting.apply_preset("edm", 1.2, 1.4)
		await get_tree().create_timer(0.2).timeout
		if world.lighting.current_preset != "edm":
			failures.append("không đổi được preset ánh sáng")
		world.dj.ensure_default_track()
		await get_tree().create_timer(0.2).timeout
		var demo: AudioStreamWAV = world.dj._demo_stream
		if demo == null or demo.get_length() < 5.0:
			failures.append("track demo không sinh được")
		else:
			print("[SMOKE] demo track: %.1fs @ %dHz" % [demo.get_length(), demo.mix_rate])
		var tv_result: Dictionary = world.tv.publish("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "Kiểm tra TV")
		if not bool(tv_result.get("ok", false)):
			failures.append("TV publish thất bại: " + str(tv_result.get("reason", "")))
		else:
			print("[SMOKE] TV kind=%s embedded=%s" % [str(tv_result.get("kind", "")), str(tv_result.get("embedded", false))])
		var player = world.local_player_ref()
		if player == null:
			failures.append("không lấy được local player")
		else:
			var start_position: Vector3 = player.global_position
			player.set_touch_move(Vector2(0, 1))
			await get_tree().create_timer(0.7).timeout
			player.set_touch_move(Vector2.ZERO)
			if player.global_position.distance_to(start_position) < 0.2:
				failures.append("nhân vật không di chuyển")
			else:
				print("[SMOKE] di chuyển OK: %s -> %s" % [start_position, player.global_position])
			# Kiểm tra phím WASD thật (InputMap -> player), không chỉ joystick.
			await get_tree().create_timer(0.2).timeout
			var key_start: Vector3 = player.global_position
			Input.action_press("move_forward")
			Input.action_press("move_right")
			await get_tree().create_timer(0.6).timeout
			Input.action_release("move_forward")
			Input.action_release("move_right")
			await get_tree().create_timer(0.15).timeout
			var key_distance := key_start.distance_to(player.global_position)
			if key_distance < 0.5:
				failures.append("WASD không di chuyển nhân vật (%.2fm)" % key_distance)
			else:
				print("[SMOKE] WASD OK: di chuyển %.2fm" % key_distance)
			Net.request_interaction("lounge_sofa_-1", "seat", {"seat": Vector3(-9.5, 0.62, 14.4), "yaw": PI})
			await get_tree().create_timer(0.2).timeout
			if not player.seated:
				failures.append("tương tác ngồi ghế thất bại")
			else:
				Net.request_interaction("self", "stand", {})
				await get_tree().create_timer(0.2).timeout
				if player.seated:
					failures.append("không đứng dậy được")
	var elapsed := Time.get_ticks_msec() - started
	if failures.is_empty():
		print("[SMOKE] OK trong %d ms" % elapsed)
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("[SMOKE] FAIL: " + str(failure))
		get_tree().quit(1)


func _run_hud_test() -> void:
	print("[HUD-TEST] Kiểm tra menu nhanh + góc nhìn thứ ba")
	SettingsManager.preset_name = "high"
	SettingsManager.apply_all()
	if ui == null:
		_boot_client()
	await get_tree().create_timer(2.0).timeout
	start_solo()
	await get_tree().create_timer(1.2).timeout
	var player = local_player()
	if player == null or world == null:
		printerr("[HUD-TEST] Không có world/player")
		get_tree().quit(1)
		return
	world.lighting.apply_preset("party", 1.2, 1.0)
	world.dj.ensure_default_track()
	player.teleport_to(Vector3(0.0, 0.1, 20.0), 0.0)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://export/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var view_image := get_viewport().get_texture().get_image()
	var view_err := view_image.save_png(dir.path_join("hud_third_person.png"))
	print("[HUD-TEST] ảnh góc nhìn thứ ba -> %s" % error_string(view_err))

	var hud = ui.hud
	if hud == null:
		printerr("[HUD-TEST] FAIL: không có HUD")
		get_tree().quit(1)
		return
	hud.call("_toggle_quick_menu")
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var quick_image := get_viewport().get_texture().get_image()
	var quick_err := quick_image.save_png(dir.path_join("hud_quick_menu.png"))
	var quick: Control = hud.get("_quick_menu")
	var open_ok: bool = quick != null and quick.visible
	var blocked_ok: bool = bool(ui.call("is_input_blocked"))
	print("[HUD-TEST] menu nhanh mở=%s chặn_input=%s ảnh=%s" % [str(open_ok), str(blocked_ok), error_string(quick_err)])
	hud.call("_close_quick_menu")
	await get_tree().create_timer(0.3).timeout
	var closed_ok := quick != null and not quick.visible and not bool(ui.call("is_input_blocked"))
	print("[HUD-TEST] menu nhanh đóng=%s" % str(closed_ok))
	if not open_ok or not blocked_ok or not closed_ok:
		printerr("[HUD-TEST] FAIL: menu nhanh hoạt động sai")
		get_tree().quit(1)
		return
	print("[HUD-TEST] OK")
	get_tree().quit(0)


func _run_character_test() -> void:
	print("[CHAR-TEST] Kiểm tra nhân vật GLB + animation")
	SettingsManager.preset_name = "high"
	SettingsManager.apply_all()
	if ui == null:
		_boot_client()
	await get_tree().create_timer(2.0).timeout
	start_solo()
	await get_tree().create_timer(1.5).timeout
	var player = local_player()
	if player == null or world == null:
		printerr("[CHAR-TEST] Không có world/player")
		get_tree().quit(1)
		return
	player.teleport_to(Vector3(0.0, 0.1, 20.0), 0.0)
	Input.action_release("move_forward")
	player.set_touch_move(Vector2.ZERO)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	await get_tree().create_timer(2.0).timeout
	var rig = player.rig
	var dir := ProjectSettings.globalize_path("res://export/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var idle_err := image.save_png(dir.path_join("character_idle.png"))
	print("[CHAR-TEST] glb=%s clips=%d idle_anim=%s pos=%s vel=%s move=%s floor=%s ảnh=%s" % [str(rig.get("_glb")), int(rig.get("_clips").size()), str(rig.get("_current_clip")), str(player.global_position), str(player.velocity), str(player.get("_move_input")), str(player.is_on_floor()), error_string(idle_err)])

	# Camera tạm phía trước để kiểm tra texture/khuôn mặt.
	var face_cam := Camera3D.new()
	face_cam.fov = 45.0
	face_cam.near = 0.05
	add_child(face_cam)
	face_cam.global_position = player.global_position + Vector3(0.35, 1.55, -1.7)
	face_cam.look_at(player.global_position + Vector3(0.0, 1.42, 0.0), Vector3.UP)
	face_cam.current = true
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	image = get_viewport().get_texture().get_image()
	var face_err := image.save_png(dir.path_join("character_face.png"))
	player.camera.current = true
	face_cam.queue_free()
	print("[CHAR-TEST] mặt trước ảnh=%s" % error_string(face_err))

	# Ảnh cận màn LED lớn để kiểm tra dòng ghi công nhà phát triển.
	var tv_cam := Camera3D.new()
	tv_cam.fov = 46.0
	add_child(tv_cam)
	tv_cam.global_position = Vector3(0.0, 4.4, 3.2)
	tv_cam.look_at(Vector3(0.0, 5.3, -6.05), Vector3.UP)
	tv_cam.current = true
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	image = get_viewport().get_texture().get_image()
	var tv_err := image.save_png(dir.path_join("tv_credit.png"))
	player.camera.current = true
	tv_cam.queue_free()
	print("[CHAR-TEST] màn LED ảnh=%s" % error_string(tv_err))

	player.play_emote("dance")
	await get_tree().create_timer(1.4).timeout
	await RenderingServer.frame_post_draw
	image = get_viewport().get_texture().get_image()
	var dance_err := image.save_png(dir.path_join("character_dance.png"))
	print("[CHAR-TEST] dance_anim=%s ảnh=%s" % [str(rig.get("_current_clip")), error_string(dance_err)])

	player.set("_emote_timer", 0.0)
	player.set("emote", "")
	Input.action_press("move_forward")
	await get_tree().create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	image = get_viewport().get_texture().get_image()
	var walk_err := image.save_png(dir.path_join("character_walk.png"))
	Input.action_release("move_forward")
	print("[CHAR-TEST] walk_anim=%s ảnh=%s" % [str(rig.get("_current_clip")), error_string(walk_err)])
	print("[CHAR-TEST] OK")
	get_tree().quit(0)


func _run_screenshots() -> void:
	SettingsManager.preset_name = "high"
	SettingsManager.apply_all()
	var shot_dir := ProjectSettings.globalize_path("res://export/screenshots")
	DirAccess.make_dir_recursive_absolute(shot_dir)
	# Chụp main menu (Game Menu Kit Lite) trước khi vào club.
	if ui == null:
		_boot_client()
	await get_tree().create_timer(2.0).timeout
	if ui != null:
		ui.call("show_screen", "main_menu")
		await get_tree().create_timer(1.4).timeout
		await RenderingServer.frame_post_draw
		var menu_image := get_viewport().get_texture().get_image()
		var menu_path := shot_dir.path_join("00_main_menu.png")
		var menu_err := menu_image.save_png(menu_path)
		print("[SHOT] 00_main_menu -> %s (%s)" % [menu_path, error_string(menu_err)])
	start_solo()
	await get_tree().create_timer(0.6).timeout
	var player = local_player()
	if player == null or world == null:
		printerr("[SHOT] Không có world/player")
		get_tree().quit(1)
		return
	world.lighting.apply_preset("party", 1.2, 1.0)
	world.dj.ensure_default_track()
	player.teleport_to(Vector3(0, 0.1, 19.5), 0.0)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	await get_tree().create_timer(0.3).timeout

	# Camera review riêng để ảnh QA không phụ thuộc camera gameplay.
	var review_cam := Camera3D.new()
	review_cam.name = "ReviewCamera"
	review_cam.fov = 72.0
	review_cam.near = 0.05
	review_cam.far = 250.0
	add_child(review_cam)
	review_cam.current = true

	var dir := ProjectSettings.globalize_path("res://export/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().create_timer(0.5).timeout
	var ui_image: Image = world.tv.get("viewport").get_texture().get_image()
	var ui_err: int = ui_image.save_png(dir.path_join("tv_ui.png"))
	print("[SHOT] tv_ui -> %s (%s) size=%s" % [ui_err, error_string(ui_err), ui_image.get_size()])
	var shots := [
		{"name": "01_entrance", "eye": Vector3(0.0, 1.75, 24.5), "yaw": 0.0, "pitch": -0.02},
		{"name": "02_dancefloor", "eye": Vector3(0.0, 1.8, 13.5), "yaw": 0.0, "pitch": 0.02},
		{"name": "03_stage", "eye": Vector3(0.0, 2.2, 13.0), "yaw": 0.0, "pitch": 0.03},
		{"name": "04_bar", "eye": Vector3(-22.0, 1.7, 5.0), "yaw": PI * 0.5, "pitch": 0.02},
		{"name": "05_vip", "eye": Vector3(21.8, 1.85, 5.0), "yaw": -PI * 0.5, "pitch": 0.06},
		{"name": "06_balcony", "eye": Vector3(7.0, 6.9, 13.4), "yaw": 0.0, "pitch": -0.18},
	]
	for shot in shots:
		review_cam.global_position = shot["eye"]
		review_cam.rotation = Vector3(float(shot["pitch"]), float(shot["yaw"]), 0.0)
		await get_tree().create_timer(0.55).timeout
		await RenderingServer.frame_post_draw
		print("[SHOT] %s cam=%s rot=%s" % [shot["name"], review_cam.global_position, review_cam.global_rotation_degrees])
		var image := get_viewport().get_texture().get_image()
		var path := dir.path_join(str(shot["name"]) + ".png")
		var err := image.save_png(path)
		print("[SHOT] %s -> %s (%s)" % [shot["name"], path, error_string(err)])
	get_tree().quit(0)


func _run_tv_web_test(url: String) -> void:
	print("[TV-TEST] URL: " + url)
	SettingsManager.preset_name = "high"
	SettingsManager.apply_all()
	start_solo()
	await get_tree().create_timer(0.8).timeout
	if world == null or world.tv == null:
		printerr("[TV-TEST] Không có world/TV")
		get_tree().quit(1)
		return
	if world.tv.renderer == null or not world.tv.renderer.available:
		printerr("[TV-TEST] Không có trình duyệt để render web.")
		get_tree().quit(1)
		return
	print("[TV-TEST] backend=" + world.tv.web_backend_name())
	var result: Dictionary = world.tv.publish(url, "TV web test", true)
	print("[TV-TEST] publish ok=%s kind=%s embedded=%s" % [str(result.get("ok", false)), str(result.get("kind", "")), str(result.get("embedded", false))])
	var waited := 0.0
	while waited < 30.0 and world.tv.renderer.texture == null:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if world.tv.renderer.texture == null:
		printerr("[TV-TEST] FAIL: không nhận được frame web sau %.0fs" % waited)
		get_tree().quit(1)
		return
	# Để trang kịp render nội dung đầy đủ sau frame đầu.
	await get_tree().create_timer(6.0).timeout
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://export/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var image: Image = world.tv.viewport.get_texture().get_image()
	var path := dir.path_join("tv_web.png")
	var err := image.save_png(path)
	print("[TV-TEST] frame sau %.1fs, texture=%s, lưu %s (%s)" % [waited, str(world.tv.renderer.texture), path, error_string(err)])
	# Bấm thử vào nút menu của YouTube (góc trên trái) để kiểm tra input CDP.
	world.tv.click_page(Vector2(36, 40), false)
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var click_image: Image = world.tv.viewport.get_texture().get_image()
	var click_path := dir.path_join("tv_web_click.png")
	var click_err := click_image.save_png(click_path)
	print("[TV-TEST] sau click -> %s (%s)" % [click_path, error_string(click_err)])
	# Gõ thử vào ô tìm kiếm YouTube để kiểm tra input bàn phím qua CDP.
	world.tv.click_page(Vector2(900, 36), false)
	await get_tree().create_timer(0.7).timeout
	for ch in "lofi":
		var down := InputEventKey.new()
		down.keycode = OS.find_keycode_from_string(ch.to_upper())
		down.unicode = ch.unicode_at(0)
		down.pressed = true
		world.tv.key_page(down, true)
		var up := InputEventKey.new()
		up.keycode = down.keycode
		up.unicode = down.unicode
		up.pressed = false
		world.tv.key_page(up, false)
		await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var keys_image: Image = world.tv.viewport.get_texture().get_image()
	var keys_path := dir.path_join("tv_web_keys.png")
	var keys_err := keys_image.save_png(keys_path)
	print("[TV-TEST] gõ phím -> %s (%s)" % [keys_path, error_string(keys_err)])
	# Ảnh trong thế giới 3D: xác nhận texture map đúng lên màn LED sân khấu.
	var review_cam := Camera3D.new()
	review_cam.fov = 72.0
	review_cam.far = 250.0
	add_child(review_cam)
	review_cam.global_position = Vector3(0.0, 2.2, 13.0)
	review_cam.rotation = Vector3(0.03, 0.0, 0.0)
	review_cam.current = true
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var scene_image: Image = get_viewport().get_texture().get_image()
	var scene_path := dir.path_join("tv_web_scene.png")
	var scene_err := scene_image.save_png(scene_path)
	print("[TV-TEST] ảnh sân khấu -> %s (%s)" % [scene_path, error_string(scene_err)])
	get_tree().quit(0 if err == OK and click_err == OK and keys_err == OK and scene_err == OK else 1)


func _run_tv_fullscreen_test() -> void:
	## Kiểm tra shim fullscreen: một khối đỏ gọi requestFullscreen() phải phủ
	## kín khung 1920x1080 thay vì làm cửa sổ Chromium đổi kích thước.
	print("[FS-TEST] bắt đầu")
	SettingsManager.preset_name = "high"
	SettingsManager.apply_all()
	start_solo()
	# Không để TV tự mở YouTube: test cần điều khiển trang và chụp đúng trang test.
	if world != null and world.tv != null:
		world.tv.auto_home = false
	await get_tree().create_timer(0.8).timeout
	if world == null or world.tv == null or world.tv.renderer == null or not world.tv.renderer.available:
		printerr("[FS-TEST] FAIL: không có renderer web")
		get_tree().quit(1)
		return
	# Bật lớp web của TV (auto_home đã tắt nên không mở YouTube) rồi mới nạp
	# trang test, tránh việc ảnh chụp rơi vào màn hình chờ visualizer.
	world.tv.call("_show_web", "about:blank", "FS test")
	# Chờ CDP sẵn sàng rồi mới điều hướng để lệnh không bị trang mặc định ghi đè.
	var waited_cdp := 0.0
	while waited_cdp < 20.0 and world.tv.renderer.texture == null:
		await get_tree().create_timer(0.4).timeout
		waited_cdp += 0.4
	var html := """<!doctype html><html><head><meta charset="utf-8"><style>
		html,body{margin:0;background:#06121e;color:#e8f7ff;font-family:sans-serif}
		#box{position:absolute;left:40px;top:120px;width:420px;height:240px;background:#ff2050;
			display:flex;align-items:center;justify-content:center;font-size:54px;font-weight:700}
		#filler{height:2400px;background:linear-gradient(#06121e,#123)}
		</style></head><body>
		<div id="box">TV FULLSCREEN</div><div id="filler"></div>
		<script>
		var box = document.getElementById('box');
		try { box.requestFullscreen().catch(function(e) { box.dataset.err = e.message; }); }
		catch (e) { box.dataset.err = String(e); }
		setTimeout(function() {
			box.textContent = 'FS:' + (document.fullscreenElement ? 'yes' : 'no') +
				' shim:' + (window.__qboTvShim ? '1' : '0') +
				' cls:' + box.className +
				' err:' + (window.__qboTvShimError || box.dataset.err || 'none');
		}, 700);
		</script>
		</body></html>"""
	world.tv.renderer.navigate("data:text/html;charset=utf-8," + html.uri_encode())
	var waited := 0.0
	while waited < 20.0 and world.tv.renderer.texture == null:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	if world.tv.renderer.texture == null:
		printerr("[FS-TEST] FAIL: không nhận được frame")
		get_tree().quit(1)
		return
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://export/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var image: Image = world.tv.viewport.get_texture().get_image()
	var path := dir.path_join("tv_fullscreen.png")
	var err := image.save_png(path)
	print("[FS-TEST] lưu %s (%s) size=%s" % [path, error_string(err), image.get_size()])
	get_tree().quit(0 if err == OK else 1)


const VIEWPORT_DIAG_JS := """(() => JSON.stringify({
  inner: [innerWidth, innerHeight],
  client: [document.documentElement.clientWidth, document.documentElement.clientHeight],
  dpr: devicePixelRatio,
  scroll: [document.documentElement.scrollWidth, document.documentElement.scrollHeight],
}))()"""

const FULLSCREEN_DIAG_JS := """(() => {
  const r = (el) => {
    if (!el) return null;
    const b = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return {
      tag: el.tagName, id: el.id, cls: String(el.className).slice(0, 90),
      x: Math.round(b.x), y: Math.round(b.y), w: Math.round(b.width), h: Math.round(b.height),
      display: s.display, visibility: s.visibility, opacity: s.opacity,
      position: s.position, transform: s.transform, z: s.zIndex, bg: s.backgroundColor,
    };
  };
  const v = document.querySelector('video');
  return JSON.stringify({
    inner: [innerWidth, innerHeight],
    htmlClass: document.documentElement.className,
    fs: r(document.fullscreenElement),
    player: r(document.querySelector('#movie_player')),
    video: r(v),
    videoBox: v ? [v.videoWidth, v.videoHeight, v.readyState, v.paused, Math.round(v.currentTime * 10) / 10, v.muted] : null,
    shim: !!window.__qboTvShim, shimErr: window.__qboTvShimError || null,
  });
})()"""


func _run_youtube_fullscreen_test(url: String) -> void:
	## Tái hiện lỗi "bấm fullscreen YouTube chỉ thấy màn đen": mở video, bấm nút
	## fullscreen của player, rồi chụp lại màn TV + in trạng thái DOM.
	print("[YT-FS] bắt đầu: %s" % url)
	SettingsManager.preset_name = "high"
	SettingsManager.apply_all()
	start_solo()
	if world != null and world.tv != null:
		world.tv.auto_home = false
	await get_tree().create_timer(0.8).timeout
	if world == null or world.tv == null or world.tv.renderer == null or not world.tv.renderer.available:
		printerr("[YT-FS] FAIL: không có renderer web")
		get_tree().quit(1)
		return
	var tv = world.tv
	var renderer = tv.renderer
	# Mở lớp web trên TV trước để có viewport thật, rồi mới nạp YouTube.
	tv.call("_show_web", "about:blank", "YouTube fullscreen test")
	var waited_cdp := 0.0
	while waited_cdp < 20.0 and renderer.texture == null:
		await get_tree().create_timer(0.4).timeout
		waited_cdp += 0.4
	renderer.evaluate(VIEWPORT_DIAG_JS, "viewport")
	renderer.navigate(url)
	await get_tree().create_timer(10.0).timeout
	renderer.evaluate(VIEWPORT_DIAG_JS, "viewport-youtube")
	renderer.evaluate("(() => { const v = document.querySelector('video'); return v ? 'video-ok ' + v.videoWidth + 'x' + v.videoHeight : 'video-no'; })()", "video")
	var dir := ProjectSettings.globalize_path("res://export/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	renderer.capture_screenshot(dir.path_join("yt_before_fs.png"))
	renderer.evaluate("(() => { const b = document.querySelector('.ytp-fullscreen-button'); if (!b) return 'no-button'; b.click(); return 'clicked'; })()", "click-fullscreen")
	await get_tree().create_timer(3.0).timeout
	renderer.evaluate(FULLSCREEN_DIAG_JS, "after-fullscreen")
	renderer.evaluate("(() => { const e = document.elementFromPoint(640, 360); return e ? e.tagName + '#' + e.id + '.' + String(e.className).slice(0, 60) : 'none'; })()", "element-at-center")
	renderer.capture_screenshot(dir.path_join("yt_after_fs.png"))
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var image: Image = tv.viewport.get_texture().get_image()
	var path := dir.path_join("yt_fullscreen.png")
	var err := image.save_png(path)
	print("[YT-FS] lưu %s (%s) size=%s" % [path, error_string(err), image.get_size()])
	get_tree().quit(0 if err == OK else 1)


func _run_tv_aim_test() -> void:
	## Đo sai số ánh xạ ngược: chiếu một điểm đã biết trên mặt TV ra toạ độ màn
	## hình, rồi đưa toạ độ đó trở lại `screen_pixel_at()` để so với pixel gốc.
	print("[AIM-TEST] bắt đầu")
	SettingsManager.preset_name = "low"
	SettingsManager.apply_all()
	start_solo()
	await get_tree().create_timer(0.8).timeout
	if world == null or world.tv == null or world.stage_web_screen == null:
		printerr("[AIM-TEST] FAIL: thiếu world/TV")
		get_tree().quit(1)
		return
	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.near = 0.05
	cam.far = 250.0
	add_child(cam)
	var max_err := 0.0
	var worst := ""
	var views := [
		{"pos": Vector3(0.0, 2.2, 13.0), "target": Nightclub.SIDE_TV_CENTER},
		{"pos": Vector3(2.5, 4.0, 8.0), "target": Nightclub.SIDE_TV_CENTER},
		{"pos": Vector3(-4.0, 1.8, 3.0), "target": Nightclub.SIDE_TV_CENTER},
	]
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for view in views:
		cam.global_position = view["pos"]
		cam.look_at(view["target"], Vector3.UP)
		cam.current = true
		await get_tree().process_frame
		var xform: Transform3D = world.stage_web_screen.global_transform
		for v in [0.04, 0.25, 0.5, 0.75, 0.96]:
			for u in [0.04, 0.25, 0.5, 0.75, 0.96]:
				var world_pt: Vector3 = xform * Vector3(
					(float(u) - 0.5) * Nightclub.SIDE_TV_SIZE.x,
					(0.5 - float(v)) * Nightclub.SIDE_TV_SIZE.y,
					0.0
				)
				var screen_pt: Vector2 = cam.unproject_position(world_pt)
				# Player tự khoá chuột lại mỗi frame; đặt VISIBLE ngay trước phép
				# đo để kiểm tra nhánh ánh xạ theo vị trí con trỏ (menu/PC).
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				var mapped: Vector2 = world.tv.screen_pixel_at(screen_pt)
				var expected := Vector2(float(u) * 1920.0, float(v) * 1080.0)
				var err := mapped.distance_to(expected)
				if err > max_err:
					max_err = err
					worst = "view=%s uv=(%.2f,%.2f) mapped=%s expected=%s screen=%s" % [
						view["pos"], u, v, mapped, expected, screen_pt,
					]
	print("[AIM-TEST] sai số lớn nhất = %.3f px  (%s)" % [max_err, worst])
	var ok := max_err < 3.0
	print("[AIM-TEST] " + ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _run_click_test() -> void:
	## Kiểm tra end-to-end: click trên lớp web của máy tính phải tới đúng toạ độ
	## CSS của trang (không lệch do texture/viewport khác kích thước).
	print("[CLICK-TEST] bắt đầu")
	SettingsManager.preset_name = "high"
	SettingsManager.apply_all()
	if ui == null:
		_boot_client()
	start_solo()
	if world != null and world.tv != null:
		world.tv.auto_home = false
	await get_tree().create_timer(1.5).timeout
	App.open_computer("browser")
	await get_tree().create_timer(0.6).timeout
	var comp = ui.overlays.get("computer")
	if comp == null or world == null or world.tv == null or world.tv.renderer == null:
		printerr("[CLICK-TEST] FAIL: thiếu máy tính/TV")
		get_tree().quit(1)
		return
	var html := """<!doctype html><html><head><meta charset="utf-8"><style>
		html,body{margin:0;height:100%;background:#0a1a22;color:#e8f7ff;font-family:sans-serif}
		#hud{font-size:44px;padding:24px}
		</style></head><body><div id="hud">click</div>
		<script>
		window.__clicks = [];
		addEventListener('mousedown', function(e) {
			window.__clicks.push({x: e.clientX, y: e.clientY});
			var d = document.createElement('div');
			d.style.cssText = 'position:fixed;left:' + e.clientX + 'px;top:' + e.clientY +
				'px;width:22px;height:22px;margin:-11px 0 0 -11px;background:#ffe14d;border-radius:50%;z-index:99';
			document.body.appendChild(d);
			document.getElementById('hud').textContent = 'x=' + e.clientX + ' y=' + e.clientY;
		});
		</script></body></html>"""
	world.tv.renderer.navigate("data:text/html;charset=utf-8," + html.uri_encode())
	var waited := 0.0
	while waited < 20.0 and world.tv.renderer.texture == null:
		await get_tree().create_timer(0.3).timeout
		waited += 0.3
	while waited < 24.0 and world.tv.renderer.loading:
		await get_tree().create_timer(0.3).timeout
		waited += 0.3
	await get_tree().create_timer(1.5).timeout
	world.tv.renderer.evaluate("location.href.slice(0, 24) + '|' + (typeof window.__clicks)", "click-page")
	world.tv.renderer.evaluate(VIEWPORT_DIAG_JS, "click-viewport")
	var tex: TextureRect = comp.get("_webview_texture")
	if tex == null:
		printerr("[CLICK-TEST] FAIL: không có webview")
		get_tree().quit(1)
		return
	var box: Vector2 = tex.size
	var css_size := Vector2(QBOTVSystem.SCREEN_SIZE)
	print("[CLICK-TEST] webview=%s css=%s" % [box, css_size])
	var fit_scale := minf(box.x / css_size.x, box.y / css_size.y)
	var content := css_size * fit_scale
	var offset := (box - content) * 0.5
	var max_err := 0.0
	for local in [Vector2(120, 120), Vector2(box.x * 0.5, box.y * 0.5), Vector2(box.x - 120, box.y - 120)]:
		var expected: Vector2 = (local - offset) / fit_scale
		world.tv.renderer.evaluate("typeof window.__clicks === 'object' ? window.__clicks.length : -1", "clicks-before")
		var click := InputEventMouseButton.new()
		click.position = local
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		comp.call("_on_web_surface_input", click)
		await get_tree().create_timer(0.5).timeout
		world.tv.renderer.evaluate(
			"JSON.stringify(window.__clicks[window.__clicks.length - 1] || null)", "clicked"
		)
		print("[CLICK-TEST] local=%s expected_css=%s" % [local, expected])
	await get_tree().create_timer(0.5).timeout
	var dir := ProjectSettings.globalize_path("res://export/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	world.tv.renderer.capture_screenshot(dir.path_join("click_test.png"))
	await get_tree().create_timer(1.2).timeout
	print("[CLICK-TEST] DONE")
	get_tree().quit(0)


func _run_embed_test(url: String) -> void:
	## Kiểm tra luồng mới: dán link YouTube → TV phát iframe nhúng (không mở cả
	## trang web), rồi bấm fullscreen của player nhúng.
	print("[EMBED-TEST] bắt đầu: %s" % url)
	SettingsManager.preset_name = "high"
	SettingsManager.apply_all()
	start_solo()
	if world != null and world.tv != null:
		world.tv.auto_home = false
	await get_tree().create_timer(0.8).timeout
	if world == null or world.tv == null or world.tv.renderer == null or not world.tv.renderer.available:
		printerr("[EMBED-TEST] FAIL: không có renderer web")
		get_tree().quit(1)
		return
	var tv = world.tv
	var renderer = tv.renderer
	var result: Dictionary = tv.play_youtube(url)
	print("[EMBED-TEST] play_youtube ok=%s reason=%s" % [
		str(result.get("ok", false)), str(result.get("reason", "")),
	])
	var waited := 0.0
	while waited < 25.0 and renderer.texture == null:
		await get_tree().create_timer(0.4).timeout
		waited += 0.4
	await get_tree().create_timer(8.0).timeout
	renderer.evaluate(VIEWPORT_DIAG_JS, "embed-viewport")
	renderer.evaluate("(() => { const v = document.querySelector('video'); return v ? 'video ' + v.videoWidth + 'x' + v.videoHeight + ' t=' + v.currentTime + ' paused=' + v.paused : 'no-video'; })()", "embed-video")
	renderer.evaluate("window.__qboTvShim ? 'shim-ok' : 'shim-missing'", "embed-shim")
	var dir := ProjectSettings.globalize_path("res://export/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	renderer.capture_screenshot(dir.path_join("embed_player.png"))
	await RenderingServer.frame_post_draw
	var image: Image = tv.viewport.get_texture().get_image()
	var err := image.save_png(dir.path_join("embed_tv.png"))
	print("[EMBED-TEST] lưu embed_tv.png (%s) size=%s" % [error_string(err), image.get_size()])
	# Nút fullscreen nằm trong iframe nên phải bấm bằng toạ độ (chuột thật).
	renderer.mouse_move(640, 360)
	await get_tree().create_timer(0.5).timeout
	renderer.mouse_click(1244, 690)
	await get_tree().create_timer(3.0).timeout
	renderer.capture_screenshot(dir.path_join("embed_fullscreen.png"))
	await RenderingServer.frame_post_draw
	var fs_image: Image = tv.viewport.get_texture().get_image()
	var fs_err := fs_image.save_png(dir.path_join("embed_tv_fullscreen.png"))
	print("[EMBED-TEST] lưu embed_tv_fullscreen.png (%s) size=%s" % [error_string(fs_err), fs_image.get_size()])
	get_tree().quit(0)


func _run_computer_test() -> void:
	## Kiểm tra cửa sổ LOTUS NET: kích thước vùng web + ánh xạ click/gõ phím.
	print("[COMPUTER-TEST] bắt đầu")
	SettingsManager.preset_name = "high"
	SettingsManager.apply_all()
	if ui == null:
		_boot_client()
	start_solo()
	await get_tree().create_timer(2.0).timeout
	if ui == null:
		printerr("[COMPUTER-TEST] FAIL: không có UI")
		get_tree().quit(1)
		return
	App.open_computer("browser")
	await get_tree().create_timer(0.8).timeout
	var comp = ui.overlays.get("computer")
	if comp == null:
		printerr("[COMPUTER-TEST] FAIL: không mở được máy tính")
		get_tree().quit(1)
		return
	comp.call("_navigate", "https://www.youtube.com/watch?v=aqz-KE-bpKQ")
	await get_tree().create_timer(9.0).timeout
	if world != null and world.tv != null and world.tv.renderer != null:
		world.tv.renderer.evaluate(VIEWPORT_DIAG_JS, "computer-viewport")
		world.tv.renderer.evaluate("(() => { const v = document.querySelector('video'); return v ? 'video ' + v.videoWidth + 'x' + v.videoHeight + ' t=' + v.currentTime + ' paused=' + v.paused : 'no-video'; })()", "computer-video")
	var tex: TextureRect = comp.get("_webview_texture")
	var win = comp.get("_window")
	var tex_size := Vector2(1280, 720)
	if tex != null and tex.texture != null:
		tex_size = Vector2(tex.texture.get_size())
	print("[COMPUTER-TEST] window=%s panel=%s webview=%s tex=%s" % [
		win.size if win != null else Vector2.ZERO,
		tex.get_parent().size if tex != null else Vector2.ZERO,
		tex.size if tex != null else Vector2.ZERO,
		tex_size,
	])
	if win != null:
		var vbox: Node = win.get_child(0)
		print("[COMPUTER-TEST] vbox=%s" % [vbox.size if vbox is Control else Vector2.ZERO])
	if tex == null or tex.texture == null:
		printerr("[COMPUTER-TEST] FAIL: chưa có texture web")
		get_tree().quit(1)
		return
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://export/screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var image: Image = get_viewport().get_texture().get_image()
	var path := dir.path_join("computer_browser.png")
	var err := image.save_png(path)
	print("[COMPUTER-TEST] lưu %s (%s) size=%s" % [path, error_string(err), image.get_size()])
	get_tree().quit(0 if err == OK else 1)


func _run_perf_test() -> void:
	## Đo FPS thực tế trong club và tách chi phí từng hạng mục.
	print("[PERF-TEST] renderer=%s gpu=%s preset=%s" % [
		RenderingServer.get_current_rendering_method(),
		RenderingServer.get_video_adapter_name(),
		SettingsManager.preset_name,
	])
	SettingsManager.apply_all()
	if ui == null:
		_boot_client()
	start_solo()
	await get_tree().create_timer(3.0).timeout
	var env: Environment = null
	if world != null and world.environment_node != null:
		env = world.environment_node.environment
	_log_phase("baseline", await _sample_fps(3.0))
	if env != null:
		env.glow_enabled = false
		env.adjustment_enabled = false
		_log_phase("-glow/adjust", await _sample_fps(3.0))
	get_viewport().scaling_3d_scale = 0.6
	_log_phase("+scale 0.6", await _sample_fps(3.0))
	if world != null:
		for entry in world.get("_managed_lights"):
			var light: Light3D = entry["node"]
			if is_instance_valid(light):
				light.visible = false
		world.set_process(false)
	_log_phase("+lights off", await _sample_fps(3.0))
	if world != null:
		for node in world.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_log_phase("+no cast shadow", await _sample_fps(3.0))
	if world != null and world.tv != null:
		world.tv.visible = false
		var renderer = world.tv.get("renderer")
		if renderer != null:
			renderer.call("stop_browser")
	_log_phase("+tv off", await _sample_fps(3.0))
	print("[PERF-TEST] DONE")
	get_tree().quit(0)


func _sample_fps(seconds: float) -> Dictionary:
	await get_tree().create_timer(0.3).timeout
	var samples: Array[float] = []
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(seconds * 1000.0):
		await get_tree().create_timer(0.25).timeout
		samples.append(Engine.get_frames_per_second())
	var total := 0.0
	var lowest := 9999.0
	var highest := 0.0
	for value in samples:
		total += value
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	return {
		"avg": total / maxf(1.0, float(samples.size())),
		"min": lowest,
		"max": highest,
	}


func _log_phase(phase_name: String, stats: Dictionary) -> void:
	print("[PERF-TEST] %-22s avg=%.1f min=%.1f max=%.1f fps" % [
		phase_name, stats["avg"], stats["min"], stats["max"],
	])


func _run_net_smoke(port_text: String) -> void:
	var port := int(port_text)
	print("[NET-SMOKE] kết nối tới 127.0.0.1:%d" % port)
	_load_world({"code": "NETSMOKE", "name": "Net Smoke", "maxPlayers": 8}, false)
	Net.connect_to_room("127.0.0.1", port, "dev-ticket")
	await get_tree().create_timer(3.0).timeout
	var players_count := Net.players.size()
	print("[NET-SMOKE] players=%d roster=%d local=%d owner=%d connected=%s" % [players_count, Net.roster.size(), Net.local_peer_id, Net.owner_id, str(Net.is_online())])
	var ok := players_count >= 1 and Net.is_online()
	if ok:
		var player = world.local_player_ref()
		if player != null:
			player.set_touch_move(Vector2(0, 1))
			await get_tree().create_timer(0.6).timeout
			player.set_touch_move(Vector2.ZERO)
			print("[NET-SMOKE] vị trí sau di chuyển: %s" % str(player.global_position))
		Net.send_chat("net smoke: xin chào")
		Net.request_interaction("lounge_sofa_1", "seat", {"seat": Vector3(9.5, 0.62, 14.4), "yaw": PI})
		await get_tree().create_timer(0.5).timeout
		if player != null and not player.seated:
			ok = false
			printerr("[NET-SMOKE] FAIL: server không broadcast tương tác")
	print("[NET-SMOKE] %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
