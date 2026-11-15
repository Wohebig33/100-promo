extends Node
## Buckshot Cheat - in-game cheat menu for Buckshot Roulette (single player).
##
## Loaded by the game itself through override.cfg (see INSTALL.bat).
## F1 or Insert opens / closes the menu.
##
## Features:
##   * Shell X-ray: live / blank count and the exact order, current shell first
##   * Set the next shell (or every shell) to live or blank
##   * Change your health or the dealer's, or keep your health topped up
##   * Rig the item briefcase: pick which item it hands out and how many you grab
##
## Multiplayer is detected and the mod switches itself off there.

const VERSION := "1.0"
const ITEMS := ["handsaw", "magnifying glass", "beer", "cigarettes", "handcuffs",
		"expired medicine", "inverter", "burner phone", "adrenaline"]

const C_LIVE := Color(0.90, 0.25, 0.20)
const C_BLANK := Color(0.30, 0.55, 0.95)
const C_TEXT := Color(0.92, 0.89, 0.80)
const C_DIM := Color(0.60, 0.58, 0.52)
const C_GOLD := Color(0.85, 0.68, 0.20)

# --- game references ---
var rm: Node = null            # the RoundManager node
var _scan_cd := 0.0
var _ui_cd := 0.0
var _flash_t := 0.0
var _in_mp := false

# --- cheat options ---
var keep_health_full := false
var rig_item := ""             # "" means normal random items
var items_per_grab := 0        # 0 means use the game's number
var show_hud := true

# originals, so switching a cheat off puts the game back the way it was
var _orig_active := {}         # itemName -> amount_active
var _orig_grab := {}           # RoundClass resource -> numberOfItemsToGrab
var _added_available := false

# --- UI ---
var layer: CanvasLayer
var panel: PanelContainer
var hud: HBoxContainer
var hud_shells: HBoxContainer
var status_lbl: Label
var shell_count_lbl: Label
var shell_flow: HFlowContainer
var health_lbl: Label
var grab_lbl: Label
var item_opt: OptionButton
var keep_cb: CheckBox
var _last_seq := "?"
var _prev_mouse_mode := -1
var font_size := 14


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var v := Engine.get_version_info()
	print("[BuckshotCheat] v%s loaded (Godot %s). Press F1 in game." % [VERSION, v.get("string", "?")])
	_build_ui()


# ======================================================================
# Finding the game
# ======================================================================
func _process(delta: float) -> void:
	_scan_cd -= delta
	if _scan_cd <= 0.0:
		_scan_cd = 1.0
		_scan()

	if rm != null and not _in_mp:
		_enforce()

	_flash_t -= delta
	_ui_cd -= delta
	if _ui_cd <= 0.0:
		_ui_cd = 0.1
		_refresh_ui()


func _scan() -> void:
	_in_mp = _detect_multiplayer()
	if _in_mp:
		_release()
		return
	if rm != null and is_instance_valid(rm) and rm.is_inside_tree():
		return
	if rm != null:
		_release()
	var found := get_tree().get_first_node_in_group("round_manager")
	if found == null or not _looks_like_round_manager(found):
		found = _find_round_manager(get_tree().root)
	rm = found
	if rm != null:
		print("[BuckshotCheat] found round manager at ", rm.get_path())


func _looks_like_round_manager(n: Node) -> bool:
	return n.get("health_player") != null and n.get("health_opponent") != null \
			and n.get("shellSpawner") != null


func _find_round_manager(n: Node) -> Node:
	if n == self:
		return null
	if _looks_like_round_manager(n):
		return n
	for c in n.get_children():
		var r := _find_round_manager(c)
		if r != null:
			return r
	return null


func _detect_multiplayer() -> bool:
	var cs := get_tree().current_scene
	if cs == null:
		return false
	var s := (cs.scene_file_path + " " + str(cs.name)).to_lower()
	return s.find("multiplayer") != -1 or s.find("lobby") != -1 \
			or s.find("/mp_") != -1 or s.find("/mp/") != -1


func _spawner() -> Object:
	return rm.get("shellSpawner") if rm != null else null


func _health_counter() -> Object:
	return rm.get("healthCounter") if rm != null else null


func _item_manager() -> Object:
	return rm.get("itemManager") if rm != null else null


func _sequence() -> Array:
	var sp := _spawner()
	if sp == null:
		return []
	var seq = sp.get("sequenceArray")
	return seq if seq is Array else []


func _current_round_res() -> Object:
	if rm == null:
		return null
	var ra = rm.get("roundArray")
	var cr = rm.get("currentRound")
	if ra is Array and cr is int and cr >= 0 and cr < ra.size():
		return ra[cr]
	return null


# ======================================================================
# Shells
# ======================================================================
func _set_next(kind: String) -> void:
	var seq := _sequence()
	if seq.is_empty():
		_flash("No shells in the gun right now")
		return
	seq[0] = kind


func _set_all(kind: String) -> void:
	var seq := _sequence()
	if seq.is_empty():
		_flash("No shells in the gun right now")
		return
	for i in seq.size():
		seq[i] = kind


