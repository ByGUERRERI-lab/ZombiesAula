extends RefCounted
# Datos de las armas (precio en puntos, cargador, munición de reserva, daño...)
#
# Daño por disparo, de menos a más (un zombie de la oleada 1 tiene 14 de vida):
#   Subfusil 2 (pero dispara muy rápido) · Pistola 3 · Fusil 4,5 (automático)
#   Pistola Rayo 8 + explosión de 14
#   Francotirador 30 y atraviesa a todos los de la fila

const DATA := {
	"pistola": {
		"name": "Pistola", "price": 0, "mag": 12, "reserve": 72, "dmg": 3.0, "pellets": 1,
		"spread": 1.5, "cd": 0.26, "auto": false, "reload": 1.2, "range": 30.0, "pierce": false,
		"tracer": Color(1.0, 0.9, 0.5), "snd": 0.2, "low": false,
	},
	"subfusil": {
		"name": "Subfusil", "price": 1000, "mag": 30, "reserve": 180, "dmg": 2.0, "pellets": 1,
		"spread": 3.0, "cd": 0.08, "auto": true, "reload": 1.7, "range": 28.0, "pierce": false,
		"tracer": Color(1.0, 0.85, 0.4), "snd": 0.15, "low": false,
	},
	"fusil": {
		"name": "Fusil de asalto", "price": 1500, "mag": 30, "reserve": 150, "dmg": 4.5, "pellets": 1,
		"spread": 2.5, "cd": 0.11, "auto": true, "reload": 2.0, "range": 40.0, "pierce": false,
		"tracer": Color(1.0, 0.8, 0.3), "snd": 0.22, "low": true,
	},
	"francotirador": {
		"name": "Francotirador", "price": 2000, "mag": 5, "reserve": 30, "dmg": 30.0, "pellets": 1,
		"spread": 0.0, "cd": 1.0, "auto": false, "reload": 2.5, "range": 80.0, "pierce": true,
		"tracer": Color(1.0, 1.0, 1.0), "snd": 0.5, "low": true,
	},
	# Dispara una bola de energía que explota al chocar (contra un enemigo, la pared
	# o el suelo) y hace daño a todo lo que haya alrededor... menos a ti.
	"pistola_rayo": {
		"name": "Pistola Rayo", "price": 0, "mag": 20, "reserve": 100, "dmg": 8.0, "pellets": 1,
		"spread": 0.5, "cd": 0.3, "auto": false, "reload": 1.5, "range": 35.0, "pierce": false,
		"tracer": Color(0.2, 1.0, 0.4), "snd": 0.25, "low": false,
		"explode": true, "splash_dmg": 14.0, "splash_r": 3.0, "speed": 38.0,
	},
}

# Armas que puede dar la caja misteriosa
const BOX_POOL := ["subfusil", "fusil", "francotirador", "pistola_rayo"]


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
				return ("la " if n.begins_with("Pistola") else "el ") + n
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
