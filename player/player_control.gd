extends CharacterBody3D

@export_group("Walking")
@export var walk_speed: float = 4.0
@export var crouch_speed: float = 2.0
@export var acceleration: float = 15.0
@export var friction: float = 8.0

@export_group("Sprinting")
@export var sprint_speed: float = 8.0
@export var max_stamina: float = 10.0
@export var can_sprint: bool = true
@export var unlimited_sprint: bool = true
@export var stamina_drain_rate: float = 2.0 
@export var stamina_regen_rate: float = 1.0 
@export var stamina_regen_delay: float = 0.5

@export_group("Jumping")
@export var jump_height: float = 1.5
@export var gravity_scale: float = 2.0 #dont ask what's the difference between gravity and gravity_scale, i stole it
@export var air_control: float = 0.3
@export var gravity: float = 9.0 #dont ask what's the difference between gravity and gravity_scale, i stole it

@export_group("Additional Jumps")
#double jumps
@export var mid_air_jumps: int = 0
#wall jumps
@export var wall_jumps: int = 0
@export var wall_jump_force: float = 10.0
@export var wall_jump_height: float = 5.0
@export var wall_jump_cooldown: float = 0.1

@export_group("Crouching")
@export var can_crouch: bool = true
@export var crouch_height: float = 1.0
@export var standing_height: float = 2.0
@export var crouch_transition_speed: float = 5.0
enum CrouchMode { TOGGLE, HOLD }
@export var crouch_mode: CrouchMode = CrouchMode.HOLD

@export_group("Sliding")
@export var can_slide: bool = true
@export var slide_friction: float = 2.5 #how fast you rip ur ass
@export var slide_min_speed: float = 1.0 #speed when you go back into crouching
@export var slide_max_speed: float = 20.0 #cap for slide boost
@export var slide_air_control: float = 2.0 #how much you control during sliding, like in ultrakill
@export var slide_boost_multiplier: float = 999.0 #player speed * this thingy = boost (caps at slide_max_speed), i set to 999 so it maxes

@export_group("Head Bobbing")
@export var bobbing_enabled: bool = true
@export var bobbing_amplitude: float = 0.04 #up down
@export var bobbing_frequency: float = 2.0 #how fast

@export_group("Mouse Look")
@export var mouse_sensitivity: float = 0.008
@export var max_look_angle: float = 90.0
# ----- NODE REFERENCES -----

@onready var interactable_cursor: TextureRect = $UI/Cursor/Interactable_Cursor
@onready var camera_pivot: Node3D = $Camera_Pivot
@onready var player_camera: Camera3D = $Camera_Pivot/Player_Camera
@onready var body_collision: CollisionShape3D = $Body_Collision
@onready var hit_ray: RayCast3D = $Camera_Pivot/Player_Camera/Hit_Ray
@onready var test_label: Label = $UI/Position_Label
@onready var stamina_bar: ProgressBar = $UI/Stamina_Bar


# ----- INTERNAL VARIABLES -----
#camera
var yaw: float = 0.0
var pitch: float = 0.0
#crouch
var is_crouching: bool = false
var target_height: float = standing_height
var current_height: float = standing_height
#sprint
var is_sprinting: bool = false
var stamina_regen_timer: float = 0.0
var stamina: float = 0.0
#slides
var is_sliding: bool = false
var slide_direction: Vector3 = Vector3.ZERO
var slide_speed: float = 0.0
var slide_boosted: bool = false
#jumps
var jump_buffer_timer: float = 0.0
var coyote_timer: float = 0.0
var BUFFER_TIME: float = 0.1
var COYOTE_TIME: float = 0.2
#double jumps
var mid_air_jumps_remaining: int = 0
var wall_jumps_remaining: int = 1
var wall_jump_timer: float = 0.0
var wall_normal: Vector3 = Vector3.ZERO
#bobbingh
var bobbing_time: float = 0.0
#interaction
var is_interacting: bool = false

# ----- INITIALIZATION -----

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	current_height = standing_height
	target_height = standing_height
	body_collision.shape.height = standing_height

	mid_air_jumps_remaining = mid_air_jumps

	wall_jumps_remaining = wall_jumps

	stamina_bar.max_value = max_stamina
	stamina = max_stamina

