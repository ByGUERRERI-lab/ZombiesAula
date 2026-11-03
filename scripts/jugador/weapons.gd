extends RefCounted
# Datos de las armas (precio en puntos, cargador, munición de reserva, daño...)
#
# Daño por disparo, de menos a más (un zombie de la oleada 1 tiene 14 de vida):
#   Mini Uzi 1,7 · Subfusil 2 · Minigun 2,6 (muy rápidas) · Pistola 3 · Ametralladora 4
#   Fusil 4,5 · Revólver 9 · Desert Eagle 14 · Francotirador 30 (atraviesa)
#   Escopetas: 7-8 perdigones de 2-2,4 · Pistola Rayo 8 + 14 · Ballesta 18 + 24
#   Lanzacohetes 25 + explosión de 45

# Cómo se sujeta cada arma (en el espacio del modelo de util.gd, el cañón hacia -Z):
#   grip   dónde va la mano derecha (empuñadura)
#   fore   dónde va la mano izquierda (guardamanos, o debajo de la empuñadura en las pistolas)
#   sight  altura de la línea de mira sobre el origen del modelo (para apuntar)
#   rear   z de la mira trasera (al apuntar queda a un palmo del ojo)
#   ads    campo de visión al apuntar · scope = mira telescópica (pantalla de la mira)
#   larga  se lleva con las dos manos separadas (fusiles, escopetas...)
const DATA := {
	"pistola": {
		"name": "Pistola", "price": 0, "mag": 12, "reserve": 72, "dmg": 3.0, "pellets": 1,
		"spread": 1.5, "cd": 0.26, "auto": false, "reload": 1.2, "range": 30.0, "pierce": false,
		"tracer": Color(1.0, 0.9, 0.5), "snd": 0.2, "low": false,
		"grip": Vector3(0, -0.075, 0.03), "fore": Vector3(-0.012, -0.105, 0.05), "sight": 0.068, "rear": 0.015, "ads": 62.0,
	},
	"revolver": {
		"name": "Revólver", "price": 900, "mag": 6, "reserve": 48, "dmg": 9.0, "pellets": 1,
		"spread": 1.0, "cd": 0.42, "auto": false, "reload": 2.2, "range": 35.0, "pierce": false,
		"tracer": Color(1.0, 0.85, 0.5), "snd": 0.35, "low": true,
		"grip": Vector3(0, -0.075, 0.05), "fore": Vector3(-0.012, -0.105, 0.07), "sight": 0.06, "rear": 0.0, "ads": 60.0,
	},
	"deagle": {
		"name": "Desert Eagle", "price": 0, "mag": 7, "reserve": 56, "dmg": 14.0, "pellets": 1,
		"spread": 1.2, "cd": 0.38, "auto": false, "reload": 1.6, "range": 40.0, "pierce": false,
		"tracer": Color(1.0, 0.9, 0.4), "snd": 0.4, "low": true,
		"grip": Vector3(0, -0.085, 0.03), "fore": Vector3(-0.012, -0.115, 0.05), "sight": 0.078, "rear": 0.02, "ads": 60.0,
	},
	"uzi": {
		"name": "Mini Uzi", "price": 1100, "mag": 32, "reserve": 224, "dmg": 1.7, "pellets": 1,
		"spread": 4.0, "cd": 0.06, "auto": true, "reload": 1.5, "range": 24.0, "pierce": false,
		"tracer": Color(1.0, 0.85, 0.45), "snd": 0.13, "low": false,
		"grip": Vector3(0, -0.08, -0.02), "fore": Vector3(0, -0.035, -0.17), "sight": 0.07, "rear": 0.08, "ads": 60.0, "larga": true,
	},
	"subfusil": {
		"name": "Subfusil", "price": 1000, "mag": 30, "reserve": 180, "dmg": 2.0, "pellets": 1,
		"spread": 3.0, "cd": 0.08, "auto": true, "reload": 1.7, "range": 28.0, "pierce": false,
		"tracer": Color(1.0, 0.85, 0.4), "snd": 0.15, "low": false,
		"grip": Vector3(0, -0.08, 0.025), "fore": Vector3(0, -0.035, -0.32), "sight": 0.081, "rear": 0.06, "ads": 58.0, "larga": true,
	},
	"escopeta": {
		"name": "Escopeta de corredera", "price": 1250, "mag": 6, "reserve": 42, "dmg": 2.4, "pellets": 8,
		"spread": 7.0, "cd": 0.85, "auto": false, "reload": 2.8, "range": 16.0, "pierce": false,
		"tracer": Color(1.0, 0.75, 0.35), "snd": 0.45, "low": true,
		"grip": Vector3(0, -0.075, 0.12), "fore": Vector3(0, -0.055, -0.36), "sight": 0.05, "rear": 0.0, "ads": 62.0, "larga": true,
	},
	"fusil": {
		"name": "Fusil de asalto", "price": 1500, "mag": 30, "reserve": 150, "dmg": 4.5, "pellets": 1,
		"spread": 2.5, "cd": 0.11, "auto": true, "reload": 2.0, "range": 40.0, "pierce": false,
		"tracer": Color(1.0, 0.8, 0.3), "snd": 0.22, "low": true,
		"grip": Vector3(0, -0.08, 0.125), "fore": Vector3(0, -0.05, -0.36), "sight": 0.084, "rear": -0.22, "ads": 55.0, "larga": true,
	},
	"francotirador": {
		"name": "Francotirador", "price": 2000, "mag": 5, "reserve": 30, "dmg": 30.0, "pellets": 1,
		"spread": 0.0, "cd": 1.0, "auto": false, "reload": 2.5, "range": 80.0, "pierce": true,
		"tracer": Color(1.0, 1.0, 1.0), "snd": 0.5, "low": true, "hip_spread": 6.0,
		"grip": Vector3(0, -0.1, 0.135), "fore": Vector3(0, -0.08, -0.3), "sight": 0.085, "rear": 0.1, "ads": 22.0, "scope": true, "larga": true,
	},
	"escopeta_auto": {
		"name": "Escopeta automática", "price": 0, "mag": 20, "reserve": 100, "dmg": 2.0, "pellets": 7,
		"spread": 6.5, "cd": 0.22, "auto": true, "reload": 2.5, "range": 16.0, "pierce": false,
		"tracer": Color(1.0, 0.7, 0.3), "snd": 0.4, "low": true,
		"grip": Vector3(0, -0.085, 0.1), "fore": Vector3(0, -0.06, -0.3), "sight": 0.075, "rear": 0.0, "ads": 60.0, "larga": true,
	},
	"ametralladora": {
		"name": "Ametralladora ligera", "price": 0, "mag": 100, "reserve": 400, "dmg": 4.0, "pellets": 1,
		"spread": 3.5, "cd": 0.085, "auto": true, "reload": 4.5, "range": 40.0, "pierce": false,
		"tracer": Color(1.0, 0.6, 0.25), "snd": 0.28, "low": true,
		"grip": Vector3(0, -0.09, 0.14), "fore": Vector3(0, -0.06, -0.3), "sight": 0.1, "rear": -0.05, "ads": 58.0, "larga": true,
	},
	"minigun": {
		"name": "Minigun", "price": 0, "mag": 250, "reserve": 500, "dmg": 2.6, "pellets": 1,
		"spread": 5.0, "cd": 0.035, "auto": true, "reload": 6.0, "range": 32.0, "pierce": false,
		"tracer": Color(1.0, 0.95, 0.5), "snd": 0.12, "low": true,
		"grip": Vector3(0, 0.06, 0.18), "fore": Vector3(0, 0.11, -0.12), "sight": 0.16, "rear": 0.0, "ads": 66.0, "larga": true,
		"fp": Vector3(0.2, -0.3, -0.5),
	},
	# Disparan algo que explota al chocar (contra un enemigo, la pared o el suelo) y
	# hace daño a todo lo que haya alrededor... menos a ti. "proj" = cómo se ve.
	"pistola_rayo": {
		"name": "Pistola Rayo", "price": 0, "mag": 20, "reserve": 100, "dmg": 8.0, "pellets": 1,
		"spread": 0.5, "cd": 0.3, "auto": false, "reload": 1.5, "range": 35.0, "pierce": false,
		"tracer": Color(0.2, 1.0, 0.4), "snd": 0.25, "low": false,
		"explode": true, "splash_dmg": 14.0, "splash_r": 3.0, "speed": 38.0, "proj": "energia",
		"grip": Vector3(0, -0.08, 0.035), "fore": Vector3(-0.012, -0.11, 0.055), "sight": 0.1, "rear": 0.0, "ads": 62.0,
	},
	"ballesta": {
		"name": "Ballesta explosiva", "price": 0, "mag": 5, "reserve": 30, "dmg": 18.0, "pellets": 1,
		"spread": 0.3, "cd": 0.7, "auto": false, "reload": 2.2, "range": 50.0, "pierce": false,
		"tracer": Color(1.0, 0.55, 0.15), "snd": 0.1, "low": false,
		"explode": true, "splash_dmg": 24.0, "splash_r": 2.8, "speed": 48.0, "proj": "virote",
		"grip": Vector3(0, -0.08, 0.15), "fore": Vector3(0, -0.04, -0.12), "sight": 0.07, "rear": 0.05, "ads": 50.0, "larga": true,
	},
	"lanzacohetes": {
		"name": "Lanzacohetes", "price": 0, "mag": 1, "reserve": 14, "dmg": 25.0, "pellets": 1,
		"spread": 0.4, "cd": 0.6, "auto": false, "reload": 2.8, "range": 60.0, "pierce": false,
		"tracer": Color(1.0, 0.5, 0.1), "snd": 0.6, "low": true,
		"explode": true, "splash_dmg": 45.0, "splash_r": 4.5, "speed": 26.0, "proj": "cohete", "hombro": true, "fp": Vector3(0.24, -0.11, -0.26),
		"grip": Vector3(0, -0.11, 0.05), "fore": Vector3(0, -0.11, -0.3), "sight": 0.12, "rear": 0.05, "ads": 58.0, "larga": true,
	},
}

