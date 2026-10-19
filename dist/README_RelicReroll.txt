Relic Reroll v1.1.0
Dragon's Dogma 2: Dark Arisen - REFramework script

WHAT IT DOES
  Reforge the perks on level 5 relics at Jiera, temper weapon elements at Hal,
  buy and craft the materials to pay for it.

  REFORGE (Jiera)
    1. Talk to Jiera -> "Reforge Relic". Her appraisal screen opens as
       "Relic ReRoll", listing the unequipped level 5 relics in your bag.
    2. View Details (R3 on controller, V on keyboard) on a relic opens its
       perks: Confirm binds / unbinds (up to 2, 5 Brinebeast Ore each per
       roll), Back returns. Satanchia's Battle Frenzy binds itself for free
       and uses one of the two slots - it can never be rerolled, upgraded
       or rolled onto anything.
    3. Confirm on the relic opens the reforge popup: 10 Wyrmslife Crystals,
       rising to a 100 cap by the 10th reroll of the same relic. Left/right
       adds a boost: +10 / +25 / +50 Wyrmslife for 12.5% / 25% / 50% odds
       the roll carries an enhanced (^) or tier III perk.
    4. The roll plays on the appraisal result screen beside the current
       perks: take it, keep the old perks, or roll again (binds carry
       over). Cost is spent either way - riven rules.

  TEMPER (Hal)
    Talk to Hal -> "Temper Weapon". The same screen opens as "Weapon
    Temper", listing your carried, unequipped weapons with their element.
    Confirm one and pick a Morbid Glare tier: 1 = the game's own odds,
    2 = even odds of an element, 3 = an element guaranteed. Level 5
    weapons can roll Light. Take the new element, keep the current one,
    or temper again. An item holds exactly ONE appraisal bonus: taking an
    element replaces a stat/enhanced bonus (the screen warns you first).

  SHOP & CRAFTING
    Hal sells Wyrmslife Crystals (1,000 g) and Brinebeast Ore (1,500 g)
    in place of his lantern supplies (other vendors still sell those).
    New Combine recipes:
      2x Malecryst Shard        -> Malecryst
      2x Malecryst              -> 2x Brinebeast Ore
      2x Brinebeast Fragment    -> Brinebeast Ore
      Malecryst + Brinebeast Ore -> 33x Wyrmslife Crystal

  POOLS
    Level 5 weapons can now roll the game's Lv5 generic perks alongside
    their five signature skills (signatures stay dominant), Molten Spirit
    can roll on level 5 body armor, and level 5 weapon spoils can roll
    Light (holy). These also apply to fresh appraisals.

REQUIREMENTS
  REFramework                  nexusmods.com/dragonsdogma2/mods/8
  Rancor Reinforcements        nexusmods.com/dragonsdogma2/mods/1817
    The intended material farm: its Rancor brine bosses drop the brine
    materials, its Rancor Medusa drops Morbid Glare, its dragons drop
    Wyrmslife, and the events rain the level 5 spoils you'll reforge.

INSTALL
  Copy the reframework folder into the game folder (the one with DD2.exe):
    reframework\autorun\RelicReroll.lua
    reframework\data\RelicReroll_origins.json
  Debug panel: REFramework menu (Insert) -> Script Generated UI -> Relic Reroll.
  All prices and rules are in the CONFIG table at the top of the .lua.

SOURCE
  github.com/Pluralmite/RelicReroll (MIT)
