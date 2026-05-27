# 333-02 — SWEEP-01 Adversarial Log (v49.0 TERMINAL)

**Phase:** 333 (TERMINAL) · **Plan:** 02 · **Requirement:** SWEEP-01
**Audit subject (FROZEN):** `4c9f9d9b` · **Baseline:** v48.0 closure HEAD `0cc5d10fbc1232a6d2e7b0464fe21541b9812029`
**Date:** 2026-05-27 · **Read-only:** `git diff 4c9f9d9b HEAD -- contracts/` empty throughout (no `contracts/*.sol` edits).

Mirrors the v44/v46/v47/v48 (Phase 320/324/328) `§A CHARGE / §B raw per-skill / §C disposition / §D
Skeptic-Reviewer Filter Attestation` adversarial-log structure.

---

## §A — CHARGE

### A.1 The FIXED 3-skill set
The sweep ran the FIXED set **`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`**.
**`/degen-skeptic` is OUT** (carried decision D-271-ADVERSARIAL-02, held through v44/v45/v46/v47/v48) — the
skeptic *function* is preserved as the mandatory **dual-gate** applied to every elevation (§D), NOT as a skill.

### A.2 Execution path — GENUINE PARALLEL_SUBAGENT
**Path used: GENUINE PARALLEL_SUBAGENT.** All 3 skills launched as concurrent background Task spawns from the
main orchestrator context (which holds the Task/Agent tool), per CONTEXT D-02 + the hard-won v45/314,
v47/324, v48/328 lesson (NOT nested inside a `gsd-executor`, which lacks the Task tool and would force the
HYBRID/SEQUENTIAL_MAIN_CONTEXT fallback). Each subagent adopted its persona by reading its dedicated
`$HOME/.claude/skills/<skill>/SKILL.md`, probed the FROZEN subject via `git show 4c9f9d9b:contracts/...`
(READ-ONLY, never from memory), and re-grep-verified every cited `file:line` against `4c9f9d9b`. The 3 ran
concurrently (~127–220 s each, wall-clock overlapped) and returned their raw outputs to the orchestrator,
which applied the integration-time dual-gate and assembled §C/§D.

### A.3 The charge weighting (CONTEXT D-01 — the unified router is the v49-novel surface; weighted, NOT uniform)

| Tier | Probe | Lead skill | Structural defense being adversarially re-attested |
|------|-------|-----------|-----------------------------------------------------|
| **TIER-A (deepest)** | advance-timing MEV / same-tx bundling of advance-consume + buy/open | `/zero-day-hunter` (Pitfall 3) | invariant (b) frozen-advance-consume (ADV-04), proven by TST-01 |
| **TIER-A (deepest)** | bounty economics — stall-multiplier abuse / bounty-stacking / faucet self-crank on the unified surface | `/economic-analyst` (lead) + `/contract-auditor` (structural corroboration) | invariant (a) one-category early-return + single `creditFlip` CEI-last (TST-02); the WR-01 round-trip guard / flat sub-gwei peg |
| **TIER-B (re-attest only)** | composed reentrancy router→game→`creditFlip` | `/zero-day-hunter` (Pitfall 6) | USER-locked 332 stance: no ETH push, pinned `ContractAddresses.*`, CEI-last single `creditFlip` → SAFE_BY_DESIGN, no attacker harness |
| **TIER-B (re-attest only)** | unrewarded-advance liveness backstop | `/contract-auditor` | invariant (c) free-fallback callers intact under autoBuy-first ordering (D-04a) |

### A.4 Known Non-Issues honored (NOT re-flagged)
The minted-BURNIE-flip-credit bounty (intended + faucet-bounded: finite pool + self-exclude + ETH-work-gate,
[[project_free_burnie_crank_button]]); the operator-approval trust boundary as the consent unit
([[open-e-operator-approval-trust-boundary]] — no "tricked into approving" actor); the USER-locked
SAFE_BY_DESIGN reentrancy stance ([[v49-keeper-router-redesign]] D-01); the v44 §9d 135-anchor maximalist
register (NOT live vectors, [[project_rnglock_audit_disposition]]).

---

## §B — RAW PER-SKILL OUTPUT

### B.1 `/zero-day-hunter` raw output (TIER-A Pitfall 3 + TIER-B Pitfall 6)

