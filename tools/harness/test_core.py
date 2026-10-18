"""Tests RelicReroll.lua's pure Core logic + Jiera flow outside the game (pip install lupa)."""
import sys, pathlib
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "RelicReroll.lua").read_text()
mod = lua.execute(src)
mod.CONFIG.free_mode = False   # tests exercise the real cost curve
Core = mod.Core
fails = 0

def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name)
    fails += 0 if cond else 1

T, L = lua.table_from, (lambda xs: lua.table_from(xs))
rng = lua.eval("(function() local s=1 return function() s=(s*16807)%2147483647 return s/2147483647 end end)()")

# --- costs
costs = [Core.reroll_cost(n) for n in range(13)]
print("  curve:", costs)
check("starts at 10, caps at 100 on the 10th reroll",
      costs[0] == 10 and costs[9] == 100 and costs[10:] == [100, 100, 100])
check("strictly rises until cap", all(a < b for a, b in zip(costs[:10], costs[1:10])))
check("5 ore per lock", Core.lock_cost(0) == 0 and Core.lock_cost(1) == 5 and Core.lock_cost(2) == 10)

# --- reroll rules
pool = L([T({"id": f"p{i}", "weight": 1}) for i in range(10)] +
         [T({"id": "atk1", "weight": 1, "excl_group": "atk"}),
          T({"id": "atk2", "weight": 1, "excl_group": "atk"})])
perks = L(["p0", "p1", "atk1", "p3"])
locks = lua.eval("{[1]=true,[3]=true}")
ok = {"locks": True, "nodup": True, "grp": True, "len": True}
for _ in range(500):
    out = Core.reroll(perks, locks, pool, rng)
    v = [out[i] for i in range(1, 5)]
    ok["locks"] &= v[0] == "p0" and v[2] == "atk1"
    ok["nodup"] &= len(set(v)) == 4
    ok["grp"] &= "atk2" not in v
check("locked perks survive", ok["locks"])
check("no duplicate perks", ok["nodup"])
check("no two tiers of one passive", ok["grp"])
res, err = Core.reroll(perks, lua.eval("{[1]=true,[2]=true,[3]=true}"), pool, rng)
check("3 locks rejected", res is None and "too many" in err)
wpool = L([T({"id": "rare", "weight": 1}), T({"id": "common", "weight": 99})])
hits = sum(1 for _ in range(2000) if Core.reroll(L(["x"]), lua.table(), wpool, rng)[1] == "common")
check(f"weights honored ({hits}/2000)", 1900 < hits < 2000)

# --- holy patch
tables = lua.eval("""{
  sword_a = {spoil_type="Light", spoil_level=5, elements={ {element=1,weight=10,mult=1.1,fx="fire"}, {element=7,weight=5,mult=1.25,fx="holy_fx"} }},
  sword_b = {spoil_type="Light", spoil_level=5, elements={ {element=1,weight=10,mult=1.1,fx="fire"} }},
  sword_c = {spoil_type="Light", spoil_level=4, elements={ }},
  gs_a    = {spoil_type="Long",  spoil_level=5, elements={ }} }""")
plan = Core.plan_holy_patch(tables, 7, 5)
check("holy only to Lv5 sibling missing it", len(plan) == 1 and plan[1].weapon == "sword_b")
e = plan[1].entry
check("holy copies donor mult/FX/weight", e.mult == 1.25 and e.fx == "holy_fx" and e.weight == 5)

