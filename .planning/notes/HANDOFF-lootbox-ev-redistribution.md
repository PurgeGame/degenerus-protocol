# ✅ CLOSED 2026-07-09 — SHIPPED in frozen tree d5e9f58a (constants verified live). HANDOFF no longer needed.
# HANDOFF — implement the lootbox FLIP→ticket EV redistribution (v2, USER-LOCKED 2026-07-03)

Paste the block below into a fresh session.

---

Implement the lootbox FLIP→ticket EV redistribution, v2, which the USER has LOCKED. Full spec is in `.planning/notes/pending-flip-to-ticket-ev-shift.md` — READ IT FIRST, it is authoritative; this handoff summarizes and pins locations. It is EV-neutral (total box value unchanged; shifts ~1/3 of FLIP EV into tickets, split 62.8:37.2 → 75.2:24.8). All edits are in `contracts/modules/DegenerusGameLootboxModule.sol` unless noted.

STATE: v75 mutation campaign is CLOSED, forge is FREE. sDGNRS fixes A+B are committed (`fb7a1879`). Four EV-multiplier comment fixes are already applied uncommitted (incl. two in LootboxModule at L480/L571). Verify current constant values before editing (they should equal the "before" column).

## Change set

1. FLIP ladder constants (LootboxModule ~L301–307), verify-then-swap:
   - `LOOTBOX_LARGE_FLIP_LOW_BASE_BPS`  5_808  → 4_388
   - `LOOTBOX_LARGE_FLIP_LOW_STEP_BPS`    477  →   360
   - `LOOTBOX_LARGE_FLIP_HIGH_BASE_BPS` 30_705 → 23_199
   - `LOOTBOX_LARGE_FLIP_HIGH_STEP_BPS`  9_430 →  7_125
   These make the flat FLIP branch = original × 34/45 (E[largeFlip] 1.64784× → 1.24477×; new ranges low 43.88%–97.88%, high 231.99%–445.74%).

2. NEW constant + a LOGIC change (not just a comment) — the spins-branch stake haircut:
   - Declare near the other LOOTBOX_LARGE_FLIP_* constants: `uint16 private constant LOOTBOX_FLIP_SPINS_STAKE_BPS = 7_060;`
   - In `_resolveLootboxRoll`, the FLIP-spins branch (roll 17–18, ~L2027) currently reads:
       `uint256 stake = _largeFlipOut(amount, targetPrice, seed);`
     change to:
       `uint256 stake = (_largeFlipOut(amount, targetPrice, seed) * LOOTBOX_FLIP_SPINS_STAKE_BPS) / 10_000;`
   - This gives the spins branch an extra × ~12/17 haircut on top of the reduced ladder (spins conditional stake 0.2929× → 0.8788×/3). Flat:spins split within FLIP 60:40 → 68:32.
   - `_largeFlipOut` is shared by the flat branch (roll 14–16) and this spins stake; only the spins call site gets the haircut. Presale/foil-pack FLIP (`PRESALE_BOX_FLIP_*`) is a SEPARATE ladder — do NOT touch it.

3. Ticket variance tiers (LootboxModule ~L268–277), verify-then-swap (chances 1/4/20/45/30% unchanged):
   - TIER1 LOW/HIGH: 32_000 / 60_000 → 40_000 / 65_000
   - TIER2 LOW/HIGH: 16_000 / 30_000 → 20_000 / 35_000
   - TIER3 LOW/HIGH:  8_000 / 14_000 → 10_000 / 16_000
   - TIER4 LOW/HIGH:  4_510 /  8_510 →  5_923 /  9_923
   - TIER5 LOW/HIGH:  3_000 /  6_000 →  3_600 /  7_200
   E[variance] 0.7859 → 0.940985; ticket-branch conditional face 1.5465× → 1.8517×. (The roll-19 ETH-spin stake reads these tiers, so it scales +19.7% automatically — intentional.)
   NOTE: TIER1 HIGH 65_000 is near the uint16 bps ceiling (65_535); pure scaling wanted ~7.18× but was capped at 6.50× on purpose. Keep uint16 unless USER later asks for a wider top.

4. Comment updates (describe what IS, no history) — per spec section "Diff must also update adjacent comments":
   - Inline per-tier band comments at L268–277 (e.g. `// 3.20x`, `// 6.00x`) and the per-tier mean comments (4.6×/2.3×/1.1×/0.651× → 5.25×/2.75×/1.30×/0.792×; T5 0.45×→0.54×).
   - The tier block comment's "overall variance EV (~0.786x)" → ~0.941x (drop any "unchanged vs prior static value" framing).
   - `_largeFlipOut` range comments (~L2090 "58%-130%", ~L2094 "307%-590%") → 43.88%–97.88% / 231.99%–445.74%; and any FLIP-ladder "(58.1%)"-style comments.
   - The 20-branch header comment in `_resolveLootboxRoll` if it quotes FLIP-spins stake/EV.
   - Any Degenerette/lootbox docs quoting the old means.

## Verify (forge is free)
- `grep -rn "5808\|30705\|9430\|8510\|4510\|32000\|60000\|0.786\|1.648" test/ .planning/` (and the bare/underscored forms) — update every stat oracle / hardcoded assertion of the old constants or the ~0.786× variance EV / ~1.648× FLIP EV to the new values.
- Run the lootbox + degenerette EV oracle tests; they must pass with the new numbers. Expected intentional knock-ons: box FLIP faucet (creditFlip) −33% on every box path; box-sourced ticket issuance +19.7%; roll-19 ETH-spin stakes +19.7%.
- Sanity: recompute E[largeFlip]=1.24477, spins stake 0.8788×, E[variance]=0.940985, and confirm the ticket:FLIP split lands ~75.2:24.8 (residual +0.000012 tickets / −4.6e-5 FLIP from rounding is expected).

## Constraints
- Editing contracts/*.sol is fine; COMMITTING needs USER approval via: `mv .git/hooks/pre-commit .git/hooks/pre-commit.bak` → `CONTRACTS_COMMIT_APPROVED=1 git commit -m "<msg without the literal contracts/ string>"` → restore hook. See memory `[[contract-commit-bypass-and-stash-gotcha-2026-06-24]]` / `[[pending-contract-fixes]]`.
- There may already be uncommitted comment-only edits in this file (L480/L571) and in DegenerusGame.sol / DegenerusGameDegeneretteModule.sol — leave them; they get committed together or separately per USER.
- Do the constant + logic edits, run/verify oracles, present the diff for USER review; do NOT commit without explicit approval.
