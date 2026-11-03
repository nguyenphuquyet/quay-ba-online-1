extends SceneTree
## ENet server tối giản để kiểm tra tools/net_probe.gd (không cần cả game).
## Chạy: godot --headless --path game --script res://tools/net_echo_server.gd -- 7001

var _peer: ENetMultiplayerPeer


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0]) if args.size() > 0 else 7001
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, 8)
	if err != OK:
		print("[ECHO] FAIL create_server=%s" % error_string(err))
		quit(1)
		return
	print("[ECHO] listening on %d" % port)


func _process(_delta: float) -> bool:
	_peer.poll()
	return false


func _poll() -> void:
	pass
