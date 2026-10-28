# SHARED CONTRACT v1 (FROZEN)

> Both AIs hold an identical copy of this section. Once `docs/CONTRACT.md` exists in the repo, **the repo copy is authoritative**. Do not change this contract unilaterally; file a request in `docs/REQUESTS.md` (see Section "Cross-AI requests").

## Game in one paragraph
**Dust & Bones**: a portrait, touch-first Android idle game made with **Godot 4 / GDScript**. The player brushes dirt off fossil slabs with a finger (variable-reward reveal), earns coins, hires auto-diggers, fills a museum collection, and prestiges by moving to a new dig site. Calm, tactile, obsessive. No ads, no forced IAP, no server.

## Global conventions
- Currencies: `"coins"` (soft), `"fieldwork"` (prestige). All amounts are `float`.
- Rarities (lowercase strings, ascending): `common, uncommon, rare, epic, legendary`.
- IDs: `snake_case` strings. Slab ids: incrementing `int`.
- Autoloads (registered in `project.godot`): `EventBus` -> `res://src/autoload/event_bus.gd`, `GameState` -> `res://src/autoload/game_state.gd`.
- Number display: `NumFormat.fmt(x: float) -> String` (`class_name NumFormat`, static, in `src/core/num_format.gd`, owned by AI-A). Output like `950`, `1.24K`, `3.50M`, `1.20e15`. The UI must use it for every number shown.
- **All balance numbers live in `data/*.json`. No gameplay math in UI code. No UI code in `src/core`.**
- GDScript: static typing everywhere (`var x: float`, typed func signatures), `class_name` on core classes, no magic numbers.
- Target device: low-end Android (2 GB RAM, Compatibility renderer). Portrait only.

## EventBus signals (declared in `src/autoload/event_bus.gd`)
```gdscript
# Slab lifecycle
signal slab_started(slab: Dictionary)
signal slab_revealed(result: Dictionary)
    # {slab_id:int, specimen_id:String, name:String, rarity:String, era:String,
    #  value:float, is_new:bool}
signal auto_dig_tick(summary: Dictionary)   # emitted at most 1x/second, only if count>0
    # {count:int, coins:float, best_find:Dictionary(same keys as slab_revealed result),
    #  new_discoveries:Array[String]}
# Economy
signal currency_changed(currency: String, amount: float)  # throttled <=10/s per currency
signal income_changed(per_second: float)
signal item_purchased(item_id: String, new_count: int)
# Meta
signal specimen_discovered(specimen_id: String)
signal offline_report_ready(report: Dictionary)
    # {seconds:float, coins:float, slabs:int, new_discoveries:Array[String], capped:bool}
signal prestige_available_changed(available: bool)
signal prestige_done(info: Dictionary)      # {site_id:String, fieldwork_gained:float, total_fieldwork:float}
signal site_changed(site: Dictionary)
signal save_completed()
```

## GameState public API (`src/autoload/game_state.gd`)
```gdscript
func get_balance(currency: String) -> float
func get_income_per_sec() -> float
func get_brush_power() -> float              # brush radius multiplier, 1.0 = base
func get_current_site() -> Dictionary        # {id, name, bg_tint:String(hex), rock_tint:String(hex)}
func start_new_slab() -> Dictionary
    # {id:int, specimen_id:String, rarity:String, hardness:float,
    #  reveal_threshold:float, rock_tint:String(hex)}
    # specimen is pre-rolled (pity applied) so the UI can draw it under the dirt.
func report_brush_progress(slab_id: int, fraction: float) -> void
    # UI reports 0..1 cleared. Core emits slab_revealed exactly once when
    # fraction >= reveal_threshold, credits coins, updates collection.
func get_shop_items(category: String) -> Array[Dictionary]   # "brush"|"digger"|"upgrade"
    # item: {id, category, name, desc, icon:String, owned:int, max_owned:int(-1=inf),
    #        cost:float (for qty 1), affordable:bool, locked:bool,
    #        unlock_text:String, effect_text:String}
func get_buy_cost(item_id: String, qty: int) -> float
func buy(item_id: String, qty: int = 1) -> bool              # qty == -1 -> max affordable
func get_collection(site_id: String = "") -> Array[Dictionary]
    # {id, name, era, rarity, site, discovered:bool, value:float, fact:String}
    # name == "???" and fact == "" while undiscovered.
func get_collection_progress() -> Dictionary
    # {discovered:int, total:int, by_era:{era:{discovered:int,total:int}}}
func get_specimen(specimen_id: String) -> Dictionary
func claim_offline_report() -> void          # credits the pending offline earnings
func get_prestige_preview() -> Dictionary
    # {can_prestige:bool, fieldwork_gain:float, bonus_text:String, next_site:Dictionary}
func do_prestige() -> void
func get_stats() -> Dictionary               # {slabs_dug:int, play_seconds:float, total_coins:float}
func save_now() -> void
func reset_all_data() -> void
```
GameState handles Android lifecycle itself (`NOTIFICATION_APPLICATION_PAUSED` / `RESUMED`): saves on pause, computes offline gains on resume and at boot. Specimen art: UI loads `res://assets/sprites/specimens/<specimen_id>.png` if present, otherwise draws a procedural placeholder.

