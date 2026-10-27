extends RefCounted

const Rules = preload("res://scripts/rules/battle_rules.gd")
const AI = preload("res://scripts/rules/battle_ai.gd")

var failures: Array[String] = []
var checks = 0
var current = ""


func run() -> int:
	failures.clear()
	checks = 0
	_test_die_table()
	_test_placement_limits()
	_test_ai_deploy_groups()
	_test_alley_capture_and_shields()
	_test_fortify_and_damage()
	_test_cannon_shot_and_pass()
	_test_boss_endings()
	_test_initiative()
	_test_snapshot_roundtrip()
	_test_ai_does_not_mutate()
	_test_ai_games_finish()
	if failures.is_empty():
		print("ALL CHECKS PASSED (%d)" % checks)
		return 0
	for failure in failures:
		print("FAIL ", failure)
	print("FAILED %d of %d checks" % [failures.size(), checks])
	return 1


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append("%s: %s" % [current, msg])


func fresh():
	var battle = Rules.new()
	battle.set_seed(7)
	battle.setup_match("black", "calico")
	battle.player_names = ["You", "AI"]
	return battle


func jail(battle, id: String, jailer: int) -> void:
	var p = battle.piece(id)
	p["captured"] = true
	p["jailer"] = jailer
	p["zone"] = "jail"
	p["slots"] = []
	p["shield"] = false
	p["group"] = -1
	p["rug_hearts"] = 0


func act(battle, player: int, die: int) -> void:
	battle.current_player = player
	battle.stage = "act"
	battle.roll = die
	battle.phase = "battle"


func _test_die_table() -> void:
	current = "die table"
	var battle = fresh()
	battle.begin_battle(0)
	var expected = {
		1: ["capture_alleys"],
		2: ["capture_alleys", "damage"],
		3: ["capture_alleys", "capture_box"],
		4: ["capture_alleys", "damage"],
		5: ["capture_alleys", "cannon_shot"],
		6: ["capture_alleys", "damage"],
	}
	for face in expected.keys():
		battle.force_roll(int(face))
		var types: Array = []
		for spec in battle.legal_types():
			types.append(str(spec["type"]))
		check(types == expected[face], "roll %s produced %s" % [str(face), str(types)])
		var boss_hit = false
		if types.has("damage"):
			for id in battle.damage_targets():
				if str(battle.piece(str(id))["kind"]) == "boss":
					boss_hit = true
		check(not boss_hit, "boss is not a target before it is exposed")


func _test_placement_limits() -> void:
	current = "placement"
	var battle = fresh()
	check(battle.place("0_boss_0", "sofa", 0) != "", "boss on sofa should fail")
	check(battle.place("0_boss_0", "rug", 0) != "", "boss on rug should fail")
	check(battle.place("0_cannon_0", "rug", 2) != "", "cannon at the end of a rug row should fail")
	check(battle.place("0_cannon_0", "rug", 0) == "", "cannon on rug 0")
	check(battle.place("0_cannon_1", "sofa", 0) != "", "second cannon on a special zone should fail")
	check(battle.place("0_alley_0", "rug", 0) != "", "overlap with the cannon should fail")
	check(battle.place("0_box_0", "rug", 2) == "", "box beside the cannon")
	check(battle.piece("0_cannon_1")["zone"] == "floor", "second cannon stays on the floor")


func _test_ai_deploy_groups() -> void:
	current = "ai deploy"
	var battle = fresh()
	check(AI.deploy(battle, 0) == "", "deploy player")
	check(AI.deploy(battle, 1) == "", "deploy ai")
	battle.begin_battle(0)
	var cannon = battle.piece("0_cannon_0")
	var box = battle.piece("0_box_0")
	var alley = battle.piece("0_alley_0")
	var box2 = battle.piece("0_box_1")
	check(str(cannon["zone"]) == "rug" and int(cannon["rug_hearts"]) == 2, "cannon fortify hearts")
	check(int(cannon["group"]) == int(box["group"]) and int(cannon["group"]) >= 0, "cannon shares a group with a box")
	check(int(alley["rug_hearts"]) == 2 and int(alley["group"]) == int(box2["group"]), "alley fortify pair")
	check(int(alley["group"]) != int(cannon["group"]), "the two groups are distinct")
	check(bool(battle.piece("0_alley_1")["shield"]), "sofa cat has a shield")
	check(str(battle.piece("0_cannon_1")["zone"]) == "floor", "spare cannon is on the floor")
	check(str(battle.piece("0_boss_0")["zone"]) == "floor", "boss is on the floor")
	check(battle.defense_summary(0) == "3 sofa shields, 2 fortified groups.", "defense summary")


