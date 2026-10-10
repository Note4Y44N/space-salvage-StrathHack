class_name Sounds
extends RefCounted
## Sound effects and music. play() fires a one-off sound that deletes itself
## when done; given a world position it is positional (quieter further away).
## Sounds: Kenney.nl (CC0). Music: "Observing The Star" by yd, OpenGameArt (CC0).

## The sounds live in res://sounds/ (music, pickup, sell, buy, radar, alarm,
## thruster, snap, blackout, relic, launch, win).
static func stream(sound: String) -> AudioStream:
	return load("res://sounds/%s.ogg" % sound)


## Play a sound once. With `at`, it plays from that spot in the world.
static func play(from: Node, sound: String, volume_db := 0.0, at := Vector2.INF) -> void:
	var player: Node
	if at == Vector2.INF:
		var flat := AudioStreamPlayer.new()
		flat.stream = stream(sound)
		flat.volume_db = volume_db
		flat.finished.connect(flat.queue_free)
		player = flat
	else:
		var positional := AudioStreamPlayer2D.new()
		positional.stream = stream(sound)
		positional.volume_db = volume_db
		positional.position = at
		positional.max_distance = 2500.0
		positional.finished.connect(positional.queue_free)
		player = positional
	from.get_tree().current_scene.add_child(player)
	player.play()


## A looping player you start and stop yourself (music, jetpack hiss).
static func loop(sound: String, volume_db := 0.0) -> AudioStreamPlayer:
	var looping := stream(sound) as AudioStreamOggVorbis
	looping.loop = true
	var player := AudioStreamPlayer.new()
	player.stream = looping
	player.volume_db = volume_db
	return player