## Data files (owner: AI-A) and schemas
```
data/config.json    {reveal_threshold, offline_cap_hours, offline_efficiency, autosave_seconds,
                     pity:{uncommon:int, rare:int, epic:int, legendary:int},
                     rarity_weights:{common,uncommon,rare,epic,legendary}, cost_growth_default}
data/sites.json     [{id, name, order, unlock_fieldwork, bg_tint, rock_tint, specimen_ids:[...]}]
data/specimens.json [{id, name, era, rarity, site, base_value, weight, fact(<=120 chars, true)}]
data/tools.json     [{id, name, desc, icon, base_cost, cost_growth, brush_power, requires:{item_id?,fieldwork?}}]   # brushes
data/diggers.json   [{id, name, desc, icon, base_cost, cost_growth, slabs_per_sec, requires:{...}}]
data/upgrades.json  [{id, name, desc, icon, base_cost, cost_growth, max_owned, effect_type, effect_value, requires:{...}}]
                    # effect_type in: click_value_mult, digger_speed_mult, rarity_luck, offline_cap_hours_add,
                    #   offline_efficiency_add, value_mult_era(era), fieldwork_gain_mult
data/prestige.json  {formula:"fieldwork = floor(k * (lifetime_coins / base)^exp)", k, base, exp,
                     per_fieldwork_income_mult, min_lifetime_coins}
```

## Ownership map (one owner per file, no exceptions)
| Path | Owner |
|---|---|
| `data/**`, `src/core/**`, `src/autoload/game_state.gd`, `src/autoload/event_bus.gd`, `tests/**`, `tools/simulate.gd`, `addons/gut/**`, `docs/CONTRACT.md`, `docs/ECONOMY.md` | **AI-A** |
| `project.godot`, `export_presets.cfg`, `.github/**`, `.gitignore`, `README.md`, `src/ui/**`, `scenes/**`, `shaders/**`, `assets/**`, `tools/assets_gen/**`, `docs/ASSET_LIST.md`, `docs/TOOLCHAIN.md` | **AI-B** |
| `docs/REQUESTS.md` | both (append-only) |

## Cross-AI requests
Need something from the other side? Append one line to `docs/REQUESTS.md`:
`- [ ] A->B | 2026-MM-DD | one-sentence request | why`  (use `B->A` the other way). The owner ticks it `[x]` with a short note when done. Never edit the other AI's files, even for a typo.

## Git protocol
- Repo: https://github.com/manofwhitebrown/Dust-Bones  (`git clone https://github.com/manofwhitebrown/Dust-Bones && cd Dust-Bones`)
- **Phase 0 exception:** each AI may push its listed Phase 0 files straight to `main`. After that, never push to `main`.
- Branches: AI-A -> `ai-core`, AI-B -> `ai-ui`. Small commits (`feat(core): ...`, `fix(ui): ...`). `git pull --rebase origin main` before every PR. Open PRs into `main`; the **human merges**.
- Never commit secrets, keystores, `.godot/` cache, or build outputs.
