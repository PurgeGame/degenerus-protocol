# Phase 325: SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation - Context

**Gathered:** 2026-05-25
**Status:** Ready for planning

<domain>
## Phase Boundary

The v48.0 design-lock phase (direct analog of v47's Phase 321). Produce `325-SPEC.md` — a
paper-only reconciliation, **zero `contracts/*.sol` mutation** — that lets Phase 326 apply ONE
fully-reconciled batched diff with no "by construction" assumptions. Three jobs:

1. **Settle the final shared signatures** for every multi-item file so none of items 2/3/4/7 can
   land as an independent diff that breaks another:
   - `DegenerusGame.sol` — item 2 (`pullRedemptionReserve` coverage branch) + item 3 (renamed
     crank entrypoints) + item 7 (`sellFarFutureTickets`) + the inline `claimableWinnings[SDGNRS]`
     debit.
   - `StakedDegenerusStonk.sol` — item 2 (`_submitGamblingClaimFrom` `maxIncrement` pull) + item 4
     (`receive()` relaxation + `burnAtGameOver` pool-recovery + the `IAfKing` `withdraw`/`poolOf`
     interface adds).
   - `DegenerusVault.sol` — item 3 (`affiliateCode` pass-through) + item 4 (`recoverAfKingPool()`)
     + item 7 (`gameSellFarFutureTickets onlyVaultOwner`).
2. **Grep-attest every cited `file:line`** across all 7 plan docs against the v47.0-closure HEAD
   `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`; correct any drift in the SPEC;
   no "single fn reaches all paths" claim survives un-grepped (re-check the `DegenerusGame`
   mint/jackpot inline-duplication precedent).
3. **Resolve every SPEC-time open item on paper** (the `<decisions>` below) + re-confirm the
   load-bearing salvage-swap no-arb floor before any code is written.

**No research** — all 7 item designs are LOCKED in their plan docs. This phase is attestation +
calibration-lock + shared-signature reconciliation only.

</domain>

<decisions>
## Implementation Decisions

### HERO-04 — Degenerette hero 2-pt rescale payout shape (DISCUSSED — user 2026-05-25)
- **D-01 (curve shape): Continuity.** Across `S ∈ {0..9}` (fixed EV budget = 100 centi-x per
  pick, RTP unchanged), keep the per-hit payouts of the "real-match" tiers `S=3..9` tracking
  today's `M=2..8` curve (shift-by-one — forced at the top by the locked `S=9 ≡ old M=8` jackpot
  relabel, identical odds). The new frequent hero-alone `S=2` tier is inserted at the bottom as a
  small consolation. Lowest calibration risk / least player surprise. NOT the flatter
  "frequent-reward" nor the steeper "lottery" shapes.
- **D-02 (`S=2` magnitude): Partial refund (~40–60% of wager).** A *felt* consolation that honors
  the "just getting the hero symbol right is a win" vision, without gutting continuity. `S=2` hits
  ~16–20% of picks (15.9%@N=4 → 20.2%@N=0), consuming ~9% of the EV budget → `S=3..9` drift
  *modestly* below today's values to hold EV=100. (NOT a ~10–20% token, NOT ~0.8–1× break-even.)
  The exact constants are solved by `derive_5_tables.py` at TST under the byte-reproduce gate.
- **D-03 (bonus-currency thresholds): Preserve rarity → S≥7.** Map today's `matches M≥6`
  thresholds (`_awardDegeneretteDgnrs` `DEGEN_DGNRS_6/7/8_BPS`; WWXRP bonus buckets) onto the new
  scale at `S≥7` (the shift-by-one rule, consistent with `S=9≡M=8`) so WWXRP-bonus / sDGNRS award
  physical rarity matches today. Recompute factors so the ETH +5% / WWXRP high-roi bonus EV stays
  exact per `N`.

### POOL-06 — AfKing post-gameOver re-stranding (DISCUSSED — user 2026-05-25)
- **D-04: Accept-as-minor — NO second sweep.** `burnAtGameOver()` already auto-recovers all ETH
  deposited into the sDGNRS pool *before* gameOver. A `depositFor(SDGNRS)` landing *after*
  `burnAtGameOver` re-strands (sDGNRS has no later trigger and — per the locked design — gets NO
  standalone withdraw), but that's an adversarial / pointless self-donation that harms only the
  donor. Do NOT add a second sweep in `handleFinalSweep` (+30d). Record the donor-only residual as
  a documented known-minor in the SPEC. VAULT is unaffected (anytime `recoverAfKingPool()`).

