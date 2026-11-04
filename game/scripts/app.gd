extends Node
## App — điều phối toàn bộ vòng đời: UI, world, kết nối phòng.
## Được đăng ký như autoload để mọi hệ thống có thể gọi App.toast(), App.open_computer()…

signal world_loaded(world: Nightclub)
signal world_unloaded()

var ui: CanvasLayer
var world: Nightclub
var booted := false

## Phòng tạm thời: client gửi nhịp để backend biết phòng còn sống.
const ROOM_HEARTBEAT_INTERVAL := 30.0
var _heartbeat_timer := 0.0
var _leaving := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AppConfig.is_dedicated:
		_boot_dedicated_server()
		return
	for arg in AppConfig.launch_args:
		if arg == "--smoke":
			_run_smoke_test()
			return
		if arg == "--media-test":
			_run_media_test()
			return
		if arg == "--ui-test":
			_run_ui_test()
			return
		if arg == "--screenshot":
			_run_screenshots()
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


func _process(delta: float) -> void:
	if AppConfig.is_dedicated or not booted or not GameState.is_logged_in():
		return
	var code := str(GameState.room.get("code", "SOLO"))
	if code == "" or code == "SOLO":
		_heartbeat_timer = 0.0
		return
	_heartbeat_timer -= delta
	if _heartbeat_timer <= 0.0:
		_heartbeat_timer = ROOM_HEARTBEAT_INTERVAL
		Api.room_heartbeat(code)


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
	if _leaving:
		return
	_leaving = true
	_heartbeat_timer = 0.0
	var code := str(GameState.room.get("code", "SOLO"))
	var online := code != "" and code != "SOLO" and GameState.is_logged_in()
	# Chủ phòng rời đi -> phòng đóng ngay, không chuyển quyền cho người khác.
	if online and Net.mode == AppConfig.Mode.CLIENT and Net.is_owner():
		Net.notify_owner_leaving()
		await get_tree().create_timer(0.25).timeout
	if online:
		Api.leave_room(code)
	Net.stop()
	GameState.clear_room()
	GameState.ticket = ""
	unload_world()
	_leaving = false
	if ui != null:
		ui.call("exit_game")


func return_to_menu() -> void:
	leave_room()


# ------------------------------------------------------------------ UI helpers

func toast(message: String, level := "info") -> void:
	GameState.toast_requested.emit(message, level)


func open_computer(tab := "music") -> void:
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
		if world.tv == null:
			failures.append("thiếu TVSystem")
		else:
			print("[SMOKE] TV music screen ready (video backend: %s)" % world.tv.video_backend_name())
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
	# URL guard: chặn SSRF (IPv4/IPv6/credentials) và chỉ nhận media trực tiếp.
	var blocked := [
		"http://localhost/x.mp3",
		"http://127.0.0.1/x.mp3",
		"http://10.1.2.3/x.mp4",
		"http://192.168.0.5/x.mp3",
		"http://169.254.169.254/latest/meta-data",
		"http://[::1]/x.mp3",
		"http://[fc00::1]/x.mp3",
		"http://user:pass@127.0.0.1/x.mp3",
	]
	for candidate in blocked:
		if bool(QBOUrlGuard.validate(candidate).get("ok", false)):
			failures.append("URL guard cho phép URL nội bộ: " + candidate)
	if QBOUrlGuard.is_supported_audio("file:///etc/passwd"):
		failures.append("URL guard nhận file:// là audio")
	var audio_check := QBOUrlGuard.validate("https://music.nguyenphuquyet.online/media/audio/a.mp3")
	if str(audio_check.get("kind", "")) != "audio" or not bool(audio_check.get("trusted", false)):
		failures.append("URL guard không nhận diện audio API")
	if str(QBOUrlGuard.validate("https://example.com/clip.mp4").get("kind", "")) != "video":
		failures.append("URL guard không nhận diện video MP4")
	var joined := QBOUrlGuard.absolute_url("/media/audio/a.mp3", "https://music.nguyenphuquyet.online")
	if joined != "https://music.nguyenphuquyet.online/media/audio/a.mp3":
		failures.append("absolute_url ghép sai: " + joined)
	else:
		print("[SMOKE] URL guard OK (%d URL nội bộ bị chặn)" % blocked.size())
	var elapsed := Time.get_ticks_msec() - started
	if failures.is_empty():
		print("[SMOKE] OK trong %d ms" % elapsed)
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("[SMOKE] FAIL: " + str(failure))
		get_tree().quit(1)


