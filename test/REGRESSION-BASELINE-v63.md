# Regression Baseline — v63.0 (GREEN full-suite baseline at subject `a8b702a7`)

> **POST-AUDIT UPDATE 2026-06-15 — BURNIE-04 fix applied (commit `98c4f049`, local, UNPUSHED).** The
> audit freeze was lifted to apply the one routed finding — BURNIE-04 (sDGNRS redemption carry-escrow:
> the auto-rebuy carry is now included in the redemption BURNIE backing, removed from sDGNRS at submit
> and paid flip-contingently on the resolving day's coinflip) — plus the `CoinflipClaimState` indexer
> event. **New green full-suite baseline: 864 / 0 / 110** at commit `98c4f049`. **New `contracts/`
> byte-freeze tree-hash: `3264a4f8da8b0a8704d2f82c8eeb603e422a678a`** (`git rev-parse 98c4f049:contracts`).
> Storage layout is UNSHIFTED vs the audit subject — the new `PendingRedemption.burnieEscrow` is in-slot
> (96+16+96=208 bits) and no scalar/mapping-root slot moved (re-verified via `forge inspect`). A
> 20-agent adversarial review across 7 correctness axes found 0 HIGH/MEDIUM contract defects. The
> audit-subject record below (`a8b702a7` / tree `2934d3d8`, 854/0/110) is preserved as the v63 audit
> oracle; this fix supersedes it as the current head baseline. 110 commits ahead of origin (USER pushes).

**Subject under test (the audit oracle):** `a8b702a7` — the v63.0 audit subject, byte-frozen at
FOUNDATION (Phase 388). It is the v62.0 closure subject `77580320` plus the ~60 post-v62 commits that
landed on `main` without a formal audit-milestone close (40 contract-source files, +4322/−3489: a full
storage-packing phase, the solvency-adjacent redemption rework, the RNG-freeze-adjacent BURNIE emission
rework, the new permissionless/keeper entrypoints, the gas-identity refactors, and the reward
game-theory). This is the FROZEN audit subject the v63 sweeps (389–396) reproduce findings against.

**`contracts/` fingerprint (the byte-frozen pin — from 388-03-BASELINE-DIFF.md):**
- git tree-hash (content-addressed): `2934d3d8987a09c5f073549a0cb499f6c5f28620` (`git rev-parse
  a8b702a7:contracts`; `git rev-parse HEAD:contracts` == this value — the working tree's
  contract-source tree is byte-identical to the subject; HEAD is a later docs/planning-only commit).
- deterministic content sha256 (`find contracts -name '*.sol' | sort | xargs sha256sum | sha256sum`):
  `0c684378df8d12f339af54e39de7df55971643f69e6b68f02332e918c20d15b3` (60 contract-source `.sol` files).
- `git diff a8b702a7 -- contracts/` EMPTY; `git status --porcelain contracts/` EMPTY before and after
  every run in this gate (the hardhat-regenerates-ContractAddresses landmine guarded — see §5).

**Captured:** 2026-06-14, Phase 388 Plan 03 (the final serial green-baseline gate), after Plan 388-01
re-derived the authoritative storage layout and reconciled every slot-hardcoded harness, and Plan
388-02 audited the verifier oracle holes (the green run rests on both — see §4).

---

## 0. THIS SUPERSEDES `REGRESSION-BASELINE-v62.md` (and the carried-red ledger lineage)

**The signal is "0 deterministic failures" against this green baseline — NOT "a large red count
certified by a by-name non-widening diff."**

The v62 ledger (`REGRESSION-BASELINE-v62.md`) was itself a GREEN baseline (789/3/110 at `c4d48008`)
that retired the v61 non-widening-name-diff debt — but it still carried **3 permitted residual reds**:
the bucket-A non-deterministic VRF-path invariants `invariant_allGapDaysBackfilled`,
`invariant_rngUnlockedAfterSwap`, `invariant_stallRecoveryValid` in
`VRFPathInvariants.inv.t.sol` (run-variance-sensitive ghost-counter properties, proven pre-existing,
enumerated by name as the only permitted exceptions).

**At the v63 subject `a8b702a7`, those carried exceptions are GONE.** The `VRFPathInvariants` suite
now runs **7 invariants, 7 passed, 0 failed** — each at `runs: 256, calls: 32768, reverts: 0`
(`invariant_allGapDaysBackfilled` and `invariant_stallRecoveryValid` now pass green; the suite was
also strengthened — `invariant_rngUnlockedAfterSwap` is superseded by `invariant_swapPreservesLockState`,
which passes, alongside the new `invariant_everyIndexHasWord` / `invariant_indexNeverSkips` /
`invariant_noDoubleIncrement` / `invariant_handlerCanary`). **There are ZERO permitted residual reds at
this subject** — the bucket-A exception list is empty.

Going forward, **a regression is caught by "0 deterministic failures against this green baseline,"
BY NAME (never by raw count).** The expected forge failure name-set is now strictly empty. Any failing
NAME in a future `forge test` run at this subject is a candidate regression.

`REGRESSION-BASELINE-v62.md` remains in the tree as the historical ledger for the v62 milestone close;
it is no longer the live oracle. THIS document is the live oracle for v63 and the council sweeps.

---

## 1. GREEN forge counts (the PRIMARY baseline)

`forge test` (default profile: `via_ir=true`, `evm_version="osaka"`, `[fuzz] runs=1000
seed=0xdeadbeef` deterministic, `[invariant] runs=256 depth=128 fail_on_revert=false`) on a CLEAN
fixture (`forge clean && forge build`, build exit 0) at the frozen `a8b702a7` subject:

| | passed | failed | skipped | total |
|---|---|---|---|---|
| **`a8b702a7` GREEN baseline** | **854** | **0** | **110** | **964** |

- **122 test suites; ALL GREEN** (122 `Suite result: ok`, 0 `Suite result: FAILED`, 0 `[FAIL]`
  lines in the entire run).
- **0 deterministic `test*` failures AND 0 non-deterministic `invariant_*` failures.** Unlike v62,
  there is **no carried bucket-A exception** — the previously-red VRF-path invariants now pass.
- Run timing: 122 suites in ~60s wall (1112.87s CPU). `forge test` exit code 0.
- This is the GREEN signal. A future run that shows **any** failing NAME is a candidate regression.

### 1a. The (now-empty) bucket-A residual set

v62 §2 enumerated 3 permitted residual `invariant_*` reds. **At `a8b702a7` the permitted-residual set
is EMPTY.** The `VRFPathInvariants.inv.t.sol` suite — the sole home of the v62 carried reds — now
reports `Suite result: ok. 7 passed; 0 failed; 0 skipped`:

```
invariant_allGapDaysBackfilled()    PASS  (runs: 256, calls: 32768, reverts: 0)   <- v62 carried-red, now GREEN
invariant_stallRecoveryValid()      PASS  (runs: 256, calls: 32768, reverts: 0)   <- v62 carried-red, now GREEN
invariant_swapPreservesLockState()  PASS  (runs: 256, calls: 32768, reverts: 0)   <- supersedes v62 invariant_rngUnlockedAfterSwap
invariant_everyIndexHasWord()       PASS  (runs: 256, calls: 32768, reverts: 0)
invariant_indexNeverSkips()         PASS  (runs: 256, calls: 32768, reverts: 0)
invariant_noDoubleIncrement()       PASS  (runs: 256, calls: 32768, reverts: 0)
invariant_handlerCanary()           PASS  (runs: 256, calls: 32768, reverts: 0)
```

No `vm.skip`-quarantined finding-candidate carries over as a RED — the 110 skips are the intentional
census (§6).

---

## 2. The RNG-freeze + solvency floor — exercised, not vacuously green

The hard-floor invariants are confirmed EXERCISED at this subject (388-02 oracle-hole audit, FND-04):

- **RNG-window freeze** — `RngWindowFreeze.inv.t.sol` is EXERCISED + non-vacuous (`afterInvariant`
  gates `ghost_windowsOpened>0 AND ghost_inWindowActions>0`) + falsifiable
  (`test_invariantCatchesSeededInWindowMutation` PASS: a seeded in-window mutation of
  `rngWordByDay[snapDay]` makes the detector fire). Its handler slots (10 / 34 / 35 + dailyIdx) MATCH
  the authoritative `forge inspect` layout at the subject. Plus the 7/7 GREEN VRFPath suite (§1a).
- **ETH solvency** — `EthSolvency.inv.t.sol` reads `SolvencyObligations.obligations(game)` via getters
  (slot-drift-immune) and asserts `balance >= obligations`, driven by GameHandler/WhaleHandler/VRFHandler.
  `PoolConservation.inv.t.sol` reads the live `*View()` getters and is falsifiable
  (`test_invariantIsFalsifiable_unbackedCreditMint` seeds an unbacked `futurePrizePool` and asserts
  both bounds break). The redemption-credit-leg solvency coverage lives in
  `RedemptionAccounting.t.sol` + `RedemptionStethFallback.t.sol` (EXERCISED, deterministic branch-proofs).
- **One routed oracle HOLE** (388-02 #2): the legacy `RedemptionInvariants.inv.t.sol` 7-INV harness is
  un-wired (`calls_claim: 0`) + reads stale slots → vacuous. It is **fully superseded** by the EXERCISED
  redemption tests above; its closure is routed to **390 SOLVENCY-SPINE** (do not rely on its green for
  SOLV-03/05/06). This does not amend the GREEN verdict — it is a coverage routing, recorded for the sweep.

---

## 3. Hardhat deterministic subset (CORROBORATING — forge is PRIMARY)

The npm `test` script globs `test/adversarial/*.test.js`, which is ABSENT from the working tree at the
subject (`test/adversarial/` does not exist) → Mocha's glob expansion fails with `MODULE_NOT_FOUND`
before any spec loads. This is the v62 §5 (and v61 §6) documented environment/repo-state limitation; it
affects the baseline and subject identically and is NOT a v63-specific defect. The probabilistic
`test:stat` (chi²/EV distribution suite) is excluded by design.

The runnable deterministic subset was therefore run explicitly, avoiding the broken glob:
`npx hardhat test test/unit/*.test.js test/edge/*.test.js` (34 + 20 specs; evm target osaka).

**Result (2026-06-14):** `1105 passing / 121 failing / 5 pending`. (A stray reference to a
non-existent `test/unit/AffiliateHardening.test.js` prints a `MODULE_NOT_FOUND` line at the END of the
run — AFTER all specs executed; that is the trailing-error exit-1, NOT a pre-load abort like the
`npm test` adversarial glob.)

**Characterization — corroborating only, NO hard-floor breach.** The 121 failures are the SAME
pre-existing gameover-VRF-drive / stale-expectation harness-drift families the v62 §5 ledger
documented (v62 was 1110/117/5; the +4 here is run/checkout drift in the same families, not the v63
contract surface). The dominant families are identical:
`SecurityEconHardening` (16), `RngStall` (13), `AffiliateHardening` (11), `BafCreditRouting` (8),
`GameOver` (7), `DegenerusAffiliate` (7), `DegenerusStonk`/`DGNRS-Liquid` (8), `MintBatchDeterminism` (6),
`DegenerusGame` (11), `HeroOverride`/`TST-JPSURF` (10), `WhaleBundle` (3), plus the `LastPurchaseDayRace`
/ `LivenessMidJackpot` / `LivenessProductivePause` / `LootboxAutoResolve` singletons.

Two spot-checks confirm the family classification (no genuine breach):

- **The one solvency-titled failure** — `EthInvariant (ACCT-01, ACCT-08)` →
  `7. Game-over terminal state — solvency invariant holds (ACCT-08)` fails on
  `Game should be over after 912-day timeout: expected false to be true` (`EthInvariant.test.js:228`).
  I.e. `gameOver()` never LATCHES under the multi-step gameover-VRF drive harness — the SAME
  DEF-380-02-01 drive drift v62 documented — so the solvency assertion never runs. **The solvency
  identity is NOT violated; the gameover precondition is not reached.**
- **The one RNG-titled failure** — `RngStall → 18-hour timeout and retry → rngLocked remains true
  immediately after the retry request` reverts inside the harness's `advanceGame` drive
  (`RngStall.test.js:94/113`) with custom error selector `0xbb3e844f` = **`RngNotReady()`** — a
  CONTRACT GUARD firing (the buffer-freeze / not-ready anti-reroll gate), the correct defensive
  behavior, hit because the JS harness drives the old multi-step stall/retry lifecycle. This is a
  harness drive-shape drift, the OPPOSITE of a freeze breach (cf. the v62 DEF-380-04-FC1
  mid-day-request-gates-next-advance observation).

A scan of all 121 failure-detail blocks for genuine breach evidence
(`insolven|underflow.*pool|conservation.*viol|claimablePool.*(mismatch|exceed|underflow)|freeze.*violat|frozen.*chang`)
returns NONE — the SOLVENCY-01 hard floor is not breached in the JS subset, and no RNG-freeze
determinism property fails on a contract divergence (the freeze authority is the forge
`RngWindowFreeze` falsifiable invariant + the 7/7 GREEN VRFPath suite, §2/§1a).

These belong to the broader Hardhat gameover-VRF-drive harness recalibration (a corroborating
workstream) — they do NOT amend the forge GREEN verdict. Repairing the full JS subset to green is out
of this gate's scope.

**Disposition.** The forge by-name GREEN baseline (§1–§2) is the PRIMARY and sufficient oracle (the
v61/v62 "forge is primary, Hardhat is corroborating" allowance). After the hardhat run the fixture was
restored (`git checkout HEAD -- contracts/ContractAddresses.sol` — a no-op this run, the osaka-target
hardhat compile did not regenerate it) and `git status --porcelain contracts/` re-verified empty +
`forge build` re-confirmed clean (exit 0) BEFORE this baseline was trusted (§5 landmine guard).

---

## 4. The green baseline rests on Plan 388-01 + 388-02 (not vacuously green)

A green run is only trustworthy if the slot-hardcoded harnesses read the LIVE fields (else a stale slot
masks a bug while the test passes) AND the invariants actually exercise their target (else a vacuous
pass). This baseline rests on the Wave-1 outputs:

- **388-01 (FND-02 layout key + canary):** re-derived the authoritative storage layout at the subject
  via `forge inspect <C> storageLayout --json` (contracts tree hash `2934d3d8…`, matching the §0 pin)
  and reconciled EVERY slot-hardcoded poke literal-by-literal — verdict "No bare stale slot literal
  targeting a moved field remains." The region-dependent packing shifts (not a uniform −1) were each
  confirmed against the inspected value, so the green run is NOT green-because-a-stale-slot-masks-a-bug.
- **388-02 (FND-04 oracle-hole audit):** of the 9 invariant/proof tests over post-v62 CHANGED surface,
  7 are EXERCISED (slot-validated + non-vacuity/falsifiability or deterministic branch-proofs), 1 is
  game-side-EXERCISED with the redemption-credit-leg gap routed to 390, and 1 is a HOLE (legacy
  `RedemptionInvariants` 7-INV, superseded, routed to 390). So green means invariants RAN, not vacuous
  passes — except the single routed HOLE, which is covered by the EXERCISED redemption tests.

---

## 5. Contracts byte-frozen attestation (the landmine guard)

`contracts/` was byte-untouched throughout Phase 388-03. The git tree-hash held at
`2934d3d8987a09c5f073549a0cb499f6c5f28620` (== `a8b702a7:contracts`) across every command;
`git status --porcelain contracts/` is empty; `forge build` is clean (exit 0) on the subject both
before the forge run and after the hardhat run. The forge baseline was captured FIRST on a clean
fixture, then the hardhat subset ran; `ContractAddresses.sol` was restored after hardhat (a no-op this
run — the osaka-target hardhat compile reused the existing fixture rather than regenerating it) and the
subject re-verified byte-identical. No test was made to pass by editing a contract source — every
green is against the frozen subject; the JS reds are documented carried harness drift, not contract
divergence.

---

## 6. The skip census (110 skipped)

Skips are intentional, not failures — carried forward unchanged from the v62 census (the contract
behaviors those skips encode are byte-identical or superseded at this subject):

- The deliberate `RngLockDeterminism.t.sol` Option-C `vm.skip` blocks (the Phase-301 RNGLOCK
  determinism catalog).
- Pre-existing supersession / adapted-surface skips with inline reasons (the v55 box-decoding
  decoders, the passless-subscribe supersessions, etc.).
- The v62 DEF-380-04-FC* finding-candidate skips persist where the underlying divergence is unchanged
  at this subject (they were routed to the v62 council and adjudicated; any that touch a v63 CHANGED
  surface are re-intaken by the 388-02 ledger and the per-sweep planners).

The skip count (110) is identical to the v62 baseline — no test moved pass→skip or skip→fail at this
subject.

---

*This is the v63.0 GREEN full-suite baseline — the audit oracle for the council sweeps (389–396). It
SUPERSEDES `REGRESSION-BASELINE-v62.md` (and its carried-red lineage): regressions are now caught by
"0 deterministic failures against this baseline" BY NAME, and unlike v62 there are ZERO permitted
residual reds. Forge is the declared PRIMARY oracle; the Hardhat subset is corroborating (carried
gameover-VRF-drive harness drift, no hard-floor breach). The green baseline rests on the 388-01 slot
reconciliation + the 388-02 oracle-hole audit. Subject byte-frozen at `a8b702a7` throughout.*
