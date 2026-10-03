extends Resource

# Starting presentation values for the seated 25-40 table.
# The reference feel notes are estimates. This game keeps its own rules.

@export_group("Camera")
@export var camera_fov := 56.0
@export var camera_near := 0.05
@export var eye_lift := 0.02
@export var breath_meters := 0.004
@export var breath_hz := 0.25
@export var sway_meters := 0.003
@export var sway_radians := 0.006
@export var sway_enabled := true
@export var look_enabled := true
@export var look_sensitivity := 0.0022
@export var look_omega := 46.0
@export var look_yaw_limit := 1.92
@export var look_pitch_min := -0.55
@export var look_pitch_max := 0.45
@export var inspect_pitch := -0.16
@export var reveal_pitch := -0.07
@export var reveal_dolly := 0.06
@export var body_follow := 0.22

@export_group("Look")
@export var look_spine := 0.15
@export var look_neck := 0.25
@export var look_head := 0.60
@export var head_lag := 0.11
@export var torso_lag := 0.26

@export_group("Hands")
@export var table_clearance := 0.016
@export var plant_lift := 0.05
@export var arm_skin := 0.028
@export var finger_lift := 0.12
@export var arm_slide := 0.06

@export_group("Light")
@export var lamp_color := Color(1.0, 0.72, 0.45, 1.0)
@export var lamp_energy := 3.6
@export var lamp_angle := 48.0
@export var ambient_color := Color(0.4, 0.29, 0.2, 1.0)
@export var ambient_energy := 0.74
@export var fill_energy := 0.36
@export var glow_strength := 0.14
@export var contrast := 1.03
@export var saturation := 1.05
