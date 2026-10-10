extends Node
## Autoload "NetworkManager": ENet host/join, leaving, and dev command-line flags.
##
## Dev flags go after "--" (or in Debug > Customize Run Instances > Launch Arguments):
##   --host / --join=IP     skip the menu
##   --name=Bob             player name
##   --bot                  autopilot (see dev_bot.gd) for solo/headless testing
##   --local                host binds to 127.0.0.1 only (no firewall prompt)
##   --money=5000           host starts with team money (test the shop/win screen)
##   --quit-after-sec=N     quit automatically

const PORT := 9999
const MAX_PLAYERS := 8

var player_name := ""
var join_ip := "127.0.0.1"
var want_host := false
var last_error := ""

var auto_start := ""  # "host", "join" or ""
var bot_mode := false
var bind_local_only := false
var dev_money := 0


func _ready() -> void:
	_parse_cmdline()


func host() -> Error:
	var peer := ENetMultiplayerPeer.new()
	if bind_local_only:
		peer.set_bind_ip("127.0.0.1")
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		last_error = "Could not host on port %d. Is another game already hosting?" % PORT
		return err
	multiplayer.multiplayer_peer = peer
	print("[%s] hosting on port %d" % [player_name, PORT])
	return OK


func join(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		last_error = "Could not connect to %s." % ip
		return err
	multiplayer.multiplayer_peer = peer
	print("[%s] joining %s:%d" % [player_name, ip, PORT])
	return OK


## Disconnect and go back to the menu, optionally showing an error there.
func leave(error_text := "") -> void:
	last_error = error_text
	if error_text != "":
		print("[%s] %s" % [player_name, error_text])
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	GameState.reset()
	get_tree().change_scene_to_file.call_deferred("res://menu.tscn")


## LAN IPv4 addresses friends can use to join this machine, best first:
## real Wi-Fi/Ethernet before virtual adapters (VirtualBox, Hyper-V/WSL,
## Bluetooth...) that friends can't reach.
func local_ips() -> PackedStringArray:
	var scored := []
	for iface in IP.get_local_interfaces():
		var label := String(iface["friendly"]).to_lower()
		for ip: String in iface["addresses"]:
			if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
				scored.append([_adapter_score(label, ip), ip])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var ips := PackedStringArray()
	for entry in scored:
		ips.append(entry[1])
	return ips


func _adapter_score(label: String, ip: String) -> int:
	if ip.begins_with("192.168.56."):  # VirtualBox's default host-only network
		return 0
	for word in ["virtual", "vmware", "vethernet", "hyper-v", "wsl", "bluetooth", "loopback", "docker"]:
		if word in label:
			return 0
	for word in ["wi-fi", "wifi", "wlan", "wireless"]:
		if word in label:
			return 3
	return 2 if "ethernet" in label else 1


func _parse_cmdline() -> void:
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1) if "=" in arg else ""
		if arg == "--host":
			auto_start = "host"
		elif arg.begins_with("--join"):
			auto_start = "join"
			if value != "":
				join_ip = value
		elif arg.begins_with("--name="):
			player_name = value
		elif arg == "--bot":
			bot_mode = true
		elif arg == "--local":
			bind_local_only = true
		elif arg.begins_with("--money="):
			dev_money = value.to_int()
		elif arg.begins_with("--quit-after-sec="):
			get_tree().create_timer(value.to_float()).timeout.connect(get_tree().quit)
	if DisplayServer.get_name() == "headless":
		Engine.max_fps = 60
		


## Short join code: the end of this machine's IP. my_code() is the last number
## (e.g. "144"); my_code(2) is the last two (e.g. "117.144"), for big networks
## where the third number differs between laptops.
func my_code(part_count := 1) -> String:
	var ips := local_ips()
	if ips.is_empty():
		return ""
	var parts := ips[0].split(".")
	return ".".join(parts.slice(4 - part_count))


func code_to_ip(code: String) -> String:	
	var code_parts := code.split(".")
	var ips := local_ips()
	
	if code_parts.size() >= 4 or ips.is_empty():
		return code
	var parts := ips[0].split(".")       # our own IP, e.g. ["10", "12", "117", "50"]
	parts.resize(4 - code_parts.size())  # keep the front, e.g. ["10", "12"]
	parts.append_array(code_parts)       # add the code, e.g. ["10", "12", "117", "144"]
	return ".".join(parts)               # "10.12.117.144"
	