# ----- INPUT HANDLING -----

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("Escape"):
		if is_interacting:
			is_interacting = false
		else:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				get_tree().paused = true
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				get_tree().paused = false
	
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-max_look_angle), deg_to_rad(max_look_angle))
		
		rotation.y = yaw
		camera_pivot.rotation.x = pitch
	
	# ----- CROUCH INPUT -----
	
	match crouch_mode:
		CrouchMode.TOGGLE:
			if event is InputEventKey and event.keycode == KEY_CTRL and event.pressed:
				toggle_crouch()
			if event is InputEventAction and event.action == "crouch" and event.pressed:
				toggle_crouch()
		
		CrouchMode.HOLD:
			if event is InputEventKey and event.keycode == KEY_CTRL:
				if event.pressed:
					start_crouch()
				else:
					stop_crouch()
			if event is InputEventAction and event.action == "crouch":
				if event.pressed:
					start_crouch()
				else:
					stop_crouch()

# ----- MAIN LOOP -----

func _physics_process(delta: float) -> void:
	# --- INTERACTABLES ---
	if hit_ray.is_colliding():
		var target = hit_ray.get_collider()
		if target.is_in_group("Interactable"):
			interactable_cursor.scale = Vector2(lerpf(interactable_cursor.scale.x, 1.0, delta * 5), lerpf(interactable_cursor.scale.y, 1.0, delta * 5))
		else:
			interactable_cursor.scale = Vector2(lerpf(interactable_cursor.scale.x, 0.0, delta * 5), lerpf(interactable_cursor.scale.y, 0.0, delta * 5))
	else:
		interactable_cursor.scale = Vector2(lerpf(interactable_cursor.scale.x, 0.0, delta * 5), lerpf(interactable_cursor.scale.y, 0.0, delta * 5))

	# --- POSITION LABEL ---
	test_label.text = str("X:", snappedf(position.x, 0.01), "\n",
	"Y:", snappedf(position.y, 0.01), "\n",
	"Z:", snappedf(position.z, 0.01), "\n")
	
	# --- COYOTE TIMER ---
	if is_on_floor():
		coyote_timer = COYOTE_TIME
		mid_air_jumps_remaining = mid_air_jumps
		wall_jumps_remaining = wall_jumps
	else:
		coyote_timer -= delta
	
	if wall_jump_timer > 0:
		wall_jump_timer -= delta
	
	if Input.is_action_just_pressed("Jump"):
		jump_buffer_timer = BUFFER_TIME
	else:
		jump_buffer_timer -= delta
	
	# --- GRAVITY ---
	if not is_on_floor():
		velocity.y -= gravity * gravity_scale * delta
	else:
		if velocity.y < 0:
			velocity.y = 0
	
	# --- JUMPING ---
	if jump_buffer_timer > 0:
		if coyote_timer > 0:
			_jump()
			jump_buffer_timer = 0.0
		elif mid_air_jumps_remaining > 0 and !is_on_floor():
			_mid_air_jump()
			jump_buffer_timer = 0.0
		elif wall_jumps_remaining > 0 and _is_on_wall() and wall_jump_timer <= 0:
			_wall_jump()
			jump_buffer_timer = 0.0
	
	# --- SPRINTING ---
	is_sprinting = Input.is_action_pressed("Sprint") and !is_crouching and can_sprint and stamina > 0.0
	stamina_bar.value = stamina
	if stamina == max_stamina:
		stamina_bar.modulate.a = lerpf(stamina_bar.modulate.a, 0.0, delta * 3)
	else:
		stamina_bar.modulate.a = lerpf(stamina_bar.modulate.a, 1.0, delta * 5)
	
	# --- STAMINA DRAIN ---
	if !unlimited_sprint:
		if is_sprinting and is_on_floor():  # only consume when on ground (optional)
			stamina = max(0.0, stamina - stamina_drain_rate * delta)
			stamina_regen_timer = stamina_regen_delay  # reset delay
		else:
			if stamina_regen_timer > 0:
				stamina_regen_timer -= delta
			else:
				stamina = min(max_stamina, stamina + stamina_regen_rate * delta)
		stamina = clamp(stamina, 0.0, max_stamina)
	
	# --- CROUCHING ---
	if crouch_mode == CrouchMode.HOLD:
		if Input.is_key_pressed(KEY_CTRL) or Input.is_action_pressed("Crouch"):
			start_crouch()
		else:
			stop_crouch()
	current_height = lerp(current_height, target_height, crouch_transition_speed * delta)
	body_collision.shape.height = current_height
	camera_pivot.position.y = current_height / 4
	
	# --- SLIDING ---
	_handle_slide_start()
	if is_sliding:
		_handle_slide_movement(delta)
	else:
		_handle_normal_movement(delta)
	
	# --- MOVEMENT ---
	move_and_slide()
	_update_wall_normal()
	
	# --- HEAD BOBBING ---
	bobbing_time += delta * velocity.length() * float(is_on_floor())
	player_camera.transform.origin = _handle_view_bobbing()

