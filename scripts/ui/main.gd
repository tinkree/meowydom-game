extends Control

const Rules = preload("res://scripts/rules/battle_rules.gd")
const AI = preload("res://scripts/rules/battle_ai.gd")

const INK := Color("2c2416")
const CREAM := Color("fff8ee")
const PAPER := Color("f3e6d0")
const GREEN := Color("2f6a45")
const GREEN_DARK := Color("214833")
const CLAY := Color("c46b3a")
const ROSE := Color("8c2f2f")
const BOARD_RATIO := 1492.0 / 1054.0
const SOFA_SLOTS: Array[Rect2] = [
	Rect2(0.332, 0.385, 0.112, 0.120),
	Rect2(0.448, 0.385, 0.112, 0.120),
	Rect2(0.564, 0.385, 0.112, 0.120),
]
const RUG_SLOTS: Array[Rect2] = [
	Rect2(0.284, 0.548, 0.132, 0.118),
	Rect2(0.440, 0.548, 0.122, 0.118),
	Rect2(0.586, 0.548, 0.134, 0.118),
	Rect2(0.284, 0.692, 0.132, 0.125),
	Rect2(0.440, 0.692, 0.122, 0.125),
	Rect2(0.586, 0.692, 0.134, 0.125),
]
const BOSS_SLOT := Rect2(0.068, 0.390, 0.125, 0.150)

var rules = Rules.new()
var host: MarginContainer
var human_color := "black"
var ai_color := "calico"
var _screen := "menu"
var _selected := ""
var _pending: Dictionary = {}
var _picked: Array = []
var _error := ""
var _ai_busy := false
var _ai_token := 0
var _shot := ""
var _tex := {}

var scroll: ScrollContainer
var board_box: BoxContainer
var action_box: VBoxContainer
var _army_buttons: Array[Button] = []
var _ai_army_button: Button
var log_label: Label
var header_label: Label
var die_rect: TextureRect
var status_label: Label
var modal: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	host = MarginContainer.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		host.add_theme_constant_override(side, 16)
	add_child(host)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_shot = str(args[0])
	if _shot == "deploy" or _shot == "battle":
		_build(_shot)
	else:
		_build("menu")
	if _shot != "":
		_capture_shot()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


func _on_back() -> void:
	if modal != null:
		_close_modal()
		return
	match _screen:
		"menu":
			get_tree().quit()
		"armies", "initiative":
			_go("menu")
		"deploy":
			_go("armies")
		"battle":
			_confirm_leave()
		"result":
			_go("menu")


func _go(screen: String) -> void:
	call_deferred("_build", screen)


func _build(screen: String) -> void:
	_screen = screen
	_close_modal()
	_wipe(host)
	_selected = ""
	_pending = {}
	_picked = []
	_error = ""
	match screen:
		"menu":
			_build_menu()
		"armies":
			_build_armies()
		"deploy":
			if rules.pieces.is_empty() or rules.phase != "deploy":
				_start_match()
			_build_deploy()
		"initiative":
			_build_initiative()
		"battle":
			if rules.phase != "battle":
				_boot_sample_battle()
			_build_battle()
		"result":
			_build_result()


func _capture_shot() -> void:
	await get_tree().create_timer(0.5).timeout
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://shot_%s.png" % _shot)
	image.save_png(path)
	print("SHOT ", path)
	get_tree().quit()


func _start_match() -> void:
	_cancel_ai()
	rules = Rules.new()
	rules.setup_match(human_color, ai_color)
	rules.player_names = ["You", "AI"]


func _boot_sample_battle() -> void:
	_start_match()
	AI.deploy(rules, 0)
	AI.deploy(rules, 1)
	rules.begin_battle(0)
	rules.force_roll(4)


func _wipe(node: Node) -> void:
	while node.get_child_count() > 0:
		var child := node.get_child(0)
		node.remove_child(child)
		child.queue_free()


