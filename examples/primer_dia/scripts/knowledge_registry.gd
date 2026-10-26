class_name KnowledgeRegistry
extends RefCounted
## Lo que se puede saber en este juego (contrato del framework: Kind, FLAGS, is_valid, kind_of). Un flag que no esté
## acá no existe: DataValidator lo marca. kind: cómo se supo (visto, dicho, documento, objeto, oído, deducción) o estado.

enum Kind { WITNESS, TESTIMONY, DOCUMENT, PHYSICAL, HEARD, TRUST, DEDUCTION, STATE, NEGATIVE }

const FLAGS: Dictionary = {
	"journal_owned": {"kind": Kind.PHYSICAL, "category": "village"},
	"oven_lit": {"kind": Kind.STATE, "category": "village"},
	"tomas_exists": {"kind": Kind.TESTIMONY, "category": "village"},
	"tomas_route": {"kind": Kind.TESTIMONY, "category": "village"},
	"lucia_exists": {"kind": Kind.TESTIMONY, "category": "village"},
	"lucia_lost_cat": {"kind": Kind.TESTIMONY, "category": "village"},
	"lucia_cat_found": {"kind": Kind.DEDUCTION, "category": "village"},
}


static func is_valid(flag: String) -> bool:
	return FLAGS.has(flag)


static func kind_of(flag: String) -> int:
	return FLAGS[flag]["kind"]