func _run_media_test() -> void:
	print("[MEDIA-TEST] DJ library + audio playback + TV MP4")
	print("[MEDIA-TEST] display=%s method=%s driver=%s adapter=%s rd=%s" % [
		DisplayServer.get_name(),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		RenderingServer.get_current_rendering_driver_name(),
		RenderingServer.get_video_adapter_name(),
		str(RenderingServer.get_rendering_device() != null),
	])
	var failures: Array = []
	var started := Time.get_ticks_msec()
	start_solo()
	await get_tree().create_timer(0.8).timeout
	if world == null or world.dj == null or world.tv == null:
		printerr("[MEDIA-TEST] FAIL: thiếu world/dj/tv")
		get_tree().quit(1)
		return
	var dj: QBODJSystem = world.dj
	var waited := 0.0
	while dj.library_loading and waited < 25.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	print("[MEDIA-TEST] library=%d loading=%s error=%s" % [dj.track_count(), str(dj.library_loading), dj.library_error])
	if dj.track_count() < 1:
		failures.append("không có bài nào trong thư viện API")
	else:
		var tracks := dj.playlist()
		for i in mini(3, tracks.size()):
			print("[MEDIA-TEST] track %d: %s — %s (%s)" % [i, str(tracks[i].get("title", "")), str(tracks[i].get("artist", "")), str(tracks[i].get("url", ""))])
		var first_id := str(tracks[0].get("id", ""))
		dj.play_track(first_id)
		waited = 0.0
		while dj.is_loading_track() and waited < 25.0:
			await get_tree().create_timer(0.25).timeout
			waited += 0.25
		await get_tree().create_timer(1.0).timeout
		var stream: AudioStream = dj.music.stream
		if stream == null:
			failures.append("audio stream không được tải/giải mã")
		else:
			print("[MEDIA-TEST] audio stream=%s length=%.1fs playing=%s pos=%.2f" % [stream.get_class(), stream.get_length(), str(dj.music.playing), dj.playback_position()])
			if stream.get_length() <= 0.0:
				failures.append("audio stream có độ dài 0")
	var video_url := "https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4"
	var res: Dictionary = world.tv.play_video_url(video_url, "Media test")
	print("[MEDIA-TEST] tv play_video_url ok=%s" % str(res.get("ok", false)))
	if not bool(res.get("ok", false)):
		failures.append("TV từ chối URL MP4: " + str(res.get("reason", "")))
	else:
		waited = 0.0
		while world.tv.video_player.stream == null and waited < 30.0:
			await get_tree().create_timer(0.5).timeout
			waited += 0.5
		await get_tree().create_timer(1.5).timeout
		var vstream: VideoStream = world.tv.video_player.stream
		if vstream == null:
			failures.append("TV không tải/giải mã được MP4 (status: %s)" % world.tv.video_status.text)
		else:
			var vlength: float = world.tv.video_player.get_stream_length()
			print("[MEDIA-TEST] video stream=%s length=%.2fs playing=%s pos=%.2f" % [vstream.get_class(), vlength, str(world.tv.video_player.is_playing()), world.tv.video_player.stream_position])
			if vlength <= 0.0:
				failures.append("video stream có độ dài 0")
	# Cache video: thống kê, dừng video rồi xoá sạch.
	var cache_before: Dictionary = world.tv.video_cache_stats()
	world.tv.stop_video()
	await get_tree().create_timer(0.5).timeout
	var cleared: Dictionary = world.tv.clear_video_cache()
	var cache_after: Dictionary = world.tv.video_cache_stats()
	print("[MEDIA-TEST] video cache: %d tệp / %d bytes -> xoá %d, còn %d" % [
		int(cache_before.get("files", 0)), int(cache_before.get("bytes", 0)),
		int(cleared.get("removed", 0)), int(cache_after.get("files", 0)),
	])
	if not bool(cleared.get("ok", false)) or int(cache_after.get("files", 0)) != 0:
		failures.append("không xoá được cache video")
	# Auto-trim: tạo tệp giả rồi gọi trim với ngưỡng nhỏ để kiểm tra LRU.
	for i in 3:
		_write_cache_file("user://tv_video_cache/test_%d.bin" % i, 400)
	world.tv._trim_video_cache("", 800)
	var trimmed: Dictionary = world.tv.video_cache_stats()
	print("[MEDIA-TEST] trim 3x400B -> %d tệp / %d bytes (ngưỡng 800)" % [int(trimmed.get("files", 0)), int(trimmed.get("bytes", 0))])
	if int(trimmed.get("bytes", 0)) > 800 or int(trimmed.get("files", 0)) != 2:
		failures.append("auto-trim không xoá đủ tệp cũ")
	# keep_path phải sống sót kể cả khi ngưỡng là 0.
	_write_cache_file("user://tv_video_cache/keep.bin", 100)
	_write_cache_file("user://tv_video_cache/drop.bin", 100)
	world.tv._trim_video_cache("user://tv_video_cache/keep.bin", 0)
	var kept: Dictionary = world.tv.video_cache_stats()
	print("[MEDIA-TEST] keep_path -> %d tệp / %d bytes" % [int(kept.get("files", 0)), int(kept.get("bytes", 0))])
	if not FileAccess.file_exists("user://tv_video_cache/keep.bin"):
		failures.append("auto-trim xoá mất tệp vừa tải (keep_path)")
	if FileAccess.file_exists("user://tv_video_cache/drop.bin"):
		failures.append("auto-trim không xoá tệp cũ khi ngưỡng 0")
	world.tv.clear_video_cache()
	var elapsed := Time.get_ticks_msec() - started
	if failures.is_empty():
		print("[MEDIA-TEST] OK trong %d ms" % elapsed)
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("[MEDIA-TEST] FAIL: " + str(failure))
		get_tree().quit(1)