func _build_menu() -> void:
	var box := _center_column()
	var logo := TextureRect.new()
	logo.texture = _art("res://assets/ui/logo.png")
	logo.custom_minimum_size = Vector2(280, 160)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(logo)
	box.add_child(_title("Living Room Wars"))
	box.add_child(_body("Roll. Choose one action. Attack.\nProve the battle against an AI. Online matches come later."))
	box.add_child(_button("Play vs AI", _go.bind("armies"), GREEN))
	box.add_child(_button("How to play", _open_help, CREAM, INK))
	box.add_child(_body("© 2026 Tinkree Maker Labs"))


func _build_armies() -> void:
	var box := _center_column()
	box.add_child(_title("Choose your cat army"))
	box.add_child(_body("The AI takes a different army. There is one living-room fort in this battle."))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	_army_buttons.clear()
	for color in Rules.COLORS:
		var choice := _army_choice(str(color))
		_army_buttons.append(choice)
		grid.add_child(choice)
	_ai_army_button = _button("AI army: %s" % str(Rules.COLOR_NAMES[ai_color]), _cycle_ai, CREAM, INK)
	box.add_child(_ai_army_button)
	box.add_child(_button("Deploy", _go.bind("deploy"), GREEN))
	box.add_child(_button("Back", _go.bind("menu"), CREAM, INK))


func _army_choice(color: String) -> Button:
	var selected := color == human_color
	var button := _button(
		str(Rules.COLOR_NAMES[color]),
		_pick_human.bind(color),
		GREEN if selected else CREAM,
		CREAM if selected else INK
	)
	button.set_meta("army_color", color)
	button.custom_minimum_size = Vector2(220, 72)
	button.icon = _art("res://assets/armies/%s/A1.png" % color)
	button.expand_icon = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	return button


func _pick_human(color: String) -> void:
	human_color = color
	if ai_color == human_color:
		_cycle_ai_value()
	_paint_armies()


func _cycle_ai() -> void:
	_cycle_ai_value()
	_paint_armies()


func _paint_armies() -> void:
	for button in _army_buttons:
		if not is_instance_valid(button):
			continue
		var selected := str(button.get_meta("army_color")) == human_color
		_paint_button(button, GREEN if selected else CREAM, CREAM if selected else INK)
	if is_instance_valid(_ai_army_button):
		_ai_army_button.text = "AI army: %s" % str(Rules.COLOR_NAMES[ai_color])


func _cycle_ai_value() -> void:
	var index := Rules.COLORS.find(ai_color)
	for _step in Rules.COLORS.size():
		index = (index + 1) % Rules.COLORS.size()
		if str(Rules.COLORS[index]) != human_color:
			ai_color = str(Rules.COLORS[index])
			return


func _build_deploy() -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 16)
	host.add_child(row)
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	board_box = VBoxContainer.new()
	board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_box.add_theme_constant_override("separation", 10)
	scroll.add_child(board_box)
	_fill_deploy_board()
	var side_panel := _side_panel()
	row.add_child(side_panel)
	var side := _side_box(side_panel)
	side.add_child(_title("Deploy"))
	side.add_child(_body("Tap one of your pieces, then tap a sofa or rug slot. The Boss stays on the floor. One Yarn Cannon can use the sofa or the rug, and it needs two slots side by side."))
	status_label = _body("")
	side.add_child(status_label)
	_refresh_deploy_status()
	side.add_child(_button("Quick defense", _quick_defense, CLAY))
	side.add_child(_button("Clear sofa and rug", _clear_specials, CREAM, INK))
	side.add_child(_button("Put selected on the floor", _send_selected_floor, CREAM, INK))
	side.add_child(_button("Lock in defenses", _lock_deploy, GREEN))
	side.add_child(_button("Back", _go.bind("armies"), CREAM, INK))


func _fill_deploy_board() -> void:
	_wipe(board_box)
	board_box.add_child(_army_block(0, true))


func _refresh_deploy_status() -> void:
	if status_label == null:
		return
	var name := "nothing selected"
	if _selected != "":
		var p = rules.piece(_selected)
		if not p.is_empty():
			name = _kind_label(p)
	var note := _error if _error != "" else "Selected: %s" % name
	status_label.text = note


func _quick_defense() -> void:
	_error = AI.deploy(rules, 0)
	_selected = ""
	_fill_deploy_board()
	_refresh_deploy_status()