func _test_alley_capture_and_shields() -> void:
	current = "captures"
	var battle = fresh()
	check(battle.place("1_alley_0", "sofa", 0) == "", "shielded cat")
	check(battle.place("1_alley_1", "floor", -1) == "", "floor cat")
	battle.begin_battle(0)
	battle.force_roll(1)
	var before = battle.current_player
	check(battle.apply({"type": "capture_alleys", "targets": ["1_alley_0"]}) == "", "strip one shield")
	check(not bool(battle.piece("1_alley_0")["shield"]), "shield is gone")
	check(not bool(battle.piece("1_alley_0")["captured"]), "shielded cat stays")
	check(battle.vp(0) == 0, "no VP for a shield break")
	check(battle.current_player == 1 - before, "turn passes after a shield break")

	var mixed = fresh()
	check(mixed.place("1_alley_0", "sofa", 0) == "", "shield cat")
	mixed.begin_battle(0)
	mixed.force_roll(3)
	check(mixed.apply({
		"type": "capture_alleys",
		"targets": ["1_alley_0", "1_alley_1", "1_alley_2"],
	}) == "", "mixed capture")
	check(not bool(mixed.piece("1_alley_0")["shield"]), "the shield is spent")
	check(not bool(mixed.piece("1_alley_0")["captured"]), "a shield spends a capture and the cat stays")
	check(bool(mixed.piece("1_alley_1")["captured"]) and bool(mixed.piece("1_alley_2")["captured"]), "the other cats are jailed")
	check(mixed.vp(0) == 2, "two captures worth of VP")

	var fortified = fresh()
	check(fortified.place("1_alley_0", "rug", 0) == "", "group cat")
	check(fortified.place("1_box_0", "rug", 1) == "", "group box")
	fortified.begin_battle(0)
	fortified.force_roll(1)
	var err = fortified.apply({"type": "capture_alleys", "targets": ["1_alley_0"]})
	check(err != "", "fortified alley cannot be snatched")
	check(fortified.current_player == 0 and fortified.stage == "act", "failed move does not pass the turn")
	check(not bool(fortified.piece("1_alley_0")["captured"]), "fortified alley remains")


func _test_fortify_and_damage() -> void:
	current = "fortify"
	var battle = fresh()
	check(battle.place("1_alley_0", "rug", 0) == "", "alley")
	check(battle.place("1_box_0", "rug", 1) == "", "box")
	check(battle.place("1_cannon_0", "floor", -1) == "", "other cannon")
	battle.begin_battle(0)
	battle.force_roll(2)
	check(battle.apply({"type": "damage", "amount": 2, "target": "1_alley_0"}) == "", "chip the group")
	check(int(battle.piece("1_alley_0")["rug_hearts"]) == 1, "one fortify heart remains")
	check(not bool(battle.piece("1_alley_0")["captured"]), "group survives 2 damage")
	check(int(battle.piece("1_cannon_0")["hearts"]) == 5, "damage does not spill")

	act(battle, 0, 4)
	check(battle.apply({"type": "damage", "amount": 4, "target": "1_alley_0"}) == "", "finish the group")
	check(bool(battle.piece("1_alley_0")["captured"]) and bool(battle.piece("1_box_0")["captured"]), "group goes to jail together")
	check(battle.vp(0) == 4, "alley plus box VP")
	check(int(battle.piece("1_cannon_0")["hearts"]) == 5, "overflow still does not spill")

	var cannon = fresh()
	check(cannon.place("1_cannon_0", "rug", 0) == "", "fortified cannon")
	check(cannon.place("1_box_0", "rug", 2) == "", "its box")
	cannon.begin_battle(0)
	cannon.force_roll(4)
	check(cannon.apply({"type": "damage", "amount": 4, "target": "1_cannon_0"}) == "", "strip rug hearts")
	check(int(cannon.piece("1_cannon_0")["rug_hearts"]) == 0, "rug hearts gone")
	check(int(cannon.piece("1_cannon_0")["hearts"]) == 5, "cannon hearts untouched")
	check(not bool(cannon.piece("1_box_0")["captured"]), "box stays while the cannon lives")
	act(cannon, 0, 6)
	check(cannon.apply({"type": "damage", "amount": 6, "target": "1_cannon_0"}) == "", "6 damage into the cannon")
	check(int(cannon.piece("1_cannon_0")["hearts"]) == 2, "three hearts removed from five")
	act(cannon, 0, 6)
	check(cannon.apply({"type": "damage", "amount": 6, "target": "1_cannon_0"}) == "", "finish fortified cannon")
	check(bool(cannon.piece("1_cannon_0")["captured"]) and bool(cannon.piece("1_box_0")["captured"]), "cannon and box are captured together")
	check(cannon.vp(0) == 13, "cannon 10 plus box 3")

	var shielded = fresh()
	check(shielded.place("1_cannon_0", "sofa", 0) == "", "sofa cannon")
	shielded.begin_battle(0)
	shielded.force_roll(6)
	check(shielded.apply({"type": "damage", "amount": 6, "target": "1_cannon_0"}) == "", "shield blocks damage")
	check(not bool(shielded.piece("1_cannon_0")["shield"]), "shield is spent")
	check(int(shielded.piece("1_cannon_0")["hearts"]) == 5, "no hearts lost")
	check(not bool(shielded.piece("1_cannon_0")["captured"]), "cannon stays")