func _write_cache_file(path: String, size: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	var blob := PackedByteArray()
	blob.resize(size)
	file.store_buffer(blob)
	file.close()


func _run_ui_test() -> void:
	print("[UI-TEST] mở overlay DJ + máy tính")
	var failures: Array = []
	_boot_client()
	# Chờ splash chuyển xong sang login/main_menu rồi mới vào game, tránh việc
	# show_screen đóng overlay vừa mở. Không dùng mốc thời gian cố định: nếu
	# phiên đăng nhập còn hạn, boot() còn await Api.me() nên có thể lâu hơn.
	var boot_wait := 0.0
	while ui != null and str(ui.get("current_screen")) == "splash" and boot_wait < 12.0:
		await get_tree().create_timer(0.2).timeout
		boot_wait += 0.2
	await get_tree().create_timer(0.4).timeout
	start_solo()
	await get_tree().create_timer(1.0).timeout
	if ui == null:
		printerr("[UI-TEST] FAIL: thiếu UIRoot")
		get_tree().quit(1)
		return
	App.open_computer("music")
	await get_tree().create_timer(0.8).timeout
	if not (ui.get("overlays") as Dictionary).has("computer"):
		failures.append("overlay máy tính không mở")
	else:
		print("[UI-TEST] computer overlay OK")
	ui.call("close_overlay")
	await get_tree().create_timer(0.4).timeout
	App.open_dj_panel()
	await get_tree().create_timer(0.8).timeout
	if not (ui.get("overlays") as Dictionary).has("dj"):
		failures.append("overlay DJ không mở")
	else:
		print("[UI-TEST] DJ overlay OK")
	ui.call("close_overlay")
	await get_tree().create_timer(0.4).timeout
	App.open_tv_panel()
	await get_tree().create_timer(0.8).timeout
	if not (ui.get("overlays") as Dictionary).has("computer"):
		failures.append("overlay TV không mở")
	else:
		print("[UI-TEST] TV overlay OK")
	ui.call("close_overlay")
	await get_tree().create_timer(0.3).timeout
	if failures.is_empty():
		print("[UI-TEST] OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("[UI-TEST] FAIL: " + str(failure))
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
	# Chờ thư viện API để ảnh TV lớn có bài thật thay vì trạng thái "đang tải".
	var library_wait := 0.0
	while world.dj.library_loading and library_wait < 20.0:
		await get_tree().create_timer(0.25).timeout
		library_wait += 0.25
	if world.dj.track_count() > 0:
		var tracks: Array = world.dj.playlist()
		world.dj.play_track(str(tracks[0].get("id", "")))
		await get_tree().create_timer(2.0).timeout
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
	var dev_image: Image = world.tv.get("dev_viewport").get_texture().get_image()
	var dev_err: int = dev_image.save_png(dir.path_join("tv_dev.png"))
	print("[SHOT] tv_dev -> %s (%s) size=%s" % [dev_err, error_string(dev_err), dev_image.get_size()])
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


func _run_net_smoke(target: String) -> void:
	## Chấp nhận "port" (127.0.0.1), hoặc "host:port", hoặc "host:port:ticket"
	## để kiểm tra dedicated server thật trên VPS với ticket thật.
	var host := "127.0.0.1"
	var port := 7000
	var ticket := "dev-ticket"
	var parts := target.split(":")
	if parts.size() >= 2 and parts[1].is_valid_int():
		host = parts[0]
		port = int(parts[1])
		if parts.size() >= 3:
			ticket = parts[2]
	elif parts.size() == 1 and parts[0].is_valid_int():
		port = int(parts[0])
	print("[NET-SMOKE] kết nối tới %s:%d (ticket %s)" % [host, port, "dev" if ticket == "dev-ticket" else "thật"])
	# Tuỳ chọn: --tv-url=https://…/video.mp4 để kiểm tra đồng bộ TV.
	var tv_url := ""
	var watch_url := ""
	for arg in AppConfig.launch_args:
		if arg.begins_with("--tv-url="):
			tv_url = arg.trim_prefix("--tv-url=")
		elif arg.begins_with("--watch-tv="):
			watch_url = arg.trim_prefix("--watch-tv=")
	Net.tv_received.connect(func(state: Dictionary):
		print("[NET-SMOKE] tv_received url=%s kind=%s" % [str(state.get("url", "")), str(state.get("kind", ""))]))
	Net.player_joined.connect(func(id: int, _info: Dictionary):
		print("[NET-SMOKE] player_joined id=%d" % id))
	Net.join_failed.connect(func(reason: String): printerr("[NET-SMOKE] join_failed: " + reason))
	_load_world({"code": "NETSMOKE", "name": "Net Smoke", "maxPlayers": 8}, false)
	Net.connect_to_room(host, port, ticket)
	# Xác minh ticket đi vòng qua backend (có thể mất vài giây nếu server ở xa),
	# nên chờ đủ lâu trước khi kết luận.
	await get_tree().create_timer(12.0).timeout
	var players_count := Net.players.size()
	var scene_count := world.players.size() if world != null else 0
	print("[NET-SMOKE] players=%d roster=%d scene=%d local=%d owner=%d connected=%s" % [players_count, Net.roster.size(), scene_count, Net.local_peer_id, Net.owner_id, str(Net.is_online())])
	var ok := players_count >= 1 and Net.is_online()
	# Mỗi người trong danh sách phòng phải có avatar trong scene, nếu không thì
	# người vào sau sẽ không thấy ai (bug đồng bộ spawn).
	if ok and scene_count != players_count:
		ok = false
		printerr("[NET-SMOKE] FAIL: scene có %d người nhưng phòng có %d" % [scene_count, players_count])
	if ok and watch_url != "":
		# Client thứ hai chỉ quan sát: xác nhận nhận được đúng trạng thái TV
		# do client đầu gửi, kể cả khi vào phòng sau.
		var watched := str(Net.tv_state.get("url", ""))
		print("[NET-SMOKE] watch tv_state=%s" % watched)
		if watched != watch_url:
			ok = false
			printerr("[NET-SMOKE] FAIL: không nhận được TV state từ client khác (nhận '%s')" % watched)
	elif ok and tv_url != "":
		Net.send_tv({"url": tv_url, "title": "TV sync test", "playing": true, "kind": "video", "status": "Đồng bộ TV", "volume": 1.0, "position": 0.0, "updated_at": Time.get_unix_time_from_system()})
		await get_tree().create_timer(3.0).timeout
		var got := str(Net.tv_state.get("url", ""))
		print("[NET-SMOKE] tv_state=%s" % got)
		if got != tv_url:
			ok = false
			printerr("[NET-SMOKE] FAIL: TV không đồng bộ (nhận '%s')" % got)
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
	if ok and "--dj-test" in AppConfig.launch_args:
		# Kiểm tra tải thư viện + phát nhạc trong phòng online.
		var dj = world.dj
		var waited := 0.0
		while dj.library_loading and waited < 25.0:
			await get_tree().create_timer(0.25).timeout
			waited += 0.25
		print("[NET-SMOKE] dj library=%d loading=%s error=%s" % [dj.track_count(), str(dj.library_loading), dj.library_error])
		if dj.track_count() == 0:
			ok = false
			printerr("[NET-SMOKE] FAIL: thư viện nhạc rỗng")
		else:
			var tracks: Array = dj.playlist()
			var load_started := Time.get_ticks_msec()
			dj.play_track(str(tracks[0].get("id", "")))
			var wait := 0.0
			var next_sync := 0.0
			while dj.is_loading_track() and wait < 40.0:
				await get_tree().create_timer(0.25).timeout
				wait += 0.25
				# Giả lập echo đồng bộ 6 giây của server trong lúc đang tải:
				# trước đây mỗi state này huỷ lượt tải và làm treo "Đang tải…".
				if wait >= next_sync:
					next_sync += 1.0
					dj.call("_apply_state", dj.build_state())
			var load_ms := Time.get_ticks_msec() - load_started
			print("[NET-SMOKE] dj playing=%s track=%s loading=%s load_ms=%d" % [str(dj.playing), dj.current_track_id, str(dj.is_loading_track()), load_ms])
			if not dj.playing:
				ok = false
				printerr("[NET-SMOKE] FAIL: không phát được nhạc")
			await get_tree().create_timer(1.5).timeout
			print("[NET-SMOKE] dj_state_track=%s" % str(Net.dj_state.get("track_id", "")))
	if ok and "--owner-leave" in AppConfig.launch_args:
		# Kiểm tra chủ phòng chủ động rời -> server đóng phòng ngay.
		var closed := [false]
		Net.room_closed.connect(func(_reason: String): closed[0] = true)
		print("[NET-SMOKE] chủ phòng rời phòng...")
		Net.notify_owner_leaving()
		await get_tree().create_timer(2.0).timeout
		print("[NET-SMOKE] room_closed=%s" % str(closed[0]))
		if not closed[0]:
			ok = false
			printerr("[NET-SMOKE] FAIL: không nhận cli_room_closed")
	if ok and "--reconnect-test" in AppConfig.launch_args:
		# Giả lập mạng lag: đóng peer rồi để Net tự kết nối lại.
		print("[NET-SMOKE] giả lập mất kết nối...")
		Net._handle_connection_lost("test")
		await get_tree().create_timer(20.0).timeout
		print("[NET-SMOKE] reconnected online=%s joined=%s" % [str(Net.is_online()), str(Net._joined)])
		if not Net.is_online() or not Net._joined:
			ok = false
			printerr("[NET-SMOKE] FAIL: không kết nối lại được")
	print("[NET-SMOKE] %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
