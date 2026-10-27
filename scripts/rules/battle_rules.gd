extends RefCounted
class_name BattleRules

# Living Room Wars, playtest booklet 2026 (Tinkree Maker Labs).
#
# Assumptions where the booklet is silent or the diagram is the only spec:
# - Each heart is 2 HP. "Deal 2/4/6 damage" removes 1/2/3 hearts.
#   Extra damage does not spill onto another piece.
# - A shield cancels the whole attack. The piece is not captured and loses no hearts.
#   On a multi-cat capture, each shield removed spends 1 of the captures.
# - A fortified group is one Alley Cat or one Yarn Cannon plus one Box Fort.
#   The group has 2 hearts. A cannon's own hearts are removed only after those.
#   The box is captured with the group, not before.
# - Capture actions cannot pull a piece out of a fortified group.
#   Yarn-cannon fire uses the same rule: only an unfortified Box Fort.
# - Only one Yarn Cannon per army may sit on the sofa or the rug.
#   A cannon occupies two side-by-side slots. The Boss cannot use either.
# - Pieces left on the rug without a partner are not fortified.
# - Capturing either Boss ends the battle. Equal jail VP is a draw.
# - An initiative tie is rerolled.
# - "Up to N" may capture fewer than N, but at least one legal piece must be chosen.

const COLORS := ["black", "calico", "cream", "orange"]
const COLOR_NAMES := {
	"black": "Black",
	"calico": "Calico",
	"cream": "Cream",
	"orange": "Orange",
}
const VP := {"alley": 1, "box": 3, "cannon": 10, "boss": 5}
const CANNON_HEARTS := 5
const BOSS_HEARTS := 5
const GROUP_HEARTS := 2
const EXPOSE_ALLEYS := 8
const EXPOSE_BOXES := 3

var pieces: Array = []
var phase := "deploy" # deploy, initiative, battle, game_over
var stage := "" # roll, act
var current_player := 0
var roll := 0
var deployed: Array = [false, false]
var winner := -1
var draw := false
var player_names: Array = ["Player 1", "Player 2"]
var log: Array = []
var initiative_rolls: Array = []
var _next_group := 1
var rng := RandomNumberGenerator.new()


func set_seed(value: int) -> void:
	rng.seed = value


func setup_match(color_a: String, color_b: String) -> void:
	pieces.clear()
	_build_army(0, color_a)
	_build_army(1, color_b)
	phase = "deploy"
	stage = ""
	deployed = [false, false]
	current_player = 0
	roll = 0
	winner = -1
	draw = false
	player_names = ["Player 1", "Player 2"]
	log = []
	initiative_rolls = []
	_next_group = 1


func _build_army(owner: int, color: String) -> void:
	for i in 12:
		_add_piece(owner, color, "alley", "A%d" % (i + 1), 0)
	for _i in 5:
		_add_piece(owner, color, "box", "box", 0)
	_add_piece(owner, color, "cannon", "C1", CANNON_HEARTS)
	_add_piece(owner, color, "cannon", "C2", CANNON_HEARTS)
	_add_piece(owner, color, "boss", "boss", BOSS_HEARTS)


func _add_piece(owner: int, color: String, kind: String, art: String, hearts: int) -> void:
	var index := 0
	for p in pieces:
		if int(p["owner"]) == owner and str(p["kind"]) == kind:
			index += 1
	pieces.append({
		"id": "%d_%s_%d" % [owner, kind, index],
		"owner": owner,
		"kind": kind,
		"art": art,
		"color": color,
		"zone": "floor",
		"slots": [],
		"shield": false,
		"hearts": hearts,
		"rug_hearts": 0,
		"group": -1,
		"captured": false,
		"jailer": -1,
	})


func piece(id: String) -> Dictionary:
	for p in pieces:
		if str(p["id"]) == id:
			return p
	return {}


func texture_path(p: Dictionary) -> String:
	return "res://assets/armies/%s/%s.png" % [str(p["color"]), str(p["art"])]


