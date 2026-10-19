--[[
  Relic Reroll v1.1.0  —  Dragon's Dogma 2: Dark Arisen  (REFramework script)
  by Pluralmite  ·  source: github.com/Pluralmite/RelicReroll
  Install: <DD2>/reframework/autorun/RelicReroll.lua
           <DD2>/reframework/data/RelicReroll_origins.json   (required data)

  WHAT IT DOES
    Reforge (Jiera): talk to Jiera -> "Reforge Relic". Her appraisal screen
      opens as "Relic ReRoll", listing the unequipped level 5 relics you carry.
      View Details (R3 / V) on a relic opens its perks: confirm toggles a bind
      (up to 2, 5 Brinebeast Ore each; Satanchia's Battle Frenzy is inherent:
      it binds itself, for free, and takes one of the two bind slots). Confirm
      on the relic opens the reforge popup: pick a Wyrmslife boost tier (odds
      of an enhanced (^) or tier III perk) and pay (10 Wyrmslife rising to 100
      per reroll of the same relic). The roll plays on the game's own appraisal
      result screen beside the current perks, riven style: take it, keep the
      old, or roll again. The roll is the game's own appraisal roll for that
      relic's spoil.
    Temper (Hal): talk to Hal -> "Temper Weapon". The same screen opens as
      "Weapon Temper", listing the unequipped weapons you carry with their
      element; confirm one, pick a Morbid Glare tier (1 = the game's own odds,
      2 = even odds of an element, 3 = an element guaranteed), and take or keep
      the rolled element on the result screen. Jiera never touches elements.
    Hal's shop sells Wyrmslife Crystals and Brinebeast Ore (the Lantern Oil /
      Lantern (Fueled) rows are repointed; other vendors still sell those).
    Combine recipes: Malecryst Shard x2 -> Malecryst, Malecryst x2 -> Ore x2,
      Brinebeast Fragment x2 -> Ore, Malecryst + Ore -> Wyrmslife x33.
    Lv5 weapon pools are widened with the game's own Lv5 generic perks (vanilla
      Lv5 weapons roll only their five signature skills), Molten Spirit is
      unlocked on Lv5 body armor, and Lv5 weapon spoils can roll Light (holy).

  STRUCTURE
    CONFIG   — every tunable number (costs, tiers, pools, recipes, shop).
    Core     — pure logic: costs, merge rules, the bonus model, the flow state
               machine. No game calls; tested outside the game (tools/harness).
    Game     — the only code that touches DD2 types; all bindings were verified
               against the running game.
    Menu     — Jiera's and Hal's native talk menus: "Reforge Relic" and
               "Temper Weapon" rows are added inside the game's own display
               call and remapped to native choices (after the architecture of
               Guild Contracts, nexusmods dd2/1341). The talk-row screens remain
               as a fallback.
    Screens  — the Relic ReRoll / Weapon Temper screens are Jiera's own
               appraisal screen (ui042001), opened by the game itself and fed
               inside its own update: the grid, perk list, number popup, result
               reveal and key-guide hints are all the game's widgets.
    Debug UI — REFramework window (Script Generated UI > Relic Reroll).
]]

---------------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------------
local CONFIG = {
    -- Wyrmslife per reroll: starts at cost_base and rises by the same % each
    -- reroll of the SAME item until cost_cap, reached on reroll #cost_rolls_to_cap
    -- (Kuva also caps on the 10th riven roll). Gives 10,13,17,22,28,36,46,60,77,100.
    cost_base         = 10,
    cost_cap          = 100,
    cost_rolls_to_cap = 10,

    max_locks         = 2,
    ore_per_lock      = 5,       -- Brinebeast Ore per locked perk, per reroll

    keep_slot_count   = true,   -- a reforge never adds or removes perk slots
    allow_duplicates  = false,
    respect_spoil_level_pool = true,

    holy_patch_enabled     = true,
    reforge_lv5_only = true,   -- Jiera reforges ONLY level 5 relics (weapons and armor); Hal is unaffected
    -- Pay extra Wyrmslife on the confirm screen for a chance that the roll
    -- carries at least one enhanced (^) or tier-III perk in a rerolled slot.
    -- (Gold itself is tamper-protected save data, but Hal sells Wyrmslife at
    -- 1,000g each — so these tiers equal 10,000 / 25,000 / 50,000 gold.)
    jiera_boost = {
        enabled = true,
        tiers = {
            { wyrmslife = 10, chance = 0.125 },
            { wyrmslife = 25, chance = 0.25 },
            { wyrmslife = 50, chance = 0.5 },
        },
    },
    -- Perk families Jiera must never grant or remove: a perk in these families
    -- is auto-bound (for free, costing no ore) and can never appear in a roll.
    -- AttackAndDamageUp = Battle Frenzy I-IV, guaranteed only on Satanchia's
    -- Lv5 spoils — it stays exactly as the spoil dropped it.
    innate_lock_prefixes = { "AttackAndDamageUp" },
    -- Lv5 weapon spoils roll ONLY their five signature skills in vanilla (all
    -- four slots draw from the ExSkill-only pool). This widens that pool with
    -- the generic perks the game itself allows at Lv5 (Killers, status edges,
    -- utility), at a low weight, so Lv5 rerolls AND appraisals gain variety.
    lv5_weapon_variety = {
        enabled        = true,
        exskill_weight = 10,   -- weight of each signature weapon skill
        generic_weight = 1,    -- weight of each added generic perk
    },
    -- Specific perks unlocked into Lv5 pools (type: 0 weapon, 1 head, 2 body,
    -- 3 legs; slot/enemy pick the pool; ability by AppraisalAbilityID name).
    lv5_pool_unlocks = {
        -- Molten Spirit: Lv1-4 body-armor exclusive in vanilla
        { type = 2, slot = 5, enemy = -1, ability = "NullifyFireAndCold_ThunderDamageUp", rate = 10 },
    },
    -- Combine-menu recipes (added, nothing vanilla is replaced): A + B -> num x out.
    recipes = {
        { a = 615, b = 615, out = 614, num = 1 },  -- 2x Malecryst Shard      -> Malecryst
        { a = 614, b = 614, out = 616, num = 2 },  -- 2x Malecryst            -> 2x Brinebeast Ore
        { a = 617, b = 617, out = 616, num = 1 },  -- 2x Brinebeast Fragment  -> Brinebeast Ore
        -- The combine engine always consumes 1+1, so "3 of each -> 100" is
        -- expressed per craft: 3 crafts = 3 Malecryst + 3 Ore -> 99 crystals.
        { a = 614, b = 616, out = 359, num = 33 },  -- Malecryst + Brinebeast Ore -> 33x Wyrmslife Crystal
    },
    -- Hal's shop sells the reroll resources: Lantern Oil / Lantern (Fueled)
    -- rows are repointed in place (adding rows crashes DD2's shop UI), and the
    -- items' base buy price is set (only this shop sells them). Sell prices
    -- are untouched.
    -- Hal also TEMPERS weapons: reroll the weapon's element bonus (the thing
    -- Jiera never touches) for Morbid Glare. Weapons only.
    hal_temper = {
        enabled    = true,
        menu_label = "Temper Weapon",
        markers    = { "Manufacture", "Tailor equipment" },   -- rows unique to Hal's talk menu
        cost_item  = 715,   -- Morbid Glare
        native        = true,             -- temper on Jiera's appraisal screen (opened from Hal's menu)
        native_option = "Manufacture",    -- Hal's row whose screen request is swapped for it
        native_title  = "Weapon Temper",
        manufacture_gui = 102,            -- app.GuiDefine.GuiType of Hal's Manufacture screen
        appraisal_shop  = 200,            -- the shop id Jiera's own Appraise passes
        tiers = {   -- pay more Morbid Glare for better element odds
            { cost = 1 },                        -- the game's own odds (~1 in 18)
            { cost = 2, element_chance = 0.5 },  -- even odds of an element
            { cost = 3, element_chance = 1.0 },  -- an element, guaranteed
        },
    },
    hal_shop = {
        enabled = true,
        shop_id = 201,
        swaps   = { { from = 85, to = 359, stock = 1000 },     -- Lantern Oil -> Wyrmslife Crystal
                    { from = 86, to = 616, stock = 1000 } },   -- Lantern (Fueled) -> Brinebeast Ore
        prices  = { [359] = 1000, [616] = 1500 },              -- gold apiece: 10 for 10,000 / 10 for 15,000
    },
    holy_patch_spoil_level = 5,

    menu_label        = "Reforge Relic",
    mark_keys         = false,  -- legacy R / R3 marking in storage (replaced by the native picker and Hal's list)
    select_key        = 0x52,   -- keyboard R: marks the relic whose card is on screen
    pad_mark_button   = 0x2000, -- controller R3 (right stick click): same, via.hid.GamePadButton
    overlay           = true,   -- on-screen mark hint/toast (drawn by REFramework, not the game UI)
    free_mode         = false,  -- TESTING ONLY: when true, rerolls, binds, tempers and boosts cost nothing.
    debug_window      = true,    -- REFramework window; turn off once the menu works
    -- Jiera menu stage: "inject" = option shows, picking it closes like Cancel (safe test)
    --                   "full"   = option opens the reforge screens inside her talk
    jiera_markers     = { "Appraise", "Trade Spoils for Rift Crystals" },  -- how her menu is recognised
    -- Show each paid roll on Jiera's own appraisal result screen (reveal
    -- animation + the game's before/after perk window). false = talk-menu rows.
    native_reveal        = true,
    native_reveal_option = "Appraise",   -- her native row that opens the appraisal screen
    native_title         = "Relic ReRoll",  -- the screen's title while it shows a reforge
    -- "Reforge Relic" opens the same screen listing your unequipped Lv5 relics
    -- (in place of spoils); confirming one starts the reforge on it.
    native_pick          = true,
    inspect_key          = 0x56,     -- keyboard V: read the highlighted relic's perk descriptions
    pad_inspect_button   = 0x2000,   -- controller R3: same
    inspect_guide_tag    = "MapMarker", -- the game's own "View Details" action (R3 / V by default): device-correct icon
}

---------------------------------------------------------------------------
-- CORE (pure logic)
---------------------------------------------------------------------------
local Core = {}

-- Wyrmslife cost of an item's next reroll. reroll_count = rerolls already done.
function Core.reroll_cost(reroll_count, cfg)
    cfg = cfg or CONFIG
    if cfg.free_mode then return 0 end
    local n = reroll_count or 0
    local steps = math.max(cfg.cost_rolls_to_cap - 1, 1)
    if n >= steps then return cfg.cost_cap end
    local growth = (cfg.cost_cap / cfg.cost_base) ^ (1 / steps)
    return math.min(cfg.cost_cap, math.floor(cfg.cost_base * growth ^ n + 0.5))
end

function Core.lock_cost(locked_n, cfg)
    cfg = cfg or CONFIG
    if cfg.free_mode then return 0 end
    return (locked_n or 0) * cfg.ore_per_lock
end