# ======================================================================
# Health
# ======================================================================
func _max_health() -> int:
	var r := _current_round_res()
	var start = r.get("startingHealth") if r != null else null
	return int(start) if start != null else 4


func _display_cap() -> int:
	var hc := _health_counter()
	if hc != null:
		var sym = hc.get("symbolArray_player")
		if sym is Array and sym.size() > 0:
			return sym.size()
	return 6


func _update_health_display() -> void:
	var hc := _health_counter()
	if hc != null and hc.has_method("UpdateDisplay"):
		hc.call("UpdateDisplay")


func _change_health(who: String, delta: int) -> void:
	if rm == null:
		return
	var key := "health_player" if who == "me" else "health_opponent"
	var hp := int(rm.get(key))
	# never set 0 from here: dying has to go through the game's own death sequence
	rm.set(key, clampi(hp + delta, 1, _display_cap()))
	_update_health_display()


func _set_health(who: String, value: int) -> void:
	if rm == null:
		return
	var key := "health_player" if who == "me" else "health_opponent"
	rm.set(key, clampi(value, 1, _display_cap()))
	_update_health_display()


# ======================================================================
# Items
# ======================================================================
func _amount_array() -> Array:
	var im := _item_manager()
	if im == null:
		return []
	var amounts = im.get("amounts")
	if amounts != null:
		var arr = amounts.get("array_amounts")
		if arr is Array:
			return arr
	var alt = im.get("amountArray")
	return alt if alt is Array else []


# ======================================================================
# Cheats that are applied every frame
# ======================================================================
func _enforce() -> void:
	if not is_instance_valid(rm):
		rm = null
		return

	# keep health full
	if keep_health_full:
		var hp := int(rm.get("health_player"))
		var target := mini(_max_health(), _display_cap())
		if hp > 0 and hp < target:
			rm.set("health_player", target)
			_update_health_display()

	# rig the briefcase to one item type
	var arr := _amount_array()
	if rig_item != "":
		for res in arr:
			if res == null:
				continue
			var n := str(res.get("itemName"))
			if not _orig_active.has(n):
				_orig_active[n] = res.get("amount_active")
			res.set("amount_active", 8 if n == rig_item else 0)
		var im := _item_manager()
		var avail = im.get("availableItemArray") if im != null else null
		if avail is Array and not avail.has(rig_item):
			avail.append(rig_item)
			_added_available = true
	elif not _orig_active.is_empty():
		_restore_items()

	# number of items you grab from the briefcase
	var r := _current_round_res()
	if items_per_grab > 0 and r != null and r.get("numberOfItemsToGrab") != null:
		if not _orig_grab.has(r):
			_orig_grab[r] = r.get("numberOfItemsToGrab")
		r.set("numberOfItemsToGrab", items_per_grab)
	elif items_per_grab == 0 and not _orig_grab.is_empty():
		_restore_grab()


func _restore_items() -> void:
	for res in _amount_array():
		if res == null:
			continue
		var n := str(res.get("itemName"))
		if _orig_active.has(n):
			res.set("amount_active", _orig_active[n])
	_orig_active.clear()
	if _added_available:
		var im := _item_manager()
		var avail = im.get("availableItemArray") if im != null else null
		if avail is Array and rig_item != "" and avail.has(rig_item):
			avail.erase(rig_item)
		_added_available = false


func _restore_grab() -> void:
	for r in _orig_grab:
		if is_instance_valid(r):
			r.set("numberOfItemsToGrab", _orig_grab[r])
	_orig_grab.clear()


func _release() -> void:
	if rm != null and is_instance_valid(rm):
		_restore_items()
		_restore_grab()
	_orig_active.clear()
	_orig_grab.clear()
	_added_available = false
	rm = null