func place(id: String, zone: String, anchor: int) -> String:
	var p := piece(id)
	if p.is_empty():
		return "Unknown piece."
	if phase != "deploy":
		return "Deployment is locked."
	if bool(deployed[int(p["owner"])]):
		return "That army is already deployed."
	if bool(p["captured"]):
		return "That piece is captured."
	if zone == "floor":
		p["zone"] = "floor"
		p["slots"] = []
		p["shield"] = false
		p["group"] = -1
		p["rug_hearts"] = 0
		return ""
	if zone != "sofa" and zone != "rug":
		return "Unknown zone."
	if str(p["kind"]) == "boss":
		return "The Boss stays off the sofa and the rug."
	var slots: Array = []
	if str(p["kind"]) == "cannon":
		slots = _pair_slots(zone, anchor)
		if slots.is_empty():
			return "A Yarn Cannon needs two neighboring slots."
		if _other_cannon_on_special(p):
			return "Only one Yarn Cannon can use the sofa or the rug."
	else:
		var max_slot := 2 if zone == "sofa" else 5
		if anchor < 0 or anchor > max_slot:
			return "That slot is out of range."
		slots = [anchor]
	for s in slots:
		if _occupant(int(p["owner"]), zone, int(s), id) != "":
			return "That spot is taken."
	p["zone"] = zone
	p["slots"] = slots
	p["shield"] = false
	p["group"] = -1
	p["rug_hearts"] = 0
	return ""


func _pair_slots(zone: String, anchor: int) -> Array:
	if zone == "sofa":
		if anchor < 0 or anchor > 1:
			return []
		return [anchor, anchor + 1]
	if zone == "rug":
		if anchor < 0 or anchor > 5 or anchor % 3 == 2:
			return []
		return [anchor, anchor + 1]
	return []


func _other_cannon_on_special(p: Dictionary) -> bool:
	for other in pieces:
		if str(other["id"]) == str(p["id"]):
			continue
		if int(other["owner"]) != int(p["owner"]):
			continue
		if str(other["kind"]) != "cannon":
			continue
		var zone := str(other["zone"])
		if zone == "sofa" or zone == "rug":
			return true
	return false


func _occupant(owner: int, zone: String, slot: int, ignore_id: String) -> String:
	for p in pieces:
		if str(p["id"]) == ignore_id:
			continue
		if int(p["owner"]) != owner or str(p["zone"]) != zone:
			continue
		if bool(p["captured"]):
			continue
		for s in p["slots"]:
			if int(s) == slot:
				return str(p["id"])
	return ""


func piece_at(owner: int, zone: String, slot: int) -> Dictionary:
	var id := _occupant(owner, zone, slot, "")
	if id == "":
		return {}
	return piece(id)


func lock_deploy(owner: int) -> String:
	if phase != "deploy":
		return "Deployment is locked."
	if owner < 0 or owner > 1:
		return "Unknown army."
	refresh_defenses(owner)
	deployed[owner] = true
	log.append("%s is deployed. %s" % [str(player_names[owner]), defense_summary(owner)])
	if bool(deployed[0]) and bool(deployed[1]):
		phase = "initiative"
	return ""


func refresh_defenses(owner: int) -> void:
	var cannons: Array = []
	var boxes: Array = []
	var alleys: Array = []
	for p in pieces:
		if int(p["owner"]) != owner or bool(p["captured"]):
			continue
		p["shield"] = false
		p["rug_hearts"] = 0
		p["group"] = -1
		if str(p["zone"]) == "sofa":
			p["shield"] = true
		if str(p["zone"]) != "rug":
			continue
		match str(p["kind"]):
			"cannon":
				cannons.append(p)
			"box":
				boxes.append(p)
			"alley":
				alleys.append(p)
	cannons.sort_custom(_slot_less)
	boxes.sort_custom(_slot_less)
	alleys.sort_custom(_slot_less)
	if not cannons.is_empty() and not boxes.is_empty():
		_link_group(cannons[0], boxes[0])
		boxes.remove_at(0)
	var i := 0
	while i < alleys.size() and i < boxes.size():
		_link_group(alleys[i], boxes[i])
		i += 1


func _slot_less(a: Dictionary, b: Dictionary) -> bool:
	return int(a["slots"][0]) < int(b["slots"][0])


func _link_group(anchor: Dictionary, box: Dictionary) -> void:
	var gid := _next_group
	_next_group += 1
	anchor["group"] = gid
	box["group"] = gid
	anchor["rug_hearts"] = GROUP_HEARTS


func defense_summary(owner: int) -> String:
	var shields := 0
	var groups := {}
	for p in pieces:
		if int(p["owner"]) != owner or bool(p["captured"]):
			continue
		if bool(p["shield"]):
			shields += 1
		if int(p["group"]) >= 0 and int(p["rug_hearts"]) > 0:
			groups[int(p["group"])] = true
	return "%d sofa shields, %d fortified groups." % [shields, groups.size()]


