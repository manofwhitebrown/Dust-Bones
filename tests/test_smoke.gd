extends GutTest


func test_num_format_table() -> void:
	var cases: Array = [
		[0.0, "0"], [7.0, "7"], [950.0, "950"], [999.6, "1.00K"], [1240.0, "1.24K"],
		[3.5e6, "3.50M"], [1.2e12, "1.20T"], [1.2e15, "1.20e15"], [-1240.0, "-1.24K"],
		[1e300, "1.00e300"], [NAN, "0"], [INF, "inf"], [2.5, "2.5"], [999999.0, "1.00M"],
	]
	for c: Array in cases:
		assert_eq(NumFormat.fmt(c[0]), c[1], "fmt(%s)" % c[0])


func test_autoloads_and_stub_api() -> void:
	assert_not_null(EventBus)
	assert_not_null(GameState)
	assert_eq(GameState.get_shop_items("brush").size(), 3)
	assert_eq(GameState.get_collection().size(), 12)
	assert_eq(GameState.get_specimen("trilobite")["discovered"], false)


func test_stub_slab_flow_emits_reveal_once() -> void:
	watch_signals(EventBus)
	var slab: Dictionary = GameState.start_new_slab()
	GameState.report_brush_progress(slab["id"], 0.9)
	GameState.report_brush_progress(slab["id"], 1.0)
	assert_signal_emit_count(EventBus, "slab_revealed", 1)
