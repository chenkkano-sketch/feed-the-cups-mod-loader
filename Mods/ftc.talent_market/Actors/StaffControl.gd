extends "res://TscnAndGd/Main/Player/Control.gd"

# Retain the game's holding / arm animation protocol, without binding a human
# keyboard, Steam controller, multiplayer channel, or the trainer's input hooks.
func _ready():
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	JoyDevice = -1
	KeyboardType = -1
	CanControl = true
	CanRoll = false

func _connect_init():
	pass

func _control_logic(_button, _value, _type):
	pass

func _physics_process(_delta):
	pass