func _clear_specials() -> void:
	for p in rules.pieces:
		if int(p["owner"]) != 0:
			continue
		rules.place(str(p["id"]), "floor", -1)
	_selected = ""
	_error = ""
	_fill_deploy_board()
	_refresh_deploy_status()


func _send_selected_floor() -> void:
	if _selected == "":
		_error = "Select a piece first."
	else:
		_error = rules.place(_selected, "floor", -1)
		if _error == "":
			_selected = ""
	_fill_deploy_board()
	_refresh_deploy_status()


func _lock_deploy() -> void:
	var err = rules.lock_deploy(0)
	if err != "":
		_error = err
		_refresh_deploy_status()
		return
	err = AI.deploy(rules, 1)
	if err != "":
		_error = err
		_refresh_deploy_status()
		return
	err = rules.lock_deploy(1)
	if err != "":
		_error = err
		_refresh_deploy_status()
		return
	_go("initiative")


func _build_initiative() -> void:
	var box := _center_column()
	box.add_child(_title("Who moves first?"))
	box.add_child(_body("Each army rolls. The higher roll takes the first attack. A tie is rolled again."))
	if rules.initiative_rolls.is_empty():
		box.add_child(_button("Roll the die", _do_initiative, GREEN))
	else:
		var last: Array = rules.initiative_rolls[rules.initiative_rolls.size() - 1]
		box.add_child(_die_row(int(last[0]), int(last[1])))
		var line := "You rolled %d. AI rolled %d." % [int(last[0]), int(last[1])]
		if rules.initiative_rolls.size() > 1:
			line += " Ties were rerolled."
		box.add_child(_body(line))
		box.add_child(_body("%s goes first." % str(rules.player_names[rules.current_player])))
		box.add_child(_button("Start the battle", _go.bind("battle"), GREEN))


func _do_initiative() -> void:
	rules.roll_initiative()
	_go("initiative")


