extends Control
## Elite Space Salvage main menu with full multi-state button themes and gorgeous layout.

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
	# Background image
	var bg := TextureRect.new()
	var bg_path := "res://Imgs/identity.png"
	if ResourceLoader.exists(bg_path):
		bg.texture = load(bg_path)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# High-end sci-fi container panel with subtle borders and shadows
	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.03, 0.08, 0.90)
	panel_style.border_color = Color(0.2, 0.7, 0.9, 0.6)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.content_margin_left = 32
	panel_style.content_margin_right = 32
	panel_style.content_margin_top = 32
	panel_style.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	_add_label(box, "SPACE SALVAGE", 44, Color(1.0, 0.85, 0.3))
	_add_label(box, "Grab space gold, mind your air, and get your crew home.", 13, Color(0.8, 0.85, 1.0))
	
	name_edit = _add_field(box, "Your name", NetworkManager.player_name)
	ip_edit = _add_field(box, "Join code or IP", NetworkManager.join_ip)
	ip_edit.text_submitted.connect(func(_text: String) -> void: _start(false))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	box.add_child(buttons)
	
	# Host uses primary button assets
	_add_styled_button(buttons, "Host Game", true, _start.bind(true))
	# Join uses secondary button assets
	_add_styled_button(buttons, "Join Game", false, _start.bind(false))

	if NetworkManager.last_error != "":
		_add_label(box, NetworkManager.last_error, 14, Color(1.0, 0.4, 0.4))
		
	var ips := NetworkManager.local_ips()
	if not ips.is_empty():
		_add_label(box, "Hosting? Your code: %s (IP: %s)" % [NetworkManager.my_code(), ips[0]], 12, Color(0.5, 0.8, 1.0))
		
	_add_label(box, "WASD / arrows: move  |  E: sell  |  1-3: buy  |  Esc: leave", 11, Color(0.6, 0.65, 0.75))


func _start(as_host: bool) -> void:
	var typed_name := name_edit.text.strip_edges().left(16)
	var typed_ip := ip_edit.text.strip_edges()
	NetworkManager.player_name = typed_name if typed_name != "" else "Spacer"
	NetworkManager.join_ip = NetworkManager.code_to_ip(typed_ip) if typed_ip != "" else "127.0.0.1"
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
	edit.custom_minimum_size = Vector2(0, 42)
	
	var box_style := StyleBoxFlat.new()
	box_style.bg_color = Color(0.01, 0.02, 0.05, 0.95)
	box_style.border_color = Color(0.2, 0.5, 0.7, 0.8)
	box_style.set_border_width_all(1)
	box_style.corner_radius_top_left = 6
	box_style.corner_radius_top_right = 6
	box_style.corner_radius_bottom_left = 6
	box_style.corner_radius_bottom_right = 6
	
	# Add these lines to give the text breathing room from the borders:
	box_style.content_margin_left = 12
	box_style.content_margin_right = 12
	
	edit.add_theme_stylebox_override("normal", box_style)
	edit.add_theme_stylebox_override("focus", box_style)
	edit.add_theme_color_override("font_color", Color.WHITE)
	edit.add_theme_color_override("font_uneditable_color", Color.WHITE)
	
	parent.add_child(edit)
	return edit


func _add_styled_button(parent: Control, text: String, is_primary: bool, on_pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var prefix = "primary" if is_primary else "secondary"
	
	# Assign textures for all states using res://Imgs/
	var normal_tex = load("res://Imgs/button_%s_normal.png" % prefix) if is_primary else load("res://Imgs/button_secondary_normal.png")
	var hover_tex = load("res://Imgs/button_%s_hover.png" % prefix) if is_primary else load("res://Imgs/button_secondary_hover.png")
	var pressed_tex = load("res://Imgs/button_%s_pressed.png" % prefix) if is_primary else load("res://Imgs/button_secondary_pressed.png")
	var focus_tex = load("res://Imgs/button_%s_focus.png" % prefix) if is_primary else load("res://Imgs/button_secondary_focus.png")
	var disabled_tex = load("res://Imgs/button_%s_disabled.png" % prefix) if is_primary else load("res://Imgs/button_secondary_disabled.png")
	
	if is_primary:
		normal_tex = load("res://Imgs/button_primary_normal.png")
		hover_tex = load("res://Imgs/button_primary_hover.png")
		pressed_tex = load("res://Imgs/button_primary_pressed.png")
		focus_tex = load("res://Imgs/button_primary_focus.png")
		disabled_tex = load("res://Imgs/button_primary_disabled.png")

	button.add_theme_stylebox_override("normal", _create_texture_style(normal_tex))
	button.add_theme_stylebox_override("hover", _create_texture_style(hover_tex))
	button.add_theme_stylebox_override("pressed", _create_texture_style(pressed_tex))
	button.add_theme_stylebox_override("focus", _create_texture_style(focus_tex))
	button.add_theme_stylebox_override("disabled", _create_texture_style(disabled_tex))
	
	# Force button text to crisp black for high contrast against the bright pixel background
	button.add_theme_color_override("font_color", Color.BLACK)
	button.add_theme_color_override("font_pressed_color", Color.BLACK)
	button.add_theme_color_override("font_hover_color", Color.BLACK)
	button.add_theme_color_override("font_focus_color", Color.BLACK)
	
	button.pressed.connect(on_pressed)
	parent.add_child(button)


func _create_texture_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	if texture:
		style.texture = texture
	return style