local function count_keys(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
Core.count_keys = count_keys

-- app.EquipmentAbilityBonus: slots 0x1-0x8 (enhanced perk), elements 0x10-0x80,
-- stats 0x100-0x1000. The game stores EXACTLY ONE flag per item — combinations
-- resolve as no bonus at all (getElementBonusType returns -1) — so every write
-- must leave a single bit (or zero).
Core.ELEM_MASK = 0xF0
function Core.slot_of_bonus(b)
    b = (b or 0) & 0xF
    for s = 1, 4 do if b == (1 << (s - 1)) then return s end end
end
-- Jiera's reforge: an element/stat bonus belongs to the item and stays; a slot
-- enhancement belongs to the perk — bound keeps it, rerolled takes the roll's
-- slot enhancement (never an element or stat, Jiera doesn't grant those).
function Core.reforge_bonus(before_bonus, rolled_bonus, merged, locks)
    local bb = before_bonus or 0
    if bb ~= 0 and (bb & 0xF) == 0 then return bb end
    local s = Core.slot_of_bonus(bb)
    if s and locks and locks[s] then return bb end
    local nb = (rolled_bonus or 0) & 0xF
    local t = Core.slot_of_bonus(nb)
    if t and (merged[t] or 0) ~= 0 then return nb end
    return 0
end
-- Hal's temper: a rolled element REPLACES the item's whole bonus (one flag
-- only); rolling "None" removes an element but leaves any other bonus alone.
function Core.temper_bonus(before_bonus, rolled_elem)
    local e = (rolled_elem or 0) & Core.ELEM_MASK
    if e ~= 0 then return e end
    return (before_bonus or 0) & ~Core.ELEM_MASK
end
local ELEM_NAMES = { [0x10] = "Fire", [0x20] = "Ice", [0x40] = "Thunder", [0x80] = "Light" }
function Core.elem_name(bonus)
    local b = (bonus or 0) & Core.ELEM_MASK
    if b == 0 then return "None" end
    local out = {}
    for bit, n in pairs(ELEM_NAMES) do if (b & bit) ~= 0 then out[#out + 1] = n end end
    table.sort(out)
    return table.concat(out, "+")
end

local function weighted_pick(pool, rng)
    local total = 0
    for _, p in ipairs(pool) do total = total + (p.weight or 1) end
    if total <= 0 then return nil end
    local r = rng() * total
    for _, p in ipairs(pool) do
        r = r - (p.weight or 1)
        if r < 0 then return p end
    end
    return pool[#pool]
end

--[[ Reroll perks.
     perks  : array of current perk ids (slot order kept)
     locked : set { [slot]=true }
     pool   : { {id=, weight=, excl_group=?}, ... } already filtered to what THIS
              item may roll; excl_group stops two tiers of one passive together. ]]
function Core.reroll(perks, locked, pool, rng, cfg)
    cfg = cfg or CONFIG
    rng = rng or math.random
    locked = locked or {}
    for slot in pairs(locked) do
        if perks[slot] == nil then return nil, "locked slot " .. slot .. " is empty" end
    end
    if count_keys(locked) > cfg.max_locks then return nil, "too many locks (max " .. cfg.max_locks .. ")" end

    local by_id = {}
    for _, p in ipairs(pool) do by_id[p.id] = p end
    local out, used_ids, used_groups = {}, {}, {}
    for slot, id in ipairs(perks) do
        if locked[slot] then
            out[slot] = id
            used_ids[id] = true
            local g = by_id[id] and by_id[id].excl_group
            if g then used_groups[g] = true end
        end
    end
    for slot = 1, #perks do
        if not locked[slot] then
            local cands = {}
            for _, p in ipairs(pool) do
                if (cfg.allow_duplicates or not used_ids[p.id])
                   and not (p.excl_group and used_groups[p.excl_group]) then
                    cands[#cands + 1] = p
                end
            end
            local pick = weighted_pick(cands, rng)
            if not pick then return nil, "perk pool exhausted at slot " .. slot end
            out[slot] = pick.id
            used_ids[pick.id] = true
            if pick.excl_group then used_groups[pick.excl_group] = true end
        end
    end
    return out
end

-- Holy patch planning. tables = { [weapon_id] = {spoil_type=, spoil_level=,
--   elements={ {element=, weight=, mult=, fx=}, ... }} }
function Core.plan_holy_patch(tables, holy_id, level)
    local donor_by_type = {}
    for wid, t in pairs(tables) do
        if t.spoil_level == level then
            for _, e in ipairs(t.elements) do
                if e.element == holy_id and not donor_by_type[t.spoil_type] then
                    donor_by_type[t.spoil_type] = { weapon = wid, entry = e }
                end
            end
        end
    end
    local plan = {}
    for wid, t in pairs(tables) do
        if t.spoil_level == level then
            local has = false
            for _, e in ipairs(t.elements) do if e.element == holy_id then has = true end end
            local d = donor_by_type[t.spoil_type]
            if not has and d then
                plan[#plan + 1] = { weapon = wid, donor = d.weapon, entry = {
                    element = holy_id, weight = d.entry.weight, mult = d.entry.mult, fx = d.entry.fx } }
            end
        end
    end
    table.sort(plan, function(a, b) return tostring(a.weapon) < tostring(b.weapon) end)
    return plan
end

-- Number of filled perk slots (0 = empty slot).
function Core.filled(perks)
    local n = 0
    for _, v in ipairs(perks) do if v and v ~= 0 then n = n + 1 end end
    return n
end

-- Perk family: tiers of one passive share it (BrineKiller_M / BrineKiller_L).
function Core.family(name)
    return (tostring(name):gsub("_[SML]+$", ""):gsub("_LL$", ""))
end

--[[ Merge a fresh game roll with the locked perks.
     before/rolled : 4-slot arrays of perk ids (0 = empty)
     locks         : { [slot]=true }
     name_of(id)   : enum name, used for the family check
   Locked slots keep their old perk; every other slot takes the roll's perk at the
   same index (the game rolls per slot type, so indices carry meaning). Rejects a
   roll with a different perk count, a duplicate perk, or two tiers of one passive. ]]
function Core.merge_roll(before, rolled, locks, name_of, cfg)
    name_of = name_of or tostring
    cfg = cfg or CONFIG
    -- Like riven cycling, a reroll may change how many perks the item has,
    -- unless keep_slot_count pins it. Bound perks always survive either way.
    if cfg.keep_slot_count and Core.filled(rolled) ~= Core.filled(before) then return nil, "perk count differs" end
    local out, seen, fam = {}, {}, {}
    for i = 1, math.max(#before, #rolled) do
        local v = locks[i] and before[i] or (rolled[i] or 0)
        out[i] = v
        if v ~= 0 then
            if seen[v] then return nil, "duplicate perk" end
            local f = Core.family(name_of(v))
            if fam[f] then return nil, "two tiers of one perk" end
            seen[v], fam[f] = true, true
        end
    end
    for i in pairs(locks) do if before[i] == 0 or locks[i] and out[i] ~= before[i] then return nil, "lock lost" end end
    return out
end

-- Save state, per save slot: reroll counts per item + the item Jiera is holding.
function Core.new_state() return { version = 2, saves = {} } end
function Core.slot_state(state, save_id)
    local s = state.saves[save_id]
    if not s then s = { counts = {}, custody = nil }; state.saves[save_id] = s end
    s.counts = s.counts or {}
    return s
end
function Core.rekey(slot, old_uid, new_uid)
    if old_uid == new_uid then return end
    slot.counts[new_uid] = slot.counts[old_uid]
    slot.counts[old_uid] = nil
end

--[[ Jiera flow state machine.
  deps (all supplied by the Game adapter, or by mocks in tests):
    slot            -> Core.slot_state table (persisted)
    save()          -> persist state
    uid(item), get_perks(item), set_perks(item, perks) -> ok, err
    roll(item, before, locks) -> new perks (game roll merged with locks) | nil, err
    count(kind), spend(kind, n) -> ok, err, give(kind, n)   kind = "wyrmslife" | "ore"
  The item never leaves the player's storage: "custody" is a flag in the save
  state, so a crash or quit mid-reforge can't delete gear. Core.recover() clears
  a leftover custody on load. ]]
local S = { IDLE = "idle", SELECT = "select_item", LOCKS = "choose_locks",
            CONFIRM = "confirm", REVEAL = "reveal" }
Core.S = S

local Flow = {}
Flow.__index = Flow
Core.Flow = Flow

function Flow.new(deps, cfg)
    return setmetatable({ d = deps, cfg = cfg or CONFIG, state = S.IDLE, item = nil,
                          locks = {}, quote = nil, before = nil, after = nil }, Flow)
end

local function fail(msg) return false, msg end

function Flow:open()
    if self.state ~= S.IDLE then return fail("busy: " .. self.state) end
    self.state = S.SELECT
    return true
end

function Flow:choose_item(item)
    if self.state ~= S.SELECT then return fail("not selecting") end
    if not item then return fail("no item") end
    if item.equipped then return fail("Unequip it first, then bring it to Jiera.") end
    local perks = self.d.get_perks(item)
    if Core.filled(perks) == 0 then return fail("this item has no perks to reroll") end
    self.item, self.locks, self.before, self.innate = item, {}, perks, {}
    for s, pid in ipairs(perks) do          -- innate perks are bound before the player chooses
        if pid ~= 0 and self.d.innate and self.d.innate(pid) then
            self.locks[s], self.innate[s] = true, true
        end
    end
    if Core.filled(perks) - count_keys(self.locks) < 1 then
        self.item, self.locks, self.before, self.innate = nil, {}, nil, nil
        return fail("every perk on this relic is inherent; nothing can be rerolled")
    end
    self.d.slot.custody = self.d.uid(item)
    self.d.save()
    self.state = S.LOCKS
    return true
end

function Flow:toggle_lock(slot)
    if self.state ~= S.LOCKS then return fail("not choosing locks") end
    if self.before[slot] == nil or self.before[slot] == 0 then return fail("no perk in slot " .. slot) end
    if self.innate and self.innate[slot] then return fail("that perk is inherent to this relic and stays bound") end
    if self.locks[slot] then self.locks[slot] = nil; return true end
    if count_keys(self.locks) >= self.cfg.max_locks then
        return fail("you can lock at most " .. self.cfg.max_locks .. " perks")
    end
    if Core.filled(self.before) - count_keys(self.locks) <= 1 then
        return fail("at least one perk has to stay unlocked")
    end
    self.locks[slot] = true
    return true
end

-- Price for the current item + locks.
function Flow:price()
    local n = self.d.slot.counts[self.d.uid(self.item)] or 0
    local paid_locks = count_keys(self.locks) - count_keys(self.innate)   -- inherent binds are free
    return { wyrmslife = Core.reroll_cost(n, self.cfg),
             ore = Core.lock_cost(paid_locks, self.cfg), rerolls_done = n }
end

function Flow:request_reroll()
    if self.state ~= S.LOCKS then return fail("not choosing locks") end
    self.quote = self:price()
    self.state = S.CONFIRM
    return true, self.quote
end

function Flow:back()   -- confirm -> locks, keeps chosen locks
    if self.state ~= S.CONFIRM then return fail("nothing to go back from") end
    self.state = S.LOCKS
    return true
end

-- Reforge = pay and ROLL into a preview; nothing is written to the item yet.
-- Like a riven cycle: the cost is spent either way, then the player chooses
-- between the new roll (apply_new) and the current perks (keep_old).
-- Shared by confirm and roll_again: pay the quote plus any boost, roll (the
-- boost's odds decide whether a ^/tier-III result is demanded of the roll),
-- and stage the offer. The boost cost is gambled: a lost coin keeps it; only
-- a WON coin that the roller could not honor is refunded.
function Flow:pay_and_roll(q, boost, fail_prefix)
    local d = self.d
    local extra, want = 0, false
    if boost then
        extra = self.cfg.free_mode and 0 or (boost.wyrmslife or 0)
        want = (d.rand or math.random)() < (boost.chance or 0)
    end
    local need = q.wyrmslife + extra
    if d.count("wyrmslife") < need then return fail("Not enough Wyrmslife Crystals (" .. need .. ")") end
    if d.count("ore") < q.ore then return fail("Not enough Brinebeast Ore (" .. q.ore .. ")") end

    local new, err = d.roll(self.item, self.before, self.locks, want)
    if not new then return fail(fail_prefix .. tostring(err)) end

    local paid, perr = d.spend("wyrmslife", need)
    if paid and q.ore > 0 then
        paid, perr = d.spend("ore", q.ore)
        if not paid then d.give("wyrmslife", need) end -- refund crystals
    end
    if not paid then return fail("Payment failed, nothing changed: " .. tostring(perr)) end

    self.boost_note = nil
    if want and not new.special then
        d.give("wyrmslife", extra)      -- won the odds but no such roll exists for this relic
        need = need - extra
        self.boost_note = "No ^ or tier III roll exists here; the boost cost was returned."
    end
    q.wyrmslife = need                   -- what was actually paid (take_new refunds use this)

    local uid = d.uid(self.item)
    d.slot.counts[uid] = (d.slot.counts[uid] or 0) + 1
    d.save()
    self.after = new
    return true, new
end

function Flow:confirm(boost)
    if self.state ~= S.CONFIRM then return fail("nothing to confirm") end
    local ok, new = self:pay_and_roll(self.quote, boost, "Reroll failed: ")
    if not ok then return ok, new end
    self.state = S.REVEAL
    return true, new
end

-- Take the new roll: only now is the item written.
function Flow:apply_new()
    if self.state ~= S.REVEAL then return fail("no roll to apply") end
    local d = self.d
    local old_uid = d.uid(self.item)
    local ok, werr = d.set_perks(self.item, self.after)
    if not ok then
        -- technical failure: the roll cannot land, so give the cost back
        d.give("wyrmslife", self.quote.wyrmslife)
        if self.quote.ore > 0 then d.give("ore", self.quote.ore) end
        d.slot.counts[old_uid] = math.max(0, (d.slot.counts[old_uid] or 1) - 1)
        self:finish()
        return fail("Could not write the new perks (refunded): " .. tostring(werr))
    end
    Core.rekey(d.slot, old_uid, d.uid(self.item))
    d.slot.custody = d.uid(self.item)
    d.save()
    return self:finish()
end

-- Keep the current perks: the cost stays spent, the item is untouched.
function Flow:keep_old()
    if self.state ~= S.REVEAL then return fail("no roll to discard") end
    return self:finish()
end

-- Roll again straight from the reveal: bound perks stay bound, the pending
-- offer is discarded, and the NEXT tier's cost is quoted for confirmation.
function Flow:request_again()
    if self.state ~= S.REVEAL then return fail("no roll to continue") end
    self.quote = self:price()      -- the roll just made already counted, so this is the next tier
    return true, self.quote
end

function Flow:roll_again(boost)
    if self.state ~= S.REVEAL then return fail("no roll to continue") end
    self.quote = self.quote or self:price()
    return self:pay_and_roll(self.quote, boost, "Reroll failed, the previous offer stands: ")
end

-- Reveal screen confirmed (or cancelled before paying): item goes back.
function Flow:finish()
    if self.state == S.IDLE or self.state == S.SELECT then self.state = S.IDLE; return true end
    self.d.slot.custody = nil
    self.d.save()
    local returned = self.item
    self.state, self.item, self.locks, self.innate, self.quote, self.before, self.after =
        S.IDLE, nil, {}, nil, nil, nil, nil
    return true, returned
end
Flow.cancel = Flow.finish   -- backing out at locks/confirm returns the item unchanged

function Core.recover(slot)
    if slot.custody ~= nil then
        local uid = slot.custody
        slot.custody = nil
        return uid
    end
end

-- Outside the game (tests): hand back the pure parts.
if re == nil then return { Core = Core, CONFIG = CONFIG } end

---------------------------------------------------------------------------
-- GAME BINDINGS (verified live in DD2 Dark Arisen, Oct 18 2026)
---------------------------------------------------------------------------
local ID = {
    wyrmslife = 359,        -- "Wyrmslife Crystal" (Material)
    ore       = 616,        -- "Brinebeast Ore"    (Material)
    box       = 65535,      -- storage box owner id in ItemManager.StorageDict
    light     = 128,        -- app.EquipmentAbilityBonus.LightElement
}
local SIG = {
    roll      = "getAppraisalItemResult(System.Int32, app.Character.JobEnum, System.Int32, System.Int32)",
    have      = "getHaveNum(System.Int32, app.CharacterID)",
    delete    = "deleteItem(System.Int32, System.Int32, app.CharacterID)",
    give      = "getItem(System.Int32, System.Int32, app.CharacterID)",
    write     = "updateEquipAbility(app.ItemDefine.StorageData, app.ItemDefine.EquipmentAbilityParam)",
    acquire   = "acquireEquipmentAbility(app.ItemDefine.EquipmentAbilityParam)",
    jobs      = "getJobListForItem(System.Int32)",
}

local function safe(fn, ...) local ok, r = pcall(fn, ...); if ok then return r end; return nil end
local function im()  return sdk.get_managed_singleton("app.ItemManager") end
local function iam() return sdk.get_managed_singleton("app.ItemAppraisalManager") end
local function player_id()
    local cm = sdk.get_managed_singleton("app.CharacterManager")
    local pl = cm and cm["<ManualPlayer>k__BackingField"]
    return pl and safe(function() return pl:call("get_CharaID") end)
end

local function enum_map(tn)
    local m, td = {}, sdk.find_type_definition(tn)
    for _, fd in ipairs(td and td:get_fields() or {}) do
        if fd:is_static() then
            local v = safe(function() return fd:get_data(nil) end)
            if type(v) == "number" and m[v] == nil then m[v] = fd:get_name() end
        end
    end
    return m
end
local ABILITY = enum_map("app.EquipmentAbilityID")
local function perk_enum(id) return ABILITY[id] or tostring(id) end

local function dict_get(d, k) return d and safe(function() return d:call("get_Item", k) end) end
local function list_each(l, fn)
    if not l then return end
    local items, n = l:get_field("_items"), l:get_field("_size") or 0
    for i = 0, n - 1 do fn(items:get_element(i), i) end
end
local function dict_each(d, fn)
    if not d then return end
    local e, n = d:get_field("_entries"), d:get_field("_count") or 0
    for i = 0, n - 1 do
        local x = e:get_element(i)
        local v = x and x:get_field("value")
        if v ~= nil then fn(x:get_field("key"), v) end
    end
end

-- Display names -------------------------------------------------------------
local GB = sdk.find_type_definition("app.GUIBase")
local GET_ITEM_NAME = GB:get_method("getItemName(app.ItemDefine.StorageData, System.Boolean)")
local GET_ITEM_NAME_BY_ID = GB:get_method("getItemName(System.Int32)")
local GET_MSG2
for _, m in ipairs(GB:get_methods()) do
    if m:get_name() == "getMsg" and #m:get_param_types() == 2 then GET_MSG2 = m end
end
local function resolve_refs(s)
    return (tostring(s):gsub("<REF ([%w_]+)>", function(key)
        local r = GET_MSG2 and safe(function() return GET_MSG2:call(nil, key, "") end)
        return (r and r ~= "") and r or key
    end):gsub("<[^>]+>", ""))
end
local function item_name(param)
    return resolve_refs(safe(function() return GET_ITEM_NAME:call(nil, param, false) end) or "?")
end
local function item_name_by_id(id)
    return resolve_refs(safe(function() return GET_ITEM_NAME_BY_ID:call(nil, id) end) or ("item " .. tostring(id)))
end
-- Perk names and descriptions, exactly as the game's UI shows them: the game's
-- own lookup (GuiManager.getEquipmentAbilityNameMsgData and
-- getEquipmentAblityDescriptionMsgData — Capcom's spelling) maps every
-- EquipmentAbilityID to its localized text. Pure data calls, cached per id,
-- correct in every game language with no data files.
local PERK_NAMES, PERK_DESCS = {}, {}
local function gm_text(method, id, flag)
    local gm = sdk.get_managed_singleton("app.GuiManager")
    if not gm then return nil end
    local ok, s = pcall(function()
        local md = (flag == nil) and gm:call(method, id) or gm:call(method, id, flag)
        local t = md and md:call("getMessage")
        return (t and #t > 0) and t or nil
    end)
    if ok then return s end
end
local function perk_name(id)
    if id == 0 then return "(empty)" end
    local n = PERK_NAMES[id]
    if n == nil then
        n = gm_text("getEquipmentAbilityNameMsgData", id) or false
        PERK_NAMES[id] = n
    end
    if n then return n end
    local e = perk_enum(id)  -- fallback: prettified enum name
    e = e:gsub("Job0(%d)_ExSkill(%d)", "Weapon Skill %2"):gsub("_([SML]+)$", " (%1)")
    return (e:gsub("(%l)(%u)", "%1 %2"))
end
local function perk_desc(id)
    if id == 0 then return "" end
    local d = PERK_DESCS[id]
    if d == nil then
        d = gm_text("getEquipmentAblityDescriptionMsgData", id, false) or false
        if d then d = d:gsub("\r", ""):gsub("\n", " ") end
        PERK_DESCS[id] = d
    end
    return d or ""
end

-- Inventory -------------------------------------------------------------------
local Game = {}
Game.perk_name, Game.perk_desc, Game.perk_enum, Game.item_display_name = perk_name, perk_desc, perk_enum, item_name

local function read_slots(param)
    local a = param:get_field("_Ability")
    return { a:get_field("Slot1"), a:get_field("Slot2"), a:get_field("Slot3"), a:get_field("Slot4") },
           a:get_field("IsAppraised"),
           tonumber(a:get_field("Bonus")) or 0
    -- Bonus: ONE app.EquipmentAbilityBonus flag per item — 0x1-0x8 enhanced
    -- perk slot, 0x10-0x80 element, 0x100+ stat. Never combine bits.
end

-- Every appraised relic the player carries or keeps in the storage box.
function Game.list_relic_items(origins)
    local out, pid = {}, player_id()
    local sd = im() and im():get_field("StorageDict")
    if not sd or not pid then return out end
    for _, owner in ipairs({ pid, ID.box }) do
        list_each(dict_get(sd, owner), function(master)
            local p = master:get_field("_Param")
            local slots, appraised = read_slots(p)
            local item_id = p:get_field("_ItemId")
            if appraised and Core.filled(slots) > 0 and (not origins or origins[item_id])
               and Game.reforge_eligible(item_id) then
                out[#out + 1] = {
                    uid = tostring(p:get_field("_StorageId")) .. ":" .. tostring(item_id),
                    storage_id = p:get_field("_StorageId"), item_id = item_id, owner = owner,
                    equipped = p:get_field("_IsEquipped") == true,
                    name = item_name(p) .. (owner == ID.box and " (storage)" or ""),
                    master = master,
                }
            end
        end)
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Weapons Hal can temper: carried (not storage), unequipped, appraised, with
-- spoil origin data (the element roll needs it).
function Game.list_weapons(origins)
    local out, pid = {}, player_id()
    local sd = im() and im():get_field("StorageDict")
    if not sd or not pid then return out end
    list_each(dict_get(sd, pid), function(master)
        local p = master:get_field("_Param")
        local slots, appraised = read_slots(p)
        local item_id = p:get_field("_ItemId")
        if appraised and p:get_field("_IsEquipped") ~= true and Game.is_weapon(item_id)
           and (not origins or origins[item_id]) then
            out[#out + 1] = {
                uid = tostring(p:get_field("_StorageId")) .. ":" .. tostring(item_id),
                storage_id = p:get_field("_StorageId"), item_id = item_id, owner = pid,
                equipped = false, name = item_name(p), master = master,
            }
        end
    end)
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Re-find the live StorageMasterData each time (lists can be rebuilt).
local function find_master(item)
    local found
    local sd = im() and im():get_field("StorageDict")
    list_each(dict_get(sd, item.owner), function(master)
        if found then return end
        local p = master:get_field("_Param")
        if p:get_field("_StorageId") == item.storage_id and p:get_field("_ItemId") == item.item_id then found = master end
    end)
    return found
end

function Game.get_perks(item)
    local m = find_master(item)
    if not m then return {} end
    local slots, _, bonus = read_slots(m:get_field("_Param"))
    slots.bonus = bonus      -- rides along; Core only looks at the array part
    return slots
end

function Game.set_perks(item, perks)
    local m = find_master(item)
    if not m then return false, "item not found" end
    local p = m:get_field("_Param")
    local a = p:get_field("_Ability")
    for i = 1, 4 do a:set_field("Slot" .. i, perks[i] or 0) end
    if perks.bonus ~= nil then a:set_field("Bonus", perks.bonus) end
    local ok, err = pcall(im().call, im(), SIG.write, p, a)
    if not ok then return false, err end
    local check = Game.get_perks(item)
    for i = 1, 4 do if (check[i] or 0) ~= (perks[i] or 0) then return false, "write did not stick" end end
    if perks.bonus ~= nil and (check.bonus or 0) ~= perks.bonus then return false, "bonus write did not stick" end
    pcall(im().call, im(), SIG.acquire, a)   -- registers new perks as discovered, like appraisal does
    return true
end

function Game.item_uid(item) return item and item.uid end

-- Currency: carried first, then the storage box. Pawns are never touched.
local function have(item_id, owner)
    return safe(function() return im():call(SIG.have, item_id, owner) end) or 0
end
function Game.count(kind)
    local id = ID[kind]
    return have(id, player_id()) + have(id, ID.box)
end
function Game.count_item(item_id)
    return have(item_id, player_id()) + have(item_id, ID.box)
end
function Game.spend_item(item_id, n)              -- storage box first, then carried
    if n <= 0 then return true end
    if Game.count_item(item_id) < n then return false, "not enough" end
    local before = Game.count_item(item_id)
    local from_box = math.min(n, have(item_id, ID.box))
    if from_box > 0 then pcall(im().call, im(), SIG.delete, item_id, from_box, ID.box) end
    local rest = n - from_box
    if rest > 0 then pcall(im().call, im(), SIG.delete, item_id, rest, player_id()) end
    if Game.count_item(item_id) ~= before - n then return false, "count mismatch after spending" end
    return true
end
-- Refunds go back to the storage box: costs are taken from the box first, so
-- this is where they came from (and the bag count never "grows" from a refund).
function Game.give_item(item_id, n)
    if n <= 0 then return true end
    return pcall(im().call, im(), SIG.give, item_id, n, ID.box)
end
function Game.spend(kind, n) return Game.spend_item(ID[kind], n) end
function Game.give(kind, n)
    return Game.give_item(ID[kind], n)
end

-- Origins: which spoil + job can produce each relic item -----------------------
-- This is fixed game data, so it ships with the mod as a table
-- (reframework/data/RelicReroll_origins.json, built once from the game's own
-- appraisal rolls). Nothing is scanned at runtime.
local ORIGIN_FILE = "RelicReroll_origins.json"
local Origins = { map = nil, error = nil }
local function load_origins()
    local data = json.load_file(ORIGIN_FILE)
    if type(data) ~= "table" or type(data.map) ~= "table" then
        Origins.error = ORIGIN_FILE .. " is missing from reframework/data"
        return
    end
    local map = {}
    for k, v in pairs(data.map) do map[tonumber(k)] = v end
    Origins.map = map
end
load_origins()
local ANCIENT_ONLY = {}   -- [gear_type][level] = { [perk_id] = true }

local function build_ancient_only()
    local root = iam() and iam():get_field("AppraisalLevelSettingDict")
    dict_each(root, function(gear, levels)
        ANCIENT_ONLY[gear] = {}
        dict_each(levels, function(lv, setting)
            local normal, special = {}, {}
            list_each(setting:get_field("abilityDataList"), function(s)
                local bucket = (s:get_field("enemyType") == -1) and normal or special
                list_each(s:get_field("AbilityDatas"), function(r) bucket[r:get_field("abilityID")] = true end)
            end)
            local only = {}
            for id in pairs(special) do if not normal[id] then only[id] = true end end
            ANCIENT_ONLY[gear][lv] = only
        end)
    end)
end

-- Pick the spoil + job to roll with. Same level as the item's own spoils; an
-- Ancient spoil only if the item already carries an Ancient-only perk.
local function pick_origin(item, before)
    local list = Origins.map and Origins.map[item.item_id]
    if not list or #list == 0 then return nil, "unknown origin" end
    if next(ANCIENT_ONLY) == nil then build_ancient_only() end
    local o0 = list[1]
    local only = (ANCIENT_ONLY[o0.gear] or {})[o0.level] or {}
    local wants_ancient = false
    for _, v in ipairs(before) do if only[v] then wants_ancient = true end end
    local pool = {}
    for _, o in ipairs(list) do
        if ((o.enemy ~= -1) == wants_ancient) then pool[#pool + 1] = o end
    end
    if #pool == 0 then pool = list end
    return pool
end

-- A "special" roll: at least one rerolled (unlocked) slot holds a tier-III/IV
-- perk, or the roll grants a fresh enhanced (^) flag on a rerolled slot.
local T3_CACHE = {}
local function is_t3_perk(pid)
    local v = T3_CACHE[pid]
    if v == nil then
        local n = perk_name(pid)
        v = (n:find(" III$") ~= nil) or (n:find(" IV$") ~= nil)
        T3_CACHE[pid] = v
    end
    return v
end
local function roll_is_special(merged, locks)
    local s = Core.slot_of_bonus(merged.bonus)
    if s and not locks[s] then return true end
    for i = 1, 4 do
        local pid = merged[i] or 0
        if pid ~= 0 and not locks[i] and is_t3_perk(pid) then return true end
    end
    return false
end

-- One draw from the game's own appraisal roll for this relic, merged with the
-- bound perks. Returns a valid merged roll, or nil when this draw can't be
-- used (wrong item from the spoil, duplicate/tier clash, stray innate perk).
local function draw_once(item, before, locks, pool, mgr)
    local o = pool[math.random(#pool)]
    local arr = safe(function() return mgr:call(SIG.roll, o.spoil, o.job, math.random(1, 0x3FFFFFFF), math.random(1, 0x3FFFFFFF)) end)
    local els = arr and safe(function() return arr:get_elements() end)
    for _, info in ipairs(els or {}) do
        if info:get_field("ItemId") == item.item_id then
            local a = info:get_field("Ability")
            local rolled = { a:get_field("Slot1"), a:get_field("Slot2"), a:get_field("Slot3"), a:get_field("Slot4") }
            local merged = Core.merge_roll(before, rolled, locks, perk_enum, CONFIG)
            if merged then
                -- innate families (Battle Frenzy) may only sit in their bound
                -- slot — a roll that grants one anywhere else is discarded
                for s = 1, 4 do
                    local pid = merged[s] or 0
                    if pid ~= 0 and not locks[s] and Game.innate_perk(pid) then return nil end
                end
                merged.bonus = Core.reforge_bonus(before.bonus, tonumber(a:get_field("Bonus")) or 0, merged, locks)
                merged.special = roll_is_special(merged, locks)
                return merged
            end
        end
    end
    return nil
end

function Game.roll(item, before, locks, want_special)
    local pool, err = pick_origin(item, before)
    if not pool then return nil, err end
    local mgr = iam()
    local fallback
    for _ = 1, want_special and 900 or 600 do
        local merged = draw_once(item, before, locks, pool, mgr)
        if merged then
            if not want_special or merged.special then return merged end
            fallback = fallback or merged
        end
    end
    if fallback then return fallback end   -- the boost coin was won but no special roll exists
    return nil, "no matching roll found (try again)"
end

-- How often this relic, with these binds, naturally rolls a ^ / tier III perk:
-- the share of valid draws that are special. 0 means the boost can't help,
-- so the confirm screen hides it. Cached per relic + bind set.
local ODDS = {}
function Game.special_odds(item, before, locks, draws)
    local key = tostring(item.uid) .. ":" .. (locks[1] and 1 or 0) .. (locks[2] and 1 or 0) .. (locks[3] and 1 or 0) .. (locks[4] and 1 or 0)
    if ODDS[key] then return ODDS[key] end
    local pool = pick_origin(item, before)
    if not pool then return 0 end
    local mgr = iam()
    local valid, hits = 0, 0
    for _ = 1, draws or 400 do
        local merged = draw_once(item, before, locks, pool, mgr)
        if merged then
            valid = valid + 1
            if merged.special then hits = hits + 1 end
        end
    end
    local p = valid > 0 and hits / valid or 0
    ODDS[key] = p
    return p
end

-- Tempering (Hal): reroll ONLY the element bonus, weapons only.
function Game.is_weapon(item_id)
    local d = safe(function() return im():call("getItemData(System.Int32)", item_id) end)
    return d ~= nil and d:get_type_definition():get_full_name() == "app.ItemWeaponParam"
end
function Game.innate_perk(pid)
    if pid == 0 then return false end
    local e = perk_enum(pid)
    for _, p in ipairs(CONFIG.innate_lock_prefixes or {}) do
        if e:sub(1, #p) == p then return true end
    end
    return false
end
local ELIG = {}
function Game.reforge_eligible(item_id)
    if not CONFIG.reforge_lv5_only then return true end
    local c = ELIG[item_id]
    if c == nil then
        if not Origins.map then
            return false, "origin data not loaded"   -- don't cache a pre-load verdict
        end
        local lv = 0
        for _, o in ipairs(Origins.map[item_id] or {}) do lv = math.max(lv, o.level or 0) end
        c = (lv >= 5) and { true } or { false, "level 5 relics only" }
        ELIG[item_id] = c
    end
    return c[1], c[2]
end
function Game.get_bonus(item)
    local m = find_master(item)
    if not m then return nil, "item not found" end
    local _, _, bonus = read_slots(m:get_field("_Param"))
    return bonus
end
function Game.roll_element(item, need_element)
    local pool, err = pick_origin(item, Game.get_perks(item))
    if not pool then return nil, err end
    local mgr = iam()
    for _ = 1, need_element and 900 or 200 do
        local o = pool[math.random(#pool)]
        local arr = safe(function() return mgr:call(SIG.roll, o.spoil, o.job, math.random(1, 0x3FFFFFFF), math.random(1, 0x3FFFFFFF)) end)
        local els = arr and safe(function() return arr:get_elements() end)
        for _, info in ipairs(els or {}) do
            if info:get_field("ItemId") == item.item_id then
                local a = info:get_field("Ability")
                local e = (tonumber(a:get_field("Bonus")) or 0) & Core.ELEM_MASK
                if e ~= 0 or not need_element then return e end
            end
        end
    end
    return nil, "no roll found (try again)"
end
function Game.set_element(item, rolled_bonus)
    local m = find_master(item)
    if not m then return false, "item not found" end
    local p = m:get_field("_Param")
    local a = p:get_field("_Ability")
    local nb = Core.temper_bonus(tonumber(a:get_field("Bonus")) or 0, rolled_bonus)
    a:set_field("Bonus", nb)
    local ok, err = pcall(im().call, im(), SIG.write, p, a)
    if not ok then return false, err end
    if (Game.get_bonus(item) or -1) ~= nb then return false, "element write did not stick" end
    return true
end



function Game.origins_ready() return Origins.map ~= nil end
function Game.origins_error() return Origins.error end
function Game.in_game() return player_id() ~= nil and im() ~= nil and iam() ~= nil end

-- Holy patch: add Light to the Lv5 weapon element bonus list ---------------------
local Holy = { status = "waiting", added = 0 }
local function holy_patch()
    if not CONFIG.holy_patch_enabled then Holy.status = "off"; return end
    local mgr = iam(); if not mgr then return end
    local lv = dict_get(dict_get(mgr:get_field("AppraisalLevelSettingDict"), 0), CONFIG.holy_patch_spoil_level)
    if not lv then return end
    list_each(lv:get_field("BonusSettingList"), function(b)
        local el = b:get_field("ElementSettingList")
        if not el or (el:get_field("_size") or 0) == 0 then return end
        local has, rate = false, 0
        list_each(el, function(x)
            if x:get_field("type") == ID.light then has = true end
            rate = math.max(rate, x:get_field("rate") or 0)   -- siblings' rate (10)
        end)
        if has then Holy.status = "Light present at Lv" .. CONFIG.holy_patch_spoil_level; return end
        local entry = sdk.create_instance("app.AppraisalBonusSetting.ElementSettingData")
        if not entry then Holy.status = "could not create entry"; return end
        entry = entry:add_ref()
        entry:set_field("type", ID.light)
        entry:set_field("rate", CONFIG.holy_rate or rate)
        el:call("Add", entry)
        Holy.added = Holy.added + 1
        Holy.status = "Light added at Lv" .. CONFIG.holy_patch_spoil_level .. " (rate " .. tostring(CONFIG.holy_rate or rate) .. ")"
    end)
end
Game.holy = Holy

-- Lv5 weapon variety: widen the Lv5 ExSkill-only slot pool with the Lv5
-- generic pool's perks (same mechanism as the holy patch: edit loaded data).
local Variety = { status = "waiting", aname = nil }
local function variety_patch()
    local c = CONFIG.lv5_weapon_variety
    if not c or not c.enabled then Variety.status = "off"; return end
    local mgr = iam(); if not mgr then return end
    local wd = dict_get(mgr:get_field("AppraisalLevelSettingDict"), 0)
    local ts = wd and dict_get(wd, 5)
    if not ts then return end
    if not Variety.aname then
        Variety.aname, Variety.rname = {}, {}
        local AA = sdk.find_type_definition("app.AppraisalSetting.AppraisalAbilityID")
        for _, f in ipairs(AA:get_fields()) do
            if f:is_static() then
                local ok, v = pcall(function() return f:get_data(nil) end)
                if ok then Variety.aname[v] = f:get_name(); Variety.rname[f:get_name()] = v end
            end
        end
    end
    local list = ts:get_field("abilityDataList")
    local type0, type3
    for i = 0, list:call("get_Count") - 1 do
        local d = list:call("get_Item", i)
        if d:get_field("enemyType") == -1 then
            if d:get_field("type") == 0 then type0 = d end
            if d:get_field("type") == 3 then type3 = d end
        end
    end
    if not (type0 and type3) then Variety.status = "Lv5 pools not found"; return end
    local function is_ex(id) return (Variety.aname[id] or ""):find("^ExSkill") ~= nil end
    local tgt = type3:get_field("AbilityDatas")
    local have = {}
    for i = 0, tgt:call("get_Count") - 1 do
        local e = tgt:call("get_Item", i)
        local id = e:get_field("abilityID")
        have[id] = true
        e:set_field("rate", is_ex(id) and c.exskill_weight or c.generic_weight)
    end
    local src, added = type0:get_field("AbilityDatas"), 0
    for i = 0, src:call("get_Count") - 1 do
        local e = src:call("get_Item", i)
        local id = e:get_field("abilityID")
        if not have[id] and not is_ex(id) then
            local ne = sdk.create_instance("app.SlotAbilitySetting.AbilityRateData")
            if ne then
                ne = ne:add_ref()
                ne:set_field("abilityID", id)
                ne:set_field("rate", c.generic_weight)
                tgt:call("Add", ne)
                have[id] = true
                added = added + 1
            end
        end
    end
    -- explicit single-perk unlocks into chosen Lv5 pools
    local unlocked = 0
    for _, u in ipairs(CONFIG.lv5_pool_unlocks or {}) do
        local aid = Variety.rname[u.ability]
        local wd2 = dict_get(mgr:get_field("AppraisalLevelSettingDict"), u.type)
        local ts2 = wd2 and dict_get(wd2, 5)
        local lst2 = ts2 and ts2:get_field("abilityDataList")
        if aid and lst2 then
            for i = 0, lst2:call("get_Count") - 1 do
                local d = lst2:call("get_Item", i)
                if d:get_field("type") == u.slot and d:get_field("enemyType") == u.enemy then
                    local ab = d:get_field("AbilityDatas")
                    local found = false
                    for j = 0, ab:call("get_Count") - 1 do
                        if ab:call("get_Item", j):get_field("abilityID") == aid then found = true break end
                    end
                    if not found then
                        local ne = sdk.create_instance("app.SlotAbilitySetting.AbilityRateData")
                        if ne then
                            ne = ne:add_ref()
                            ne:set_field("abilityID", aid)
                            ne:set_field("rate", u.rate or 10)
                            ab:call("Add", ne)
                        end
                    end
                    unlocked = unlocked + 1
                    break
                end
            end
        end
    end
    Variety.status = "Lv5 weapon pool widened (" .. tgt:call("get_Count") .. " perks)"
        .. (unlocked > 0 and (" +" .. unlocked .. " unlock(s)") or "")
end
Game.variety = Variety

-- Combine recipes: the game keeps TWO registries — ItemMixParamTable (the
-- crafting rules, official addItemMixParam API) and RecipeListTable (what the
-- combine menu's ingredient grid offers). Both get rebuilt on reload, so this
-- reapplies whenever an entry goes missing. Enum arrays are written raw:
-- elements sit at +0x20, 4 bytes each (never touch the count at +0x1C).
local Mix = { status = "waiting", params = {}, qvc = nil }
local function mix_id_array(ids)
    local arr = sdk.create_managed_array("app.ItemIDEnum", #ids)
    if not arr then return nil end
    arr = arr:add_ref()
    for j, v in ipairs(ids) do
        arr:write_dword(0x20 + 4 * (j - 1), v)
        local e = arr:get_element(j - 1)
        if not e or e:get_field("value__") ~= v then return nil end
    end
    return arr
end
local function arr_has(arr, v)
    for j = 0, (arr and arr:get_size() or 0) - 1 do
        local e = arr:get_element(j)
        if e and e:get_field("value__") == v then return true end
    end
    return false
end
local function mix_patch()
    local rs = CONFIG.recipes
    if not rs or #rs == 0 then Mix.status = "off"; return end
    local mgr = im(); if not mgr then return end
    local tbl = mgr:get_field("RecipeListTable")
    if not tbl or tbl:call("get_Count") == 0 then Mix.status = "recipe tables not loaded yet"; return end
    if not Mix.qvc then   -- borrow a no-op quest condition from any vanilla grid entry
        pcall(function()
            local it = tbl:call("GetEnumerator")
            if it:call("MoveNext") then
                Mix.qvc = it:call("get_Current"):get_field("value")
                    :get_field("_CombineRecipe"):call("get_Item", 0):get_field("_QuestVariableCondition")
            end
        end)
        if not Mix.qvc then return end
    end
    local live = 0
    for i, r in ipairs(rs) do
        -- 1) crafting rule
        local have_rule = false
        local hs = safe(function() return mgr:call("getItemMixParam", r.out) end)
        for j = 0, (hs and hs:get_size() or 0) - 1 do
            if arr_has(hs:get_element(j):call("get_MaterialA"), r.a) then have_rule = true; break end
        end
        if not have_rule then
            local p = Mix.params[i]
            if not p then
                p = sdk.create_instance("app.ItemMixParam")
                if p then
                    p = p:add_ref()
                    p:set_field("_ItemId", r.out); p:set_field("_Num", r.num)
                    p:set_field("_MaterialA", mix_id_array({ r.a }))
                    p:set_field("_MaterialB", mix_id_array({ r.b }))
                    p:set_field("_IsNoSame", false); p:set_field("_IsAutoMix", false)
                    p:set_field("_AutoMixPrio", 0);  p:set_field("_IsRare", false)
                    Mix.params[i] = p
                end
            end
            if p then pcall(function() mgr:call("addItemMixParam", p) end) end
        end
        -- 2) combine-menu grid entries for both ingredients
        for _, pair in ipairs({ { r.a, r.b }, { r.b, r.a } }) do
            local mat, partner = pair[1], pair[2]
            local ok, mp = pcall(function() return tbl:call("get_Item", mat) end)
            local list = ok and mp and mp:get_field("_CombineRecipe")
            local have = false
            for j = 0, (list and list:call("get_Count") or 0) - 1 do
                local cd = list:call("get_Item", j)
                if cd:get_field("_CombineItem") == r.out and arr_has(cd:get_field("_PairList"), partner) then
                    have = true; break
                end
            end
            if not have then
                local cd = sdk.create_instance("app.ItemMixMaterialParam.CombineData")
                if cd then
                    cd = cd:add_ref()
                    cd:set_field("_PairList", mix_id_array({ partner }))
                    cd:set_field("_CombineItem", r.out)
                    cd:set_field("_CombineMakeNum", r.num)
                    cd:set_field("_Rare", false)
                    cd:set_field("_QuestVariableCondition", Mix.qvc)
                    if list then
                        list:call("Add", cd)
                    else
                        local nmp = sdk.create_instance("app.ItemMixMaterialParam")
                        if nmp then
                            nmp = nmp:add_ref()
                            nmp:set_field("_ItemID", mat)
                            local nl = sdk.create_instance("System.Collections.Generic.List`1<app.ItemMixMaterialParam.CombineData>")
                            if nl then
                                nl = nl:add_ref()
                                pcall(function() nl:call(".ctor") end)
                                nl:call("Add", cd)
                                nmp:set_field("_CombineRecipe", nl)
                                pcall(function() tbl:call("Add", mat, nmp) end)
                            end
                        end
                    end
                end
            end
            if mat == r.b and r.a == r.b then break end   -- same-item pair: one entry suffices
        end
        live = live + 1
    end
    Mix.status = live .. " recipe(s) kept registered"
end
Game.mix = Mix

-- Hal's shop: swap the lantern rows for reroll resources, pin their buy price.
local Shop = { status = "waiting" }
local function shop_patch()
    local c = CONFIG.hal_shop
    if not c or not c.enabled then Shop.status = "off"; return end
    local mgr = im(); if not mgr then return end
    for id, price in pairs(c.prices) do
        local d = safe(function() return mgr:call("getItemData(System.Int32)", id) end)
        if d and d:get_field("_BuyPrice") ~= price then d:set_field("_BuyPrice", price) end
    end
    local sp = safe(function() return mgr:call("getItemShopData", c.shop_id) end)
    local buys = sp and sp:get_field("_BuyParams")
    if not buys then Shop.status = "shop " .. c.shop_id .. " not loaded yet"; return end
    local done = 0
    for i = 0, buys:get_size() - 1 do
        local row = buys:get_element(i)
        local iid = row:get_field("_ItemId")
        for _, sw in ipairs(c.swaps) do
            if iid == sw.from then
                row:set_field("_ItemId", sw.to)
                row:set_field("_Stock", sw.stock)
                row:set_field("_AddStockNum", sw.stock)
                row:set_field("_AddStockDays", 1)
                done = done + 1
            elseif iid == sw.to then
                done = done + 1
            end
        end
    end
    Shop.status = done >= #c.swaps and "stocked" or "rows matched: " .. done
end
Game.shop = Shop

---------------------------------------------------------------------------
-- STATE + FLOW
---------------------------------------------------------------------------
local STATE_FILE = "RelicReroll_state.json"
local state = json.load_file(STATE_FILE)
if type(state) ~= "table" or type(state.saves) ~= "table" then state = Core.new_state() end
local function save_state() json.dump_file(STATE_FILE, state) end
local slot = Core.slot_state(state, "default")
if Core.recover(slot) then save_state() end

local flow = Flow.new({
    slot = slot, save = save_state, uid = Game.item_uid,
    get_perks = Game.get_perks, set_perks = Game.set_perks, roll = Game.roll,
    count = Game.count, spend = Game.spend, give = Game.give, innate = Game.innate_perk,
})
RelicReroll = { flow = flow, Game = Game, Core = Core, CONFIG = CONFIG }   -- for the menu layer + debugging (Menu/Native added below)

-- Everything that calls into the game runs here, in the game's own update phase.
-- re.on_frame / re.on_draw_ui run on the render side; calling game menus or
-- changing game data from there crashed DD2 (three times, Oct 18 2026).
local GameThread = { queue = {} }
function GameThread.run(fn) GameThread.queue[#GameThread.queue + 1] = fn end
RelicReroll.GameThread = GameThread
local View = { wyrmslife = 0, ore = 0, items = {}, in_game = false }   -- cached for the debug panel
local next_tick = 0
re.on_pre_application_entry("UpdateBehavior", function()
    local q = GameThread.queue
    if #q > 0 then
        GameThread.queue = {}
        for _, fn in ipairs(q) do
            local ok, err = pcall(fn)
            if not ok then pcall(fs.write, "RelicReroll_error.txt", os.date("%H:%M:%S ") .. tostring(err)) end
        end
    end
    local now = os.clock()
    if now < next_tick then return end
    next_tick = now + 2.0
    View.in_game = Game.in_game()
    if not View.in_game then return end
    pcall(holy_patch)
    pcall(shop_patch)
    pcall(variety_patch)
    pcall(mix_patch)
    if RelicReroll.Menu and RelicReroll.Menu.state then
        local tm = sdk.get_managed_singleton("app.TalkEventManager")
        local info = tm and tm:get_field("<CurrentTalkInfo>k__BackingField")
        if info == nil then                      -- conversation is over; stand down
            RelicReroll.Menu.state = nil
            pcall(function() if flow.state ~= S.IDLE then flow:cancel() end end)
        end
    end
    if CONFIG.debug_window then
        View.wyrmslife, View.ore = Game.count("wyrmslife"), Game.count("ore")
    end
end)

---------------------------------------------------------------------------
-- JIERA MENU — built only from calls proven safe in this save, following the
-- architecture of ArrythmiaFPS's Guild Contracts (nexusmods dd2/1341):
--   * never display anything ourselves: the game re-shows her talk menu on its
--     own after the "Talk" choice, and we only edit the incoming list INSIDE
--     the game's own reqDisp call (that's how "Reforge Relic" already shows)
--   * picks are read in the setFlowId hook and remapped to a NATIVE choice:
--     "Talk" to stay in the loop (the game then redisplays), "Cancel" to leave
--   * all game-data work (rolls, writes, costs) runs in UpdateBehavior
---------------------------------------------------------------------------
local Menu = { state = nil, page = 1, rows = nil, note = nil, pending = nil,
               talk_idx = 2, cancel_idx = 3, ours = nil, template = nil, log = {} }
local Mark = { hover = nil, marked = nil, flash = nil, flash_t = 0 }   -- relic marked via R in storage
RelicReroll.Mark = Mark
local function mlog(s)
    Menu.log[#Menu.log + 1] = os.date("%H:%M:%S ") .. s
    if #Menu.log > 300 then table.remove(Menu.log, 1) end
    pcall(fs.write, "RelicReroll_menu_log.txt", table.concat(Menu.log, "\n"))
end
RelicReroll.Menu = Menu

local function list_msgs(list)
    local out = {}
    list_each(list, function(e) out[#out + 1] = tostring(e:get_field("Msg")) end)
    return out
end
local function has_all(msgs, markers)
    for _, want in ipairs(markers) do
        local hit = false
        for _, m in ipairs(msgs) do if m == want then hit = true; break end end
        if not hit then return false end
    end
    return true
end
local function which_npc(msgs)
    if has_all(msgs, CONFIG.jiera_markers) then return "jiera" end
    local t = CONFIG.hal_temper
    if t and t.enabled and has_all(msgs, t.markers) then return "hal" end
end
local function make_entry(text, template, selectable)
    local li = sdk.create_instance("app.ui021601.ListInfo")
    if not li then return nil end
    li = li:add_ref()
    li:call(".ctor")
    if template then
        for _, f in ipairs({ "IsNotice", "IsElf", "SpeakerType", "ListenerType", "ItemType", "_WaitSec",
                             "BorderLineOffset", "DecideSeId", "IsVisibleBorder" }) do
            pcall(function() li:set_field(f, template:get_field(f)) end)
        end
    end
    li:set_field("Msg", text)
    li:set_field("NeedItemId", -1); li:set_field("Gold", -1); li:set_field("Rim", -1)
    li:set_field("IsEnable", true)
    li:set_field("IsCanSelect", selectable ~= false)
    return li
end

-- Row builders. A row: { text=, act=, item=, slot=, sel=false for labels }.
local function fmt_cost(p)
    if p.wyrmslife == 0 and p.ore == 0 then return "free  (test mode)" end
    if p.ore > 0 then return string.format("%d Wyrmslife, %d Brinebeast Ore", p.wyrmslife, p.ore) end
    return string.format("%d Wyrmslife Crystals", p.wyrmslife)
end
-- " ^" marks the enhanced tier of a perk (the game's little arrow on the icon).
local function slot_enhanced(perks, s)
    return ((((perks and perks.bonus) or 0)) & (1 << (s - 1))) ~= 0
end
local function perk_label(pid, enhanced)
    return Game.perk_name(pid) .. (enhanced and " ^" or "")
end
local PAGE = 4
local build = {}
function build.pick()
    local items = Game.list_relic_items(Origins.map)
    local pages = math.max(1, math.ceil(#items / PAGE))
    Menu.page = math.min(math.max(Menu.page, 1), pages)
    local r = {}
    if #items == 0 then r[#r + 1] = { text = "No relics to reforge.", sel = false } end
    if CONFIG.mark_keys and not Mark.marked then r[#r + 1] = { text = "(Tip: view a relic in storage and press R to bring it here.)", sel = false } end
    for i = (Menu.page - 1) * PAGE + 1, math.min(#items, Menu.page * PAGE) do
        local it = items[i]
        if it.equipped then
            r[#r + 1] = { text = it.name .. "  (unequip first)", sel = false }
        else
            local n = flow.d.slot.counts[it.uid] or 0
            r[#r + 1] = { text = it.name .. (n > 0 and ("   (reforged x" .. n .. ")") or ""), act = "item", item = it }
        end
    end
    if pages > 1 then r[#r + 1] = { text = string.format("Next page  (%d of %d)", Menu.page, pages), act = "next" } end
    r[#r + 1] = { text = "Never mind", act = "leave_to_menu" }
    return r
end
function build.locks()
    local p = flow:price()
    local r = { { text = string.format("Reforge %d:  %s", p.rerolls_done + 1, fmt_cost(p)), sel = false } }
    for s, pid in ipairs(flow.before) do
        if pid ~= 0 then
            if flow.innate and flow.innate[s] then
                r[#r + 1] = { text = "[ Inherent ]  " .. perk_label(pid, slot_enhanced(flow.before, s)), sel = false }
            else
                r[#r + 1] = { text = (flow.locks[s] and "[ Bound ]  " or "Bind:  ") .. perk_label(pid, slot_enhanced(flow.before, s)), act = "lock", slot = s }
            end
        end
    end
    r[#r + 1] = { text = "Reforge now", act = "reforge" }
    r[#r + 1] = { text = "Take it back", act = "to_pick" }
    return r
end
local function boost_rows(r, q, have_w, back_act)
    local jb = CONFIG.jiera_boost
    if not (jb and jb.enabled) then return end
    if Menu.special_p == 0 then
        r[#r + 1] = { text = "(No boost: this relic can't roll a ^ or tier III perk here)", sel = false }
        return
    end
    for i, t in ipairs(jb.tiers or {}) do
        local extra = CONFIG.free_mode and 0 or t.wyrmslife
        local label = string.format("... +%d Wyrmslife:  %d%% for a ^ / tier III perk", extra, math.floor(t.chance * 100 + 0.5))
        if have_w >= q.wyrmslife + extra then
            r[#r + 1] = { text = label, act = back_act, boost = i }
        else
            r[#r + 1] = { text = label .. "   (not enough)", sel = false }
        end
    end
end
local function lack_text(q, have_w, have_o)
    local lack = {}
    if have_w < q.wyrmslife then lack[#lack + 1] = string.format("Wyrmslife %d of %d", have_w, q.wyrmslife) end
    if have_o < q.ore then lack[#lack + 1] = string.format("Brinebeast Ore %d of %d", have_o, q.ore) end
    return "Not enough:  " .. table.concat(lack, ",  ")
end
function build.confirm()
    local q = flow.quote
    local have_w, have_o = Game.count("wyrmslife"), Game.count("ore")
    local enough = have_w >= q.wyrmslife and have_o >= q.ore
    local r = { { text = flow.item.name, sel = false } }
    if enough then
        r[#r + 1] = { text = "Reforge for " .. fmt_cost(q), act = "yes" }
        boost_rows(r, q, have_w, "yes")
    else
        r[#r + 1] = { text = lack_text(q, have_w, have_o), sel = false }
    end
    r[#r + 1] = { text = "Not now", act = "to_locks" }
    return r
end
-- One row per perk (old > new), so the whole screen fits the talk list's
-- visible window: the cursor starts on the first selectable row and label
-- rows above it can scroll out of reach.
function build.reveal()
    local r = {}
    for s, pid in ipairs(flow.before) do
        local newp = flow.after[s] or 0
        local olde, newe = slot_enhanced(flow.before, s), slot_enhanced(flow.after, s)
        if pid ~= 0 or newp ~= 0 then
            if flow.locks[s] then
                r[#r + 1] = { text = perk_label(pid, olde) .. "   [bound]", sel = false }
            elseif newp == pid and newe == olde then
                r[#r + 1] = { text = perk_label(pid, olde) .. "   (unchanged)", sel = false }
            else
                r[#r + 1] = { text = perk_label(pid, olde) .. "  >  " .. perk_label(newp, newe), sel = false }
            end
        end
    end
    -- header only when everything still fits the talk list's visible window
    if #r <= 3 then table.insert(r, 1, { text = flow.item.name .. "  --  current > new:", sel = false }) end
    r[#r + 1] = { text = "Take the new roll", act = "take_new" }
    r[#r + 1] = { text = "Roll again  (" .. fmt_cost(flow:price()) .. ")", act = "again" }
    r[#r + 1] = { text = "Keep the current perks", act = "keep_old" }
    return r
end
-- TEMPER (Hal): reroll the marked weapon's element for Morbid Glare.
local T = { item = nil, cur = 0, rolled = nil, paid = 0 }
local function temper_cost(tier)
    return CONFIG.free_mode and 0 or tier.cost
end
local function glare_text(n)
    if n == 0 then return "free  (test mode)" end
    return n .. " " .. item_name_by_id(CONFIG.hal_temper.cost_item)
end
local TIER_WORDS = { [0.5] = "even odds of an element", [1.0] = "an element, guaranteed" }
local function tier_label(tier)
    local tail = tier.element_chance
        and ("  --  " .. (TIER_WORDS[tier.element_chance] or math.floor(tier.element_chance * 100 + 0.5) .. "% for an element"))
        or ""
    return "Temper for " .. glare_text(temper_cost(tier)) .. tail
end
-- Hal's weapon list: your carried, unequipped weapons, with their element.
function build.t_pick()
    local items = Game.list_weapons(Origins.map)
    local pages = math.max(1, math.ceil(#items / PAGE))
    Menu.page = math.min(math.max(Menu.page, 1), pages)
    local r = {}
    if #items == 0 then r[#r + 1] = { text = "Carry an unequipped weapon to temper it.", sel = false } end
    for i = (Menu.page - 1) * PAGE + 1, math.min(#items, Menu.page * PAGE) do
        local it = items[i]
        r[#r + 1] = { text = it.name .. "   (" .. Core.elem_name(Game.get_bonus(it) or 0) .. ")", act = "t_item", item = it }
    end
    if pages > 1 then r[#r + 1] = { text = string.format("Next page  (%d of %d)", Menu.page, pages), act = "next" } end
    r[#r + 1] = { text = "Never mind", act = "leave_to_menu" }
    return r
end
function build.t_confirm()
    local r = {}
    if not T.item then
        r[#r + 1] = { text = "Choose a weapon first.", sel = false }
        r[#r + 1] = { text = "Never mind", act = "leave_to_menu" }
        return r
    end
    r[#r + 1] = { text = T.item.name .. "  --  element: " .. Core.elem_name(T.cur), sel = false }
    local have = Game.count_item(CONFIG.hal_temper.cost_item)
    for i, tier in ipairs(CONFIG.hal_temper.tiers or {}) do
        if have >= temper_cost(tier) then
            r[#r + 1] = { text = tier_label(tier), act = "t_yes", tier = i }
        else
            r[#r + 1] = { text = tier_label(tier) .. "   (not enough)", sel = false }
        end
    end
    r[#r + 1] = { text = "Never mind", act = "leave_to_menu" }
    return r
end
function build.t_reveal()
    local r = { { text = "Element:  " .. Core.elem_name(T.cur) .. "  >  " .. Core.elem_name(T.rolled), sel = false } }
    if (T.rolled or 0) ~= 0 and (T.cur & ~Core.ELEM_MASK) ~= 0 then
        r[#r + 1] = { text = "(an item holds one bonus: taking this replaces its current one)", sel = false }
    end
    r[#r + 1] = { text = "Take the new element", act = "t_take" }
    r[#r + 1] = { text = "Temper again", act = "t_retier" }
    r[#r + 1] = { text = "Keep the current element", act = "t_keep" }
    return r
end

-- Confirmation between consecutive rolls: next tier's cost, binds untouched.
function build.again()
    local q = flow.quote
    local have_w, have_o = Game.count("wyrmslife"), Game.count("ore")
    local enough = have_w >= q.wyrmslife and have_o >= q.ore
    local r = { { text = string.format("Roll %d  --  the current offer will be lost.", (q.rerolls_done or 0) + 1), sel = false } }
    if enough then
        r[#r + 1] = { text = "Roll again for " .. fmt_cost(q), act = "yes_again" }
        boost_rows(r, q, have_w, "yes_again")
    else
        r[#r + 1] = { text = lack_text(q, have_w, have_o), sel = false }
    end
    r[#r + 1] = { text = "Back to the offer", act = "to_reveal" }
    return r
end

-- While the native reveal is up the talk list is not showing; if it ever
-- redisplays in this state (the appraisal screen did not open), fall back to
-- the talk-row reveal of the same offer.
function build.native() return build.reveal() end

-- NATIVE REVEAL state (the hooks live with the other ui hooks further down).
local GUIDE = { keys = nil, explain = nil }   -- the key-guide HUD's texts (see guide_set)
local guide_find, guide_hide, guide_set                 -- defined with the relic screen below
-- Managed strings handed to the game for keeps (labels, hints) are created
-- once and held for good: the game may keep pointing at them.
local HELD = {}
local function held_str(text)
    local o = HELD[text]
    if not o then o = sdk.create_managed_string(text):add_ref(); HELD[text] = o end
    return o
end
local Native = { route = false, ready = false, abort = false, active = false,
                 close = false, decided = nil, old_vt = nil, saved = nil, t0 = 0 }
local function native_wanted() return CONFIG.native_reveal and Menu.appraise_idx ~= nil end
-- NATIVE PICK state: the same screen as a relic picker.
local Pick = { route = false, active = false, t0 = 0, items = nil, kind = "reforge" }
local function temper_mode() return Pick.kind == "temper" end
local function screen_title()
    return temper_mode() and CONFIG.hal_temper.native_title or CONFIG.native_title
end
RelicReroll.Pick = Pick
RelicReroll.Menu, RelicReroll.Native = Menu, Native

-- Game-data work queued from the pick handler, run in UpdateBehavior.
local function do_action(a)
    local act = a.act
    if act == "open" then
        if not Game.origins_ready() then Menu.note = tostring(Game.origins_error()); Menu.state = nil; return end
        flow:open(); Menu.page = 1; Menu.state = "pick"
    elseif act == "item" then
        local ok, err = flow:choose_item(a.item)
        if ok then Menu.state = "locks" else Menu.note = tostring(err) end
    elseif act == "next" then Menu.page = Menu.page + 1
    elseif act == "lock" then
        local ok, err = flow:toggle_lock(a.slot)
        if not ok then Menu.note = tostring(err) end
    elseif act == "reforge" then
        flow:request_reroll()
        Menu.special_p = Game.special_odds(flow.item, flow.before, flow.locks)
        Menu.state = "confirm"
    elseif act == "to_pick" then
        flow:cancel()
        if CONFIG.native_pick then Menu.state = nil          -- back to her menu
        else flow:open(); Menu.state = "pick" end
    elseif act == "yes" then
        local jb = CONFIG.jiera_boost
        local boost = a.boost and jb and jb.tiers and jb.tiers[a.boost] or nil
        local ok, err = flow:confirm(boost)
        if ok then
            Menu.note = flow.boost_note
            if a.native then Native.ready = true; Menu.state = "native" else Menu.state = "reveal" end
        else
            Native.abort = true
            Menu.note = tostring(err); flow:back(); Menu.state = "locks"
        end
    elseif act == "to_locks" then flow:back(); Menu.state = "locks"
    elseif act == "take_new" then
        local ok, err = flow:apply_new()
        if not ok then Menu.note = tostring(err) end
        Menu.state = nil
    elseif act == "keep_old" or act == "keep_old_quiet" then flow:keep_old(); Menu.state = nil
    elseif act == "again" then
        local ok, err = flow:request_again()
        if ok then
            Menu.special_p = Game.special_odds(flow.item, flow.before, flow.locks)
            Menu.state = "again"
        else Menu.note = tostring(err); Menu.state = "reveal" end
    elseif act == "yes_again" then
        local jb = CONFIG.jiera_boost
        local boost = a.boost and jb and jb.tiers and jb.tiers[a.boost] or nil
        local ok, err = flow:roll_again(boost)
        if ok then
            Menu.note = flow.boost_note
            if a.native then Native.ready = true; Menu.state = "native"; return end
        else
            Native.abort = true
            Menu.note = tostring(err)
        end
        Menu.state = "reveal"
    -- the Relic ReRoll screen: pay + roll from the boost popup
    elseif act == "s_roll" then
        local jb = CONFIG.jiera_boost
        local boost = a.boost and jb and jb.tiers and jb.tiers[a.boost] or nil
        flow:request_reroll()
        local ok, err = flow:confirm(boost)
        if ok then
            Pick.boost = a.boost
            Pick.active = false
            Native.route, Native.ready, Native.abort, Native.decided, Native.close = true, true, false, nil, false
            Native.t0 = os.clock()
        else
            flow:back()
            Pick.msg, Pick.msg_t = tostring(err), os.clock()
        end
    elseif act == "s_again" then
        local jb = CONFIG.jiera_boost
        local boost = Pick.boost and jb and jb.tiers and jb.tiers[Pick.boost] or nil
        local ok, err = flow:request_again()
        if ok then ok, err = flow:roll_again(boost) end
        if ok then
            Pick.after = "again"
            Native.route, Native.ready, Native.abort, Native.t0 = true, true, false, os.clock()
        else
            flow:keep_old()
            Pick.msg, Pick.msg_t = tostring(err), os.clock()
            Pick.after = "grid"
        end
    -- decisions made on the native result screen
    elseif act == "n_take" then
        local ok, err = flow:apply_new()
        if not ok then Menu.note = tostring(err); Pick.msg, Pick.msg_t = tostring(err), os.clock() end
        mlog("native reveal: took the new roll")
        Menu.state = nil
        Pick.after = "grid"
    elseif act == "n_keep" then
        flow:keep_old()
        mlog("native reveal: kept the current perks")
        Menu.state = nil
        Pick.after = "grid"
    elseif act == "n_again" then
        local ok, err = flow:request_again()
        if ok then
            Menu.special_p = Game.special_odds(flow.item, flow.before, flow.locks)
            Menu.state = "again"
        else Menu.note = tostring(err); flow:keep_old(); Menu.state = nil end
    elseif act == "to_reveal" then Menu.state = "reveal"
    elseif act == "t_open" then
        if not Game.origins_ready() then Menu.note = tostring(Game.origins_error()); Menu.state = nil; return end
        T.item, T.rolled = nil, nil
        local m = CONFIG.mark_keys and Mark.marked
        if m and Game.is_weapon(m.item_id) then
            T.item = m
            T.cur = Game.get_bonus(m) or 0
            Menu.state = "t_confirm"
        else
            Menu.page = 1
            Menu.state = "t_pick"
        end
    elseif act == "t_item" then
        T.item, T.rolled = a.item, nil
        T.cur = Game.get_bonus(a.item) or 0
        Menu.state = "t_confirm"
    elseif act == "t_yes" then
        local c = CONFIG.hal_temper
        local tier = (c.tiers or {})[a.tier or 1] or { cost = 1 }
        local price = temper_cost(tier)
        local ok, err = Game.spend_item(c.cost_item, price)
        if not ok then Menu.note = tostring(err); return end
        local rolled, rerr
        if tier.element_chance and math.random() >= tier.element_chance then
            rolled = 0                                         -- the bought odds came up empty
        else
            rolled, rerr = Game.roll_element(T.item, tier.element_chance ~= nil)
        end
        if rolled == nil then
            Game.give_item(c.cost_item, price)
            Menu.note = tostring(rerr) .. " (refunded)"
            return
        end
        T.rolled, T.paid = rolled, price
        mlog(string.format("temper %s (%d glare): %s -> %s", T.item.name, price, Core.elem_name(T.cur), Core.elem_name(rolled)))
        Menu.state = "t_reveal"
    elseif act == "t_retier" then Menu.state = "t_confirm"
    elseif act == "t_take" then
        local ok, err = Game.set_element(T.item, T.rolled)
        if not ok then
            Game.give_item(CONFIG.hal_temper.cost_item, T.paid or 0)
            Menu.note = tostring(err) .. " (refunded)"
            Pick.msg, Pick.msg_t = tostring(err) .. " (refunded)", os.clock()
        else
            mlog("temper: took " .. Core.elem_name(Core.temper_bonus(T.cur, T.rolled)) .. " on " .. T.item.name)
        end
        T.rolled = nil
        Menu.state = nil
        if Pick.studio then Pick.after = "grid" end
    elseif act == "t_keep" then
        T.rolled = nil
        Menu.state = nil
        if Pick.studio then Pick.after = "grid" end
    -- the Weapon Temper screen: pay + roll from the tier popup
    elseif act == "ts_roll" or act == "ts_again" then
        local tier_i = (act == "ts_again") and (T.tier or 1) or (a.tier or 1)
        local c = CONFIG.hal_temper
        local tier = (c.tiers or {})[tier_i] or { cost = 1 }
        local price = temper_cost(tier)
        local ok, err = Game.spend_item(c.cost_item, price)
        local rolled, rerr
        if ok then
            if tier.element_chance and math.random() >= tier.element_chance then
                rolled = 0
            else
                rolled, rerr = Game.roll_element(T.item, tier.element_chance ~= nil)
            end
            if rolled == nil then Game.give_item(c.cost_item, price); err = tostring(rerr) .. " (refunded)" end
        else
            err = "Not enough " .. item_name_by_id(c.cost_item)
        end
        if rolled ~= nil then
            T.rolled, T.paid, T.tier = rolled, price, tier_i
            mlog(string.format("temper %s (tier %d, %d glare): %s -> %s", T.item.name, tier_i, price, Core.elem_name(T.cur), Core.elem_name(rolled)))
            Pick.active = false
            if act == "ts_again" then
                Pick.after = "again"                      -- the screen is still clearing the last result
                Native.route, Native.ready, Native.abort = true, true, false
            else
                Native.route, Native.ready, Native.abort, Native.decided, Native.close = true, true, false, nil, false
            end
            Native.t0 = os.clock()
        else
            T.rolled = nil
            Pick.msg, Pick.msg_t = tostring(err), os.clock()
            if act == "ts_again" then Pick.after = "grid" end
        end
    elseif act == "grabbed" then
        local elig, why = Game.reforge_eligible(a.item.item_id)
        if not elig then
            Menu.note = "Jiera reforges " .. (why or "other relics") .. "."
            if CONFIG.native_pick then Menu.state = nil else flow:open(); Menu.page = 1; Menu.state = "pick" end
            return
        end
        flow:open()
        local ok, err = flow:choose_item(a.item)
        if ok then Menu.state = "locks"
        else
            Menu.note = tostring(err)
            if CONFIG.native_pick then flow:cancel(); Menu.state = nil else Menu.page = 1; Menu.state = "pick" end
        end
    elseif act == "leave_to_menu" then
        if flow.state ~= S.IDLE then flow:cancel() end
        Menu.state = nil
    end
end

re.on_pre_application_entry("UpdateBehavior", function()
    local a = Menu.pending
    if not a then return end
    Menu.pending = nil
    local ok, err = pcall(do_action, a)
    if not ok then
        mlog("action error: " .. tostring(err))
        pcall(function() if flow.state ~= S.IDLE then flow:cancel() end end)
        Menu.state = nil
    end
end)

local TS_TD = sdk.find_type_definition("app.ui021601")
local REQDISP = TS_TD:get_method("reqDisp(System.Collections.Generic.List`1<app.ui021601.ListInfo>, System.Boolean, via.gui.GenderType, via.gui.GenderType, System.Boolean, System.Boolean, System.Int32)")
local SETFLOW = TS_TD:get_method("setFlowId(app.ui021601.FlowId)")

-- Inside the game's own display call: add our option, or swap in our screen.
sdk.hook(REQDISP, function(args)
    local ok, err = pcall(function()
        Menu.ours = nil
        local list = sdk.to_managed_object(args[3])
        if not list then return end
        local msgs = list_msgs(list)
        local npc = which_npc(msgs)
        if not npc then
            if Menu.state then     -- some other conversation: stand down
                Menu.state = nil
                Menu.pending = { act = "leave_to_menu" }
            end
            return
        end
        Menu.npc = npc
        Menu.template = list:get_field("_items"):get_element(0):add_ref()
        Menu.talk_idx, Menu.cancel_idx = #msgs - 2, #msgs - 1
        Menu.appraise_idx, Menu.manufacture_idx = nil, nil
        for i, m in ipairs(msgs) do
            if m == "Talk" then Menu.talk_idx = i - 1 end
            if m == "Cancel" then Menu.cancel_idx = i - 1 end
            if npc == "jiera" and m == CONFIG.native_reveal_option then Menu.appraise_idx = i - 1 end
            if npc == "hal" and m == CONFIG.hal_temper.native_option then Menu.manufacture_idx = i - 1 end
        end
        -- Her talk list is back: the appraisal screen is not up (anymore).
        if Native.route or Native.active then
            mlog(string.format("native reveal: talk list came back (route=%s active=%s)", tostring(Native.route), tostring(Native.active)))
            if Native.active and not Native.decided then Menu.pending = { act = temper_mode() and "t_keep" or "n_keep" } end   -- riven rule
            Native.route, Native.active, Native.close = false, false, false
        end
        if Menu.state == "native" then Menu.state = "reveal" end   -- screen never opened: talk-row reveal
        if Pick.studio or Pick.active or Pick.route then
            pcall(guide_hide, false)
            mlog("screen: talk list came back -> screen closed")
            Pick.route, Pick.active, Pick.items, Pick.studio, Pick.mode = false, false, nil, false, nil
            Pick.swap_t, GUIDE.reveal = nil, false
            if flow.state == S.SELECT or flow.state == S.LOCKS or flow.state == S.CONFIRM then flow:cancel() end
            Menu.state = nil
        end
        if Menu.state == nil then
            local base = (npc == "hal") and CONFIG.hal_temper.menu_label or CONFIG.menu_label
            local show_mark = CONFIG.mark_keys and Mark.marked and ((npc == "jiera" and not CONFIG.native_pick and Game.reforge_eligible(Mark.marked.item_id))
                                               or (npc == "hal" and Game.is_weapon(Mark.marked.item_id)))
            local label = base .. (show_mark and (":  " .. Mark.marked.name) or "")
            for i, m in ipairs(msgs) do
                if m:sub(1, #base) == base then
                    Menu.ours = i - 1
                    if m ~= label then   -- marked relic changed: retitle our existing row
                        pcall(function() list:get_field("_items"):get_element(i - 1):set_field("Msg", label) end)
                    end
                    return
                end
            end
            local entry = make_entry(label, Menu.template)
            if not entry then mlog("could not create entry"); return end
            list:call("Insert", Menu.cancel_idx, entry)
            Menu.ours = Menu.cancel_idx
            Menu.cancel_idx = Menu.cancel_idx + 1
        else
            local okb, rows = pcall(build[Menu.state])
            if not okb or not rows then mlog("build failed: " .. tostring(rows)); Menu.state = nil; return end
            if Menu.note then table.insert(rows, 1, { text = Menu.note, sel = false }); Menu.note = nil end
            list:call("Clear")
            for _, row in ipairs(rows) do
                list:call("Add", make_entry(row.text, Menu.template, row.sel ~= false))
            end
            Menu.rows = rows
            mlog("screen " .. Menu.state .. " (" .. #rows .. " rows)")
        end
    end)
    if not ok then mlog("reqDisp hook error: " .. tostring(err)) end
end, function(r) return r end)

---------------------------------------------------------------------------
-- MARKING: pick the relic in the game's own storage / inventory UI, with all
-- of its filtering. Whenever an appraised item's card renders, the game asks
-- GuiManager.getAppraisalBonusTypeUV for its perk icons — a pure data call —
-- so the pre-hook sees exactly which relic is on screen. Pressing the select
-- key while the card is up marks that relic; Jiera's "Reforge Relic" then
-- starts straight on it (with no mark, her menu lists relics as before).
---------------------------------------------------------------------------
local UVM = sdk.find_type_definition("app.GuiManager"):get_method("getAppraisalBonusTypeUV(app.ItemDefine.StorageData)")
if UVM then
    sdk.hook(UVM, function(args)
        pcall(function()
            local p = sdk.to_valuetype(args[3], "app.ItemDefine.StorageData")
            local a = p and p:get_field("_Ability")
            if not CONFIG.mark_keys then return end
            if not a or not a:get_field("IsAppraised") then return end
            -- The compare panel draws the EQUIPPED item's card alongside whatever
            -- is being viewed; equipped gear can't be reforged, so never let it
            -- become the mark candidate (it would shadow the viewed relic).
            if p:get_field("_IsEquipped") == true then return end
            local has = false
            for i = 1, 4 do if a:get_field("Slot" .. i) ~= 0 then has = true end end
            if not has then return end
            local item = { storage_id = p:get_field("_StorageId"), item_id = p:get_field("_ItemId"),
                           owner = p:get_field("_CharaId"), equipped = p:get_field("_IsEquipped") == true,
                           name = Game.item_display_name(p) }
            -- a reveal's result card (and any not-yet-owned appraisal result) has no
            -- storage slot yet: it is not a relic you can mark
            if (item.storage_id or 0) == 0 or Native.active or Pick.active then return end
            -- with Jiera's relic picker, marking only serves Hal (weapons)
            if CONFIG.native_pick and not Game.is_weapon(item.item_id) then return end
            item.uid = tostring(item.storage_id) .. ":" .. tostring(item.item_id)
            Mark.hover = { t = os.clock(), item = item }
        end)
    end, function(r) return r end)
else
    mlog("WARNING: getAppraisalBonusTypeUV not found; marking disabled")
end

local PAD_T = sdk.find_type_definition("via.hid.GamePad")
local function pad_buttons()
    local ok, b = pcall(function()
        local pad = sdk.get_native_singleton("via.hid.GamePad")
        local dev = pad and sdk.call_native_func(pad, PAD_T, "get_MergedDevice")
        return dev and dev:call("get_Button") or 0
    end)
    return ok and b or 0
end
local key_was_down, pad_was_down = false, false
re.on_pre_application_entry("UpdateBehavior", function()
    local okk, kdown = pcall(function() return reframework:is_key_down(CONFIG.select_key) end)
    kdown = (okk and kdown) or false
    local pdown = (pad_buttons() & CONFIG.pad_mark_button) ~= 0
    local edge = (kdown and not key_was_down) or (pdown and not pad_was_down)
    if not CONFIG.mark_keys then key_was_down, pad_was_down = kdown, pdown; return end
    key_was_down, pad_was_down = kdown, pdown
    if not edge then return end
    local h = Mark.hover
    if not h or os.clock() - h.t > 1.5 then return end
    if not Game.origins_ready() or not Origins.map[h.item.item_id] then
        Mark.flash, Mark.flash_t = h.item.name .. " can't be reforged", os.clock()
        mlog("mark refused (no origin data): " .. h.item.name .. " [" .. h.item.uid .. "]")
        return
    end
    Mark.marked = h.item
    Mark.flash, Mark.flash_t = (CONFIG.native_pick and "Marked for tempering: " or "Marked for reforging: ") .. h.item.name, os.clock()
    mlog("marked: " .. h.item.name .. " [" .. h.item.uid .. "]")
end)

-- On-screen hint and toast, drawn by REFramework's own overlay (render side,
-- reads mod state only — never touches the game). Visible without opening the
-- REFramework menu, works the same on keyboard and controller.
re.on_frame(function()
    if not CONFIG.overlay or not CONFIG.mark_keys then return end
    local now = os.clock()
    local h = Mark.hover
    local hov = (h and now - h.t < 0.6) and h.item or nil
    local flash = (Mark.flash and now - Mark.flash_t < 3.5) and Mark.flash or nil
    if not hov and not flash then return end
    local okd, ds = pcall(imgui.get_display_size)
    local w = (okd and ds and ds.x) or 1920
    local x, y = w * 0.355, 24
    if flash then draw.text(flash, x, y, 0xFF7BE0FF); y = y + 22 end
    if hov then
        if Mark.marked and Mark.marked.uid == hov.uid then
            if not flash then draw.text(CONFIG.native_pick and "Marked for tempering  --  bring it to Hal" or "Marked for reforging  --  bring it to Jiera", x, y, 0xFF7BE0FF) end
        else
            draw.text("Press R (R3 on controller) to mark " .. hov.name .. (CONFIG.native_pick and " for Hal's tempering" or " for reforging"), x, y, 0xFFE8E8E8)
        end
    end
end)

-- A choice was made: queue the work, remap to a NATIVE choice.
sdk.hook(SETFLOW, function(args)
    local ok, err = pcall(function()
        if (sdk.to_int64(args[3]) & 0xFFFFFFFF) ~= 1 then return end   -- only End
        local ts = sdk.to_managed_object(args[2])
        local sel = ts:get_field("SelectedIndex")
        if Menu.state == nil then
            if Menu.ours == nil then return end
            if sel == Menu.ours then
                if Menu.npc == "hal" and CONFIG.native_pick and CONFIG.hal_temper.native
                   and Menu.manufacture_idx and Game.origins_ready() then
                    Pick.route, Pick.active, Pick.t0, Pick.kind = true, false, os.clock(), "temper"
                    Pick.swap_t = os.clock()                      -- his Manufacture request becomes the appraisal screen
                    ts:set_field("SelectedIndex", Menu.manufacture_idx)
                    mlog("'" .. CONFIG.hal_temper.menu_label .. "' picked -> weapon screen")
                    Menu.ours = nil
                    return
                elseif Menu.npc == "hal" then
                    Menu.pending = { act = "t_open" }
                elseif not Game.origins_ready() then
                    Menu.pending = { act = "leave_to_menu" }
                elseif CONFIG.native_pick and Menu.appraise_idx then
                    Pick.route, Pick.active, Pick.t0, Pick.kind = true, false, os.clock(), "reforge"
                    ts:set_field("SelectedIndex", Menu.appraise_idx)   -- her own screen, as a relic picker
                    mlog("'" .. CONFIG.menu_label .. "' picked -> relic picker")
                    Menu.ours = nil
                    return
                elseif CONFIG.mark_keys and Mark.marked then
                    Menu.pending = { act = "grabbed", item = Mark.marked }
                    mlog("'" .. CONFIG.menu_label .. "' picked -> marked relic: " .. Mark.marked.name)
                else
                    Menu.pending = { act = "open" }
                    mlog("'" .. CONFIG.menu_label .. "' picked -> pick list (no marked relic)")
                end
                ts:set_field("SelectedIndex", Menu.talk_idx)      -- stay in her menu loop
            elseif sel > Menu.ours then
                ts:set_field("SelectedIndex", sel - 1)          -- restore native index
            end
            Menu.ours = nil
            return
        end
        local row = Menu.rows and Menu.rows[sel + 1]
        local act = row and row.act
        mlog(string.format("screen %s: row %d -> %s", tostring(Menu.state), sel, tostring(act)))
        if act == "leave_to_menu" or act == "accept" then
            Menu.pending = { act = act }
            ts:set_field("SelectedIndex", Menu.talk_idx)        -- back to her menu, via Talk
        elseif (act == "yes" or act == "yes_again") and not native_wanted() and CONFIG.native_reveal then
            mlog("native reveal: no Appraise row seen in her menu -> talk-row reveal")
            Menu.pending = row
            ts:set_field("SelectedIndex", Menu.talk_idx)
        elseif (act == "yes" or act == "yes_again") and native_wanted() then
            -- pay + roll next tick, while the game opens her own appraisal
            -- screen; the roll is fed to it there (see NATIVE REVEAL)
            local p = {}
            for k, v in pairs(row) do p[k] = v end
            p.native = true
            Menu.pending = p
            Native.route, Native.ready, Native.abort, Native.decided = true, false, false, nil
            Native.t0 = os.clock()
            ts:set_field("SelectedIndex", Menu.appraise_idx)
            mlog("native reveal: routing to her Appraise row (index " .. tostring(Menu.appraise_idx) .. ")")
        elseif act then
            Menu.pending = row
            ts:set_field("SelectedIndex", Menu.talk_idx)        -- stay in the loop
        else                                                     -- label row / cancel button
            if Menu.state == "reveal" or Menu.state == "again" then  -- backing out of a paid roll keeps the old perks
                Menu.pending = { act = "keep_old_quiet" }
            elseif Menu.state == "t_reveal" then                     -- same riven rule for tempering
                Menu.pending = { act = "t_keep" }
            else
                Menu.pending = { act = "leave_to_menu" }
            end
            ts:set_field("SelectedIndex", Menu.cancel_idx)
        end
    end)
    if not ok then mlog("setFlowId hook error: " .. tostring(err)) end
end, function(r) return r end)

-- Hal's "Temper Weapon" is remapped to his own Manufacture row; the game's
-- request for that screen is answered with Jiera's appraisal screen instead
-- (the same call her own Appraise makes), which becomes the Weapon Temper
-- screen. His conversation waits on it like on any menu and resumes after.
do
    local GM_T = sdk.find_type_definition("app.GuiManager")
    local m = GM_T and GM_T:get_method("requestMenuUI")
    if m then
        sdk.hook(m, function(args)
            if not Pick.swap_t then return end
            local c = CONFIG.hal_temper
            local gtype = sdk.to_int64(args[3]) & 0xFFFFFFFF
            if gtype ~= c.manufacture_gui then return end
            local fresh = os.clock() - Pick.swap_t < 5
            Pick.swap_t = nil
            if not fresh then return end
            local ok, err = pcall(function()
                sdk.to_managed_object(args[2]):call("requestAppraisalMenu(System.Int32)", c.appraisal_shop)
            end)
            mlog("weapon screen: Manufacture request -> appraisal screen " .. (ok and "ok" or ("FAILED: " .. tostring(err))))
            if ok then return sdk.PreHookResult.SKIP_ORIGINAL end
            Pick.route = false                                 -- his own screen opens instead
        end, function(r) return r end)
    else
        mlog("WARNING: GuiManager.requestMenuUI not found; Weapon Temper uses the talk list")
    end
end

---------------------------------------------------------------------------
-- NATIVE REVEAL: the paid roll is shown on Jiera's own appraisal result
-- screen (ui042001). The game opens that screen itself (the confirm pick was
-- remapped to her native "Appraise" row); we only feed it data inside its own
-- update: the rolled relic goes into the appraisal manager's result list and
-- the screen's own successAppraisalAction() takes it from there — reveal
-- animation, item card, and the before/after perk window, which we point at
-- the relic's CURRENT perks. Every result command is funnelled into
-- reserveItem, which we answer ourselves: the decision is queued, the result
-- is cleared, and nothing is ever created — perks are written onto the
-- original relic (n_take) or not at all (n_keep / n_again).
---------------------------------------------------------------------------
local UI_T = sdk.find_type_definition("app.ui042001")
local CW_T = sdk.find_type_definition("app.GUIBase.EquipmentAbilityCompareWindowRef")
local CMD = { TAKE = 0, ARISEN = 1, PAWN = 2, STORE = 3, SELL = 4, CANCEL = 5, FAV = 6 }
local FLOW_ORDER   = 2    -- app.ui042001.FlowId.DisplayOrder (the spoil list)
local FLOW_CHECKEND = 7   -- app.ui042001.FlowId.CheckEndMenu (results done?)
local FLOW_ALLITEMS = 12  -- app.ui042001.FlowId.ExecAllItemAction ("Receive Selected" dialog)
local FLOW_NUMINPUT = 15  -- app.ui042001.FlowId.InputItemNumResult
local FLOW_RESERVEFAIL = 16  -- app.ui042001.FlowId.FailReserveResultItem
local FLOW_FADEOUT = 31   -- app.ui042001.FlowId.FadeOut (leaving the screen)

local function native_label(cmd)
    if temper_mode() then
        local nb = Core.temper_bonus(T.cur, T.rolled)
        if cmd == CMD.TAKE or cmd == CMD.ARISEN or cmd == CMD.PAWN then return "Take the new element: " .. Core.elem_name(nb) end
        if cmd == CMD.STORE then return "Keep the current element: " .. Core.elem_name(T.cur) end
        if cmd == CMD.SELL then return "Temper again  (" .. glare_text(temper_cost(CONFIG.hal_temper.tiers[T.tier or 1])) .. ")" end
        return
    end
    if cmd == CMD.TAKE or cmd == CMD.ARISEN or cmd == CMD.PAWN then return "Take the new roll" end
    if cmd == CMD.STORE then return "Keep the current perks" end
    if cmd == CMD.SELL then return "Roll again  (" .. fmt_cost(flow:price()) .. ")" end
end
local function native_relabel(ui, on)
    local gp = ui:get_field("AppraisalItemGridPanel")
    if not gp then return end
    for _, fname in ipairs({ "EquipDefaultPulldownCommandList", "ItemDefaultPulldownCommandList" }) do
        local i = 0
        list_each(gp:get_field(fname), function(li)
            local key = fname .. i
            i = i + 1
            local cmd = li:get_field("CommandId")
            if on then
                Native.saved = Native.saved or {}
                if not Native.saved[key] then Native.saved[key] = { li:get_field("Msg"), li:get_field("IsSelectable") } end
                local label = native_label(cmd)
                if label then li:set_field("Msg", held_str(label)) end
                if cmd == CMD.FAV then li:set_field("IsSelectable", false) end
            elseif Native.saved and Native.saved[key] then
                li:set_field("Msg", Native.saved[key][1])
                li:set_field("IsSelectable", Native.saved[key][2])
            end
        end)
    end
    if not on then Native.saved = nil end
end
local function native_decide(cmd)
    if Native.decided then return end
    local take = cmd == CMD.TAKE or cmd == CMD.ARISEN or cmd == CMD.PAWN
    local act
    if temper_mode() then
        act = take and "t_take" or (cmd == CMD.SELL) and "ts_again" or "t_keep"
    else
        act = take and "n_take" or (cmd == CMD.SELL) and (Pick.studio and "s_again" or "n_again") or "n_keep"
    end
    Pick.after = nil
    Native.decided = act
    Menu.pending = { act = act }
    Native.close = true
    mlog("native reveal: command " .. tostring(cmd) .. " -> " .. act)
end

-- The screen's bottom "Receive Selected" button is hidden and inert during a
-- reveal: the item's own action menu is the one way to decide.
local function native_exec_button(ui, visible)
    pcall(function() ui:get_field("ActionListPanel"):get_field("PnlRoot"):call("set_ForceInvisible", not visible) end)
end
sdk.hook(UI_T:get_method("onDecideExitBtn()"), function(args)
    if Native.active then return sdk.PreHookResult.SKIP_ORIGINAL end
end, function(r) return r end)

-- Feed the roll in / leave once decided — inside the screen's own update.
local TITLE_EMPTY_ID = ValueType.new(sdk.find_type_definition("System.Guid"))
local title_ui = nil
sdk.hook(UI_T:get_method("update()"), function(args)
    title_ui = nil
    if not (Native.route or Native.close or Native.active) then return end
    title_ui = sdk.to_managed_object(args[2])
    local ok, err = pcall(function()
        local ui = sdk.to_managed_object(args[2])
        local f = ui:get_field("CurrFlowId")
        -- Decided from the item's own menu: the menu then heads for its
        -- quantity step (and from there a "can't add" notice) for the result we
        -- already removed. Steer it to the screen's "anything left?" step instead.
        if Native.active then native_exec_button(ui, false) end   -- the screen re-shows it each frame
        local nx = ui:get_field("NextFlowId")
        -- however it is reached (button, key, mouse, back), the screen's
        -- "what to do with the selected items?" dialog never opens on a reveal
        if Native.active and not Native.close and nx == FLOW_ALLITEMS then
            ui:set_field("NextFlowId", 0)
            return
        end
        if Native.close and (f == FLOW_NUMINPUT or f == FLOW_RESERVEFAIL
                             or nx == FLOW_NUMINPUT or nx == FLOW_RESERVEFAIL) then
            ui:set_field("NextFlowId", FLOW_CHECKEND)
            return
        end
        if f ~= FLOW_ORDER then return end
        if Native.route then
            if Native.abort or (not Native.ready and os.clock() - Native.t0 > 5) then
                Native.route, Native.close = false, true          -- payment failed: just leave
            elseif Native.ready and ((temper_mode() and T.item and T.rolled ~= nil) or (not temper_mode() and flow.after and flow.item)) then
                Native.route = false
                local item = temper_mode() and T.item or flow.item
                local list = iam():call("get_ResultDatasList")
                local m = find_master(item)
                if not m or not list or list:call("get_Count") ~= 0 then Native.close = true; return end
                Native.old_vt = m:get_field("_Param")                  -- a copy: the CURRENT perks
                local ab = Native.old_vt:get_field("_Ability")
                if temper_mode() then
                    ab:set_field("Bonus", Core.temper_bonus(T.cur, T.rolled))   -- same perks, the new element
                    GUIDE.reveal = true
                else
                    for i = 1, 4 do ab:set_field("Slot" .. i, flow.after[i] or 0) end
                    ab:set_field("Bonus", flow.after.bonus or 0)
                end
                local ri = sdk.create_instance("app.ItemAppraisalManager.ResultItemInfo"):add_ref()
                ri:set_field("ItemId", item.item_id)
                ri:set_field("ItemCount", 1)
                ri:set_field("Ability", ab)
                Native.ri = ri
                list:call("Add", ri)
                native_relabel(ui, true)
                native_exec_button(ui, false)
                Native.active, Native.close, Native.decided = true, false, nil
                Native.ui = ui:add_ref()
                ui:call("successAppraisalAction()")
                mlog("native reveal: shown " .. item.name)
                Native.guide_logged = false
                return
            end
        end
        if Native.close then                 -- result cleared
            if Pick.studio then
                -- on the Relic ReRoll screen: wait for the decision to be applied,
                -- then back to the relic grid (Roll again re-enters above)
                if Pick.after ~= "grid" then return end
                Native.close, Pick.after, GUIDE.reveal = false, nil, false
                Native.active, Native.old_vt, Native.ri, Native.ui = false, nil, nil, nil
                Pick.route, Pick.t0 = true, os.clock()   -- refill: perks and names changed
                return
            end
            Native.close = false
            if Native.active then native_relabel(ui, false); native_exec_button(ui, true) end
            Native.active, Native.old_vt, Native.ri, Native.ui = false, nil, nil, nil
            ui:set_field("NextFlowId", FLOW_FADEOUT)   -- the screen's own exit, as pressing back here does
        end
    end)
    if not ok then
        mlog("native reveal error: " .. tostring(err))
        Native.route, Native.close = false, false
    end
end, function(r)
    -- The screen re-titles itself every frame; after its update, call it ours.
    if title_ui and (Native.route or Native.active or Pick.studio) and CONFIG.native_title then
        pcall(function()
            local tx = title_ui:get_field("TitleBoard"):get_field("TxtName")
            tx:call("set_MessageId", TITLE_EMPTY_ID)
            tx:call("set_Message", screen_title())
        end)
    end
    return r
end)

---------------------------------------------------------------------------
-- THE RELIC REROLL SCREEN (Jiera). "Reforge Relic" opens her appraisal screen
-- (remapped to her own "Appraise" row) and the whole reforge lives in it:
--   grid    your carried, unequipped Lv5 relics in place of spoils; Special
--           Skills shows the highlighted relic's perks
--   confirm a relic       -> it is chosen and its perk list takes the cursor:
--                            confirm a perk to bind / unbind it, back = grid
--   confirm it again      -> the screen's own number popup becomes the boost
--                            tier with the total cost; confirming pays and
--                            rolls, and the reveal plays on this screen
--   reveal: Take / Keep   -> back to the grid (refreshed)
--           Roll again    -> pays the next tier, next reveal here, binds kept
-- Everything happens inside the screen's own update; nothing is displayed or
-- opened from script.
---------------------------------------------------------------------------
local GI_T = "app.ui042001.StorageAppraisalItemPanel.GridInfo"
local GL_T = "System.Collections.Generic.List`1<app.ui042001.StorageAppraisalItemPanel.GridInfo>"
local FLOW_EXEC, FLOW_APPCONFIRM, FLOW_NUMORDER, FLOW_SLOTLIST = 9, 10, 14, 17

local function pick_say(text) Pick.msg, Pick.msg_t = text, os.clock() end

local function pick_chrome(ui, hidden)
    for _, f in ipairs({ "ActionListPanel", "AppraisalExecBtn", "UnitPrice", "OrderListPanel" }) do
        pcall(function() ui:get_field(f):get_field("PnlRoot"):call("set_ForceInvisible", hidden) end)
    end
end
local function pick_fill(ui)
    local items = {}
    local src = temper_mode() and Game.list_weapons(Origins.map) or Game.list_relic_items(Origins.map)
    for _, it in ipairs(src) do
        -- the Arisen's own bag only: nothing equipped, nothing in storage
        if not it.equipped and it.owner ~= ID.box then items[#items + 1] = it end
    end
    Pick.items, Pick.shown_sid, Pick.bonus = {}, nil, {}
    if #items == 0 then return 0 end
    local list = sdk.create_instance(GL_T):add_ref()
    list:call(".ctor")
    for i, it in ipairs(items) do
        local g = sdk.create_instance(GI_T):add_ref()
        g:call(".ctor")
        g:set_field("_Storage", it.master:get_field("_Param"))
        g:call("set_SortNo", i - 1)
        g:call("set_InitCount", 1)
        list:call("Add", g)
        Pick.items[it.storage_id] = it
        local _, _, b = read_slots(it.master:get_field("_Param"))
        Pick.bonus[it.storage_id] = b
    end
    local sp = ui:get_field("StoragePanel")
    local gc = sp:get_field("GridCtrl")
    gc:call("makeList(System.Collections.Generic.List`1<app.ui042001.StorageAppraisalItemPanel.GridInfo>, System.Int32, System.Boolean)", list, 0, true)
    pcall(gc.call, gc, "makeListSub(System.Int32, System.Boolean)", #items, true)
    pcall(sp.call, sp, "updateDisp()")
    return #items
end
local function pick_selected(ui, info)
    info = info or ui:get_field("StoragePanel"):call("get_SelectedInfo")
    local sid = info and info:get_field("_Storage"):get_field("_StorageId")
    return sid and Pick.items and Pick.items[sid]
end
local function chosen_is(item)
    return item ~= nil and flow.item ~= nil and flow.item.uid == item.uid and flow.state == S.LOCKS
end
-- The game's own "Special Skills" panel, showing the highlighted relic's
-- current perks (refreshed when the highlight moves).
local function pick_perks(ui)
    local info = ui:get_field("StoragePanel"):call("get_SelectedInfo")
    local sid = info and info:get_field("_Storage"):get_field("_StorageId")
    if Pick.slots_on then ui:get_field("SlotInfoListPanel"):call("set_Visible", true) end
    if not sid or sid == Pick.shown_sid then return end
    Pick.shown_sid = sid
    local cw = ui:get_field("SlotInfoListPanel")
    cw:set_field("_EnableBeforeList", true)
    cw:set_field("_EnableAfterList", false)
    local sd = info:get_field("_Storage")
    cw:call("setup(app.ItemDefine.StorageData, app.ItemDefine.StorageData)", sd, sd)
    -- one list, not a before/after pair: hide the lower list and its arrow
    local c = cw:get_field("PnlRoot"):call("get_Child")
    while c do
        local nm = c:call("get_Name")
        if nm == "PNL_ExAfter" or nm == "PNL_RArrow_01S" then c:call("set_ForceInvisible", true) end
        c = c:call("get_Next")
    end
    if not Pick.slots_on then
        Pick.slots_on = true
        ui:call("switchSlotViewVisible(System.Boolean)", true)
    end
    cw:call("set_Visible", true)
end
-- Hide the grid's multi-select check boxes (one relic at a time here).
local function pick_hide_checks(ui)
    local gc = ui:get_field("StoragePanel"):get_field("GridCtrl")
    local items = gc:get_field("ItemList")
    for _, gi in ipairs(items and items:get_elements() or {}) do
        local root = gi:get_field("PNL_item")
        local c = root and root:call("get_Child")
        while c do
            if c:call("get_Name") == "PNL_Check" then c:call("set_ForceInvisible", true); break end
            c = c:call("get_Next")
        end
    end
end
-- Choose a relic for reforging (binds start empty; inherent ones pre-bound).
local function studio_choose(item)
    if not item then return false end
    if flow.state ~= S.IDLE then flow:cancel() end
    flow:open()
    local ok, err = flow:choose_item(item)
    if not ok then
        if flow.state ~= S.IDLE then flow:cancel() end
        pick_say(tostring(err))
        return false
    end
    Pick.odds_key = nil
    mlog("relic screen: chose " .. item.name)
    return true
end
-- Weapon Temper: the popup's number picks the Morbid Glare tier (0 = tier 1);
-- it only goes as high as the tiers you can pay for.
local function temper_max_tier()
    local have = Game.count_item(CONFIG.hal_temper.cost_item)
    local mx = 0
    for i, tier in ipairs(CONFIG.hal_temper.tiers or {}) do
        if have >= temper_cost(tier) then mx = i end
    end
    return mx
end
local TEMPER_ODDS = { [0.5] = "Element: 50%", [1.0] = "Element: guaranteed" }
local function temper_tier_title(i)
    local tier = (CONFIG.hal_temper.tiers or {})[i]
    if not tier then return "" end
    if not tier.element_chance then return "Element: usual odds" end
    return TEMPER_ODDS[tier.element_chance] or ("Element: " .. math.floor(tier.element_chance * 100 + 0.5) .. "%")
end
local function temper_confirm(ui, item)
    if not item then ui:set_field("NextFlowId", 0); return end
    local mx = temper_max_tier()
    if mx == 0 then
        local need = temper_cost((CONFIG.hal_temper.tiers or {})[1] or { cost = 1 })
        pick_say("Need " .. need .. " " .. item_name_by_id(CONFIG.hal_temper.cost_item))
        ui:set_field("NextFlowId", 0)
        return
    end
    T.item, T.rolled = item, nil
    T.cur = (Pick.bonus and Pick.bonus[item.storage_id]) or Game.get_bonus(item) or 0
    Pick.temper_max = mx
    Pick.mode, Pick.boost_set = "boost", false
    mlog("weapon screen: chose " .. item.name .. " (" .. Core.elem_name(T.cur) .. ")")
    ui:set_field("NextFlowId", FLOW_NUMORDER)
end
local function boost_max()
    if temper_mode() then return math.max((Pick.temper_max or 1) - 1, 0) end
    local jb = CONFIG.jiera_boost
    if not (jb and jb.enabled and jb.tiers) then return 0 end
    if Menu.special_p == 0 then return 0 end
    return #jb.tiers
end
local function boost_text(n)
    local q = flow:price()
    local jb = CONFIG.jiera_boost
    local t = n and n > 0 and jb and jb.tiers and jb.tiers[n]
    local w = q.wyrmslife + ((t and not CONFIG.free_mode) and t.wyrmslife or 0)
    local s = w .. " WLC" .. (q.ore > 0 and (", " .. q.ore .. " Brinebeast Ore") or "")
    if t then s = s .. string.format("  (%d%% ^/III)", math.floor(t.chance * 100 + 0.5)) end
    return s
end

local function studio_boost_odds()
    local key = flow.item.uid .. ":" .. tostring(flow.locks[1]) .. tostring(flow.locks[2]) .. tostring(flow.locks[3]) .. tostring(flow.locks[4])
    if Pick.odds_key ~= key then
        Pick.odds_key = key
        Menu.special_p = Game.special_odds(flow.item, flow.before, flow.locks)
    end
end
-- A relic confirmed on the grid (Cross / F / click, or R3 / V): choose it and
-- go to its perks; confirmed again once chosen: the reforge popup.
-- Confirm on a relic: the reforge popup (boost tier + total), keeping any
-- binds already made on it. R3 / V on a relic: its perks, to bind.
local function studio_confirm(ui, item)
    if temper_mode() then return temper_confirm(ui, item) end
    if not chosen_is(item) and not studio_choose(item) then ui:set_field("NextFlowId", 0); return end
    studio_boost_odds()
    Pick.mode, Pick.boost_set = "boost", false
    ui:set_field("NextFlowId", FLOW_NUMORDER)
end
local function studio_bind(ui, item)
    if not chosen_is(item) and not studio_choose(item) then ui:set_field("NextFlowId", 0); return end
    Pick.slot_cancel, Pick.slot_frames, Pick.decide = false, 0, false
    Pick.mode = "bind"
    ui:set_field("NextFlowId", FLOW_SLOTLIST)
end

local pick_ui = nil
local function pick_flow_hook(args)
    pick_ui = nil
    if not (Pick.route or Pick.active or Pick.studio) then return end
    local ok, err = pcall(function()
        local ui = sdk.to_managed_object(args[2])
        pick_ui = ui
        local f, nx = ui:get_field("CurrFlowId"), ui:get_field("NextFlowId")
        if Pick.route then
            if f == FLOW_ORDER then
                Pick.route = false
                local n = pick_fill(ui)
                if n == 0 then
                    if not Pick.studio then
                        Menu.note = temper_mode() and "Carry an unequipped weapon to temper it."
                                                   or "Carry an unequipped level 5 relic to reforge it."
                    end
                    Pick.studio = false
                    ui:set_field("NextFlowId", FLOW_FADEOUT)
                    return
                end
                Pick.active, Pick.slots_on, Pick.studio, Pick.mode = true, false, true, "grid"
                pick_chrome(ui, true)
                pcall(guide_find)
                mlog("relic screen: " .. n .. (temper_mode() and " weapons" or " relics") .. " listed")
            elseif os.clock() - Pick.t0 > 6 and not Pick.studio then
                Pick.route = false
            end
            return
        end
        if not Pick.active then return end
        Pick.frame = (Pick.frame or 0) + 1
        pick_chrome(ui, true)                          -- the screen re-shows them
        pick_perks(ui)
        if Pick.frame % 10 == 1 then pick_hide_checks(ui) end
        local okk, kd = pcall(function() return reframework:is_key_down(CONFIG.inspect_key) end)
        local okg, gd = pcall(ui.call, ui, "isMapMarker")   -- the game's binding for that action (follows rebinds)
        local down = (okg and gd == true) or (okk and kd) or ((pad_buttons() & CONFIG.pad_inspect_button) ~= 0)
        local edge = down and not Pick.inspect_was
        Pick.inspect_was = down

        -- On the perk list: confirm binds, back / V / R3 returns to the grid.
        if f == FLOW_SLOTLIST then
            Pick.slot_frames = (Pick.slot_frames or 0) + 1
            local leaving = nx ~= 0 and nx ~= FLOW_SLOTLIST and nx ~= FLOW_ORDER
            if Pick.decide then
                Pick.decide = false
                local info = ui:get_field("SlotInfoListPanel"):call("get_SelectedInfo")
                local aid = info and info:call("get_AbilityId")
                if aid and flow.state == S.LOCKS then
                    for s, pid in ipairs(flow.before) do
                        if pid == aid then
                            local okl, errl = flow:toggle_lock(s)
                            if not okl then pick_say(tostring(errl)) end
                            break
                        end
                    end
                end
            end
            if edge or Pick.slot_cancel then              -- back / R3 / V: to the relics
                Pick.slot_cancel = false
                ui:set_field("NextFlowId", FLOW_ORDER)
            elseif leaving and Pick.slot_frames <= 3 then
                ui:set_field("NextFlowId", 0)            -- the step's reflex bail on entry
            elseif leaving then
                ui:set_field("NextFlowId", FLOW_ORDER)   -- the player's back / cancel
            end
            return
        end
        if f == FLOW_ORDER and Pick.mode ~= "boost" then Pick.mode = "grid" end
        if f == FLOW_ORDER and Pick.mode == "boost" and nx == 0 and Pick.boost_set then
            Pick.mode = "grid"                         -- popup closed (cancelled)
        end

        if edge and f == FLOW_ORDER and nx == 0 and not temper_mode() then   -- R3 / V on a relic: its perks
            studio_bind(ui, pick_selected(ui))
            return
        end
        if nx == FLOW_NUMORDER and f == FLOW_ORDER and Pick.mode == "grid" then   -- (stack route)
            studio_confirm(ui, pick_selected(ui))
            return
        end
        if f == FLOW_NUMORDER and Pick.mode == "boost" and not Pick.boost_set then
            Pick.boost_set = true
            local wrap = ui:get_field("NumInputWindow")
            local nw = wrap:get_field("NumInputWindow")
            local mx = boost_max()
            -- entered by us (single relics never ask "How many?"), so bring the
            -- popup up the way the grid's own confirm does
            local a1 = pcall(wrap.call, wrap, "setActive(app.ui042001.NumInput.DispType)", 0)
            local a2 = pcall(nw.call, nw, "setNum(System.Int32, System.Int32, System.Int32)", 0, 0, mx)
            local a3 = pcall(nw.call, nw, "setRange(System.Int32, System.Int32)", 0, mx)
            local a4 = pcall(nw.call, nw, "setFocus(System.Boolean)", true)
            pcall(function() wrap:get_field("PnlRoot"):call("set_Visible", true) end)
            mlog(string.format("relic screen: reforge popup, boost 0-%d (active %s num %s range %s focus %s, now %s)",
                mx, tostring(a1), tostring(a2), tostring(a3), tostring(a4), tostring(nw:call("getNum"))))
        end
        if nx == FLOW_EXEC or nx == FLOW_APPCONFIRM then
            ui:set_field("NextFlowId", 0)              -- never appraise in this mode
        end
    end)
    if not ok then mlog("relic screen error: " .. tostring(err)); Pick.route, Pick.active, Pick.studio = false, false, false end
end

-- Flow hints on the game's key-guide strip (a separate HUD, ui011601): its two
-- text lines are rewritten as plain text after the HUD's own late update each
-- frame while the relic grid is up (the <BTN ...> tags still draw as button
-- icons). Nothing is handed to the HUD and none of its calls are altered.
guide_find = function()
    GUIDE.keys, GUIDE.explain = nil, nil
    local scene = sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"), sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
    local comps = scene and scene:call("findComponents(System.Type)", sdk.typeof("app.ui011601"))
    local kg = comps and comps:get_elements()[1]
    local gui = kg and kg:call("get_GameObject"):call("getComponent(System.Type)", sdk.typeof("via.gui.GUI"))
    local function child(c, name)
        c = c and c:call("get_Child")
        while c do if c:call("get_Name") == name then return c end c = c:call("get_Next") end
    end
    local key = gui and child(child(child(gui:call("get_View"), "PNL_Main"), "PNL_Keyguide"), "PNL_Key")
    if key then GUIDE.keys, GUIDE.explain = child(key, "txt_keyguide"), child(key, "txt_explain") end
    mlog("relic screen: key guide " .. (GUIDE.keys and "found" or "NOT found"))
end
guide_hide = function(hidden) end
guide_set = function(keys, explain) GUIDE.want_keys, GUIDE.want_exp = table.concat(keys, " "), explain end
do
    local KG = sdk.find_type_definition("app.ui011601")
    local m = KG and KG:get_method("lateUpdate()")
    if m then
        sdk.hook(m, function(args) end, function(r)
            if GUIDE.reveal and Native.active and GUIDE.explain and T.item and T.rolled ~= nil then
                pcall(function()
                    local nb = Core.temper_bonus(T.cur, T.rolled)
                    local note = ((T.rolled & Core.ELEM_MASK) ~= 0 and (T.cur & ~Core.ELEM_MASK) ~= 0)
                                 and "   (replaces its current bonus)" or ""
                    GUIDE.explain:call("set_MessageId", TITLE_EMPTY_ID)
                    GUIDE.explain:call("set_Message", "Element:  " .. Core.elem_name(T.cur) .. "  >  " .. Core.elem_name(nb) .. note)
                end)
            elseif Pick.active and GUIDE.keys and GUIDE.want_keys then
                pcall(function()
                    GUIDE.keys:call("set_MessageId", TITLE_EMPTY_ID)
                    GUIDE.keys:call("set_Message", GUIDE.want_keys)
                    GUIDE.explain:call("set_MessageId", TITLE_EMPTY_ID)
                    GUIDE.explain:call("set_Message", GUIDE.want_exp)
                end)
            end
            return r
        end)
    end
end
local function pick_set(ui, panel_field, child, text)
    local c = ui:get_field(panel_field):get_field("PnlRoot"):call("get_Child")
    while c do
        if c:call("get_Name") == child then
            c:call("set_MessageId", TITLE_EMPTY_ID)
            c:call("set_Message", text)
            return
        end
        c = c:call("get_Next")
    end
end
local function pick_draw_hook(r)
    if not (pick_ui and (Pick.route or Pick.active or Pick.studio)) then return r end
    local okd, errd = pcall(function()
        local ui = pick_ui
        local tb = ui:get_field("TitleBoard")
        local tx = tb:get_field("TxtName")
        tx:call("set_MessageId", TITLE_EMPTY_ID)
        tx:call("set_Message", screen_title())
        if not Pick.active then return end
        local it = pick_selected(ui)
        if temper_mode() then
            local fnow = ui:get_field("CurrFlowId")
            if Pick.msg and os.clock() - (Pick.msg_t or 0) < 3.5 then
                pick_set(ui, "OrderItemCount", "txt_TitleTotalNum", Pick.msg)
                pick_set(ui, "OrderItemCount", "txt_TotalNum", "")
            else
                pick_set(ui, "OrderItemCount", "txt_TitleTotalNum", "Element")
                pick_set(ui, "OrderItemCount", "txt_TotalNum", it and Core.elem_name(Pick.bonus[it.storage_id] or 0) or "")
            end
            if not Pick.glare_t or os.clock() - Pick.glare_t > 0.5 then
                Pick.glare_t, Pick.glare = os.clock(), Game.count_item(CONFIG.hal_temper.cost_item)
            end
            pick_set(ui, "Price", "txt_TitleTotal", item_name_by_id(CONFIG.hal_temper.cost_item))
            pick_set(ui, "Price", "txt_TitleMoney", Pick.glare .. " owned")
            if Pick.mode == "boost" and fnow == FLOW_NUMORDER then
                guide_set({ "<BTN Decide>Temper", "<BTN BackCancel>Back" },
                          "Pay more " .. item_name_by_id(CONFIG.hal_temper.cost_item) .. " for better odds of an element.")
                pcall(function() ui:get_field("NumInputWindow"):get_field("PnlRoot"):call("set_Visible", true) end)
                local nw = ui:get_field("NumInputWindow"):get_field("NumInputWindow")
                local i = (nw:call("getNum") or 0) + 1
                local tier = (CONFIG.hal_temper.tiers or {})[i] or { cost = 1 }
                nw:call("setTitle(System.String)", temper_tier_title(i))
                nw:call("setMoneyTitle(System.String)", "Total")
                nw:call("setMoney(System.String)", glare_text(temper_cost(tier)))
            elseif fnow == FLOW_ORDER then
                guide_set({ "<BTN Decide>Temper", "<BTN BackCancel>Cancel" },
                          "Temper a weapon to reroll its element.")
            end
            return
        end
        local chosen = chosen_is(it)
        -- the two rows: browsing -> history and price; chosen -> binds and cost
        if Pick.msg and os.clock() - (Pick.msg_t or 0) < 3.5 then
            pick_set(ui, "OrderItemCount", "txt_TitleTotalNum", Pick.msg)
            pick_set(ui, "OrderItemCount", "txt_TotalNum", "")
        elseif chosen then
            local binds = count_keys(flow.locks)
            pick_set(ui, "OrderItemCount", "txt_TitleTotalNum", "Binds")
            pick_set(ui, "OrderItemCount", "txt_TotalNum", binds .. " of " .. CONFIG.max_locks)
        else
            local n = it and (flow.d.slot.counts[it.uid] or 0) or 0
            pick_set(ui, "OrderItemCount", "txt_TitleTotalNum", "Reforged")
            pick_set(ui, "OrderItemCount", "txt_TotalNum", n == 1 and "1 time" or (n .. " times"))
        end
        if chosen then
            pick_set(ui, "Price", "txt_TitleTotal", "Reforge")
            pick_set(ui, "Price", "txt_TitleMoney", boost_text(0))
        else
            local n = it and (flow.d.slot.counts[it.uid] or 0) or 0
            pick_set(ui, "Price", "txt_TitleTotal", "Next reroll")
            pick_set(ui, "Price", "txt_TitleMoney", Core.reroll_cost(n) .. " WLC")
        end
        -- bound perks wear a tag on the Special Skills list
        if chosen and Pick.shown_sid == it.storage_id then
            local cw = ui:get_field("SlotInfoListPanel")
            local lc = cw:get_field("BeforeSlotListCtrl")
            list_each(lc:get_field("InfoList"), function(info)
                local aid = info:call("get_AbilityId")
                local s
                for k, pid in ipairs(flow.before) do if pid == aid then s = k end end
                if not s then return end
                local item = lc:call("getItem(app.GUIBase.EquipmentAbilityCompareWindowRef.SlotListInfo)", info)
                local t = item and item:get_field("TxtCommon")
                if not t then return end
                local tag = (flow.innate and flow.innate[s]) and "[Inherent]  " or (flow.locks[s] and "[Bound]  " or "")
                t:call("set_MessageId", TITLE_EMPTY_ID)
                t:call("set_Message", tag .. perk_name(aid))
            end)
        end
        local fnow = ui:get_field("CurrFlowId")
        local insp = CONFIG.inspect_guide_tag and ("<BTN " .. CONFIG.inspect_guide_tag .. ">Bind perks") or "R3 / V  Bind perks"
        if Pick.mode == "bind" and fnow == FLOW_SLOTLIST then
            guide_set({ "<BTN Decide>Bind / Unbind", "<BTN BackCancel>Back" },
                      "Bind up to " .. CONFIG.max_locks .. " perks: bound perks are kept through the reforge.")
        elseif Pick.mode == "boost" and fnow == FLOW_NUMORDER then
            guide_set({ "<BTN Decide>Reforge", "<BTN BackCancel>Back" },
                      boost_max() > 0 and "Raise the boost for better odds of a ^ or tier III perk."
                                       or "This relic can't roll a ^ or tier III perk, so there is no boost.")
        elseif fnow == FLOW_ORDER then
            guide_set({ "<BTN Decide>Reforge", insp, "<BTN BackCancel>Cancel" },
                      "Bind perks to keep them, then reforge the relic.")
        end
        -- the boost / reforge popup
        if Pick.mode == "boost" and fnow == FLOW_NUMORDER then
            pcall(function() ui:get_field("NumInputWindow"):get_field("PnlRoot"):call("set_Visible", true) end)
            local nw = ui:get_field("NumInputWindow"):get_field("NumInputWindow")
            local n = nw:call("getNum") or 0
            local jb = CONFIG.jiera_boost
            local t = n > 0 and jb and jb.tiers and jb.tiers[n]
            nw:call("setTitle(System.String)", t and string.format("Boost: %d%% ^ / III", math.floor(t.chance * 100 + 0.5)) or "Boost: none")
            nw:call("setMoneyTitle(System.String)", "Total")
            local q = flow:price()
            nw:call("setMoney(System.String)", (q.wyrmslife + ((t and not CONFIG.free_mode) and t.wyrmslife or 0)) .. " WLC")
        end
    end)
    if not okd and not Pick.draw_err then Pick.draw_err = true; mlog("relic screen draw error: " .. tostring(errd)) end
    return r
end
sdk.hook(UI_T:get_method("update()"), pick_flow_hook, pick_draw_hook)

do  -- (diagnostic) how the screen sizes the popup, to match its argument order
    local nt = sdk.find_type_definition("app.GUIBase.NumInputWindowRef")
    local m = nt and nt:get_method("setNum(System.Int32, System.Int32, System.Int32)")
    if m then
        sdk.hook(m, function(args)
            if Pick.active and Pick.mode == "boost" and not Pick.setnum_logged then
                Pick.setnum_logged = true
                mlog(string.format("relic screen: popup setNum(%d, %d, %d)", sdk.to_int64(args[3]) & 0xFFFFFFFF,
                    sdk.to_int64(args[4]) & 0xFFFFFFFF, sdk.to_int64(args[5]) & 0xFFFFFFFF))
            end
        end, function(r) return r end)
    end
end

-- On the perk list the cursor stays on the one visible list...
sdk.hook(CW_T:get_method("updateInput(app.GUIBase.EquipmentAbilityCompareWindowRef.ControlTarget)"), function(args)
    if Pick.active then args[3] = sdk.to_ptr(1) end   -- ControlTarget.Before
end, function(r) return r end)
-- ...its confirm binds (the list reports Decide; the game itself ignores it)...
do
    local base = CW_T:get_field("BeforeSlotListCtrl"):get_type():get_parent_type()
    local m = base and base:get_method("updateInput(app.GUIBase.InputEvent, System.Int32)")
    if m then
        local this_ctrl
        sdk.hook(m, function(args)
            this_ctrl = nil
            if Pick.active and Pick.mode == "bind" then this_ctrl = sdk.to_managed_object(args[2]) end
        end, function(r)
            if this_ctrl and pick_ui and (sdk.to_int64(r) & 0xFF) == 1 then
                local okc, before = pcall(function() return pick_ui:get_field("SlotInfoListPanel"):get_field("BeforeSlotListCtrl") end)
                if okc and before and before:get_address() == this_ctrl:get_address() then Pick.decide = true end
            end
            this_ctrl = nil
            return r
        end)
    end
end
-- ...and the game's own back on the list returns to the grid.
sdk.hook(UI_T:get_method("canceledSlotList()"), function(args)
    if Pick.active then Pick.slot_cancel = true end
end, function(r) return r end)
-- The skill-list step normally only runs over an appraisal result.
local SLOTLIST_OK = UI_T:get_method("isEnableSlotListInput()")
if SLOTLIST_OK then
    sdk.hook(SLOTLIST_OK, function(args) end, function(r)
        if Pick.active then return sdk.to_ptr(1) end
        return r
    end)
end

-- The popup's confirm would add the relic to the appraisal order: instead it
-- is the reforge, with the popup's number as the boost tier.
for _, sig in ipairs({ "applyItemSet(app.ui042001.StorageAppraisalItemPanel.GridInfo, System.Int32)", "applyItemSet(System.Int32)" }) do
    local m = UI_T:get_method(sig)
    if m then
        sdk.hook(m, function(args)
            if not Pick.active then return end
            pcall(function()
                local ui = sdk.to_managed_object(args[2])
                local n = 0
                if sig:find("GridInfo") then n = sdk.to_int64(args[4]) & 0xFFFFFFFF
                else
                    local nw = ui:get_field("NumInputWindow"):get_field("NumInputWindow")
                    n = nw:call("getNum") or 0
                end
                if Pick.apply_frame == Pick.frame then return end   -- one per frame (select-all etc.)
                Pick.apply_frame = Pick.frame
                if Pick.mode == "boost" and temper_mode() and T.item then
                    Menu.pending = { act = "ts_roll", tier = n + 1 }
                    mlog("weapon screen: temper, tier " .. tostring(n + 1))
                    Pick.mode = "grid"
                    ui:set_field("NextFlowId", FLOW_ORDER)
                elseif Pick.mode == "boost" and flow.state == S.LOCKS then
                    Menu.pending = { act = "s_roll", boost = (n > 0) and n or nil }
                    mlog("relic screen: reforge, boost tier " .. tostring(n))
                    Pick.mode = "grid"
                    ui:set_field("NextFlowId", FLOW_ORDER)
                else
                    -- a single relic confirmed on the grid goes straight here
                    local info = sig:find("GridInfo") and sdk.to_managed_object(args[3]) or nil
                    studio_confirm(ui, pick_selected(ui, info))
                end
            end)
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, function(r) return r end)
    end
end

-- The before/after perk window compares against the relic's current perks
-- (normally it would compare against what the character has equipped).
sdk.hook(CW_T:get_method("setup(app.ItemDefine.StorageData, app.ItemDefine.StorageData)"), function(args)
    if Native.active and Native.old_vt then
        pcall(function() args[3] = sdk.to_ptr(Native.old_vt:address()) end)
    end
end, function(r) return r end)

-- Clear the (single) result from the screen ourselves and hand the screen to
-- its own "anything left?" step, which fades the results out and returns to
-- the spoil list, where the update hook above leaves. Nothing is created,
-- sold or equipped, and no storage/weight check can interrupt it.
local function native_finish(ui)
    local res = ui:get_field("Result")
    local slots = res and res:call("getResultSlotList")
    for _, slot in ipairs(slots and slots:get_elements() or {}) do
        res:call("subStack(System.Int32, System.Int32)", slot:call("get_Key"), 1)
    end
    ui:get_field("AppraisalItemGridPanel"):call("setAppraisalItemInfo(app.GUIAppraisalResultData)", res)
    ui:set_field("NextFlowId", FLOW_CHECKEND)
end

-- Acting on the result: the item's own action menu (onSelectPullDownAction,
-- which would otherwise go on to a quantity/space check for the item we never
-- hand out) and the "Receive Selected" dialog (executeCommand). Both are
-- answered ourselves.
local function native_answer(args)
    if not Native.active then return end
    local cmd = sdk.to_int64(args[3]) & 0xFFFFFFFF
    if cmd == CMD.CANCEL or cmd == CMD.FAV then return end
    native_decide(cmd)
    local ok, err = pcall(native_finish, sdk.to_managed_object(args[2]))
    if not ok then mlog("native finish error: " .. tostring(err)) end
    return sdk.PreHookResult.SKIP_ORIGINAL
end
sdk.hook(UI_T:get_method("onSelectPullDownAction(app.ui042001.ResultItemCommand)"), native_answer, function(r) return r end)
sdk.hook(UI_T:get_method("executeCommand(app.ui042001.ResultItemCommand, System.Boolean, System.Int32)"), native_answer, function(r) return r end)

-- Backstop: should anything still try to hand the result out, create nothing.
sdk.hook(UI_T:get_method("reserveItem(app.GUIAppraisalResultData.ResultSlot, app.CharacterID, System.Int32)"), function(args)
    if not Native.active then return end
    pcall(function()
        local ui = sdk.to_managed_object(args[2])
        local slot = sdk.to_managed_object(args[3])
        ui:get_field("Result"):call("subStack(System.Int32, System.Int32)", slot:call("get_Key"), 1)
    end)
    if not Native.decided then native_decide(CMD.STORE) end
    return sdk.PreHookResult.SKIP_ORIGINAL
end, function(r) return r end)

-- Scripts reset (or the mod unloads) with a reveal on screen: without these
-- hooks the screen would treat the shown roll as a real appraisal result and
-- hand it out as a NEW item. Take it off the screen first.
re.on_script_reset(function()
    if not (Native.active and Native.ui) then return end
    pcall(function()
        local res = Native.ui:get_field("Result")
        local slots = res and res:call("getResultSlotList")
        for _, slot in ipairs(slots and slots:get_elements() or {}) do
            res:call("subStack(System.Int32, System.Int32)", slot:call("get_Key"), 1)
        end
        Native.ui:get_field("AppraisalItemGridPanel"):call("setAppraisalItemInfo(app.GUIAppraisalResultData)", res)
        local list = iam():call("get_ResultDatasList")
        if list then list:call("Clear") end
        native_exec_button(Native.ui, true)
        Native.ui:set_field("NextFlowId", FLOW_CHECKEND)
    end)
    Native.active = false
end)


---------------------------------------------------------------------------
-- DEBUG WINDOW (drives the same flow as the Jiera menu)
---------------------------------------------------------------------------
local msg = ""
local function say(ok, m) msg = ok and "" or tostring(m) end
-- Panel buttons never touch the game directly: they queue work for the update phase.
local function act(fn) GameThread.run(function() say(fn()) end) end
local function refresh_items() GameThread.run(function() View.items = Game.list_relic_items(Origins.map) end) end

re.on_draw_ui(function()
    if not CONFIG.debug_window or not imgui.tree_node("Relic Reroll") then return end
    if not View.in_game then imgui.text("Load a save first."); imgui.tree_pop(); return end
    imgui.text(string.format("Wyrmslife: %d   Brinebeast Ore: %d   Holy patch: %s",
        View.wyrmslife, View.ore, Holy.status))
    imgui.text("Hal's shop: " .. Shop.status .. "   Lv5 variety: " .. Variety.status)
    imgui.text("Recipes: " .. Mix.status)
    if Mark.flash and os.clock() - Mark.flash_t < 5 then imgui.text_colored(Mark.flash, 0xFF80FF80) end
    imgui.text("Marked relic: " .. (Mark.marked and Mark.marked.name or "(none — view one in storage and press R)"))
    if not Game.origins_ready() then
        imgui.text_colored(tostring(Game.origins_error()), 0xFF5555FF)
        imgui.tree_pop(); return
    end

    if flow.state == S.IDLE then
        if imgui.button(CONFIG.menu_label) then act(function() refresh_items(); return flow:open() end) end
    elseif flow.state == S.SELECT then
        imgui.text(#View.items .. " relics (equipped gear must be unequipped first)")
        for i, item in ipairs(View.items) do
            local label = item.name .. (item.equipped and "  [equipped]" or "")
            if imgui.button(label .. "##i" .. i) then act(function() return flow:choose_item(item) end) end
        end
        if imgui.button("Back") then act(function() return flow:finish() end) end
    elseif flow.state == S.LOCKS or flow.state == S.CONFIRM then
        imgui.text(flow.item.name)
        for s, pid in ipairs(flow.before) do
            if pid ~= 0 then
                local changed = imgui.checkbox("Lock: " .. perk_name(pid) .. "##p" .. s, flow.locks[s] == true)
                if changed and flow.state == S.LOCKS then act(function() return flow:toggle_lock(s) end) end
            end
        end
        local p = flow:price()
        imgui.text(string.format("Rerolls so far: %d   Cost: %d Wyrmslife + %d Brinebeast Ore",
            p.rerolls_done, p.wyrmslife, p.ore))
        if flow.state == S.LOCKS then
            if imgui.button("Reroll") then act(function() return flow:request_reroll() end) end
            imgui.same_line()
            if imgui.button("Take item back") then act(function() return flow:cancel() end) end
        else
            if imgui.button("Confirm") then act(function() return flow:confirm() end) end
            imgui.same_line()
            if imgui.button("Back") then act(function() return flow:back() end) end
        end
    elseif flow.state == S.REVEAL then
        imgui.text("New roll for " .. flow.item.name .. ":")
        for s, pid in ipairs(flow.after) do
            if pid ~= 0 then imgui.text("  " .. perk_name(pid) .. (flow.locks[s] and "  (bound)" or "")) end
        end
        if imgui.button("Take the new roll") then act(function() return flow:apply_new() end) end
        imgui.same_line()
        if imgui.button("Keep the current perks") then act(function() return flow:keep_old() end) end
    end
    if msg ~= "" then imgui.text_colored(msg, 0xFF5555FF) end
    imgui.tree_pop()
end)
