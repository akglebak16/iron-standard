extends RefCounted
## Spatial index of the world step (ADR-025, #242): parties and settlements near a point. The goal evaluator
## (party_goals.gd) and the allies count (world_skirmish.gd) start their loops with a box test; the native kernel
## answers that box over packed columns, and the loops keep every exact check of their own, in list order.
## Columns are taken at the start of the step and the party that has just had its turn is put where it went
## (moved()); the box of parties is still widened by the way a party can go in one step, so the answer holds every
## party the full loop would accept even if something else moved one during the step.
## Without the native kernel, or outside the AI phase of a step, active() is false and the callers loop over their own
## full lists: the reference.
const MOVE_PER_HOUR := 40.0  # above any party speed (22 mounted × 1.3 road × 1.04 bandits ≈ 29.7)

var native: RefCounted = null
var verify := false  # tests: every answer is checked against the full scan
var _parties: Array = []
var _settles: Array = []
var _margin := -1.0  # < 0 outside a world step
var _px := PackedFloat64Array()
var _py := PackedFloat64Array()
var _pn := -1
var _plast: Variant = null
var _pat := {}  # party id -> its row in the columns (a party Dictionary as a key would be hashed by its contents)
var _sx := PackedFloat64Array()
var _sy := PackedFloat64Array()
var _sn := -1
var _slast: Variant = null

## The AI phase of a step begins: columns from the live lists, parties may now move up to `dh` hours of way.
func begin(parties: Array, settles: Array, dh: float) -> void:
	_parties = parties
	_settles = settles
	if native == null:
		return
	_margin = maxf(0.0, dh) * MOVE_PER_HOUR
	_take_parties()
	if _settles.size() != _sn or (_sn > 0 and not is_same(_settles[_sn - 1], _slast)):
		_take_settles()

## The party has had its turn: its row follows it (an arrival puts it on its settlement, further than a step of way).
func moved(p: Dictionary) -> void:
	if not active():
		return
	if _parties.size() != _pn or (_pn > 0 and not is_same(_parties[_pn - 1], _plast)):
		_take_parties()  # a party joined or left the roster during the turn
		return
	var i: int = _pat.get(p.id, -1)
	if i >= 0 and is_same(_parties[i], p):
		_px[i] = p.x
		_py[i] = p.y

## The AI phase is over: later queries (contacts, battles, the interface) get the full lists.
func finish() -> void:
	_margin = -1.0

## Whether queries answer now: the native kernel is there and the AI phase of a step is running.
func active() -> bool:
	return native != null and _margin >= 0.0

## Parties whose box test around (x, y) with half-size `half` may pass, in list order; a superset of them.
func parties_near(x: float, y: float, half: float) -> Array:
	assert(active(), "world index: ask only while active()")
	if _parties.size() != _pn or (_pn > 0 and not is_same(_parties[_pn - 1], _plast)):
		_take_parties()  # a party joined or left the roster during the step
	var out := _pick(_parties, native.box(_px, _py, x, y, half + _margin))
	if verify:
		_check(_parties, out, x, y, half)
	return out

## Settlements whose box test around (x, y) with half-size `half` may pass, in list order.
func settles_near(x: float, y: float, half: float) -> Array:
	assert(active(), "world index: ask only while active()")
	if _settles.size() != _sn or (_sn > 0 and not is_same(_settles[_sn - 1], _slast)):
		_take_settles()
	var out := _pick(_settles, native.box(_sx, _sy, x, y, half))
	if verify:
		_check(_settles, out, x, y, half)
	return out

func _take_parties() -> void:
	_pn = _parties.size()
	_plast = _parties[_pn - 1] if _pn > 0 else null
	_px.resize(_pn)
	_py.resize(_pn)
	_pat = {}
	for i in _pn:
		var q: Dictionary = _parties[i]
		_px[i] = q.x
		_py[i] = q.y
		_pat[q.id] = i

func _take_settles() -> void:
	_sn = _settles.size()
	_slast = _settles[_sn - 1] if _sn > 0 else null
	_sx.resize(_sn)
	_sy.resize(_sn)
	for i in _sn:
		_sx[i] = _settles[i].x
		_sy[i] = _settles[i].y

## Columns [xs, ys] of a list of places that do not move (own settlements of a faction during a step).
static func columns(list: Array) -> Array:
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	xs.resize(list.size())
	ys.resize(list.size())
	for i in list.size():
		xs[i] = list[i].x
		ys[i] = list[i].y
	return [xs, ys]

## Items of `list` (with its columns()) that may lie in the box, in list order.
func list_near(list: Array, cols: Array, x: float, y: float, half: float) -> Array:
	assert(active(), "world index: ask only while active()")
	var out := _pick(list, native.box(cols[0], cols[1], x, y, half))
	if verify:
		_check(list, out, x, y, half)
	return out

static func _pick(list: Array, idx: PackedInt32Array) -> Array:
	var out: Array = []
	out.resize(idx.size())
	for k in idx.size():
		out[k] = list[idx[k]]
	return out

## Every item of the live list inside the box must be in the answer, in the same order.
static func _check(list: Array, out: Array, x: float, y: float, half: float) -> void:
	var want: Array = list.filter(func(o): return absf(o.x - x) <= half and absf(o.y - y) <= half)
	var got: Array = out.filter(func(o): return absf(o.x - x) <= half and absf(o.y - y) <= half)
	assert(want.size() == got.size() and range(want.size()).all(func(i): return is_same(want[i], got[i])), "world index: a box answer lost an item")
