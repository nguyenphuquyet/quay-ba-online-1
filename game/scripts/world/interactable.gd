class_name QBOInteractable
extends Area3D
## Component tương tác dùng chung cho mọi vật thể trong nightclub.
## Vật thể chỉ cần gắn component này + metadata; Player raycast vào layer 3 (mask 4).

var interact_id := ""
var prompt := "Tương tác"
var action := "use"
var payload: Dictionary = {}
var enabled := true


func configure(id: String, prompt_text: String, action_name: String, data: Dictionary = {}, size := Vector3(1.4, 1.8, 1.4)) -> void:
	interact_id = id
	prompt = prompt_text
	action = action_name
	payload = data
	name = "Interact_" + id
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group("interactable")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)


func set_enabled(value: bool) -> void:
	enabled = value
	monitoring = false
	collision_layer = 4 if value else 0