# --- bonus model: exactly ONE flag per item
tb = Core.temper_bonus
check("temper: rolled element replaces the whole bonus", tb(0x100, 0x80) == 0x80 and tb(0x8, 0x10) == 0x10 and tb(0x40, 0x20) == 0x20)
check("temper: rolling None removes element, keeps other bonus", tb(0x40, 0) == 0 and tb(0x100, 0) == 0x100 and tb(0x8, 0) == 0x8)
rb = Core.reforge_bonus
locks1 = lua.eval("{[1]=true}")
merged4 = lua.eval("{ 5, 6, 7, 0 }")
check("reforge: element/stat bonus stays with the item", rb(0x80, 0x2, merged4, lua.table()) == 0x80 and rb(0x100, 0x1, merged4, lua.table()) == 0x100)
check("reforge: bound slot keeps its enhancement", rb(0x1, 0x2, merged4, locks1) == 0x1)
check("reforge: rerolled slot takes the roll's enhancement only", rb(0x2, 0x4, merged4, lua.table()) == 0x4 and rb(0x2, 0x80, merged4, lua.table()) == 0)
check("reforge: enhancement never lands on an empty slot", rb(0, 0x8, merged4, lua.table()) == 0)
en = Core.elem_name
check("element names", en(0x80) == "Light" and en(0x10) == "Fire" and en(0) == "None" and en(0x1108) == "None" and en(0x90) == "Fire+Light")

# --- Jiera flow with a mock game
mock = lua.execute("""
local Core = ...
local M = { wallet = { wyrmslife = 0, ore = 0 }, saves = 0, fail_write = false, fail_ore = false }
local item = { uid = "sword#1", perks = { "p0", "p1", "p2" } }
M.item = item
M.slot = Core.slot_state(Core.new_state(), "s1")
M.deps = {
  slot = M.slot, save = function() M.saves = M.saves + 1 end,
  uid = function(it) return it.uid end,
  get_perks = function(it) local c = {} for i, v in ipairs(it.perks) do c[i] = v end return c end,
  set_perks = function(it, p) if M.fail_write then return false, "nope" end it.perks = p return true end,
  roll = function(it, before, locks)
    for _ = 1, 200 do
      local ids, r = {}, {}
      for i = 0, 9 do ids[#ids+1] = "p" .. i end
      for i = #ids, 2, -1 do local j = math.random(i); ids[i], ids[j] = ids[j], ids[i] end
      for i = 1, #before do r[i] = (before[i] ~= 0) and ids[i] or 0 end
      local m = Core.merge_roll(before, r, locks)
      if m then return m end
    end
    return nil, "no roll" end,
  count = function(k) return M.wallet[k] end,
  spend = function(k, n) if k == "ore" and M.fail_ore then return false, "ore gone" end
                          if M.wallet[k] < n then return false, "short" end
                          M.wallet[k] = M.wallet[k] - n return true end,
  give = function(k, n) M.wallet[k] = M.wallet[k] + n return true end,
}
return M
""", Core)
F = Core.Flow.new(mock.deps)
S = Core.S

check("open -> select", F.open(F) and F.state == S.SELECT)
F.choose_item(F, mock.item)
check("choosing item hands it to Jiera (custody saved)", F.state == S.LOCKS and mock.slot.custody == "sword#1")
check("lock slot 1", F.toggle_lock(F, 1))
check("lock slot 2", F.toggle_lock(F, 2))
r, m = F.toggle_lock(F, 3)
check("third lock refused", r is False and "at most 2" in m)
F.toggle_lock(F, 2)  # unlock
check("unlock works", Core.count_keys(F.locks) == 1)
F.toggle_lock(F, 2)
_, q = F.request_reroll(F)
check("quote = 10 Wyrmslife + 10 ore for 2 locks", q.wyrmslife == 10 and q.ore == 10)

r, m = F.confirm(F)
check("blocked without Wyrmslife", r is False and "Wyrmslife" in m)
mock.wallet.wyrmslife = 500
r, m = F.confirm(F)
check("blocked without ore", r is False and "Brinebeast Ore" in m)
check("nothing changed while blocked", list(mock.item.perks.values()) == ["p0", "p1", "p2"] and mock.wallet.wyrmslife == 500)

mock.wallet.ore = 50
mock.fail_ore = True
r, m = F.confirm(F)
check("payment failure reverts perks and refunds crystals",
      r is False and list(mock.item.perks.values()) == ["p0", "p1", "p2"] and mock.wallet.wyrmslife == 500)
mock.fail_ore = False