# Las que se compran en la pared (cada mapa pone su cartel) y las que solo te pueden
# tocar en la caja misteriosa. La caja puede dar cualquiera menos la pistola del principio.
const PARED := ["revolver", "uzi", "subfusil", "escopeta", "fusil", "francotirador"]
const SOLO_CAJA := ["deagle", "escopeta_auto", "ametralladora", "minigun", "pistola_rayo", "ballesta", "lanzacohetes"]
const BOX_POOL := ["revolver", "uzi", "subfusil", "escopeta", "fusil", "francotirador",
	"deagle", "escopeta_auto", "ametralladora", "minigun", "pistola_rayo", "ballesta", "lanzacohetes"]


# Texto del daño para enseñarlo en la tienda y en el HUD
static func damage_text(id: String) -> String:
	var d: Dictionary = DATA[id]
	if d.get("explode", false):
		return "Daño %d + explosión %d" % [int(d["dmg"]), int(d["splash_dmg"])]
	if int(d["pellets"]) > 1:
		return "Daño %d (%d perdigones)" % [roundi(float(d["dmg"]) * int(d["pellets"])), int(d["pellets"])]
	var t := "Daño %s" % str(snappedf(float(d["dmg"]), 0.1)).trim_suffix(".0")
	if d["pierce"]:
		t += " (atraviesa)"
	return t


# Nombre de lo que te ha robado Víctor
static func loot_name(item: Dictionary, article := false) -> String:
	match str(item["k"]):
		"arma":
			var n := str(DATA[item["w"]["id"]]["name"])
			if article:
				var la := n.begins_with("Pistola") or n.begins_with("Escopeta") or n.begins_with("Ametralladora") \
						or n.begins_with("Ballesta") or n.begins_with("Mini") or n.begins_with("Desert") or n == "Minigun"
				return ("la " if la else "el ") + n
			return n
		"jan":
			return "%d %s" % [item["n"], "Jan" if int(item["n"]) == 1 else "Janes"]
		"cafe":
			return "tu café"
		"porro":
			return "tu porro"
		"gta":
			return "tu GTA VI"
	return "%d puntos" % item["n"]