### SWAP-08 — Salvage-swap no-arb margin (SKIPPED in discussion → LOCKED to plan lean)
- **D-05: Accept the ~4.5pp ceiling margin as the security floor.** The SPEC must still RE-DERIVE
  it from current source at the v47.0-closure HEAD: max full payout `110% × fractionBps(6) = 16.5%
  of face @d6` < cheapest far-future-entry acquisition (~21%, lootbox tier-1). The `fractionBps`
  curve (15%@d6 → 5%@d100) and the jitter band (fraction ×∈[70%,110%], cash share ∈[20%,60%]) are
  NOT widened. If the re-derivation shows the margin does NOT hold at the band CEILING, STOP and
  surface — do not silently proceed.

### RFALL-04 — Redemption reservation accounting shape (SKIPPED in discussion → LOCKED to plan lean)
- **D-06: Single tracked `pendingRedemptionEthValue`.** Pure-ETH OR pure-stETH reservation, no
  mix (keeps the accounting simple). Do NOT introduce a separate stETH-denominated reservation
  value. Applied consistently across submit / claim / gameOver. Coverage checked against the SAME
  asset basis the base is inflated by (donation-robust).

### Claude's Discretion — pure attestations resolved by reading source (NOT user decisions)
The SPEC author resolves these from the live `contracts/` + grep against the v47.0-closure HEAD;
they were intentionally NOT put to the user (grep/derive work, not design choices):
- **KEEP-04:** Confirm VAULT holds a *registered* affiliate code (`owner == VAULT`, distinct from
  its address-derived default); if absent, define the setup step to register one. (Foreclosure
  intent is already locked — this is a fact-check + conditional setup.)
- **KEEP-05:** Confirm whether `autoOpen` (open subscribers' lootboxes) is an existing keeper
  capability or new; scope the rename accordingly.
- **BTOMB packing:** the `_supply.vaultAllowance` checked-add / cap so `existing + 1e36` can't
  overflow `uint128` (~340× headroom), strictly one-shot.
- **S=8 / S=9 packing scheme** for the Degenerette payout tables (both > 32-bit; likely held as
  separate `uint256` per N — settle the re-pack).
- **SWAP-03 jitter source:** pin the jitter seed to an already-SETTLED past VRF word (`lastDayRng`
  or equivalent), confirmed freeze-safe per `v45-vrf-freeze-invariant` (no new mutable SLOAD in
  the rng window).
- **SWAP-06 swap-pop enumeration:** enumerate every `ticketQueue` / `_tqFarFutureKey` consumer and
  prove the O(1) caller-verified swap-pop maintains `membership ⟺ packed != 0` and does NOT
  reproduce the `H-CANCEL-SWAP-MISS` operation class (the far-future jackpot samplers need no
  change, gain no hot-path read).
- Plan/wave decomposition for the SPEC deliverables; exact section structure of `325-SPEC.md`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner producing 325-SPEC.md) MUST read these before planning.**

