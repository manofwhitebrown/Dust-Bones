class_name Palette
extends RefCounted
## Single source of truth for colors. Warm earthy base + one gold accent for glows.

const SAND: Color = Color("#D8BC91")
const TERRACOTTA: Color = Color("#C0643C")
const BONE: Color = Color("#EADFC8")
const UMBER: Color = Color("#3B2417")
const ACCENT: Color = Color("#F2B84B")
const DEFAULT_ROCK_TINT: Color = Color("#A67C52")

const RARITY_COMMON: Color = Color("#D9CBAE")
const RARITY_UNCOMMON: Color = Color("#B7C48A")
const RARITY_RARE: Color = Color("#7FB2C9")
const RARITY_EPIC: Color = Color("#B58BC9")
const RARITY_LEGENDARY: Color = Color("#F2C14E")


static func rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon":
			return RARITY_UNCOMMON
		"rare":
			return RARITY_RARE
		"epic":
			return RARITY_EPIC
		"legendary":
			return RARITY_LEGENDARY
		_:
			return RARITY_COMMON