func roll_initiative() -> Dictionary:
	if phase != "initiative":
		return {"ok": false}
	var history: Array = []
	var first := 0
	while true:
		var a := rng.randi_range(1, 6)
		var b := rng.randi_range(1, 6)
		history.append([a, b])
		if a != b:
			first = 0 if a > b else 1
			break
		if history.size() >= 12:
			first = 0
			break
	initiative_rolls = history
	current_player = first
	phase = "battle"
	stage = "roll"
	roll = 0
	var last: Array = history[history.size() - 1]
	log.append("Initiative %d to %d. %s goes first." % [int(last[0]), int(last[1]), str(player_names[first])])
	return {"ok": true, "rolls": history, "first": first}


func begin_battle(first_player: int) -> void:
	refresh_defenses(0)
	refresh_defenses(1)
	deployed = [true, true]
	phase = "battle"
	stage = "roll"
	current_player = first_player
	roll = 0
	winner = -1
	draw = false
	log.append("%s: %s" % [str(player_names[0]), defense_summary(0)])
	log.append("%s: %s" % [str(player_names[1]), defense_summary(1)])
	log.append("%s goes first." % str(player_names[first_player]))


func roll_die() -> int:
	if phase != "battle" or stage != "roll":
		return 0
	roll = rng.randi_range(1, 6)
	stage = "act"
	log.append("%s rolled %d." % [str(player_names[current_player]), roll])
	return roll


func force_roll(n: int) -> String:
	if phase != "battle":
		return "Battle has not started."
	roll = clampi(n, 1, 6)
	stage = "act"
	return ""


func vp(player: int) -> int:
	var total := 0
	for p in pieces:
		if bool(p["captured"]) and int(p["jailer"]) == player:
			total += int(VP[str(p["kind"])])
	return total


func boss_exposed_for_attacker(attacker: int) -> bool:
	var defender := 1 - attacker
	var alleys := 0
	var boxes := 0
	for p in pieces:
		if not bool(p["captured"]) or int(p["jailer"]) != attacker:
			continue
		if int(p["owner"]) != defender:
			continue
		match str(p["kind"]):
			"alley":
				alleys += 1
			"box":
				boxes += 1
	return alleys >= EXPOSE_ALLEYS and boxes >= EXPOSE_BOXES


func legal_types() -> Array:
	if phase != "battle" or stage != "act":
		return []
	var out := _action_specs()
	if out.is_empty():
		out.append({"type": "pass"})
	return out


func _action_specs() -> Array:
	var out: Array = []
	var enemy := 1 - current_player
	if not _unfortified(enemy, "alley").is_empty():
		out.append({"type": "capture_alleys", "max": roll})
	if roll == 3 and not _unfortified(enemy, "box").is_empty():
		out.append({"type": "capture_box"})
	if roll == 5 and _has_surviving_cannon(current_player) and not _unfortified(enemy, "box").is_empty():
		out.append({"type": "cannon_shot"})
	if (roll == 2 or roll == 4 or roll == 6) and not damage_targets().is_empty():
		out.append({"type": "damage", "amount": roll})
	return out


func describe(spec: Dictionary) -> String:
	match str(spec.get("type", "")):
		"capture_alleys":
			var max_n := int(spec.get("max", 1))
			if max_n == 1:
				return "Capture 1 Alley Cat"
			return "Capture up to %d Alley Cats" % max_n
		"capture_box":
			return "Capture 1 Box Fort"
		"cannon_shot":
			return "Fire a Yarn Cannon at 1 Box Fort"
		"damage":
			return "Deal %d damage" % int(spec.get("amount", 0))
		"pass":
			return "No valid move"
	return "Move"


func targets_for(spec: Dictionary) -> Array:
	var enemy := 1 - current_player
	match str(spec.get("type", "")):
		"capture_alleys":
			return _unfortified(enemy, "alley")
		"capture_box", "cannon_shot":
			return _unfortified(enemy, "box")
		"damage":
			return damage_targets()
	return []


func damage_targets() -> Array:
	var enemy := 1 - current_player
	var ids: Array = []
	var seen_groups := {}
	for p in pieces:
		if int(p["owner"]) != enemy or bool(p["captured"]):
			continue
		var kind := str(p["kind"])
		var group := int(p["group"])
		if group >= 0 and int(p["rug_hearts"]) > 0:
			ids.append(str(p["id"]))
			seen_groups[group] = true
			continue
		if group >= 0 and kind == "cannon" and int(p["hearts"]) > 0 and not seen_groups.has(group):
			ids.append(str(p["id"]))
			seen_groups[group] = true
			continue
		if group < 0 and kind == "cannon":
			ids.append(str(p["id"]))
		elif group < 0 and kind == "boss" and boss_exposed_for_attacker(current_player):
			ids.append(str(p["id"]))
	return ids


