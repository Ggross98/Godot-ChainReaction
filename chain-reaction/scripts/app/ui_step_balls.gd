class_name UiStepBalls
extends RefCounted


static func spent_count(initial: int, remaining: int) -> int:
	return maxi(maxi(initial, 0) - remaining, 0)


static func inner_visible(index: int, initial: int, remaining: int) -> bool:
	if index < 0 or index >= initial:
		return false
	return index >= spent_count(initial, remaining)


static func sync(parent: Node, template: Control, initial: int, remaining: int) -> void:
	if parent == null or template == null:
		return
	initial = maxi(initial, 0)
	while parent.get_child_count() > initial:
		var extra: Node = parent.get_child(parent.get_child_count() - 1)
		parent.remove_child(extra)
		extra.free()
	while parent.get_child_count() < initial:
		parent.add_child(template.duplicate())
	var spent: int = spent_count(initial, remaining)
	for i in range(parent.get_child_count()):
		var inner: CanvasItem = parent.get_child(i).get_node_or_null("Inner") as CanvasItem
		if inner:
			inner.visible = i >= spent