func _test_cannon_shot_and_pass() -> void:
	current = "cannon and pass"
	var battle = fresh()
	check(battle.place("1_box_0", "sofa", 0) == "", "shielded box")
	battle.begin_battle(0)
	battle.force_roll(5)
	check(battle.apply({"type": "cannon_shot", "target": "1_box_0"}) == "", "shot hits a shield")
	check(not bool(battle.piece("1_box_0")["captured"]), "shielded box is not captured")
	check(not bool(battle.piece("1_box_0")["shield"]), "shield broke")

	act(battle, 0, 5)
	check(battle.apply({"type": "cannon_shot", "target": "1_box_0"}) == "", "second shot captures")
	check(bool(battle.piece("1_box_0")["captured"]), "box is jailed")
	check(battle.vp(0) == 3, "box VP")

	var quiet = fresh()
	for i in 12:
		jail(quiet, "1_alley_%d" % i, 0)
	jail(quiet, "0_cannon_0", 1)
	jail(quiet, "0_cannon_1", 1)
	quiet.begin_battle(0)
	quiet.force_roll(5)
	var types: Array = []
	for spec in quiet.legal_types():
		types.append(str(spec["type"]))
	check(types == ["pass"], "roll 5 with no cats and no cannon is a pass, got %s" % str(types))
	check(quiet.apply({"type": "cannon_shot", "target": "1_box_0"}) != "", "cannot fire without a cannon")
	check(quiet.apply({"type": "pass"}) == "", "pass ends the turn")
	check(quiet.current_player == 1 and quiet.stage == "roll", "turn advanced")


func _test_boss_endings() -> void:
	current = "boss"
	var battle = _exposed_battle()
	battle.force_roll(6)
	check(battle.damage_targets().has("1_boss_0"), "exposed boss can be hit")
	check(battle.apply({"type": "damage", "amount": 6, "target": "1_boss_0"}) == "", "first boss hit")
	check(int(battle.piece("1_boss_0")["hearts"]) == 2, "two hearts remain")
	check(battle.phase == "battle", "battle continues")
	act(battle, 0, 6)
	check(battle.apply({"type": "damage", "amount": 6, "target": "1_boss_0"}) == "", "boss falls")
	check(battle.phase == "game_over", "battle ends")
	check(battle.winner == 0 and not battle.draw, "captor wins while ahead")
	check(battle.vp(0) == 22, "8 + 9 + boss 5")

	var loss = _exposed_battle()
	jail(loss, "0_cannon_0", 1)
	jail(loss, "0_cannon_1", 1)
	for i in 4:
		jail(loss, "0_alley_%d" % i, 1)
	loss.force_roll(6)
	loss.apply({"type": "damage", "amount": 6, "target": "1_boss_0"})
	act(loss, 0, 6)
	loss.apply({"type": "damage", "amount": 6, "target": "1_boss_0"})
	check(loss.phase == "game_over" and loss.winner == 1, "defeating the boss can still lose")
	check(loss.vp(0) == 22 and loss.vp(1) == 24, "VP is 22 to 24")

	var tied = _exposed_battle()
	jail(tied, "0_cannon_0", 1)
	jail(tied, "0_cannon_1", 1)
	jail(tied, "0_alley_0", 1)
	jail(tied, "0_alley_1", 1)
	tied.force_roll(6)
	tied.apply({"type": "damage", "amount": 6, "target": "1_boss_0"})
	act(tied, 0, 6)
	tied.apply({"type": "damage", "amount": 6, "target": "1_boss_0"})
	check(tied.draw and tied.winner == -1, "equal VP is a draw")
	check(tied.vp(0) == tied.vp(1), "VP matches")


