# Relic Reroll

Reforge the perks on your level 5 relics, temper weapon elements, and craft the materials to pay for it — in **Dragon's Dogma 2: Dark Arisen** (PC, Steam). A REFramework Lua script.

> Everything runs through the game's own systems: Jiera's and Hal's real talk menus, the game's own appraisal rolls, the real storage interface, the vanilla combine menu. The script never displays a screen of its own.

Download the ready-to-use build from [Nexus Mods](https://www.nexusmods.com/dragonsdogma2/mods/1969). This repository is the source code.

## Features

- **Reforge at Jiera** — mark a level 5 relic (weapon or armor) in your storage or inventory, bring it to Jiera, bind up to two perks, and reroll the rest. Riven-style: every roll is a *preview* shown beside the current perks — take the new roll, keep the old one, or pay again and keep rolling with your binds intact. The cost is spent either way.
- **Perk names exactly as the game shows them** — names and the enhanced-tier marker (`^`) come from the game's own localization lookups, in every language.
- **Escalating costs** — rerolls start at 10 Wyrmslife Crystals and climb to a 100 cap on the tenth reroll of the *same* relic (the Kuva curve). Each chosen bind costs 5 Brinebeast Ore per roll.
- **Boost tiers** — pay +10 / +25 / +50 Wyrmslife on the confirm screen for a 12.5% / 25% / 50% chance that the roll carries at least one enhanced (`^`) or tier III perk in a rerolled slot. A won boost the roller cannot honor (some relics can't produce one) is refunded.
- **Satanchia's signature is sacred** — Battle Frenzy (I–IV) can never be rolled on, off, or between relics. On a Satanchia relic it arrives pre-bound ("Inherent"), costs no ore, and occupies one of the two bind slots. The tier the spoil dropped with is the tier it keeps forever.
- **Temper at Hal** — weapons only: reroll the element bonus for Morbid Glare. 1 Glare buys the game's own odds (elements are rare), 2 Glares buy even odds of an element, 3 guarantee one. Which element is always the game's roll — and level 5 weapons can land **Light**, via the same holy patch that adds it to their appraisal table. Jiera never touches elements; elements are Hal's craft.
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

1. **Mark a relic**: open your storage or inventory, view a level 5 relic's card, and press **R** (keyboard) or **click the right stick** (controller). An on-screen line confirms the mark. Equipped gear can't be marked — unequip first.
2. **Reforge**: talk to Jiera → *Reforge Relic: &lt;your relic&gt;*. Bind perks (or don't), pick a boost tier (or don't), confirm. On the reveal: *Take the new roll*, *Roll again*, or *Keep the current perks*. Backing out of a reveal keeps the current perks; the cost stays spent — riven rules.
3. **Temper**: mark a weapon, talk to Hal → *Temper Weapon: &lt;your weapon&gt;*. Pick a Glare tier, confirm, then take or keep the element. *An item holds exactly one appraisal bonus* — taking an element onto a relic with a stat or enhanced-perk bonus replaces it, and the reveal warns you first.
4. **No mark?** Jiera's option still works — it falls back to a paged list of your eligible relics.

## How it works

- **The menus are the game's own.** Script-driven display calls crash DD2, so the mod never issues one. It edits the row list *inside* the game's own `ui021601.reqDisp` call and remaps the selection index inside `setFlowId` to a native choice ("Talk" to stay in the loop, "Cancel" to leave) — the architecture of [Guild Contracts](https://www.nexusmods.com/dragonsdogma2/mods/1341). All game-data work runs in the game's update phase, never render-side.
- **The rolls are the game's own.** A reforge calls `ItemAppraisalManager.getAppraisalItemResult` for the relic's original spoil and job — the exact roll Jiera's appraisal uses — until a result passes the merge rules: bound slots keep their perks, the perk count never changes, no duplicates, no two tiers of one perk family, and no Battle Frenzy outside its bound slot.
- **Marking rides the game's card renderer.** Whenever an appraised relic's card draws, the game asks `GuiManager.getAppraisalBonusTypeUV` for its perk icons — a pure data call the mod watches to know which relic is on screen when you press the mark key.
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
| `select_key` / `pad_mark_button` | R / R3 | Mark bindings |
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
  - Hal's shop rows, the two combine-recipe registries, and the element/perk pool tables the patches edit.
- **Crashed the game six times and learned from each:** every crash traced to displaying UI or restructuring shop arrays from script — which is why the released mod does neither, anywhere.
- **Tested and fixed** against Pluralmite's live sessions, and wrote the offline harness.
- **Wrote and published the documentation and release:** this README, the release README and the Nexus description, the repository and the Nexus page.

### What Pluralmite did

- Came up with the idea and every design rule: riven-style preview rolls, the cost curve and caps, binds and their prices, level-5-only reforging, elements as Hal's craft with Glare tiers, Battle Frenzy as Satanchia's untouchable signature, the material recipes and their rates, and making it open source.
- Played and tested every build in-game and reported what was wrong: crashes, invisible menus, rolls that didn't stick, wrong prices, a tempered element that didn't display.
- Reviewed and published the release.

### Accuracy

Every perk, roll, price curve and recipe outcome the mod produces goes through the game's own systems; the script decides *when* they run and *what is kept*. It was checked by playing.

## Licence

[MIT](LICENSE). Copyright (c) 2026 Pluralmite.
