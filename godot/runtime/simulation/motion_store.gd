extends "res://runtime/spatial/contact_workspace.gd"
## Authoritative positions/velocities for active dense rows.
## Other inherited contact columns are derived inputs, refreshed by the contact phase.
func copy_row(source: int, destination: int) -> void:
	positions[destination] = positions[source]
	velocities[destination] = velocities[source]
