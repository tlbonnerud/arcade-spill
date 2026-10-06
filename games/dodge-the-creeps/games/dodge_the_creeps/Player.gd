extends Area2D

signal hit

export var speed = 250
var screen_size
var hit_tween

func _ready():
	screen_size = get_viewport_rect().size
	hide()

func _process(delta):
	var velocity = Vector2()
	if Input.is_action_pressed("p1_right"):
		velocity.x += 1
	if Input.is_action_pressed("p1_left"):
		velocity.x -= 1
	if Input.is_action_pressed("p1_down"):
		velocity.y += 1
	if Input.is_action_pressed("p1_up"):
		velocity.y -= 1
	if velocity.length() > 0:
		velocity = velocity.normalized() * speed
		$AnimatedSprite.play()
	else:
		$AnimatedSprite.stop()
	position += velocity * delta
	position.x = clamp(position.x, 0, screen_size.x)
	position.y = clamp(position.y, 0, screen_size.y)
	if velocity.x != 0:
		$AnimatedSprite.animation = "right"
		$AnimatedSprite.flip_v = false
		$AnimatedSprite.flip_h = velocity.x < 0
	elif velocity.y != 0:
		$AnimatedSprite.animation = "up"
		rotation = 0.0

func start(pos):
	if hit_tween:
		hit_tween.kill()
	position = pos
	rotation = 0
	show()
	$AnimatedSprite.modulate = Color(1, 1, 1, 1)
	$ExplosionSprite.visible = false
	$CollisionShape2D.disabled = false

func _on_Player_body_entered(_body):
	emit_signal("hit")
	$CollisionShape2D.set_deferred("disabled", true)
	$AnimatedSprite.modulate = Color(1, 0.3, 0.3)

	$ExplosionSprite.visible = true
	$ExplosionSprite.modulate = Color(1, 0.5, 0, 1)
	$ExplosionSprite.scale = Vector2(0.2, 0.2)

	var explosion_tween = get_tree().create_tween()
	explosion_tween.tween_property($ExplosionSprite, "scale", Vector2(2, 2), 0.3)
	explosion_tween.parallel().tween_property($ExplosionSprite, "modulate:a", 0.0, 0.3)

	hit_tween = get_tree().create_tween()
	hit_tween.tween_property($AnimatedSprite, "modulate:a", 0.0, 0.4)
	hit_tween.tween_callback(self, "hide")
