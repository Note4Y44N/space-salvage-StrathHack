extends Control
## Main menu, built in code: name and IP boxes plus Host and Join buttons.
## The world scene does the actual connecting (see world.gd).

const FUN_NAMES := ["Cosmo", "Nova", "Spudnik", "Orbit", "Comet", "Gizmo", "Rocket", "Nebula"]

var name_edit: LineEdit
var ip_edit: LineEdit


func _ready() -> void:
	if NetworkManager.player_name == "":
		NetworkManager.player_name = "%s%d" % [FUN_NAMES.pick_random(), randi_range(1, 99)]
	_build_ui()
	if NetworkManager.auto_start != "":
		var as_host := NetworkManager.auto_start == "host"
		NetworkManager.auto_start = ""  # only skip the menu once
		_start.call_deferred(as_host)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	_add_label(box, "SPACE SALVAGE", 56, Color(1.0, 0.82, 0.3))
	_add_label(box, "Grab space gold, mind your air, and talk your crew home.", 16, Color(0.75, 0.8, 0.95))
	name_edit = _add_field(box, "Your name", NetworkManager.player_name)
	ip_edit = _add_field(box, "Host IP", NetworkManager.join_ip)
	ip_edit.text_submitted.connect(func(_text: String) -> void: _start(false))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_add_button(buttons, "Host", _start.bind(true))
	_add_button(buttons, "Join", _start.bind(false))

	if NetworkManager.last_error != "":
		_add_label(box, NetworkManager.last_error, 15, Color(1.0, 0.45, 0.4))
	var ips := NetworkManager.local_ips()
	if not ips.is_empty():
		_add_label(box, "Hosting? Friends join your LAN IP: " + ", ".join(ips), 13, Color(0.6, 0.7, 0.8))
	_add_label(box, "WASD / arrows: move    E: sell    1-3: buy    Esc: leave", 13, Color(0.6, 0.7, 0.8))


func _start(as_host: bool) -> void:
	var typed_name := name_edit.text.strip_edges().left(16)
	var typed_ip := ip_edit.text.strip_edges()
	NetworkManager.player_name = typed_name if typed_name != "" else "Spacer"
	NetworkManager.join_ip = typed_ip if typed_ip != "" else "127.0.0.1"
	NetworkManager.want_host = as_host
	NetworkManager.last_error = ""
	get_tree().change_scene_to_file("res://world.tscn")


func _add_label(parent: Control, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _add_field(parent: Control, placeholder: String, text: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.text = text
	edit.custom_minimum_size = Vector2(0, 38)
	parent.add_child(edit)
	return edit


func _add_button(parent: Control, text: String, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_pressed)
	parent.add_child(button)