func _unfortified(owner: int, kind: String) -> Array:
	var ids: Array = []
	for p in pieces:
		if int(p["owner"]) != owner or bool(p["captured"]):
			continue
		if str(p["kind"]) != kind:
			continue
		if int(p["group"]) >= 0:
			continue
		ids.append(str(p["id"]))
	return ids


func _has_surviving_cannon(owner: int) -> bool:
	for p in pieces:
		if int(p["owner"]) == owner and str(p["kind"]) == "cannon" and not bool(p["captured"]) and int(p["hearts"]) > 0:
			return true
	return false


func apply(action: Dictionary) -> String:
	if phase == "game_over":
		return "The battle is over."
	if phase != "battle" or stage != "act":
		return "It is not time to act."
	var type := str(action.get("type", ""))
	var err := ""
	match type:
		"pass":
			err = _apply_pass()
		"capture_alleys":
			err = _apply_alleys(action.get("targets", []))
		"capture_box":
			err = _apply_box(str(action.get("target", "")), false)
		"cannon_shot":
			err = _apply_box(str(action.get("target", "")), true)
		"damage":
			err = _apply_damage(str(action.get("target", "")), int(action.get("amount", roll)))
		_:
			err = "Unknown action."
	return err


func _apply_pass() -> String:
	if not _action_specs().is_empty():
		return "A move is still available."
	log.append("%s has no valid move." % str(player_names[current_player]))
	_end_turn()
	return ""


func _apply_alleys(raw_targets) -> String:
	if typeof(raw_targets) != TYPE_ARRAY:
		return "Pick Alley Cats to capture."
	var max_n := roll
	if raw_targets.is_empty() or raw_targets.size() > max_n:
		return "Pick between 1 and %d Alley Cats." % max_n
	var allowed := {}
	for id in _unfortified(1 - current_player, "alley"):
		allowed[str(id)] = true
	var chosen: Array = []
	for raw in raw_targets:
		var id := str(raw)
		if chosen.has(id):
			return "That Alley Cat was picked twice."
		if not allowed.has(id):
			return "That Alley Cat cannot be captured that way."
		chosen.append(id)
	var captured := 0
	var broken := 0
	for id in chosen:
		var p := piece(id)
		if bool(p["shield"]):
			p["shield"] = false
			broken += 1
		else:
			_send_to_jail(p, current_player)
			captured += 1
	log.append("%s captured %d Alley Cats and broke %d shields." % [str(player_names[current_player]), captured, broken])
	_end_turn()
	return ""


func _apply_box(target_id: String, from_cannon: bool) -> String:
	if from_cannon:
		if roll != 5 or not _has_surviving_cannon(current_player):
			return "No Yarn Cannon can fire."
	elif roll != 3:
		return "That roll cannot capture a Box Fort."
	var allowed := _unfortified(1 - current_player, "box")
	if not allowed.has(target_id):
		return "That Box Fort cannot be captured that way."
	var p := piece(target_id)
	if bool(p["shield"]):
		p["shield"] = false
		log.append("A shield blocks the attack. The Box Fort stays.")
		_end_turn()
		return ""
	_send_to_jail(p, current_player)
	if from_cannon:
		log.append("%s fires a Yarn Cannon and captures a Box Fort." % str(player_names[current_player]))
	else:
		log.append("%s captures a Box Fort." % str(player_names[current_player]))
	_end_turn()
	return ""


func _apply_damage(target_id: String, amount: int) -> String:
	if amount != 2 and amount != 4 and amount != 6:
		return "That is not a damage roll."
	if roll != amount:
		return "That damage does not match the roll."
	if not damage_targets().has(target_id):
		return "That piece cannot take this damage."
	var p := piece(target_id)
	if bool(p["shield"]):
		p["shield"] = false
		log.append("A shield blocks the attack. %s is not damaged." % _kind_name(p))
		_end_turn()
		return ""
	var hearts_left := int(amount / 2)
	if int(p["rug_hearts"]) > 0:
		var take: int = mini(int(p["rug_hearts"]), hearts_left)
		p["rug_hearts"] = int(p["rug_hearts"]) - take
		hearts_left -= take
	if hearts_left > 0 and int(p["hearts"]) > 0:
		var take_own: int = mini(int(p["hearts"]), hearts_left)
		p["hearts"] = int(p["hearts"]) - take_own
	var cleared := false
	if int(p["group"]) >= 0 and str(p["kind"]) == "alley":
		cleared = int(p["rug_hearts"]) <= 0
	elif str(p["kind"]) == "cannon" or str(p["kind"]) == "boss":
		cleared = int(p["rug_hearts"]) <= 0 and int(p["hearts"]) <= 0
	if cleared:
		if int(p["group"]) >= 0:
			log.append("%s captures a fortified group." % str(player_names[current_player]))
		else:
			log.append("%s captures %s." % [str(player_names[current_player]), _kind_name(p)])
		_capture_resolved(p, current_player)
	else:
		log.append("%s deals %d damage to %s." % [str(player_names[current_player]), amount, _kind_name(p)])
	_end_turn()
	return ""