Probed the v49-novel surface (the unified router's same-tx composition) against `git show 4c9f9d9b:...` —
full `doWork`+`_autoBuy` (`AfKing:843-940`,`:561-782`); the advance RNG window / consume gate / lock
set+clear / nudge apply (`AdvanceModule:154-460`,`:1149-1230`,`:1690-1835`); the sole `totalFlipReversals`
writer `reverseFlip` (`DegenerusGame:2196-2200`); `advanceDue`/`boxesPending`/`autoOpen`
(`DegenerusGame:1637-1785`); `creditFlip`/`onlyFlipCreditors`/`_addDailyFlip` (`BurnieCoinflip.sol`).

**Core reasoning (TIER-A):** the nudge lifecycle is the ONLY player-controllable input touching a VRF-derived
output. `reverseFlip()` (sole writer of `totalFlipReversals`) is hard-gated `if (rngLockedFlag) revert
RngLocked();` (`DegenerusGame:2195`). The word is set into `rngWordCurrent` by `rawFulfillRandomWords` WHILE
`rngLockedFlag` is still true (`AdvanceModule:1738-1740`). The next `advanceGame` consumes via
`rngGate`→`_applyDailyRng` (`:1189`/`:1822-1828`), which reads `totalFlipReversals`, folds it into the word,
**and zeroes it**, BEFORE `_unlockRng` (`:1719-1726`) clears `rngLockedFlag`. So across the whole
request→reveal→consume window there is NO instant where `rngLockedFlag == false` AND a stale consumable
`totalFlipReversals` exists — `reverseFlip` is dead the entire time the word is known. The same-tx router does
NOT relax this: `doWork()` does exactly ONE category per call (RD-1 early-return), `reverseFlip` is not in the
router, and bundling `advanceGame`+`reverseFlip` in one external tx only sets nudges for the NEXT day's
not-yet-requested word (intended).

| Probe | Surface (file:line @ 4c9f9d9b) | Disposition | Skeptic-filter outcome | Tier |
|---|---|---|---|---|
| Same-tx capture of freshly-revealed daily RNG via nudge interleave | `DegenerusGame:2195` gate + `AdvanceModule:1189,1822-1828` consume+zero + `:1719-1726` unlock-after | NEGATIVE-VERIFIED | Gate-1 structural (lock-gate + consume-before-unlock ordering); fails Gate-2(a) — `reverseFlip` always reverts in-window | A |
| Line-257 mid-day pre-drain reads `totalFlipReversals` WITHOUT zeroing | `AdvanceModule:255-260` | NEGATIVE-VERIFIED | Reached only when word ready (lock still true → `reverseFlip` dead); the single authoritative zero is in `_applyDailyRng` same call. Gate-1 structural; fails Gate-2(a) | A |
| autoOpen / boxesPending capturing the in-flight word | `DegenerusGame:1655-1660` (rngLock-false), `:1696` (autoOpen `if(rngLockedFlag…) return 0`), `:1704,1718-1724` (opens off pre-frozen index word) | SAFE_BY_DESIGN | rngLock-aware no-op (RD-3); box outcome derives purely from the already-finalized index word | A |
| Router-consumed discovery views perturbing a VRF output | `advanceDue:1637-1654` (pure view), `keeperSnapshot:2628`, `mintPrice:2456-2458` | NEGATIVE-VERIFIED | All pure reads; `mintPrice` is deterministic price-curve, not RNG-derived; level advances only through the gated FSM. Fails Gate-2(b) | A |
| Buy leg (runs during rngLock) writing VRF state | `MintModule` grep: reads `lootboxRngWordByIndex@:696`, double-write guard `:1411`; never writes `rngWordCurrent`/`vrfRequestId`/`totalFlipReversals` | NEGATIVE-VERIFIED | RD-2 freeze-safe-by-construction; orphan hazard defended on the OPEN side. Gate-1 structural | A |
| Composed reentrancy router→game→`creditFlip` | `AfKing.doWork:883-919`, `creditFlip` `BurnieCoinflip:859-865` + `onlyFlipCreditors:196-204` + `_addDailyFlip` (ledger-only) | SAFE_BY_DESIGN (re-attest) | No ETH push the keeper receives (only `.call{value}` is player `withdraw` AfKing:325, CEI); every external call a pinned `ContractAddresses.*`; single `creditFlip` CEI-last `:916-918`; `AF_KING` in `onlyFlipCreditors` set | B |

**Honesty note (zero-day-hunter):** the most promising real angle was line-257's *non-zeroing* read of
`totalFlipReversals` (it diverges from `_applyDailyRng`'s zeroing pattern). Chased whether a same-tx
composition could exploit the asymmetry — it cannot: the read sits inside the lock window where the nudge
count is frozen, and the single authoritative zero happens in `_applyDailyRng` within the same call. Clean.
**0 FINDING_CANDIDATEs.** `git diff 4c9f9d9b HEAD -- contracts/` empty; zero edits/commits.

### B.2 `/economic-analyst` raw output (TIER-A bounty economics — lead)

Probed only `4c9f9d9b` via `git show`. **Load-bearing deploy parameter:** `BOUNTY_ETH_TARGET =
885_000_000 wei = 0.885 gwei` (read LIVE off the AfKing immutable ctor arg in `test/helpers/deployFixture.js:175`
and `test/fuzz/helpers/DeployProtocol.sol:126`); `PRICE_COIN_UNIT = 1000 ether` (`AfKing:233`). Bounty
BURNIE `= (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice`; the ETH-peg VALUE of the credit `=
BOUNTY_ETH_TARGET` per `unit`.

**EV arithmetic (the core of the hunt).** Bounty ETH-peg per leg: buy `= 1.5×0.885 = 1.3275 gwei`;
open(≥knee) `= 0.885 gwei`; advance×1 `= 1.77 gwei`; **advance×6 (max stall escalation) `= 10.62 gwei`**.
Break-even gas covered `= bountyWei / gasPriceWei`: at the 0.5 gwei reference peg advance×6 covers only **~21
gas**; at the 1 gwei floor **~11 gas**. A real new-day advance step (VRF request + ticket drain) burns >150k
gas; a landed keeper buy ≈262k gas; a box open ≈89k gas/box. **The round-trip is ~99.9% negative at EVERY
mult.** This matches the v49 test corpus: `test/fuzz/CrankFaucetResistance.t.sol` (1263 lines) — buy round-trip
`testRouterBuySelfCrankRoundTripNonPositive`/`testFuzz_*` (`:637`,`:676`), open round-trip
`testRouterOpenSelfCrankRoundTripNonPositive`/`testFuzz_*` (`:559`,`:607`), guard-the-guard
`testRouterBuyRewardMatchesLiveUnitRatio` reading `BOUNTY_ETH_TARGET` LIVE (`:702`); the credit lands as
ILLIQUID coinflip stake (`creditFlip`→`_addDailyFlip`, non-liquid per `CrankFaucetResistance.t.sol:255`).

| Probe | Surface (file:line @ 4c9f9d9b) | Disposition | Skeptic-filter outcome | Tier |
|---|---|---|---|---|
| Stall-multiplier abuse (artificial stall → fat 6x advance bounty) | `AdvanceModule:226-242` (1/2/4/6 ladder), `:156` (`mult=1` entry), `AfKing:898-899` | NEGATIVE-VERIFIED | Ladder keyed to wall-clock `elapsed` (permissionless, not state-manipulable); advance is a permissionless race (withholding hands the reward to a competitor); advance×6 ≈ 10.62 gwei vs >150k gas ⇒ ~99.9% loss. Gate-1 structural + Gate-2(a) fails | A |
| Mid-day partial-drain pinned to mult=1 | `AdvanceModule:193-224` (mid-day branch returns/reverts before the `:226-242` escalation block); `:217-218` `return mult`(==1) | SAFE_BY_DESIGN | Escalation block structurally unreachable on the mid-day path. Gate-1 structural | A |
| Gameover path pinned to mult=0 (no bounty) | `AdvanceModule:183-188` `return 0`; `AfKing:899` `if (mult > 0)` guard | SAFE_BY_DESIGN | Explicit zero-return + guard; flip-credit worthless at gameover anyway | A |
| Bounty-stacking (two categories in one tx) | `AfKing:888-911` (`if/else if/else if/else`), `:913-918` (single `creditFlip`) | SAFE_BY_DESIGN (invariant (a) re-attested) | Mutually-exclusive `else-if` ⇒ exactly one category; exactly ONE `creditFlip` at `:917`, CEI-last, gated `bountyEarned>0`; legs never self-credit. Gate-1 structural | A |
| Faucet self-crank — buy leg | `AfKing:850` `BUY_BATCH=50`, `:864-865` `BUY_RATIO 3/2`, `:891-893` | NEGATIVE-VERIFIED | 1.3275 gwei reward vs ≈262k gas ⇒ ~99.999% loss; illiquid stake; buys funded from subscriber pool/`fundingSource` (keeper never the value payee, ROUTER-07). Gate-2(a) fails | A |
| Faucet self-crank — open leg + knee | `AfKing:856` `OPEN_BATCH=100`, `:869` `OPEN_KNEE=5`, `:903-906` | NEGATIVE-VERIFIED | ≤0.885 gwei vs ~89k gas/box; below-knee pro-rated `unit·k/5` kills the small-batch corner; deeply -EV. Gate-2(a) fails | A |
| Faucet self-crank — advance leg (the re-homed bounty, v49 NOVEL) | `AfKing:860` `ADVANCE_RATIO_NUM=2`, `:898-899` | NEGATIVE-VERIFIED | Re-home put the advance bounty under the SAME flat unit; advance×6 = 10.62 gwei covers ~11–21 gas vs >150k real ⇒ ~5 orders-of-magnitude margin. Gate-2(a) fails. (Coverage note in §C.3) | A |
| Self-exclude / ETH-work-gate present | `AfKing:917` (bounty→`msg.sender` as flip stake, not ETH); `:146` (funded by `fundingSource ?? player`); `:911-912` (`if(bountyEarned>0)`) | SAFE_BY_DESIGN | Keeper receives only illiquid flip-credit; purchase value debited from the subscriber's prepaid pool; a no-op walk pays nothing. Gate-1 structural | A |

**0 FINDING_CANDIDATEs.** The v49 re-homing + the 331 flat-per-tx re-peg did NOT break the faucet bound; the
sub-gwei target keeps even worst-case advance×6 ~4–5 orders of magnitude below the real gas cost at any gas
price ≥0.5 gwei. `git diff 4c9f9d9b HEAD -- contracts/` empty; zero edits/commits.

### B.3 `/contract-auditor` raw output (TIER-B liveness backstop + structural + OPEN-E corroboration)

Probed `4c9f9d9b` via `git show`/`git grep`. (Anchor corrections from the charge's approximate values: the
30-min permissionless bypass is at `AdvanceModule:996` inside `_enforceDailyMintGate` (reached from
`advanceGame:154`), not `:1012`; the death-clock logic lives at `:109` (`DEPLOY_IDLE_TIMEOUT_DAYS`),
`:509-510`/`:521` (`_livenessTriggered`), `:1182-1185`, `:1775-1777`, `:1882-1883`.)

| Probe | Surface (file:line @ 4c9f9d9b) | Disposition | Skeptic-filter outcome | Tier |
|---|---|---|---|---|
| 30-min permissionless advance bypass | `AdvanceModule:996` (in `_enforceDailyMintGate`, from `advanceGame:154`) | NEGATIVE-VERIFIED | 4-tier bypass (deity always / anyone ≥30min / pass-holder ≥15min / DGVE-majority) present & unchanged; pure-arithmetic `elapsed` gate; `advanceGame()` unaltered by the bounty re-home | B |
| Vault free-fallback caller | `DegenerusVault.gameAdvance():527` → `advanceGame()` | NEGATIVE-VERIFIED | Independent `onlyVaultOwner` entrypoint calling `advanceGame()` directly, NOT routed through `doWork`; re-home touched nothing here (file not in the v49 delta) | B |
| Stonk free-fallback caller | `StakedDegenerusStonk.gameAdvance():421` → `advanceGame()` | NEGATIVE-VERIFIED | Ungated independent entrypoint; intact (file not in the v49 delta) | B |
| 120-day death-clock anchors | `:109`, `:509-510`/`:521`, `:1182-1185`, `:1775-1777`, `:1882-1883` | NEGATIVE-VERIFIED | All death-clock/liveness anchors present & route correctly; gameOver check precedes liveness; re-home added no new gate | B |
| v49 autoBuy-first ordering reaches advance | `AfKing.doWork:883`, legs `:891`/`:896`/`:902`/`:910` | NEGATIVE-VERIFIED | autoBuy(1) → `else if advanceDue()` advance(2, rngLock-independent) → autoOpen(3) → `revert NoWork`(4); advance reachable whenever no buy work pending & `advanceDue()` true; standalone callers are the unconditional backstop. Invariant (c) re-attested | B |
| Standalone `advanceGame()` unrewarded | `AdvanceModule:154`, comments `:152-153`/`:184`/`:227`/`:455` | NEGATIVE-VERIFIED | No `creditFlip`/bounty/`mintForGame` in the standalone path; the sole `creditFlip:860` credits `ContractAddresses.SDGNRS` (the gameover-RNG U6 settlement), NOT the keeper | B |
| `doWork` one-category else-if + single creditFlip | `AfKing.doWork:883-919` | NEGATIVE-VERIFIED (corroboration) | Exactly ONE executable `creditFlip(msg.sender, bountyEarned)` at `:917`, CEI-last (the `grep -c`=2 counts the `// ONE creditFlip, CEI-LAST` comment at `:913`); `mult==0` gameover pays no bounty | corrob. |

**OPEN-E corroboration (GASOPT-05) — per-protection verdict.** GASOPT-05 removed the per-iteration
`isOperatorApproved(player, AfKing)` (formerly ~`:676`, documented-as-removed at `AfKing:667-670`) and KEPT
the subscribe-time gates at `:388` (self-consent) and `:397-400` (`isOperatorApproved(fundingSource,
subscriber)`, OPENE-04):
1. **consent-gate-at-subscribe — HOLD.** `subscribe():380` gates every non-self subscription on
   `isOperatorApproved(subscriber, msg.sender)` (`:388`) AND any non-self funding source on
   `isOperatorApproved(fundingSource, subscriber)` (`:397-400`); the SUB record IS the consent unit; the
   per-iteration check was redundant.
2. **default-self byte-identical — HOLD.** `player==address(0)`→`subscriber=msg.sender` (`:386`);
   `fundingSource==address(0)` short-circuits the OPENE-04 read (`:397`) and resolves to the subscriber
   downstream (`:438`,`:642`,`:695`,`:813`); the self branch is untouched by the GASOPT-05 delta.
3. **no-escalation — HOLD.** `_resolveBuy():793` (view) only computes the payment SHAPE; funds come from
   `sub.fundingSource` (set ONLY at subscribe under the OPENE-04 gate, `:425`) or self; the keeper/caller
   cannot redirect funding to any wallet that did not approve it at subscribe; the keeper is never a payee.
4. **trust-the-sub temporal bound — HOLD.** The window is bounded by `paidThroughDay` (`WINDOW_DAYS`),
   refreshed only by a paid `burnForKeeper` (`:640-651`) or a free active-pass extend (`:632-636`);
   revocation is `setDailyQuantity(0)`→in-set tombstone, reclaimed/skipped on the next `autoBuy`
   (`:605-616`); the temporal bound & revocation path are intact, independent of the removed check.

**OPEN-E overall: HOLD on all 4** — GASOPT-05 removed a redundant per-iteration read whose authority was
already fixed (and immutable post-subscribe) at the subscribe-time gate. **0 FINDING_CANDIDATEs.**
`git diff 4c9f9d9b HEAD -- contracts/` empty; zero edits/commits.

---

## §C — DISPOSITION TABLE + OUTCOME

### §C.1 Outcome summary

| Disposition | Count |
|-------------|-------|
| **FINDING_CANDIDATE** (survives the dual-gate) | **0** |
| NEGATIVE-VERIFIED (probed, no issue) | 15 |
| SAFE_BY_DESIGN (intended / informational) | 6 |
| **Total charged-probe rows** | **21** |

**Outcome: `0 NEW_FINDINGS`** — the v45/v48 clean-closure outcome (the working target per CONTEXT D-03), reached
by a genuine hunt (every skill chased its deepest real angle and recorded the chase honestly), NOT a
rubber-stamp. KNOWN_ISSUES_UNMODIFIED.

### §C.2 Consolidated per-probe disposition table

| # | Probe | Skill | Surface | Disposition | Skeptic-filter | Tier |
|---|-------|-------|---------|-------------|----------------|------|
| P1 | Same-tx capture of revealed daily RNG via nudge interleave | zero-day-hunter | `DegenerusGame:2195` + `AdvanceModule:1189/1822-1828/1719-1726` | NEGATIVE-VERIFIED | Gate-1 structural; Gate-2(a) fails | A |
| P2 | Line-257 mid-day pre-drain non-zeroing read | zero-day-hunter | `AdvanceModule:255-260` | NEGATIVE-VERIFIED | Gate-1 structural; Gate-2(a) fails | A |
| P3 | autoOpen/boxesPending capturing in-flight word | zero-day-hunter | `DegenerusGame:1655-1724` | SAFE_BY_DESIGN | rngLock-aware no-op (RD-3) | A |
| P4 | Discovery views perturbing a VRF output | zero-day-hunter | `DegenerusGame:1637/2628/2456` | NEGATIVE-VERIFIED | Gate-2(b) fails (no VRF read) | A |
| P5 | Buy leg writing VRF state during rngLock | zero-day-hunter | `MintModule:696/1411` | NEGATIVE-VERIFIED | RD-2 freeze-safe; Gate-1 structural | A |
| P6 | Composed reentrancy router→game→creditFlip | zero-day-hunter | `AfKing.doWork:883-919`; `BurnieCoinflip:859-865` | SAFE_BY_DESIGN | USER-locked TIER-B; no harness | B |
| P7 | Stall-multiplier abuse (artificial-stall 6x harvest) | economic-analyst | `AdvanceModule:226-242/156`; `AfKing:898-899` | NEGATIVE-VERIFIED | Gate-1 structural + Gate-2(a) fails | A |
| P8 | Mid-day partial-drain pinned mult=1 | economic-analyst | `AdvanceModule:193-224/217-218` | SAFE_BY_DESIGN | Gate-1 structural | A |
| P9 | Gameover path pinned mult=0 | economic-analyst | `AdvanceModule:183-188`; `AfKing:899` | SAFE_BY_DESIGN | Gate-1 structural | A |
| P10 | Bounty-stacking (two categories one tx) | economic-analyst | `AfKing:888-918` | SAFE_BY_DESIGN | invariant (a); Gate-1 structural | A |
| P11 | Faucet self-crank — buy leg | economic-analyst | `AfKing:850/864-865/891-893` | NEGATIVE-VERIFIED | Gate-2(a) fails (~99.999% loss) | A |
| P12 | Faucet self-crank — open leg + knee | economic-analyst | `AfKing:856/869/903-906` | NEGATIVE-VERIFIED | Gate-2(a) fails | A |
| P13 | Faucet self-crank — advance leg (re-homed, NOVEL) | economic-analyst | `AfKing:860/898-899` | NEGATIVE-VERIFIED | Gate-2(a) fails (~5-orders margin) | A |
| P14 | Self-exclude / ETH-work-gate present | economic-analyst | `AfKing:146/911-917` | SAFE_BY_DESIGN | Gate-1 structural | A |
| P15 | 30-min permissionless advance bypass | contract-auditor | `AdvanceModule:996` | NEGATIVE-VERIFIED | structural, unchanged | B |
| P16 | Vault free-fallback caller | contract-auditor | `DegenerusVault.gameAdvance():527` | NEGATIVE-VERIFIED | intact (not in delta) | B |
| P17 | Stonk free-fallback caller | contract-auditor | `StakedDegenerusStonk.gameAdvance():421` | NEGATIVE-VERIFIED | intact (not in delta) | B |
| P18 | 120-day death-clock anchors | contract-auditor | `AdvanceModule:109/509-521/1182-1883` | NEGATIVE-VERIFIED | intact | B |
| P19 | autoBuy-first ordering reaches advance | contract-auditor | `AfKing.doWork:883-910` | NEGATIVE-VERIFIED | invariant (c) re-attested | B |
| P20 | Standalone advanceGame() unrewarded | contract-auditor | `AdvanceModule:154/860` | NEGATIVE-VERIFIED | no keeper payee | B |
| P21 | OPEN-E 4-protection corroboration (GASOPT-05) | contract-auditor | `AfKing:388/397-400/667-670` | SAFE_BY_DESIGN (all 4 HOLD) | corroborates the 333-01 HARD blocking re-attestation | A |

### §C.3 FINDING_CANDIDATE write-up

**None.** Zero elevations survived the dual-gate. (Per CONTEXT D-04, had any MEDIUM+ survived, it would be
recorded here WITHOUT a contract fix — the subject is FROZEN at `4c9f9d9b` — and routed to the 333-04 closure
gate for USER adjudication, default leaning DEFER→v50 with the fix design locked.)

### §C.3a Advisories / coverage notes (NOT findings; do NOT amend the verdict — CONTEXT D-05)

- **Advance-leg faucet round-trip — test-coverage observation (not a finding).** `CrankFaucetResistance.t.sol`
  has dedicated round-trip tests for the buy leg (`:637`/`:676`) and the open leg (`:559`/`:607`) but NOT a
  dedicated advance-leg round-trip test; the advance-leg gas-ceiling test (`RouterWorstCaseGas.t.sol:549`)
  proves the worst-case fit but not the EV. The advance-leg EV margin is so large (advance×6 ≈ 10.62 gwei
  vs >150k gas = ~5 orders of magnitude) that this is NOT a coverage gap worth a finding — the buy/open
  round-trip tests already exercise the shared `(BOUNTY_ETH_TARGET·PRICE_COIN_UNIT)/mp` unit formula via the
  guard-the-guard `testRouterBuyRewardMatchesLiveUnitRatio:702`. Recorded as informational (corroborates the
  SWEEP-02 §3 attestation), carried to FINDINGS §4.3.
- **v48 SWAP cash-share advisory — carried-forward-unmodified** (CONTEXT D-05 / SC2): the v48 informational
  doc-drift (`SWAP cash-share ceiling 60% code vs ≤40% design memo`; no-arb holds; USER-accepted ≤60%
  canonical; NOT a finding). The SWAP path is outside the v49 blast radius (the delta-audit confirms none of
  the 5 v49 surfaces touched it). Recorded in 333-01 §7 + carried to FINDINGS §9d.

---

## §D — SKEPTIC-REVIEWER FILTER ATTESTATION

`/degen-skeptic` is OUT as a skill; the skeptic FUNCTION is this dual-gate, applied to EVERY elevation at two
points: (1) **per-skill self-arm** — each skill armed both lenses on its own candidates before returning; and
(2) **orchestrator integration-time re-application** — the orchestrator re-applied both lenses to every §B row
when assembling §C.

**The dual-gate:**
- **Gate 1 — structural-protection lens.** Does a structural mechanism already prevent the elevation? If yes →
  NEGATIVE-VERIFIED or SAFE_BY_DESIGN, NOT a finding.
- **Gate 2 — 3-condition EV lens.** (a) manifests WITHOUT an attacker / is positive-EV to execute; (b)
  magnitude is material; (c) severity survives the skeptical re-read. An elevation becomes a FINDING_CANDIDATE
  ONLY if it survives BOTH gates.

**Application result.** All 21 charged-probe rows were filtered. Every TIER-A row failed at least one gate:
the same-tx/MEV probes failed Gate-1 (the lock-gate + consume-before-unlock ordering is the structural
defense — invariant (b)) and Gate-2(a) (cannot manifest — `reverseFlip` reverts in-window); the bounty-economics
probes failed Gate-1 (the one-category `else-if` + single CEI-last `creditFlip` — invariant (a); the time-keyed
permissionless stall ladder) and Gate-2(a) (every leg is deeply -EV at every gas price ≥0.5 gwei — the
sub-gwei `BOUNTY_ETH_TARGET` keeps the faucet bound by ~5 orders of magnitude). The TIER-B rows were
re-attestations: reentrancy recorded SAFE_BY_DESIGN per the USER-locked 332 stance (no attacker harness
built); the liveness backstop NEGATIVE-VERIFIED (all free-fallback callers intact, D-04a). The OPEN-E
corroboration confirmed all 4 protections HOLD without the per-iter `:676` check (corroborating 333-01's HARD
blocking re-attestation).

**Self-discards recorded (genuine-hunt honesty):**
- zero-day-hunter chased the line-257 non-zeroing `totalFlipReversals` read as a possible same-tx asymmetry —
  self-discarded at Gate-1 (the read is inside the lock window; the single authoritative zero is in
  `_applyDailyRng` same call).
- economic-analyst chased the v49-novel re-homed advance-leg faucet and the max-escalation advance×6 ladder —
  self-discarded at Gate-2(a) (deep -EV at every mult); separately recorded the advance-leg round-trip
  test-coverage observation as an informational note (§C.3a), explicitly NOT elevated.

**Attestation: 0 FINDING_CANDIDATEs survived the dual-gate.** SWEEP-01 outcome = `0 NEW_FINDINGS`,
KNOWN_ISSUES_UNMODIFIED. Read-only throughout: `git diff 4c9f9d9b HEAD -- contracts/` empty; zero
`contracts/*.sol` edits across all 3 skills + the orchestrator integration.