func _die_row(a: int, b: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.add_child(_die_view(a, "You"))
	row.add_child(_die_view(b, "AI"))
	return row


func _die_view(face: int, caption: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(72, 72)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture = _art("res://assets/ui/d%d.png" % face)
	box.add_child(rect)
	box.add_child(_body(caption))
	return box


func _build_battle() -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	host.add_child(column)
	header_label = _title("")
	column.add_child(header_label)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	board_box = HBoxContainer.new()
	board_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_box.add_theme_constant_override("separation", 10)
	scroll.add_child(board_box)
	scroll.resized.connect(func() -> void:
		if board_box != null:
			board_box.custom_minimum_size.x = scroll.size.x - 4.0
	)
	var side_panel := _side_panel()
	row.add_child(side_panel)
	var side := _side_box(side_panel)
	die_rect = TextureRect.new()
	die_rect.custom_minimum_size = Vector2(72, 72)
	die_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	die_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	side.add_child(die_rect)
	status_label = _body("")
	side.add_child(status_label)
	action_box = VBoxContainer.new()
	action_box.add_theme_constant_override("separation", 8)
	side.add_child(action_box)
	log_label = _body("")
	log_label.custom_minimum_size = Vector2(0, 140)
	side.add_child(log_label)
	side.add_child(_button("How to play", _open_help, CREAM, INK))
	side.add_child(_button("Leave battle", _confirm_leave, CREAM, INK))
	_fill_battle()
	_maybe_ai()


func _fill_battle() -> void:
	if board_box == null:
		return
	var kept := 0
	if scroll != null:
		kept = scroll.scroll_vertical
	_wipe(board_box)
	board_box.add_child(_army_block(1, false))
	board_box.add_child(_army_block(0, false))
	if header_label != null:
		var turn := "Your attack" if rules.current_player == 0 else "AI attack"
		if rules.phase == "game_over":
			turn = "Battle over"
		header_label.text = "You %d VP    ·    AI %d VP    ·    %s" % [rules.vp(0), rules.vp(1), turn]
	_sync_die()
	_fill_actions()
	_sync_log()
	if scroll != null:
		scroll.scroll_vertical = kept


func _sync_die() -> void:
	if die_rect == null:
		return
	if rules.roll >= 1 and rules.roll <= 6 and rules.stage == "act":
		die_rect.texture = _art("res://assets/ui/d%d.png" % rules.roll)
	else:
		die_rect.texture = null


func _sync_log() -> void:
	if log_label == null:
		return
	var start := maxi(0, rules.log.size() - 6)
	var lines: PackedStringArray = []
	for i in range(start, rules.log.size()):
		lines.append(str(rules.log[i]))
	log_label.text = "\n".join(lines)


func _fill_actions() -> void:
	if action_box == null:
		return
	_wipe(action_box)
	if status_label != null:
		status_label.text = _error
	if _ai_busy or (rules.current_player == 1 and rules.phase == "battle"):
		action_box.add_child(_body("The other army is moving."))
		return
	if rules.phase != "battle":
		return
	if rules.stage == "roll":
		action_box.add_child(_button("Roll", _human_roll, GREEN))
		action_box.add_child(_body("Roll, then choose one action."))
		return
	if not _pending.is_empty():
		action_box.add_child(_body(_target_hint()))
		action_box.add_child(_button("Confirm", _confirm_action, GREEN))
		action_box.add_child(_button("Cancel", _cancel_pending, CREAM, INK))
		return
	var any := false
	for spec in rules.legal_types():
		any = true
		var spec_copy: Dictionary = spec
		if str(spec["type"]) == "pass":
			action_box.add_child(_button("No valid move — end turn", _play_pass, CLAY))
		else:
			action_box.add_child(_button(rules.describe(spec_copy), _choose_action.bind(spec_copy), GREEN))
	if not any:
		action_box.add_child(_body("Waiting for the roll."))


func _target_hint() -> String:
	var count := ""
	if str(_pending.get("type", "")) == "capture_alleys":
		count = " Selected %d of %d." % [_picked.size(), int(_pending.get("max", 1))]
		return "Tap Alley Cats. A shield spends one capture and the cat stays." + count
	if str(_pending.get("type", "")) == "damage":
		return "Tap a Yarn Cannon, a fortified group, or the exposed Boss. Damage %d removes %d hearts." % [int(_pending.get("amount", 0)), int(_pending.get("amount", 0)) / 2]
	return "Tap a Box Fort that is not inside a fortified group."


func _human_roll() -> void:
	if rules.current_player != 0 or rules.stage != "roll":
		return
	rules.roll_die()
	_error = ""
	_fill_battle()


func _choose_action(spec: Dictionary) -> void:
	_pending = spec
	_picked = []
	_error = ""
	_fill_battle()


func _cancel_pending() -> void:
	_pending = {}
	_picked = []
	_error = ""
	_fill_battle()


func _play_pass() -> void:
	var err = rules.apply({"type": "pass"})
	_error = err
	_after_human()


func _confirm_action() -> void:
	var action := {}
	var type := str(_pending.get("type", ""))
	if type == "capture_alleys":
		if _picked.is_empty():
			_error = "Pick at least one Alley Cat."
			_fill_actions()
			return
		action = {"type": "capture_alleys", "targets": _picked.duplicate()}
	else:
		if _picked.size() != 1:
			_error = "Pick a target."
			_fill_actions()
			return
		if type == "damage":
			action = {"type": "damage", "amount": int(_pending.get("amount", rules.roll)), "target": str(_picked[0])}
		else:
			action = {"type": type, "target": str(_picked[0])}
	var err = rules.apply(action)
	_pending = {}
	_picked = []
	_error = err
	if err != "":
		_fill_battle()
		return
	_after_human()


func _after_human() -> void:
	if rules.phase == "game_over":
		_go("result")
		return
	_fill_battle()
	_maybe_ai()


func _maybe_ai() -> void:
	if _ai_busy:
		return
	if _shot != "":
		return
	if rules.phase == "battle" and rules.current_player == 1:
		_ai_turn()


func _ai_turn() -> void:
	var token := _ai_token
	_ai_busy = true
	_fill_actions()
	while rules.phase == "battle" and rules.current_player == 1 and token == _ai_token:
		await get_tree().create_timer(0.45).timeout
		if token != _ai_token or rules.phase != "battle":
			_ai_busy = false
			return
		if rules.stage == "roll":
			rules.roll_die()
			_fill_battle()
			await get_tree().create_timer(0.55).timeout
			if token != _ai_token:
				_ai_busy = false
				return
		var move := AI.choose(rules)
		var err = rules.apply(move)
		if err != "":
			_error = err
			break
		_fill_battle()
	_ai_busy = false
	if token != _ai_token:
		return
	if rules.phase == "game_over":
		_go("result")
	else:
		_fill_battle()


func _cancel_ai() -> void:
	_ai_token += 1
	_ai_busy = false


func _build_result() -> void:
	var box := _center_column()
	var heading := "Draw"
	if not rules.draw:
		heading = "You win" if rules.winner == 0 else "AI wins"
	box.add_child(_title(heading))
	box.add_child(_body("Cat Jail VP\nYou %d    ·    AI %d\n\nDefeating the Boss ends the battle. It does not award the win by itself." % [rules.vp(0), rules.vp(1)]))
	box.add_child(_jail_strip(0))
	box.add_child(_jail_strip(1))
	box.add_child(_button("Play again", _play_again, GREEN))
	box.add_child(_button("Main menu", _go.bind("menu"), CREAM, INK))


func _play_again() -> void:
	_start_match()
	_go("armies")


func _jail_strip(jailer: int) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	var caption := Label.new()
	caption.text = "%s jail" % str(rules.player_names[jailer])
	caption.add_theme_color_override("font_color", INK)
	flow.add_child(caption)
	for p in rules.pieces:
		if int(p["jailer"]) != jailer or not bool(p["captured"]):
			continue
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(42, 42)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = _art(rules.texture_path(p))
		flow.add_child(icon)
	return flow


func _army_block(owner: int, _deploying: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := _box(CREAM, 14)
	var active = rules.phase == "battle" and rules.current_player == owner
	style.border_color = GREEN if active else Color(INK, 0.12)
	for edge in ["border_width_left", "border_width_top", "border_width_right", "border_width_bottom"]:
		style.set(edge, 4 if active else 1)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var who := "You" if owner == 0 else "AI"
	var army := str(Rules.COLOR_NAMES[str(rules.piece("%d_boss_0" % owner)["color"])])
	var banner := "%s · %s · Jail %d VP" % [who, army, rules.vp(owner)]
	if rules.phase == "battle" and rules.boss_exposed_for_attacker(1 - owner):
		banner += " · Boss exposed"
	box.add_child(_label(banner, 18))
	if _deploying:
		box.add_child(_label("Your pieces", 14))
		box.add_child(_piece_flow(owner, "floor"))
	var room := _living_room(owner, 700.0 if _deploying else 0.0)
	if _deploying:
		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center.add_child(room)
		box.add_child(center)
	else:
		box.add_child(room)
		box.add_child(_piece_flow(owner, "floor"))
	return panel


func _living_room(owner: int, lock_width: float) -> Control:
	var board := Control.new()
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if lock_width > 0.0:
		board.set_meta("lock_width", lock_width)
		board.custom_minimum_size = Vector2(lock_width, lock_width / BOARD_RATIO)
		board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		board.custom_minimum_size = Vector2(0, 210)
	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.texture = _art("res://assets/ui/board.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(art)
	var skip := {}
	for zone in ["sofa", "rug"]:
		var count := 3 if zone == "sofa" else 6
		for slot in count:
			var occupant = rules.piece_at(owner, zone, slot)
			if occupant.is_empty():
				continue
			if int(occupant["slots"][0]) != slot:
				skip["%s%d" % [zone, slot]] = true
	for zone in ["sofa", "rug"]:
		var count := 3 if zone == "sofa" else 6
		for slot in count:
			if skip.has("%s%d" % [zone, slot]):
				continue
			var occupant = rules.piece_at(owner, zone, slot)
			var rect := _zone_rect(zone, slot)
			if not occupant.is_empty() and str(occupant["kind"]) == "cannon":
				rect = rect.merge(_zone_rect(zone, int(occupant["slots"][1])))
			board.add_child(_overlay_slot(owner, zone, slot, occupant, rect))
	var boss = rules.piece("%d_boss_0" % owner)
	if not boss.is_empty() and not bool(boss["captured"]) and str(boss["zone"]) == "floor":
		board.add_child(_overlay_slot(owner, "floor", -1, boss, BOSS_SLOT))
	board.resized.connect(_fit_board_aspect.bind(board))
	return board


func _fit_board_aspect(board: Control) -> void:
	if bool(board.get_meta("fitting", false)):
		return
	var lock_width := float(board.get_meta("lock_width", 0.0))
	if lock_width > 0.0:
		var locked := Vector2(lock_width, lock_width / BOARD_RATIO)
		if board.custom_minimum_size != locked:
			board.set_meta("fitting", true)
			board.custom_minimum_size = locked
			board.set_meta("fitting", false)
		return
	var width := board.size.x
	if width < 40.0:
		return
	var height := width / BOARD_RATIO
	if absf(board.custom_minimum_size.y - height) < 2.0:
		return
	board.set_meta("fitting", true)
	board.custom_minimum_size = Vector2(0, height)
	board.set_meta("fitting", false)


func _zone_rect(zone: String, slot: int) -> Rect2:
	if zone == "sofa":
		return SOFA_SLOTS[slot]
	return RUG_SLOTS[slot]


func _anchor_control(node: Control, rect: Rect2) -> void:
	node.anchor_left = rect.position.x
	node.anchor_top = rect.position.y
	node.anchor_right = rect.position.x + rect.size.x
	node.anchor_bottom = rect.position.y + rect.size.y
	node.offset_left = 1
	node.offset_top = 1
	node.offset_right = -1
	node.offset_bottom = -1


func _overlay_slot(owner: int, zone: String, slot: int, occupant: Dictionary, rect: Rect2) -> Button:
	var button := Button.new()
	_anchor_control(button, rect)
	button.focus_mode = Control.FOCUS_NONE
	var shown := ""
	if not occupant.is_empty():
		shown = str(occupant["id"])
		var sprite := TextureRect.new()
		sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
		sprite.offset_left = 2
		sprite.offset_top = 2
		sprite.offset_right = -2
		sprite.offset_bottom = -14
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.texture = _art(rules.texture_path(occupant))
		button.add_child(sprite)
		var caption := Label.new()
		caption.text = _short_status(occupant)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.anchor_left = 0.0
		caption.anchor_right = 1.0
		caption.anchor_top = 1.0
		caption.anchor_bottom = 1.0
		caption.offset_top = -15
		caption.offset_bottom = 0
		caption.add_theme_font_size_override("font_size", 11)
		caption.add_theme_color_override("font_color", Color.WHITE)
		caption.add_theme_color_override("font_outline_color", INK)
		caption.add_theme_constant_override("outline_size", 4)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(caption)
		button.tooltip_text = _kind_label(occupant)
	_paint_overlay(button, occupant, shown)
	button.pressed.connect(_on_slot.bind(owner, zone, slot))
	return button


func _paint_overlay(button: Button, occupant: Dictionary, id: String) -> void:
	var bg := Color(1, 1, 1, 0.14)
	var border := Color(1, 1, 1, 0.72)
	if not occupant.is_empty() and bool(occupant.get("shield", false)):
		bg = Color(0.72, 0.84, 0.96, 0.35)
		border = Color("2f6a9a")
	if not occupant.is_empty() and int(occupant.get("group", -1)) >= 0:
		bg = Color(0.95, 0.72, 0.48, 0.38)
		border = Color("8a4b22")
	if id != "" and id == _selected:
		border = Color("c9a227")
		bg.a = maxf(bg.a, 0.45)
	if id != "" and _picked.has(id):
		border = CLAY
		bg = Color(CLAY, 0.45)
	elif id != "" and not _pending.is_empty() and rules.targets_for(_pending).has(id):
		border = GREEN
		bg = Color(GREEN, 0.28)
	var style := _box(bg, 8)
	style.border_color = border
	for edge in ["border_width_left", "border_width_top", "border_width_right", "border_width_bottom"]:
		style.set(edge, 2)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)


func _short_status(p: Dictionary) -> String:
	var bits: PackedStringArray = []
	if bool(p.get("shield", false)):
		bits.append("S")
	if int(p.get("rug_hearts", 0)) > 0:
		bits.append("F%d" % (int(p["rug_hearts"]) * 2))
	if str(p["kind"]) == "cannon" or str(p["kind"]) == "boss":
		bits.append("%d" % (int(p["hearts"]) * 2))
	if str(p["kind"]) == "box" and int(p.get("group", -1)) >= 0:
		bits.append("G")
	if str(p["kind"]) == "boss" and rules.boss_exposed_for_attacker(1 - int(p["owner"])):
		bits.append("OPEN")
	return " ".join(bits)


func _piece_flow(owner: int, zone: String) -> ScrollContainer:
	var scroller := ScrollContainer.new()
	scroller.custom_minimum_size = Vector2(0, 78)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var flow := HBoxContainer.new()
	flow.add_theme_constant_override("separation", 6)
	scroller.add_child(flow)
	var found := false
	for p in rules.pieces:
		if int(p["owner"]) != owner or str(p["zone"]) != zone or bool(p["captured"]):
			continue
		if str(p["kind"]) == "boss":
			continue
		found = true
		var button := Button.new()
		button.custom_minimum_size = Vector2(68, 68)
		button.icon = _art(rules.texture_path(p))
		button.expand_icon = true
		button.tooltip_text = "%s %s" % [_kind_label(p), _short_status(p)]
		_paint_piece_button(button, p, str(p["id"]))
		button.pressed.connect(_on_piece.bind(str(p["id"])))
		flow.add_child(button)
	if not found:
		flow.add_child(_label("None", 14))
	return scroller


func _paint_piece_button(button: Button, occupant: Dictionary, id: String) -> void:
	var bg := CREAM
	var fg := INK
	if not occupant.is_empty() and bool(occupant.get("shield", false)):
		bg = Color("d7e4f5")
	if not occupant.is_empty() and int(occupant.get("group", -1)) >= 0:
		bg = Color("f3d7c4")
	if id != "" and id == _selected:
		bg = Color("f2d56b")
	if id != "" and _picked.has(id):
		bg = Color("f0b429")
	elif id != "" and not _pending.is_empty() and rules.targets_for(_pending).has(id):
		bg = Color("cfe8d4")
	button.add_theme_stylebox_override("normal", _box(bg, 10))
	button.add_theme_stylebox_override("hover", _box(bg.lightened(0.05), 10))
	button.add_theme_stylebox_override("pressed", _box(bg.darkened(0.05), 10))
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)


func _on_slot(owner: int, zone: String, slot: int) -> void:
	var occupant = rules.piece_at(owner, zone, slot)
	if zone == "floor":
		_on_piece("%d_boss_0" % owner)
		return
	if _screen == "deploy":
		if owner != 0:
			return
		if occupant.is_empty():
			if _selected == "":
				_error = "Select a piece first."
			else:
				_error = rules.place(_selected, zone, slot)
				if _error == "":
					_selected = ""
			_fill_deploy_board()
			_refresh_deploy_status()
			return
		_selected = str(occupant["id"])
		_error = ""
		_fill_deploy_board()
		_refresh_deploy_status()
		return
	if occupant.is_empty():
		return
	_toggle_target(str(occupant["id"]))


func _on_piece(id: String) -> void:
	if _screen == "deploy":
		_selected = id
		_error = ""
		_fill_deploy_board()
		_refresh_deploy_status()
		return
	_toggle_target(id)


func _toggle_target(id: String) -> void:
	if _pending.is_empty() or rules.current_player != 0 or _ai_busy:
		return
	if not rules.targets_for(_pending).has(id):
		_error = "That piece is not a legal target."
		_fill_actions()
		return
	if str(_pending.get("type", "")) == "capture_alleys":
		if _picked.has(id):
			_picked.erase(id)
		elif _picked.size() >= int(_pending.get("max", 1)):
			_error = "This roll cannot take any more Alley Cats."
			_fill_actions()
			return
		else:
			_picked.append(id)
	else:
		_picked = [id]
	_error = ""
	_fill_battle()


func _status_text(p: Dictionary) -> String:
	var bits: PackedStringArray = []
	if bool(p.get("shield", false)):
		bits.append("Shield")
	if int(p.get("rug_hearts", 0)) > 0:
		bits.append("Fort %d" % (int(p["rug_hearts"]) * 2))
	if str(p["kind"]) == "cannon" or str(p["kind"]) == "boss":
		bits.append("%d HP" % (int(p["hearts"]) * 2))
	if str(p["kind"]) == "box" and int(p.get("group", -1)) >= 0:
		bits.append("Group")
	if str(p["kind"]) == "boss" and rules.boss_exposed_for_attacker(1 - int(p["owner"])):
		bits.append("Open")
	return " ".join(bits)


func _kind_label(p: Dictionary) -> String:
	match str(p["kind"]):
		"alley":
			return "Alley Cat"
		"box":
			return "Box Fort"
		"cannon":
			return "Yarn Cannon"
		"boss":
			return "Boss"
	return "Piece"


func _confirm_leave() -> void:
	_open_modal("Leave this battle?", "The match will be discarded.", _leave_match)


func _leave_match() -> void:
	_cancel_ai()
	rules = Rules.new()
	_go("menu")


func _open_help() -> void:
	_open_modal("How to play", _help_text(), Callable())


func _help_text() -> String:
	return "Each army has 12 Alley Cats (1 VP), 5 Box Forts (3 VP), 2 Yarn Cannons (10 VP, 10 HP) and 1 Boss (5 VP, 10 HP).\n\nOne heart is 2 HP. A roll of 2, 4, or 6 removes 1, 2, or 3 hearts. Extra damage does not spill.\n\nSofa: each piece gets one shield. A shield cancels the whole attack. When capturing several Alley Cats, each shield you break spends one capture.\n\nRug: pair one Alley Cat or one Yarn Cannon with one Box Fort. That group has 2 hearts (4 HP). Destroy them to take every piece in the group. A fortified cannon loses the rug hearts first, then its own.\n\nOnly one Yarn Cannon may use the sofa or the rug. The Boss cannot. Capture 8 Alley Cats and 3 Box Forts to expose the enemy Boss, then remove its 5 hearts. The battle ends, and the higher Cat Jail VP wins. A tie is a draw."


func _open_modal(heading: String, body: String, on_yes: Callable) -> void:
	_close_modal()
	modal = ColorRect.new()
	modal.color = Color(INK, 0.45)
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	panel.add_theme_stylebox_override("panel", _box(CREAM, 16))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_title(heading))
	var text := _body(body)
	text.custom_minimum_size = Vector2(420, 0)
	box.add_child(text)
	if on_yes.is_valid():
		box.add_child(_button("Leave", on_yes, ROSE))
		box.add_child(_button("Stay", _close_modal, CREAM, INK))
	else:
		box.add_child(_button("Close", _close_modal, GREEN))


func _close_modal() -> void:
	if modal != null:
		modal.queue_free()
		modal = null


func _center_column() -> VBoxContainer:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	return box


func _side_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _box(CREAM, 14))
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(box)
	panel.set_meta("side_box", box)
	return panel