### Scope + requirements + roadmap
- `.planning/ROADMAP.md` — Phase 325 goal + 5 success criteria (the SPEC's acceptance bar);
  Phases 326/327/328 for downstream awareness.
- `.planning/REQUIREMENTS.md` — the 40 v48.0 REQ-IDs; phase-325 primary owners BATCH-01, RFALL-04,
  KEEP-04, KEEP-05, POOL-06; the SPEC/IMPL/TST/TERMINAL split (§ Traceability).
- `.planning/PROJECT.md` — "Current Milestone: v48.0" section (7-item summary, shared-surface
  overlap map, key constraints, out-of-scope).

### The 7 locked per-item plan docs (the binding design — no research)
- `.planning/PLAN-V48-PRESALE-BOX-DRAIN-FIX.md` (item 1, PFIX — ISOLATED, LootboxModule)
- `.planning/PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md` (item 2, RFALL — §"Fix LOCKED shape"; D-06)
- `.planning/PLAN-V48-KEEPER-RENAME-AND-VAULT-CODE.md` (item 3, KEEP — KEEP-04/05)
- `.planning/PLAN-V48-AFKING-POOL-RECOVERY.md` (item 4, POOL — §Decisions; D-04 / POOL-06)
- `.planning/PLAN-V48-GAMEOVER-BURNIE-TOMBSTONE.md` (item 5, BTOMB — ISOLATED, BurnieCoin/GameOver)
- `.planning/PLAN-V48-DEGENERETTE-HERO-2PT-RESCALE.md` (item 6, HERO — §Decisions 1-3; D-01/02/03)
- `.planning/PLAN-SDGNRS-FAR-FUTURE-SALVAGE-SWAP.md` (item 7, SWAP — the load-bearing item; D-05)

### v47 precedent (the established SPEC shape to mirror)
- `.planning/phases/321-spec-design-lock-call-graph-attestation-reconciliation/321-SPEC.md` — the
  §0 C-corrections / §1 R-reconciliation / §2 blueprint + edit-order map structure to emulate.
- `.planning/phases/321-.../321-ATTEST-*.md` — per-anchor grep-table format for the file:line
  attestations.

### Calibration source-of-truth (HERO byte-reproduce gate at TST)
- `.planning/notes/degenerette-recalibration/derive_5_tables.py` — extend SHAPE/convolution to
  `S∈{0..9}`; emit byte-verifiable constants (Phase-267-style PASS_ALL gate, NOT hand-typed).

### Audit baseline (the frozen HEAD all attestations grep against)
- v47.0 closure HEAD `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`.

### Source (read from `contracts/` ONLY — stale copies elsewhere must be ignored)
- Shared/multi-item: `DegenerusGame.sol`, `StakedDegenerusStonk.sol`, `DegenerusVault.sol`.
- Per-item: `modules/DegenerusGameLootboxModule.sol` (1), `modules/DegenerusGameDegeneretteModule.sol`
  (6), `BurnieCoin.sol` + `modules/DegenerusGameGameOverModule.sol` (5), `AfKing.sol`
  (item 4 — stays UNCHANGED; only interface adds match its signatures verbatim),
  `interfaces/IAfKing*.sol` / `interfaces/IStakedDegenerusStonk.sol` / `interfaces/IDegenerusGame.sol`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable patterns / precedents the SPEC must respect
- **Single batched diff, single approval** — items 2/3/4/7 share `DegenerusGame` /
  `StakedDegenerusStonk` / `DegenerusVault`; they CANNOT be independent diffs. The SPEC settles one
  final signature per shared construct (the v47 `resolveRedemptionLootbox` R1 reconciliation is
  the precedent — one construct edited by two items → one settled signature + apply-order).
- **`membership ⟺ packed != 0`** — the `ticketQueue` invariant the salvage swap-pop must preserve
  (SWAP-06); the `H-CANCEL-SWAP-MISS` class (v46 finding) is the negative precedent to avoid.
- **Byte-reproduce gate** — Degenerette constants come from `derive_5_tables.py`, never hand-typed
  (Phase-267-style PASS_ALL). HERO recalibration must stay write-batch byte-identical to v47's
  `resolveBets` (DGAS) — recalibration is payout-shape only.
- **Freeze invariant** — `v45-vrf-freeze-invariant`: the SWAP-03 jitter seed must be an already-
  SETTLED past VRF word; HERO scoring is deterministic post-resolution (untouched).
- **`AfKing.sol` UNCHANGED** — POOL adds only interface decls (`withdraw(uint256)` / `poolOf(address)`)
  that must match `AfKing.sol`'s signatures verbatim (POOL-05).

### Integration points
- `resolveRedemptionLootbox` is already v47-`external payable` SDGNRS-gated (the v47 R1 result) —
  RFALL's coverage branch composes on top of that, not from scratch.
- `gameOver()` → `DegenerusGameGameOverModule` already invokes `burnAtGameOver()` (`:142`) and
  `handleFinalSweep` (`:192`, +30d); BTOMB and POOL recovery both hook the existing gameover-drain.

</code_context>

<specifics>
## Specific Ideas

- **The load-bearing item is the salvage swap (item 7).** SWAP-08's no-arb proof is the single
  most security-critical SPEC deliverable; the ~4.5pp ceiling margin (D-05) is accepted but MUST be
  re-derived from current source, not assumed.
- **HERO continuity is mostly forced at the edges:** `S=9 ≡ M=8` jackpot (locked, identical odds)
  fixes the top; the `S=2` floor fixes the bottom; the shift-by-one for `S=3..8` follows. The only
  free knob the user set is the `S=2` magnitude (D-02, partial-refund) and the bonus thresholds
  (D-03, S≥7) — the derive script solves the rest to hold EV=100 per N.
- The SPEC should explicitly flag the `matches` 0-8 → 0-9 event-range widening as a frontend/
  indexer concern (out of scope per PROJECT.md) — flag, don't fix.

</specifics>

<deferred>
## Deferred Ideas

- **IMPL (Phase 326):** the single batched contract diff (all 7 items), HELD at the
  contract-commit boundary (applied + locally compiled/tested, never committed without explicit
  user hand-review).
- **TST (Phase 327):** HERO byte-reproduce gate (`derive_5_tables.py` PASS_ALL) + SWAP-08 no-arb
  empirical proof at the jitter band CEILING + RFALL stETH-coverage repro + BTOMB
  uncirculated-only signal + PFIX drain-dust + same-results/regression.
- **TERMINAL (Phase 328):** delta-audit vs v47 baseline + 3-skill adversarial sweep + closure flip.
- Off-chain indexer / webpage (`matches` 0-9 widening, salvage-swap -EV labeling UI) — separate
  frontend track, out of scope for v48.0.

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 325-spec-design-lock-call-graph-attestation-shared-surface-recon*
*Context gathered: 2026-05-25*