r, new = F.confirm(F)
nv = list(new.values())
check("roll keeps locked perks, changes unlocked one", r and nv[0] == "p0" and nv[1] == "p1" and nv[2] not in ("p0", "p1"))
check("charged 10 Wyrmslife + 10 ore", mock.wallet.wyrmslife == 490 and mock.wallet.ore == 40)
check("roll is a PREVIEW: item not written yet", list(mock.item.perks.values()) == ["p0", "p1", "p2"])
check("reveal state, still with Jiera", F.state == S.REVEAL and mock.slot.custody == "sword#1")
r2, _ = F.apply_new(F)
check("take_new writes the roll and returns item", r2 and list(mock.item.perks.values()) == nv and F.state == S.IDLE and mock.slot.custody is None)

# keep_old: cost spent, item untouched
F.open(F); F.choose_item(F, mock.item); F.request_reroll(F)
w0 = mock.wallet.wyrmslife
before_perks = list(mock.item.perks.values())
F.confirm(F)
check("2nd roll (same item) costs 13", w0 - mock.wallet.wyrmslife == 13)
F.keep_old(F)
check("keep_old leaves perks, cost stays spent", list(mock.item.perks.values()) == before_perks and mock.wallet.wyrmslife == w0 - 13 and F.state == S.IDLE)

# write failure on take_new refunds
F.open(F); F.choose_item(F, mock.item); F.request_reroll(F)
w1, o1 = mock.wallet.wyrmslife, mock.wallet.ore
F.confirm(F)
mock.fail_write = True
r3, m3 = F.apply_new(F)
mock.fail_write = False
check("failed take_new refunds and keeps old", r3 is False and "refunded" in m3 and mock.wallet.wyrmslife == w1 and mock.wallet.ore == o1
      and list(mock.item.perks.values()) == before_perks and F.state == S.IDLE)

# cost escalation reflects rolls done (2 so far -> 4th-tier price on next)
F.open(F); F.choose_item(F, mock.item); _, q2 = F.request_reroll(F)
check("after 2 kept rolls + 1 refunded, next costs 17", q2.wyrmslife == 17 and q2.ore == 0)
F.back(F); F.cancel(F)
check("backing out returns item, no charge", F.state == S.IDLE and mock.slot.custody is None)

# riven-style continue: roll again from the reveal without re-binding
first = mock.item.perks[1]
F.open(F); F.choose_item(F, mock.item); F.toggle_lock(F, 1); F.request_reroll(F)
F.confirm(F)                                    # 3rd counted roll: 17 wyrmslife + 5 ore
w3, o3 = mock.wallet.wyrmslife, mock.wallet.ore
r, q3 = F.request_again(F)
check("roll-again quote is the next tier (22 + 5 ore)", r is True and q3.wyrmslife == 22 and q3.ore == 5)
r, m = F.roll_again(F)
nv2 = list(F.after.values())
check("roll_again stays in reveal and charges the quote",
      r is True and F.state == S.REVEAL and mock.wallet.wyrmslife == w3 - 22 and mock.wallet.ore == o3 - 5)
check("roll_again keeps the bound perk", nv2[0] == first)
check("item untouched while offers cycle", mock.item.perks[1] == first)
F.keep_old(F)
check("keep after roll-again returns to idle", F.state == S.IDLE and mock.slot.custody is None)

# can't lock every perk
two = lua.eval("{ uid = 'helm#1', perks = { 'p0', 'p1' } }")
F.open(F); F.choose_item(F, two); F.toggle_lock(F, 1)
r, m = F.toggle_lock(F, 2)
check("at least one perk stays unlocked", r is False and "unlocked" in m)
F.cancel(F)

