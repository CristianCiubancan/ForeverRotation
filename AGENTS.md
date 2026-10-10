# Forever Rotation — contributor and agent guide

Rotation helper add-on for **WoW Forever** (Classic Era combat, camelot client, interface `16001`). It shows the next spells and highlights action-bar buttons. It never casts anything.

- Original author: Vohnka — https://wow-forever.fr (development stopped at 1.5.72).
- Maintained from 1.6.0 by CristianCiubancan — https://github.com/CristianCiubancan/ForeverRotation (MIT).
- Fork of `ssablon/ForeverRotation`, kept as the `upstream` remote.
- The add-on folder and SavedVariables keep their names (`WoWForeverRot`, `WoWForeverRotDB`, …) so players switching from 1.5.72 keep their settings.

The full code map is [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (French, written by the original author). This file only says where to start.

## Source of truth and dev loop

Edit **this repo**. The game folder is a directory junction to the repo root:

```bat
mklink /J "E:\World of Warcraft\_classic_beta_\Interface\AddOns\WoWForeverRot" "E:\ForeverRotation"
```

Edit, then `/reload` in game. Never copy files from the game folder over the repo. The client only loads files listed in the TOC, so `tests/`, `docs/` and `dev/` in the folder are harmless.

## Tests

Lua **5.1** (same as the client). On Windows: `lua5.1.exe` / `luac5.1.exe` on `PATH`; on Ubuntu: `apt install lua5.1`.

```sh
lua5.1 tests/run.lua                  # all tests
lua5.1 tests/run.lua --update-golden  # rewrite tests/golden/*.txt
```

- `tests/wowmock.lua` is a minimal client: units, health, power, auras, spellbook, cooldowns, a clock, and *secret values* like camelot. It loads the add-on files that build the queue (no UI).
- Golden files record the queue for every class × spec × mode in a fixed set of situations. Rewrite them **only** when the change is intended, and review the diff: it is the list of every suggestion you changed.
- CI (`.github/workflows/ci.yml`) runs `luac5.1 -p` on every `.lua` file and the tests on every push and pull request.

## Releasing

1. First line of `VERSION.txt` = the new version (`x.y.z`). Below it, the English Markdown changelog (see `.cursor/rules/changelog-pro.mdc`): player problem, new behaviour, classes affected, what did not change.
2. Same version in **both** TOCs (`## Version`).
3. Merge to `main`, then tag and push: `git tag v1.6.0 && git push origin v1.6.0`.
4. `.github/workflows/release.yml` checks the tag against `VERSION.txt` and both TOCs, runs the tests, builds `WoWForeverRot-x.y.z.zip` with `git archive` (paths marked `export-ignore` in `.gitattributes` stay out) and publishes a GitHub Release with the notes from `VERSION.txt`.

There is no CurseForge upload: CurseForge project `1708963` belongs to the original author. Do not put `X-Curse-Project-ID` back in the TOCs — the CurseForge app would "update" players back to the original 1.5.72.

## Load order

Both TOCs load the same files, in this order:

`Credits.lua` → `Locale.lua` → `API.lua` → `Data.lua` → `Physics.lua` → `Lists.lua` → `APL.lua` → `Share.lua` → `UI.lua` → `Options.lua` → `Glow.lua` → `Rotations.lua` → `Core.lua`

All shared state lives in the `ns` table (second value of `...`). `Core.lua` starts a `C_Timer.NewTicker(0.2)`. There is no `OnUpdate` on the whole HUD, only on the timing bar (50 ms) when `showPhysics` is on.

## Where to change what

| Need | File |
| --- | --- |
| New spell, racial, interrupt, purge, cleanse, weapon imbue | `Data.lua` (`ns.Spell`, then the derived tables) |
| Default order for single / AoE / burst / defense | `Lists.lua` |
| Saving, merging, adding, removing a list step | `APL.lua` |
| Profile import / export | `Share.lua` |
| "Is this step suggested" conditions | `API.lua` (`StepOk`, `Ready`, `Resolve`) |
| Classic timing (swing, auto shot, energy) | `Physics.lua` (`ns.db.showPhysics`) |
| HUD queue, defense, interrupt, weapon | `Rotations.lua` |
| Windows, toolbar | `UI.lua` |
| Options, spell drag and drop | `Options.lua` |
| Skull on the action bars | `Glow.lua` |
| Profiles, slash commands, migrations | `Core.lua` |
| Player text | `Locale.lua` (`ns.T`) |

## Pitfalls that break Forever

- Resolve a spell by **name + spellbook** (`ns.API.Resolve`). A Classic ID can be remapped on Forever.
- Reject `TEST`, `(OLD)` and `(PT)` names (`junkSpellName`).
- Buffs in `ns.MAINTENANCE_BUFF_IDS` are stripped from combat lists at load (`stripMaintFromApl`) and refused by `AddAPL`.
- The client often hides `GetSpellCooldown` in combat. `NoteSpellCast` starts the spell's base cooldown on a successful cast and the spell leaves the queue until it ends. The GCD does not count. Do not bypass `ns.API.Cooldown` with `filler`. `filler` is still blocked by `ns.Physics.Blocks` (Heroic Strike outside the swing window, Aimed/Multi during the auto-shot clip).
- `opt.hold` / `ns.SPELL_HOLD`: after a cast, the spell is not suggested again for N seconds (DoT, HoT, snare). Players can edit the value. `0` = no aura delay. Harmful holds are bound to the target GUID. For `nodebuff` / `nobuff`, a readable aura wins (missing → suggest again; remaining ≤ ~6 s → refresh). The hold is the fallback when the aura is secret.
- **Never read the combat log** (`CombatLogGetCurrentEventInfo`): the client blocks the add-on.
- Do **not** register `SPELLS_CHANGED`: Forever fires it in storms on quest turn-in and level-up and it froze the client. Learn / level-up use a soft invalidate plus a 0.5 s bar refetch.
- `roleAuto` (default true): Hunter / Shaman switch melee / ranged by range. A manual click on the HUD role button turns it off.
- Hunter stings: not on Mechanical / Elemental (`CreatureBlocked`).
- Rotation pass: a list spell already cast (even before it was shown) is marked "used" for this pass and the HUD suggests the next one. A used spell rejoins normal priority as soon as its own tracked cooldown ends or a readable aura says cast it (`readyAgain` in `Rotations.lua`, `ns.API.AuraWantsCast`). When nothing usable is left in the pass, **slot 1** restarts it from the top. Slots 2-3 may look past the pass but must never wipe it: that changed slot 1 on the next tick with nothing pressed (flicker, fixed in 1.6.0; `tests/spec_queue.lua` checks the queue is stable). Reset on target change and when leaving combat.
- Lookahead (1.6.0): slot 1 is "press now"; slots 2-3 are judged at the moment they can be pressed. After each pick, `ns.API.PredictAdvance(ns.API.SlotSeconds(...))` moves a predicted clock by the cast time or GCD; `StepOk` adds `ns.API.PredictAhead()` to its cooldown / hold gate and subtracts it from aura and totem time left. Mana and energy are projected (`ns.API.ProjectedPower`), rage is not. When nothing is pressable, `ns.API.WaitHint` gives the few moments worth re-checking (≤ 3, within 5 s). Anything evaluated with `PredictAhead() > 0` must not change real state (holds, the pass): it is a guess about the future.
- `IsRotationAction`: a filler gives slot 1 to a lower shock / DoT / cooldown / proc that is ready. Starfire and Ice Lance are not actions (no cooldown). Auto-added racials never steal the filler. A spell appears only once in the queue (except `swing`).
- Overpower, Revenge, Riposte, Counterattack and Mongoose Bite use `opt.proc` (`IsSpellUsable` true).
- `listVersion` is 4. Bump it only when saved lists must be thrown away: players lose their reordering.
- `auto` mode uses the single-target list until `ns.API.EnemyCount()` reaches `autoEnemies` (default 3, minimum 2), then the `aoe` list. Nameplates must be on.
- The druid HUD button `hybrid` is not a list key. `ns.ActiveSpec()` picks `cat`, `bear`, `heal`, `tank` or `damage`.
- `ns.ResetCurrentProfile` only wipes the active profile (`base`, `pve`, `pvp`, `custom`).
- Keep the two TOCs identical and bump the version in **both**.

## Dev-only tools

`dev/IconDump.lua` + `WoWForeverRot_IconDump.toc` form a separate developer add-on that dumps every known spell's client name and icon into `WoWForeverIconDumpDB` (`/wfrdump`, then `/reload`). It is not shipped. To use it, add a second junction:

```bat
mklink /J "E:\World of Warcraft\_classic_beta_\Interface\AddOns\WoWForeverRot_IconDump" "E:\ForeverRotation"
```
