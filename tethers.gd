class_name Tethers
extends RefCounted
## Who is roped to whom. Everyone who isn't on radar duty is always tethered:
## divers are paired in a fixed order (by sprite look) - 1+2, 3+4, ... - and an
## odd one out joins the last pair as a chain of three. A lone diver is roped to
## the station instead. Every peer works this out the same way from replicated
## state, so no extra networking is needed. The rope physics live in player.gd.

const STATION_ANCHOR := Vector2(0.0, 60.0)
const SNAP_STRETCH := 1.35            # a rope snaps at 135% of its length
const STATION_ROPE_MULTIPLIER := 3.0  # a lone diver's rope to the station is longer


## All ropes as [a, b] pairs of Players; b is null for a rope to the station.
static func links(tree: SceneTree) -> Array:
	var divers: Array[Player] = []
	for player: Player in tree.get_nodes_in_group("players"):
		if not player.on_radar:
			divers.append(player)
	divers.sort_custom(func(a: Player, b: Player) -> bool: return a.look < b.look)

	var result := []
	if divers.size() == 1:
		result.append([divers[0], null])
		return result
	for i in range(0, divers.size() - 1, 2):
		result.append([divers[i], divers[i + 1]])
	if divers.size() % 2 == 1:
		result.append([divers[-2], divers[-1]])  # odd one out joins the last pair
	return result


## The ropes attached to one player.
static func links_of(player: Player) -> Array:
	return links(player.get_tree()).filter(func(link: Array) -> bool: return player in link)


## The other end of a rope: a Player, or null for the station.
static func other_end(link: Array, player: Player) -> Player:
	return link[1] if link[0] == player else link[0]


static func rope_length(to_station: bool) -> float:
	return GameState.tether_length() * (STATION_ROPE_MULTIPLIER if to_station else 1.0)