# ----- JUMP FUNCTIONS -----

func _jump() -> void:
	if is_sliding:
		_stop_sliding()
	
	velocity.y = sqrt(2.0 * gravity * jump_height)
	jump_buffer_timer = 0.0
	coyote_timer = 0.0

func _mid_air_jump() -> void:
	if mid_air_jumps_remaining > 0:
		mid_air_jumps_remaining -= 1
		velocity.y = sqrt(2.0 * gravity * jump_height * 0.8)
		jump_buffer_timer = 0.0

func _wall_jump() -> void:
	if wall_normal != Vector3.ZERO and wall_jumps_remaining > 0 and wall_jump_timer <= 0:
		wall_jumps_remaining -= 1
		
		mid_air_jumps_remaining = mid_air_jumps
		
		var horizontal_force = wall_normal * wall_jump_force
		horizontal_force.y = 0
		
		var vertical_force = sqrt(2.0 * gravity * wall_jump_height)
		
		velocity.x = horizontal_force.x
		velocity.z = horizontal_force.z
		velocity.y = vertical_force
		
		# Start cooldown
		wall_jump_timer = wall_jump_cooldown
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		
		#print("Wall jump! Remaining: ", wall_jumps_remaining, " | Normal: ", wall_normal)

# ----- WALL DETECTION -----

func _is_on_wall() -> bool:
	# Check if we're touching a wall
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		# Check if the collision normal is mostly horizontal (not floor or ceiling)
		if collision.get_normal().y < 0.1 and collision.get_normal().y > -0.1:
			return true
	return false

func _update_wall_normal() -> void:
	# Get the normal of the wall we're touching
	wall_normal = Vector3.ZERO
	
	if wall_jumps_remaining > 0 and not is_on_floor():
		for i in range(get_slide_collision_count()):
			var collision = get_slide_collision(i)
			var normal = collision.get_normal()
			# Check if it's a wall (horizontal surface)
			if normal.y < 0.1 and normal.y > -0.1:
				wall_normal = normal
				break
	else:
		wall_normal = Vector3.ZERO

# ----- SLIDING FUNCTIONS -----

func _handle_slide_start() -> void:
	if !can_slide or !can_crouch:
		return
	
	if is_on_floor() and is_crouching and not is_sliding:
		var horizontal_velocity := Vector3(velocity.x, 0, velocity.z)
		var current_speed := horizontal_velocity.length()
		
		# Need to be sprinting or moving fast to start slide
		var is_moving_fast := current_speed > walk_speed * 0.8
		
		if is_moving_fast or is_sprinting:
			# Start the slide
			is_sliding = true
			slide_boosted = false  # Reset boost flag for this slide
			slide_direction = horizontal_velocity.normalized()
			
			# Apply boost to the slide speed
			var boosted_speed = current_speed * slide_boost_multiplier
			slide_speed = min(boosted_speed, slide_max_speed)
			
			print("Slide started! Speed: ", slide_speed, " (Boosted x", slide_boost_multiplier, ")")

func _handle_slide_movement(delta: float) -> void:
	# Apply friction to slow down the slide
	slide_speed = lerp(slide_speed, 0.0, slide_friction * delta)
	
	# Cap the speed
	slide_speed = min(slide_speed, slide_max_speed)
	
	# If slide speed drops below minimum, stop sliding
	if slide_speed < slide_min_speed:
		_stop_sliding()
		return
	
	# Apply slide velocity
	velocity.x = slide_direction.x * slide_speed
	velocity.z = slide_direction.z * slide_speed
	
	# Allow slight steering while sliding (air control style)
	var input_dir := Input.get_vector("Left", "Right", "Forward", "Backward")
	if input_dir != Vector2.ZERO:
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		# Slowly rotate the slide direction toward input
		slide_direction = slide_direction.lerp(direction, slide_air_control * delta * 2.0).normalized()

