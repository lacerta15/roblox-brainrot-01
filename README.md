# Brainrot Escape Disaster

[![make.fun · roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/lacerta15/roblox-brainrot-01/rank.svg)](https://make.fun/bounty/roblox-brainrot-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/lacerta15/roblox-brainrot-01/reward.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)

An AI-authored 3D Roblox brainrot survival game. Collect brainrots scattered
across escalating rarity zones, bank them for cash in the Safe Zone, survive
the recurring tsunami disaster, and push all the way to the Temple of
GigaChad to steal the Sacred Relic back to safety.

## Features

- **Collection loop** — six brainrots (Skibidi Toilet, Mewing Cat, Grimace
  Shake, Looksmaxxer, Baby Gronk, GigaChad) spawn across Common, Rare, Epic,
  and Legendary zones, each with its own $/s value. Fill your bag and bank
  it at the Safe Zone base.
- **Shop & progression** — spend cash on WalkSpeed, Bag Capacity, and Magnet
  Radius upgrades, or Rebirth for a permanent income multiplier.
- **Verified obstacle course** — build-tested Cyan jump pads
  (`AssemblyLinearVelocity = Vector3.new(0, 85, 45)`), yellow speed-boost
  strips with timed WalkSpeed buffs, a purple Grimace Acid Lake hazard pit
  at Z=250 with stepping stones across it, spinning red hazard lasers that
  sweep the Rare and Legendary approach lanes, and Caseoh boulders blocking
  the run from the Safe Zone all the way to the Temple.
- **Tsunami disaster** — every 60 seconds a siren warns players, then 10
  seconds later a massive blue Neon wave sweeps the field from Z=500 to
  Z=0, knocking out and respawning anyone still outside the Safe Zone.
- **Temple of GigaChad & Sacred Relic escape** — reach Z=460 to find the
  Temple holding the Sacred Relic. Touching the relic sounds an alarm and
  attaches it to the carrier; escaping back across the full hazard field
  into the Safe Zone (Z ≤ 0) triggers a Victory banner, +1 Win, and
  +$50,000 cash. Dying or leaving mid-run resets the relic to the Temple.
- **Wins leaderboard** — leaderstats (`Cash`, `Wins`, `Rebirths`) track
  every player's progress, including Temple escapes, for ranking runs
  against each other.

Compiled with Rojo 7.7.1 (`game.rbxl`, no errors) and verified end-to-end
by running `main.ts`, which produced a complete `dossier.json` covering the
place, all `src/` scripts, and the 3 tour screenshots.

## Run instructions

```sh
mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts
```