# ======================================================================
# UI
# ======================================================================
func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	font_size = clampi(int(vp.y / 38.0), 8, 22)

	layer = CanvasLayer.new()
	layer.layer = 120
	add_child(layer)

	var theme := Theme.new()
	theme.default_font_size = font_size

	# ----- always-on shell HUD (top right) -----
	hud = HBoxContainer.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.theme = theme
	hud.add_theme_constant_override("separation", 4)
	layer.add_child(hud)
	hud_shells = HBoxContainer.new()
	hud_shells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_shells.add_theme_constant_override("separation", 3)
	hud.add_child(hud_shells)

	# ----- menu panel (top left) -----
	panel = PanelContainer.new()
	panel.theme = theme
	panel.position = Vector2(6, 6)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.07, 0.92)
	sb.border_color = Color(0.35, 0.30, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(font_size * 0.6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(font_size * 0.3))
	panel.add_child(box)

	_label(box, "BUCKSHOT CHEAT  (F1 to hide)", C_GOLD)
	status_lbl = _label(box, "", C_DIM)

	_label(box, "SHELLS", C_GOLD)
	shell_count_lbl = _label(box, "", C_TEXT)
	shell_flow = HFlowContainer.new()
	box.add_child(shell_flow)
	var row := _row(box)
	_btn(row, "Next = LIVE", func(): _set_next("live"))
	_btn(row, "Next = BLANK", func(): _set_next("blank"))
	row = _row(box)
	_btn(row, "All LIVE", func(): _set_all("live"))
	_btn(row, "All BLANK", func(): _set_all("blank"))

	_label(box, "HEALTH", C_GOLD)
	health_lbl = _label(box, "", C_TEXT)
	row = _row(box)
	_btn(row, "Me +1", func(): _change_health("me", 1))
	_btn(row, "Me -1", func(): _change_health("me", -1))
	_btn(row, "Me max", func(): _set_health("me", _display_cap()))
	row = _row(box)
	_btn(row, "Dealer -1", func(): _change_health("dealer", -1))
	_btn(row, "Dealer to 1", func(): _set_health("dealer", 1))
	keep_cb = CheckBox.new()
	keep_cb.text = "Keep my health full"
	keep_cb.focus_mode = Control.FOCUS_NONE
	keep_cb.toggled.connect(func(on): keep_health_full = on)
	box.add_child(keep_cb)

	_label(box, "ITEMS (next briefcase)", C_GOLD)
	item_opt = OptionButton.new()
	item_opt.focus_mode = Control.FOCUS_NONE
	item_opt.add_item("Normal random items")
	for it in ITEMS:
		item_opt.add_item("Only: " + str(it))
	item_opt.item_selected.connect(_on_item_selected)
	box.add_child(item_opt)
	row = _row(box)
	_label(row, "Items to grab:", C_TEXT)
	_btn(row, "-", func(): items_per_grab = maxi(items_per_grab - 1, 0))
	grab_lbl = _label(row, "", C_TEXT)
	_btn(row, "+", func(): items_per_grab = mini(items_per_grab + 1, 8))

	var hud_cb := CheckBox.new()
	hud_cb.text = "Show shell HUD when menu is closed"
	hud_cb.button_pressed = true
	hud_cb.focus_mode = Control.FOCUS_NONE
	hud_cb.toggled.connect(func(on): show_hud = on)
	box.add_child(hud_cb)


func _label(parent: Node, text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _row(parent: Node) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", int(font_size * 0.3))
	parent.add_child(r)
	return r


func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _on_item_selected(idx: int) -> void:
	if rig_item != "":
		_restore_items()
	rig_item = "" if idx == 0 else str(ITEMS[idx - 1])


func _flash(msg: String) -> void:
	status_lbl.text = msg
	_flash_t = 2.0


func _shell_chip(parent: Node, kind: String, index: int, compact: bool) -> void:
	var live := kind.to_lower() == "live"
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if compact:
		l.text = "L" if live else "B"
	else:
		l.text = "%d:%s" % [index + 1, "LIVE" if live else "blank"]
	l.add_theme_color_override("font_color", C_LIVE if live else C_BLANK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.75)
	sb.set_content_margin_all(2)
	if index == 0:  # the shell in the chamber gets a gold frame
		sb.border_color = C_GOLD
		sb.set_border_width_all(1)
	l.add_theme_stylebox_override("normal", sb)
	parent.add_child(l)


func _refresh_ui() -> void:
	var seq := _sequence()
	var seq_key := ",".join(PackedStringArray(seq.map(func(s): return str(s))))
	var live_n := 0
	for s in seq:
		if str(s).to_lower() == "live":
			live_n += 1

	if seq_key != _last_seq:
		_last_seq = seq_key
		for c in shell_flow.get_children():
			c.queue_free()
		for c in hud_shells.get_children():
			c.queue_free()
		for i in seq.size():
			_shell_chip(shell_flow, str(seq[i]), i, false)
			_shell_chip(hud_shells, str(seq[i]), i, true)

	var active := rm != null and not _in_mp
	if _flash_t <= 0.0:  # don't overwrite a flashed message
		if _in_mp:
			status_lbl.text = "Multiplayer detected - cheats are off"
		elif rm == null:
			status_lbl.text = "Waiting for a single-player game..."
		else:
			status_lbl.text = "Active"

	if active:
		shell_count_lbl.text = "%d in gun: %d live / %d blank   (1 = in the chamber now)" \
				% [seq.size(), live_n, seq.size() - live_n] if not seq.is_empty() \
				else "Gun is empty"
		health_lbl.text = "Me: %s   Dealer: %s   (round max %d)" \
				% [str(rm.get("health_player")), str(rm.get("health_opponent")), _max_health()]
	else:
		shell_count_lbl.text = "-"
		health_lbl.text = "-"
	grab_lbl.text = "game default" if items_per_grab == 0 else str(items_per_grab)

	hud.visible = active and show_hud and not panel.visible and not seq.is_empty()
	if hud.visible:
		hud.reset_size()
		var vp := get_viewport().get_visible_rect().size
		hud.position = Vector2(vp.x - hud.size.x - 6, 6)


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo \
			and (k.keycode == KEY_F1 or k.keycode == KEY_INSERT):
		panel.visible = not panel.visible
		if panel.visible:
			panel.reset_size()
			_prev_mouse_mode = Input.mouse_mode
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif _prev_mouse_mode != -1:
			Input.mouse_mode = _prev_mouse_mode
			_prev_mouse_mode = -1
		_ui_cd = 0.0
		get_viewport().set_input_as_handled()