func _stop_sliding() -> void:
	if is_sliding:
		is_sliding = false
		slide_direction = Vector3.ZERO
		slide_speed = 0.0
		slide_boosted = false
		print("Slide stopped")

# ----- NORMAL MOVEMENT (No Slide) -----

func _handle_normal_movement(delta: float) -> void:
	
	var current_speed: float
	if is_crouching:
		current_speed = crouch_speed
	elif is_sprinting:
		current_speed = sprint_speed
	else:
		current_speed = walk_speed
	
	# Get input direction
	var input_dir := Input.get_vector("Left", "Right", "Forward", "Backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction != Vector3.ZERO:
		# Move in the direction we're facing
		var target_velocity: Vector3 = direction * current_speed
		
		if is_on_floor():
			velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta)
			velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta)
		else:
			velocity.x = lerp(velocity.x, target_velocity.x, acceleration * delta * air_control)
			velocity.z = lerp(velocity.z, target_velocity.z, acceleration * delta * air_control)
	else:
		if is_on_floor():
			velocity.x = lerp(velocity.x, 0.0, friction * delta)
			velocity.z = lerp(velocity.z, 0.0, friction * delta)

# ----- VIEW BOBBING FUNCTION -----

func _handle_view_bobbing():
	var headbob_position = Vector3.ZERO
	headbob_position.y = sin(bobbing_time * bobbing_frequency) * bobbing_amplitude
	headbob_position.x = sin(bobbing_time * bobbing_frequency / 2) * bobbing_amplitude
	return headbob_position
	

# ----- CROUCH HELPER FUNCTIONS -----

func toggle_crouch() -> void:
	
	is_crouching = not is_crouching
	_update_crouch_state()

func start_crouch() -> void:
	
	if not is_crouching:
		is_crouching = true
		_update_crouch_state()

func stop_crouch() -> void:
	
	if is_crouching:
		if _can_stand_up():
			is_crouching = false
			_update_crouch_state()

func _update_crouch_state() -> void:
	if !can_crouch:
		return
	
	target_height = crouch_height if is_crouching else standing_height
	
	if is_crouching and is_sprinting:
		is_sprinting = false
	
	if not is_crouching and is_sliding:
		_stop_sliding()

func _can_stand_up() -> bool:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	
	# Use a capsule shape at the standing height
	var capsule := CapsuleShape3D.new()
	capsule.height = standing_height
	capsule.radius = body_collision.shape.radius
	
	query.shape = capsule
	query.transform = Transform3D.IDENTITY.translated(global_position + Vector3.UP * (standing_height / 2))
	query.collision_mask = collision_mask
	query.exclude = [self]
	
	var results := space_state.intersect_shape(query)
	return results.is_empty()

# ----- PUBLIC FUNCTIONS (For Perks/Upgrades) -----

# --- Mid-Air Jump Perks ---

func add_mid_air_jump() -> void:
	mid_air_jumps += 1
	mid_air_jumps_remaining = mid_air_jumps

func remove_mid_air_jump() -> void:
	if mid_air_jumps > 0:
		mid_air_jumps -= 1
		if mid_air_jumps_remaining > mid_air_jumps:
			mid_air_jumps_remaining = mid_air_jumps

func set_mid_air_jumps(value: int) -> void:
	mid_air_jumps = max(0, value)
	mid_air_jumps_remaining = mid_air_jumps

# --- Wall Jump Perks ---

func add_wall_jump() -> void:
	wall_jumps += 1
	wall_jumps_remaining = wall_jumps

func remove_wall_jump() -> void:
	if wall_jumps > 0:
		wall_jumps -= 1
		if wall_jumps_remaining > wall_jumps:
			wall_jumps_remaining = wall_jumps

func set_wall_jumps(value: int) -> void:
	wall_jumps = max(0, value)
	wall_jumps_remaining = wall_jumps

# --- Slide Boost Perks ---

func set_slide_boost_multiplier(value: float) -> void:
	slide_boost_multiplier = max(1.0, value)

func add_slide_boost(percentage: float) -> void:
	slide_boost_multiplier += percentage
