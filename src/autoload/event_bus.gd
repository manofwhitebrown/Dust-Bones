extends Node
## Global signal hub. Contract v1 (frozen): see docs/CONTRACT.md.

# Slab lifecycle
signal slab_started(slab: Dictionary)
signal slab_revealed(result: Dictionary)
signal auto_dig_tick(summary: Dictionary)
# Economy
signal currency_changed(currency: String, amount: float)
signal income_changed(per_second: float)
signal item_purchased(item_id: String, new_count: int)
# Meta
signal specimen_discovered(specimen_id: String)
signal offline_report_ready(report: Dictionary)
signal prestige_available_changed(available: bool)
signal prestige_done(info: Dictionary)
signal site_changed(site: Dictionary)
signal save_completed()