func _capture_resolved(anchor: Dictionary, jailer: int) -> void:
	var ids: Array = []
	var group := int(anchor["group"])
	if group >= 0:
		for p in pieces:
			if int(p["group"]) == group and not bool(p["captured"]):
				ids.append(str(p["id"]))
	else:
		ids.append(str(anchor["id"]))
	var took_boss := false
	for id in ids:
		var p := piece(id)
		if str(p["kind"]) == "boss":
			took_boss = true
		_send_to_jail(p, jailer)
	if took_boss:
		_end_game()


func _send_to_jail(p: Dictionary, jailer: int) -> void:
	p["captured"] = true
	p["jailer"] = jailer
	p["zone"] = "jail"
	p["slots"] = []
	p["shield"] = false
	p["rug_hearts"] = 0


func _end_game() -> void:
	if phase == "game_over":
		return
	phase = "game_over"
	stage = "done"
	var left := vp(0)
	var right := vp(1)
	if left == right:
		draw = true
		winner = -1
		log.append("The Boss falls. Draw, %d VP each." % left)
	elif left > right:
		draw = false
		winner = 0
		log.append("The Boss falls. %s wins %d to %d." % [str(player_names[0]), left, right])
	else:
		draw = false
		winner = 1
		log.append("The Boss falls. %s wins %d to %d." % [str(player_names[1]), right, left])


func _end_turn() -> void:
	if phase == "game_over":
		return
	current_player = 1 - current_player
	stage = "roll"
	roll = 0


func _kind_name(p: Dictionary) -> String:
	match str(p["kind"]):
		"alley":
			return "an Alley Cat"
		"box":
			return "a Box Fort"
		"cannon":
			return "a Yarn Cannon"
		"boss":
			return "the Boss"
	return "a piece"


func duplicate_state():
	var copy = get_script().new()
	copy.apply_data(to_data())
	return copy


func to_data() -> Dictionary:
	return {
		"v": 1,
		"pieces": pieces.duplicate(true),
		"phase": phase,
		"stage": stage,
		"current_player": current_player,
		"roll": roll,
		"deployed": [bool(deployed[0]), bool(deployed[1])],
		"winner": winner,
		"draw": draw,
		"names": [str(player_names[0]), str(player_names[1])],
		"next_group": _next_group,
		"log": log.duplicate(),
	}


func apply_data(data: Dictionary) -> void:
	pieces = []
	for raw in data.get("pieces", []):
		var p: Dictionary = raw
		var slots: Array = []
		for s in p.get("slots", []):
			slots.append(int(s))
		pieces.append({
			"id": str(p["id"]),
			"owner": int(p["owner"]),
			"kind": str(p["kind"]),
			"art": str(p["art"]),
			"color": str(p["color"]),
			"zone": str(p["zone"]),
			"slots": slots,
			"shield": bool(p.get("shield", false)),
			"hearts": int(p.get("hearts", 0)),
			"rug_hearts": int(p.get("rug_hearts", 0)),
			"group": int(p.get("group", -1)),
			"captured": bool(p.get("captured", false)),
			"jailer": int(p.get("jailer", -1)),
		})
	phase = str(data.get("phase", "deploy"))
	stage = str(data.get("stage", ""))
	current_player = int(data.get("current_player", 0))
	roll = int(data.get("roll", 0))
	var dep = data.get("deployed", [false, false])
	deployed = [bool(dep[0]), bool(dep[1])]
	winner = int(data.get("winner", -1))
	draw = bool(data.get("draw", false))
	var names = data.get("names", ["Player 1", "Player 2"])
	player_names = [str(names[0]), str(names[1])]
	_next_group = int(data.get("next_group", 1))
	log = []
	for line in data.get("log", []):
		log.append(str(line))