func _exposed_battle():
	var battle = fresh()
	for i in 8:
		jail(battle, "1_alley_%d" % i, 0)
	for i in 3:
		jail(battle, "1_box_%d" % i, 0)
	battle.begin_battle(0)
	return battle


func _test_initiative() -> void:
	current = "initiative"
	var battle = fresh()
	check(not bool(battle.roll_initiative().get("ok", false)), "initiative waits until both armies lock")
	check(battle.lock_deploy(0) == "", "lock player")
	check(battle.phase == "deploy", "still deploying")
	check(battle.lock_deploy(1) == "", "lock ai")
	check(battle.phase == "initiative", "ready to roll")
	check(battle.place("0_alley_4", "sofa", 0) != "", "no moves after lock")
	var info = battle.roll_initiative()
	check(bool(info.get("ok", false)), "initiative rolls")
	var last: Array = info["rolls"][info["rolls"].size() - 1]
	check(int(last[0]) != int(last[1]), "ties are rerolled")
	var expected = 0 if int(last[0]) > int(last[1]) else 1
	check(battle.current_player == expected and battle.stage == "roll", "higher roll goes first")


func _test_snapshot_roundtrip() -> void:
	current = "snapshot"
	var battle = fresh()
	AI.deploy(battle, 0)
	AI.deploy(battle, 1)
	battle.begin_battle(0)
	battle.force_roll(4)
	check(battle.apply({"type": "capture_alleys", "targets": ["1_alley_4", "1_alley_5"]}) == "", "capture before save")
	var parsed = JSON.parse_string(JSON.stringify(battle.to_data()))
	check(typeof(parsed) == TYPE_DICTIONARY, "snapshot is JSON")
	var restored = Rules.new()
	restored.apply_data(parsed)
	check(restored.vp(0) == battle.vp(0), "VP survives JSON")
	check(int(restored.piece("0_cannon_0")["rug_hearts"]) == 2, "fortify survives JSON")
	act(restored, 0, 2)
	var target = str(restored.damage_targets()[0])
	check(restored.apply({"type": "damage", "amount": 2, "target": target}) == "", "restored battle can act")


func _test_ai_does_not_mutate() -> void:
	current = "ai purity"
	var battle = fresh()
	AI.deploy(battle, 0)
	AI.deploy(battle, 1)
	battle.begin_battle(0)
	battle.force_roll(6)
	var hearts = int(battle.piece("1_cannon_1")["hearts"])
	var vp = battle.vp(0)
	var move = AI.choose(battle)
	check(not move.is_empty(), "ai picks a move")
	check(battle.vp(0) == vp, "choosing does not change VP")
	check(int(battle.piece("1_cannon_1")["hearts"]) == hearts, "choosing does not change hearts")
	check(battle.apply(move) == "", "the chosen move is legal")


func _test_ai_games_finish() -> void:
	current = "full games"
	for seed in [1, 2, 3, 4, 5]:
		var battle = fresh()
		battle.set_seed(seed)
		check(AI.deploy(battle, 0) == "" and AI.deploy(battle, 1) == "", "seed %d deploy" % seed)
		battle.begin_battle(0 if seed % 2 == 0 else 1)
		var guard = 0
		var stuck = ""
		while battle.phase != "game_over" and guard < 400:
			guard += 1
			if battle.stage == "roll":
				battle.roll_die()
			var move = AI.choose(battle)
			var err = battle.apply(move)
			if err != "":
				stuck = err
				break
		check(stuck == "", "seed %d illegal move %s" % [seed, stuck])
		check(battle.phase == "game_over", "seed %d ended in %d turns, log %s" % [seed, guard, str(battle.log.slice(-4))])
		if battle.phase == "game_over" and not battle.draw:
			check(battle.winner == 0 or battle.winner == 1, "seed %d has a winner" % seed)
