# Successor maintenance and engine v2 — design (2026-10-10)

## Context

Vohnka stopped developing Forever Rotation at 1.5.72 and published the source (MIT). This fork continues it as the **public successor** for all Forever players: nine classes, eleven languages, saved settings that keep working across updates. Releases go to **GitHub Releases** only. CurseForge project `1708963` and the Discord belong to the original author.

Constraint that shapes everything: the camelot client often hides cooldowns and target auras from add-ons (*secret values*) and blocks the combat log. "Smarter" cannot mean reading more from the game. The add-on has to keep its own clock from the player's casts.

## Foundation

- Fork of `ssablon/ForeverRotation` at 1.5.72 (`upstream` remote). Folder, TOC names and SavedVariables unchanged, so 1.5.72 settings carry over.
- `X-Curse-Project-ID` removed from the TOCs so the CurseForge app cannot replace this build with the original.
- Dev loop: the game's `AddOns\WoWForeverRot` is a directory junction to the repo; edit, then `/reload`.
- Offline tests in Lua 5.1 (`tests/`): a fake camelot client runs the real queue code and the real `Core.lua` / `Physics.lua` event handlers, with secret values. Every test builds a fresh client (compiled chunks re-run in a new environment), so no state leaks. The approach was chosen over a Node-hosted Lua (5.3/5.4 semantics differ from the client) and over in-game-only tests (no CI, no checks on contributors' pull requests).
- Golden files: queue and defense suggestion for every class × spec × mode in seven situations plus a six-press sequence. A changed line is a changed suggestion.
- CI on every push / PR; a `vX.Y.Z` tag builds the zip with `git archive` and publishes the release.

## Engine v2

### Problem

Slots 2–3 were judged at "now" (`StepOk` gate 0.2 s). A spell coming off cooldown during slot 1's GCD never appeared; a filler did. The prediction (`PredictConsume`) tracked debuffs, buffs, cooldowns and combo points, but not resources, so slots 2–3 could show spenders the player could not pay for.

### Design

- **Slot 1 stays "press now".** Every rule, gate and side effect for slot 1 is unchanged (verified: zero slot-1 changes in the golden files' static situations).
- **Predicted clock for slots 2–3.** After each pick, `PredictAdvance(SlotSeconds)` adds max(cast time, GCD). GCD is 1 s for rogues and cat form, 1.5 s otherwise; next-swing spells add 0. `StepOk` adds the offset to its cooldown/hold gate and subtracts it from aura and totem time left. `PredictConsume` starts predicted cooldowns at the slot's own time.
- **Resource projection.** Mana and energy costs are subtracted per predicted cast; energy regenerates 20 per 2 s tick (from `Physics`, or about 10/s before a tick was seen). Rage is not projected: white hits and damage taken refill it at a rate the add-on cannot know. When the projection covers every cost of a spell, the live "not enough power" answer from the client is ignored for that later slot.
- **Wait hints.** When nothing is pressable at a later slot's time, `WaitHint` lists the moments where a list spell's own cooldown, hold, aura refresh window or energy allows it; at most three of those moments (within 5 s) are re-checked. A first version scanned a fixed time grid and cost up to 6 ms per queue build for idle healers; hints bring the worst case to about 2 ms (1.5.72: 1.5 ms) and skip the search entirely when nothing time-based is pending.
- **No real-state changes from predictions.** Anything evaluated while filling slots 2–3 (`PredictLater()`, which includes offset 0 after a cast or a next-swing slot 1) must not clear holds or touch the rotation pass.
- **Only readable costs are projected.** If the client hides a cost entry, its live "not enough power" answer still applies (otherwise slots 2–3 would ignore rage).
- **Energy is simulated spend by spend**, capping at max between spends, so ticks lost at full energy are not counted.

### Bug found on the way: queue flicker (present in 1.5.72)

`pickNext` wiped the rotation pass whenever slots 2–3 ran out of unspent spells. Building the queue therefore changed state, and the next 0.2 s tick could show a different slot 1 with nothing pressed (e.g. Warrior damage after eight presses alternated between `SunderArmor, HeroicStrike, Bloodthirst` and `Bloodthirst, SunderArmor, HeroicStrike`). Fix: only slot 1 may wipe the pass; later slots look past it without wiping. `tests/spec_queue.lua` checks two consecutive builds are identical for every class and spec.

### Consequence: when does a used spell come back?

The accidental wipe had been doing a second job: it often reset the pass, so a spell like Fire Blast returned to slot 1 as soon as its cooldown ended. With the wipe gone, the documented pass rule ("walk the list until nothing unused is left") would make it wait behind every other unused spell. Rule chosen, consistent with the existing "a readable aura beats the hold" principle: **what the add-on can read beats the pass.** A used spell rejoins normal priority when its own tracked cooldown ends, or when its aura is up, readable and asks for a cast (still stacking, inside the refresh window). A first version also counted a *missing* aura; review showed that makes a spell whose debuff never lands (Scorch without the talent, immune targets) or is still in flight (Serpent Sting) repeat in slot 1, so missing auras follow the pass as before.

### Effect

Against 1.5.72: 147 of 1013 golden lines change. Slot 1 in fresh situations: 0. Slot 1 inside press sequences: 72 (pass rule and flicker fix). Slots 2–3 only: 75, of which 47 fill a slot that used to be empty.

## Also in 1.6.0

`ns.SpellOnBar` always returned true, so "Only suggest spells that are on your action bars" never filtered. It now filters only after a finished bar scan in which every occupied slot answered and at least one spell was found; a hidden slot makes it step aside (the original reason for the fallback).

## Out of scope / next

- Rage income model (white-hit rage from swing timer and weapon damage).
- Channelled spells report no cast time; they currently count as one GCD.
- Healer specs at full health show an empty queue in burst / AoE modes; a damage filler while idle may help.
- A per-step condition field (e.g. "rage > 50") that stays safe for shared import strings.
- Merging Discipline Priest from `timgellings-cmd/ForeverRotation` after review.
