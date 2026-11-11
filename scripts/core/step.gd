extends RefCounted
## Permet à un personnage de monter une petite marche (bordure de trottoir, seuil…)
## au lieu d'être bloqué : si le mouvement est bloqué mais libre 30 cm plus haut, on monte.

const STEP_HEIGHT := 0.32


static func try_step(body: CharacterBody3D, horizontal_velocity: Vector3, delta: float) -> void:
	if horizontal_velocity.length() < 0.1 or not body.is_on_floor():
		return
	var motion := horizontal_velocity * delta + horizontal_velocity.normalized() * 0.12
	var t := body.global_transform
	if not body.test_move(t, motion):
		return
	var up := Vector3(0.0, STEP_HEIGHT, 0.0)
	if body.test_move(t, up):
		return
	if body.test_move(t.translated(up), motion):
		return
	body.global_position += up
