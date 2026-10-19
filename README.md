# Relic Reroll

Reforge the perks on your level 5 relics, temper weapon elements, and craft the materials to pay for it — in **Dragon's Dogma 2: Dark Arisen** (PC, Steam). A REFramework Lua script.

> Everything runs through the game's own systems: Jiera's and Hal's real talk menus, Jiera's real appraisal screen, the game's own appraisal rolls, the vanilla combine menu. The script never displays a screen of its own.

Download the ready-to-use build from [Nexus Mods](https://www.nexusmods.com/dragonsdogma2/mods/1969). This repository is the source code.

## Features

- **Reforge at Jiera, on her own screen** — *Reforge Relic* opens Jiera's appraisal screen as **Relic ReRoll**, listing the unequipped level 5 relics you carry (weapons and armor) with their perks and how many times each was reforged. Bind up to two perks, pick a boost tier in the game's number popup, and the roll plays on the game's own appraisal result screen beside the current perks. Riven-style: take the new roll, keep the old one, or pay again and keep rolling with your binds intact. The cost is spent either way.
- **Controller and keyboard alike** — the key-guide strip spells out every step with the game's own device-aware button icons (Confirm, Back, and View Details for binding).
- **Perk names exactly as the game shows them** — names and the enhanced-tier marker (`^`) come from the game's own localization lookups, in every language.
- **Escalating costs** — rerolls start at 10 Wyrmslife Crystals and climb to a 100 cap on the tenth reroll of the *same* relic (the Kuva curve). Each chosen bind costs 5 Brinebeast Ore per roll.
- **Boost tiers** — pay +10 / +25 / +50 Wyrmslife on the confirm screen for a 12.5% / 25% / 50% chance that the roll carries at least one enhanced (`^`) or tier III perk in a rerolled slot. A won boost the roller cannot honor (some relics can't produce one) is refunded.
- **Satanchia's signature is sacred** — Battle Frenzy (I–IV) can never be rolled on, off, or between relics. On a Satanchia relic it arrives pre-bound ("Inherent"), costs no ore, and occupies one of the two bind slots. The tier the spoil dropped with is the tier it keeps forever.
- **Temper at Hal, on the same screen** — *Temper Weapon* opens it as **Weapon Temper**, listing the unequipped weapons you carry with their current element. Weapons only: reroll the element bonus for Morbid Glare. 1 Glare buys the game's own odds (elements are rare), 2 Glares buy even odds of an element, 3 guarantee one. Which element is always the game's roll — and level 5 weapons can land **Light**, via the same holy patch that adds it to their appraisal table. Jiera never touches elements; elements are Hal's craft.
- **Hal stocks the materials** — his Lantern Oil and Lantern (Fueled) rows become Wyrmslife Crystals (1,000 g) and Brinebeast Ore (1,500 g), stock 1,000. Other vendors still sell the lantern items.
- **Crafting paths** — four recipes added to the vanilla Combine menu (nothing replaced):
  - 2× Malecryst Shard → Malecryst
  - 2× Malecryst → 2× Brinebeast Ore
  - 2× Brinebeast Fragment → Brinebeast Ore
  - Malecryst + Brinebeast Ore → 33× Wyrmslife Crystal
- **Lv5 pools opened up** — vanilla level 5 weapon spoils roll *only* their five signature skills; the mod widens that pool with the generic perks the game itself allows at Lv5 (Counters, status edges, utilities) at a low weight, so signatures stay dominant. Molten Spirit is unlocked on Lv5 body armor. Both also apply to fresh appraisals.
- **Crash-safe and save-safe** — perks are written through the game's own `updateEquipAbility`, verified after every write, with a custody record so a crash mid-reforge never eats an item. Every payment failure refunds. Nothing is ever spawned, displayed, or written outside the game's own systems.

## Requirements

- [REFramework](https://www.nexusmods.com/dragonsdogma2/mods/8) — the script loader.
- [Rancor Reinforcements](https://www.nexusmods.com/dragonsdogma2/mods/1817) — the economy. Relic Reroll consumes level 5 relics, Wyrmslife Crystals, Brinebeast Ore and Fragments, Malecryst, and Morbid Glare. In the base game those trickle; with Rancor Reinforcements every Rancor event is the farm — its brine bosses (Minotaur, Ogre, Golem, Cyclops, Drake, Sphinx, Dullahan) supply the brine materials, its Rancor Medusa makes Morbid Glare farmable, its dragon finales supply Wyrmslife, and the events themselves rain the level 5 spoils you'll be reforging. Relic Reroll was balanced around that faucet; without it the costs are a grind.

## How to use it, in game

1. **Reforge**: talk to Jiera → *Reforge Relic*. The **Relic ReRoll** screen lists the unequipped level 5 relics in your bag (equipped gear and storage are left out — unequip and carry what you want to reforge).
2. **Bind**: highlight a relic and press **View Details** (**R3** on controller, **V** on keyboard by default) to move to its perks. **Confirm** toggles a bind (up to two); **Back** returns to the relics.
3. **Reforge it**: **Confirm** on the relic opens the reforge popup — left/right picks a boost tier, and the total cost is shown. Confirm pays and rolls.
4. **Decide**: the roll plays on the appraisal result screen beside the current perks. In the item's menu: *Take the new roll*, *Roll again*, or *Keep the current perks* — then you're back at the relic list. Backing out of a reveal keeps the current perks; the cost stays spent — riven rules.
5. **Temper**: talk to Hal → *Temper Weapon*. The **Weapon Temper** screen lists your carried, unequipped weapons with their element. Confirm one, pick a Glare tier in the popup (only tiers you can pay for), confirm, then *Take the new element*, *Keep the current element*, or *Temper again*. *An item holds exactly one appraisal bonus* — taking an element onto a weapon with a stat or enhanced-perk bonus replaces it, and the key-guide strip warns you first.

## How it works

- **The screens are the game's own.** *Reforge Relic* is remapped to Jiera's native *Appraise* row, so the game opens her appraisal screen (`ui042001`) itself. *Temper Weapon* is remapped to Hal's *Manufacture* row, and the game's request for that screen is answered with the same appraisal-screen request Jiera's own Appraise makes (`GuiManager.requestAppraisalMenu`) — his conversation waits on it like any menu and resumes after. Inside the screen's own `update()` the mod fills the grid with your items (`makeList`), shows perks in the game's compare window, turns the number popup into the boost / Glare tier, hands the roll to the screen's own `successAppraisalAction()` for the reveal, and answers the result's action menu itself — nothing is created, sold or stored. Hints are written onto the key-guide strip's own text after its late update, so the `<BTN …>` icons follow the active device.
- **The menus are the game's own.** Script-driven display calls crash DD2, so the mod never issues one. It edits the row list *inside* the game's own `ui021601.reqDisp` call and remaps the selection index inside `setFlowId` to a native choice ("Talk" to stay in the loop, "Cancel" to leave) — the architecture of [Guild Contracts](https://www.nexusmods.com/dragonsdogma2/mods/1341). All game-data work runs in the game's update phase, never render-side.
- **The rolls are the game's own.** A reforge calls `ItemAppraisalManager.getAppraisalItemResult` for the relic's original spoil and job — the exact roll Jiera's appraisal uses — until a result passes the merge rules: bound slots keep their perks, the perk count never changes, no duplicates, no two tiers of one perk family, and no Battle Frenzy outside its bound slot.
- **Marking (legacy, off by default) rides the game's card renderer.** Whenever an appraised relic's card draws, the game asks `GuiManager.getAppraisalBonusTypeUV` for its perk icons — a pure data call the mod watches to know which relic is on screen when you press the mark key.
- **One bonus per item.** `app.EquipmentAbilityBonus` holds a single flag: one enhanced perk slot (0x1–0x8), *or* one element (0x10–0x80), *or* one stat bonus (0x100+). Combinations resolve to nothing in the game's own lookups, so every write the mod makes preserves that invariant — enhanced flags follow their perk through rerolls, elements stay with the item through reforges, and tempering replaces the whole bonus.
- **Names come from the game.** `GuiManager.getEquipmentAbilityNameMsgData` and `getEquipmentAblityDescriptionMsgData` (Capcom's spelling) map every ability id to its localized text at runtime.
- **The shop, pools and recipes are data edits on loaded game data**, reapplied by a watchdog whenever the game rebuilds its tables (area changes do this): Hal's two lantern rows are repointed in place (adding shop rows crashes the shop UI — learned the hard way), the Lv5 slot-pool lists get appended entries, and recipes register through the game's own `addItemMixParam` plus the combine menu's `RecipeListTable`.
- **`data/RelicReroll_origins.json`** maps every rerollable relic to the spoils and jobs that can produce it (288 items). It was generated once from the game's own appraisal tables and ships with the mod — nothing is scanned at runtime.

## Installation

Copy the `reframework` folder from the release archive into the game folder (the one with `DD2.exe`), so that you have `reframework\autorun\RelicReroll.lua` and `reframework\data\RelicReroll_origins.json`. The debug panel lives in the REFramework menu (Insert) under `Script Generated UI > Relic Reroll`.

## Configuration

Everything tunable sits in the `CONFIG` table at the top of `src/RelicReroll.lua`:

| Key | Default | Meaning |
|---|---|---|
| `cost_base` / `cost_cap` / `cost_rolls_to_cap` | 10 / 100 / 10 | Wyrmslife reroll curve per relic |
| `max_locks` / `ore_per_lock` | 2 / 5 | Bind cap and Brinebeast Ore per chosen bind per roll |
| `jiera_boost.tiers` | +10/+25/+50 → 12.5/25/50% | Boost surcharges and odds |
| `reforge_lv5_only` | true | Jiera accepts only level 5 relics |
| `innate_lock_prefixes` | AttackAndDamageUp | Perk families that auto-bind and never roll (Battle Frenzy) |
| `hal_temper.tiers` | 1/2/3 Glare | Temper odds tiers |
| `hal_shop` | shop 201 | Which shop rows become Wyrmslife / Ore, stock, prices |
| `recipes` | 4 recipes | Combine-menu additions |
| `lv5_weapon_variety` | 10 : 1 | Signature-vs-generic weights in the Lv5 weapon pool |
| `lv5_pool_unlocks` | Molten Spirit | Single perks unlocked into chosen Lv5 pools |
| `holy_patch_enabled` | true | Light on level 5 weapon spoils |
| `native_pick` / `native_reveal` | true / true | Run Jiera's reforge on her appraisal screen (false = talk-row menus) |
| `native_title` | Relic ReRoll | Screen title for the reforge |
| `inspect_guide_tag` | MapMarker | The game's *View Details* action used for binding (its icon follows the device) |
| `hal_temper.native` / `native_title` | true / Weapon Temper | Run Hal's temper on the same screen |
| `mark_keys` | false | Legacy R / R3 marking in storage (replaced by the screens) |
| `free_mode` | false | Testing: everything costs nothing |

## Offline checks

`tools/harness/test_core.py` runs the script's pure core outside the game (`pip install lupa`):

```
python3 tools/harness/test_core.py src/RelicReroll.lua
```

50+ checks: the cost curve, bind rules and inherent binds, the riven preview/keep/roll-again flow with refund paths, boost payment and refund, the one-flag bonus model, tempering math, and crash-recovery custody.

## Source layout

| File | Purpose |
|---|---|
| `src/RelicReroll.lua` | The whole mod: config, pure core, game bindings, Jiera/Hal menus, shop/pool/recipe patches, debug UI |
| `data/RelicReroll_origins.json` | Static relic → spoil/job origin table (required at runtime) |
| `tools/harness/test_core.py` | Offline test harness (lupa) |
| `dist/` | Release archives as uploaded to Nexus |

## AI usage

Relic Reroll was built with heavy use of AI. Pluralmite came up with the project, directed it and tested it. Claude, Anthropic's AI model, did most of the hands-on work, running as an agent with access to the game folder and a live Lua bridge into the running game.

### What Claude did

- **Wrote the code:** the script in `src/` and the test harness in `tools/`.
- **Found the game data and functions the mod uses:** probed the running game through REFramework and extracted the game's own localization from its PAK archives. This covers:
  - The appraisal roll (`getAppraisalItemResult`), the per-spoil slot pools, bonus tables and the origins of all 288 rerollable relics.
  - The storage data model (`StorageData`/`EquipmentAbilityParam`) and the one-flag `EquipmentAbilityBonus` invariant.
  - The ability-id → localized name/description lookups.
  - Jiera's and Hal's talk-menu display and selection flow, and the card-render call used for marking.
  - Jiera's appraisal screen (`ui042001`): its flow states, grid, compare window, number popup and result actions; the key-guide HUD; and the GUI request that opens the screen from Hal's menu.
  - Hal's shop rows, the two combine-recipe registries, and the element/perk pool tables the patches edit.
- **Crashed the game repeatedly and learned from each:** the crashes traced to displaying UI from script, restructuring shop arrays, touching a screen from outside its own update, and hooking the key-guide HUD's own setters — which is why the released mod only feeds a screen inside that screen's own update calls, and only writes the HUD's text after the HUD has drawn.
- **Tested and fixed** against Pluralmite's live sessions, and wrote the offline harness.
- **Wrote and published the documentation and release:** this README, the release README and the Nexus description, the repository and the Nexus page.

### What Pluralmite did

- Came up with the idea and every design rule: riven-style preview rolls, the cost curve and caps, binds and their prices, level-5-only reforging, elements as Hal's craft with Glare tiers, Battle Frenzy as Satanchia's untouchable signature, the material recipes and their rates, and making it open source.
- Played and tested every build in-game and reported what was wrong: crashes, invisible menus, rolls that didn't stick, wrong prices, a tempered element that didn't display, and a screen flow that has to be clear on both controller and keyboard.
- Designed the v1.1 screen flow: relic picker → View Details to bind → confirm for the boost popup → reveal, all inside Jiera's appraisal screen, and the same for Hal.
- Reviewed and published the release.

### Accuracy

Every perk, roll, price curve and recipe outcome the mod produces goes through the game's own systems; the script decides *when* they run and *what is kept*. It was checked by playing.

## Changelog

**1.1.0**
- Jiera's reforge now lives on her own appraisal screen (**Relic ReRoll**): relic picker with current perks and reforge count, View Details (R3 / V) to bind perks, a boost-tier popup with the total cost, the reveal on the appraisal result screen, and Take / Keep / Roll again without leaving the screen.
- Hal's temper moves to the same screen (**Weapon Temper**): weapon list with each weapon's element, a Glare-tier popup limited to what you can afford, and Take / Keep / Temper again on the result screen.
- Key-guide hints for every step, with the game's own button icons for controller and keyboard.
- Only the unequipped items in your bag are listed; storage marking with R / R3 is retired (still available as `mark_keys`).
- Boost hidden on relics that can't roll an enhanced or tier III perk; boost refunds go to storage.

**1.0.0** — first release.

## Licence

[MIT](LICENSE). Copyright (c) 2026 Pluralmite.
