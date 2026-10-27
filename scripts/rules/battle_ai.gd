extends RefCounted
class_name BattleAI

# Greedy proof-of-concept opponent. It simulates each legal move on a copy
# of the battle and picks the one that improves its jail VP, then hearts and shields.


static func deploy(state, owner: int) -> String:
	for p in state.pieces:
		if int(p["owner"]) != owner:
			continue
		var err = state.place(str(p["id"]), "floor", -1)
		if err != "":
			return err
	var prefix = str(owner)
	var steps = [
		["%s_cannon_0" % prefix, "rug", 0],
		["%s_box_0" % prefix, "rug", 2],
		["%s_alley_0" % prefix, "rug", 3],
		["%s_box_1" % prefix, "rug", 4],
		["%s_alley_1" % prefix, "sofa", 0],
		["%s_alley_2" % prefix, "sofa", 1],
		["%s_alley_3" % prefix, "sofa", 2],
	]
	for step in steps:
		var err = state.place(str(step[0]), str(step[1]), int(step[2]))
		if err != "":
			return err
	return ""


static func choose(state) -> Dictionary:
	if state.phase != "battle" or state.stage != "act":
		return {"type": "pass"}
	var moves = _moves(state)
	if moves.is_empty():
		return {"type": "pass"}
	var me = int(state.current_player)
	var best: Dictionary = moves[0]
	var best_score = -2_000_000_000
	for move in moves:
		var sim = state.duplicate_state()
		if sim.apply(move) != "":
			continue
		var score = _score(state, sim, me)
		if score > best_score:
			best_score = score
			best = move
	return best


static func _moves(state) -> Array:
	var moves: Array = []
	for spec in state.legal_types():
		match str(spec.get("type", "")):
			"capture_alleys":
				var picked = _greedy_alleys(state, int(spec.get("max", 1)))
				if not picked.is_empty():
					moves.append({"type": "capture_alleys", "targets": picked})
			"capture_box", "cannon_shot":
				for id in state.targets_for(spec):
					moves.append({"type": str(spec["type"]), "target": str(id)})
			"damage":
				for id in state.targets_for(spec):
					moves.append({
						"type": "damage",
						"amount": int(spec.get("amount", state.roll)),
						"target": str(id),
					})
			"pass":
				moves.append({"type": "pass"})
	return moves


static func _greedy_alleys(state, max_n: int) -> Array:
	var plain: Array = []
	var shielded: Array = []
	for id in state.targets_for({"type": "capture_alleys"}):
		var p = state.piece(str(id))
		if bool(p.get("shield", false)):
			shielded.append(str(id))
		else:
			plain.append(str(id))
	var chosen: Array = []
	for id in plain:
		if chosen.size() >= max_n:
			break
		chosen.append(id)
	for id in shielded:
		if chosen.size() >= max_n:
			break
		chosen.append(id)
	return chosen


static func _score(before, after, me: int) -> int:
	if after.phase == "game_over":
		if after.draw:
			return 500
		if int(after.winner) == me:
			return 1_000_000
		return -1_000_000
	var opp = 1 - me
	var my_gain = after.vp(me) - before.vp(me)
	var opp_gain = after.vp(opp) - before.vp(opp)
	var hearts = _living_hearts(before, opp) - _living_hearts(after, opp)
	var shields = _living_shields(before, opp) - _living_shields(after, opp)
	return my_gain * 100 - opp_gain * 100 + hearts * 8 + shields * 3


static func _living_hearts(state, owner: int) -> int:
	var total = 0
	for p in state.pieces:
		if int(p["owner"]) != owner or bool(p["captured"]):
			continue
		total += int(p["hearts"]) + int(p["rug_hearts"])
	return total


static func _living_shields(state, owner: int) -> int:
	var total = 0
	for p in state.pieces:
		if int(p["owner"]) == owner and not bool(p["captured"]) and bool(p["shield"]):
			total += 1
	return total