# merge_roll rules
mr = Core.merge_roll
before = lua.eval("{ 'A_L', 'B', 'C', 0 }")
res = mr(before, lua.eval("{ 'X', 'Y', 'Z', 0 }"), lua.eval("{[1]=true}"))
check("merge keeps locked slot, takes rolled others", res is not None and list(res.values()) == ['A_L', 'Y', 'Z', 0])
res, why = mr(before, lua.eval("{ 'X', 'Y', 0, 0 }"), lua.table())
check("perk count is pinned: count-changing rolls rejected", res is None and "count" in why)
loose = lua.eval("{ keep_slot_count = false, max_locks = 2 }")
res2 = mr(before, lua.eval("{ 'X', 'Y', 0, 0 }"), lua.eval("{[3]=true}"), None, loose)
check("(optional loose mode) bound perk survives a dropped slot", res2 is not None and list(res2.values()) == ['X', 'Y', 'C', 0])
res, why = mr(before, lua.eval("{ 'X', 'A_M', 'Z', 0 }"), lua.eval("{[1]=true}"))
check("merge rejects two tiers of one perk", res is None and "tiers" in why)
res, why = mr(before, lua.eval("{ 'X', 'X', 'Z', 0 }"), lua.table())
check("merge rejects duplicates", res is None and "duplicate" in why)
check("filled ignores empty slots", Core.filled(lua.eval("{ 5, 0, 7, 0 }")) == 2)

# equipped items refused
eq = lua.eval("{ uid = 'eq#1', perks = { 'p0', 'p1', 0, 0 }, equipped = true }")
F.open(F); r, m = F.choose_item(F, eq)
check("equipped item refused", r is False and "Unequip" in m)
F.finish(F)

# Wyrmslife boost: pay extra for a chance at a ^/tier-III roll
boost = lua.eval("{ wyrmslife = 500, chance = 0.5 }")
mock.wallet.wyrmslife = 2000
F.open(F); F.choose_item(F, mock.item); F.request_reroll(F)
wb = mock.wallet.wyrmslife
mock.deps.rand = lua.eval("(function() return 0.9 end)")   # coin lost: gamble cost stays spent
r, m = F.confirm(F, boost)
check("boost coin lost: base 28 + 500 extra paid", r is True and wb - mock.wallet.wyrmslife == 528 and F.state == S.REVEAL)
F.keep_old(F)
F.open(F); F.choose_item(F, mock.item); F.request_reroll(F)
wb = mock.wallet.wyrmslife
mock.deps.rand = lua.eval("(function() return 0.1 end)")   # coin won; mock rolls are never 'special'
r, m = F.confirm(F, boost)
check("boost won but unfulfillable: extra refunded", r is True and wb - mock.wallet.wyrmslife == 36
      and "returned" in str(F.boost_note))
F.keep_old(F)
mock.deps.rand = None

# innate perks (Battle Frenzy): auto-bound, free, immovable, cap shared
mock.deps.innate = lua.eval("(function(p) return p == 'bf' end)")
bfi = lua.eval("{ uid = 'satan#1', perks = { 'bf', 'p1', 'p2', 'p3' } }")
F.open(F); F.choose_item(F, bfi)
check("innate perk auto-bound on pickup", F.locks[1] is True and F.innate[1] is True)
check("innate bind costs no ore", F.price(F).ore == 0)
r, m = F.toggle_lock(F, 1)
check("innate bind cannot be removed", r is False and "inherent" in m)
check("one extra player lock allowed", F.toggle_lock(F, 2) is True)
r, m = F.toggle_lock(F, 3)
check("innate + 1 player lock hits the cap", r is False and "at most" in m)
check("ore charged for the player lock only", F.price(F).ore == 5)
F.cancel(F)
alli = lua.eval("{ uid = 'satan#2', perks = { 'bf', 0, 0, 0 } }")
F.open(F); r, m = F.choose_item(F, alli)
check("relic with only inherent perks refused", r is False and "inherent" in m)
F.finish(F)
mock.deps.innate = None

# crash recovery
mock.slot.custody = "sword#1"
check("leftover custody recovered on load", Core.recover(mock.slot) == "sword#1" and mock.slot.custody is None)

print(f"\n{fails} failure(s)")
sys.exit(1 if fails else 0)
