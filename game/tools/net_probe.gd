extends SceneTree
## Tiện ích kiểm tra một dedicated server ENet từ xa.
## Chạy: godot --headless --path game --script res://tools/net_probe.gd -- <host> <port>
## Chỉ kiểm tra handshake UDP của ENet — không cần game ticket.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var host := args[0] if args.size() > 0 else "serverbar1.nguyenphuquyet.online"
	var port := int(args[1]) if args.size() > 1 else 3221
	print("[PROBE] kết nối ENet tới %s:%d" % [host, port])
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		print("[PROBE] FAIL create_client=%s" % error_string(err))
		quit(1)
		return
	var status := MultiplayerPeer.CONNECTION_CONNECTING
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		status = peer.get_connection_status()
		if status != MultiplayerPeer.CONNECTION_CONNECTING:
			break
		OS.delay_msec(50)
	print("[PROBE] status=%d (%s)" % [status, "OK" if status == MultiplayerPeer.CONNECTION_CONNECTED else "FAIL"])
	peer.close()
	quit(0 if status == MultiplayerPeer.CONNECTION_CONNECTED else 1)
