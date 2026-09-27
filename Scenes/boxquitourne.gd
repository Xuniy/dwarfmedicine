extends CSGBox3D

# Vitesse de rotation en radians par seconde
var vitesse_rotation = 2.0 

func _process(delta):
	# Fait tourner la boîte sur l'axe Y (vertical)
	rotate_y(vitesse_rotation * delta)
	
	# Alternatives pour les autres axes :
	# rotate_x(vitesse_rotation * delta)
	# rotate_z(vitesse_rotation * delta)