func _side_box(panel: PanelContainer) -> VBoxContainer:
	return panel.get_meta("side_box")


func _title(text: String) -> Label:
	return _label(text, 28)


func _body(text: String) -> Label:
	var label := _label(text, 16)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", INK)
	return label


func _button(text: String, callback: Callable, bg: Color, fg: Color = CREAM) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 18)
	_paint_button(button, bg, fg)
	if callback.is_valid():
		button.pressed.connect(callback)
	return button


func _paint_button(button: Button, bg: Color, fg: Color) -> void:
	button.add_theme_color_override("font_color", fg)
	button.add_theme_color_override("font_hover_color", fg)
	button.add_theme_color_override("font_pressed_color", fg)
	button.add_theme_color_override("font_focus_color", fg)
	button.add_theme_stylebox_override("normal", _box(bg, 12))
	button.add_theme_stylebox_override("hover", _box(bg.lightened(0.06), 12))
	button.add_theme_stylebox_override("pressed", _box(bg.darkened(0.08), 12))
	button.add_theme_stylebox_override("focus", _box(bg, 12))
	button.add_theme_stylebox_override("disabled", _box(Color(bg, 0.45), 12))


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _art(path: String) -> Texture2D:
	if _tex.has(path):
		return _tex[path]
	var loaded := load(path) as Texture2D
	_tex[path] = loaded
	return loaded
