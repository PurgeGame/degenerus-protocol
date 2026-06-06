# SPEC — v61.0 Design-Lock (open knobs · re-attested anchors · producer-before-consumer edit order)

**Baseline (frozen subject):** `2bee6d6f` (`2bee6d6faa2f66a9231d4b9bd01a53d09f40ff5e`, the v60.0 closure HEAD; confirmed an ancestor of the working-tree HEAD). Every contract anchor cited in this document is grounded on `2bee6d6f` via the re-attested table in §3, **not** the pre-attestation `~:NNN` values in `375-CONTEXT.md`.

**Role.** This is the single SPEC-01 deliverable for Phase 375. It (1) locks the open knobs D-01..D-05 plus the two SPEC verification items in writing, (2) folds the `2bee6d6f`-re-attested anchor table produced by Plan 01 (`375-ANCHOR-REATTESTATION.md`) so Phase 376 IMPL edits baseline-true lines, and (3) maps the producer-before-consumer edit order (Track A balances + Track B curse counter) for the ONE batched `contracts/*.sol` diff. With this document, Phase 376 authors that diff mechanically — no "by construction" assumptions, no mid-diff re-grep, no unsettled decision.

**Scope discipline.** Paper-only. This phase edits ZERO `contracts/*.sol`. The 17 contract requirements (AFPAY-01..07 · PACK-01/02 · CURSE-01..07 · SMITE-01) are authored at Phase 376 in the Track A / Track B order below; SEC-01/02 + TST-01..06 are proven empirically at Phase 378.

**Inputs (source of truth).** `375-ANCHOR-REATTESTATION.md` (the re-attested table + the three verification verdicts) · `375-CONTEXT.md` (`<decisions>` D-01..D-05 + the edit-order tracks) · `PLAN-V61-AFKING-AS-PAYMENT-SOURCE.md` · `PLAN-CASHOUT-CURSE.md` · `PLAN-V61-DEITY-SMITE.md` · `REQUIREMENTS.md` (the 17 contract REQ-IDs).

---

## 1. Locked Knobs

Each subsection restates the LOCKED value, its rationale, and the affected REQ-IDs. Values are the canonical ones from `375-CONTEXT.md` `<decisions>`; anchors are the re-attested `2bee6d6f` lines from §3.

### D-01 — Accessor-first PACK/AFPAY sequencing (LOCKED)

**Locked order.** The single 376 diff lands the **PACK accessor layer** FIRST — the reads `_claimableOf` / `_afkingOf` and the paired mutators `_creditClaimable` / `_debitClaimable` / `_creditAfking` / `_debitAfking` (each mutator pairs its balance change with the matching `claimablePool` update) — **together with the slot repack** `[afking:high128 | claimable:low128]`, and THEN the AFPAY waterfall is authored ONCE against those accessors.

**Edit order: PACK-01 → PACK-02 → AFPAY-01..07.**

**Rationale.** The `claimablePool == Σ(claimableWinnings + afkingFunding)` solvency invariant (SOLVENCY-01) is centralized in the accessor layer **before** the new afking spend path exists. The waterfall is then written once, reading/writing through the accessors, with no raw-mapping churn and no second pass to fold a feature into a repack. SEC-02 (378) re-proves the identity at ONE home (the accessor layer) rather than across the scattered debit/credit sites enumerated in §3 (SOLVENCY).

**Supersession (reconciliation, NOT a conflict).** This order explicitly **supersedes** the "feature-first" wording in `PLAN-V61-MILESTONE-SCOPE.md` §2 and the `REQUIREMENTS.md` PACK-02 line ("Folded **feature-first** after AFPAY"). Both documents **deferred the exact feature-first-vs-accessor-first choice to SPEC-01** — so locking the accessor-first order here is the intended resolution of that deferral, not a contradiction of it. Downstream (376) MUST treat any "feature-first" phrasing as superseded by this D-01 accessor-first lock. (REQUIREMENTS.md PACK-02 itself closes with "exact feature-first vs accessor-first sequencing locked at SPEC-01" — this is that lock.)

**Affected REQ-IDs:** PACK-01, PACK-02, AFPAY-01..07.

### D-02 — `AfkingSpent` at every afking debit (LOCKED)

**Locked breadth.** Emit `AfkingSpent(address indexed player, uint256 amount)` at **EACH** afking draw — both in `_processMintPayment` (the ticket-mint path) **AND** in the shared `_settleShortfall` helper (the whale / presale / lootbox paths). This is the **broad** option, not the narrower `_processMintPayment`-only emission.

**Deliberate departure (call out at IMPL).** This is an intentional departure from how **claimable** spends stay silent outside `_processMintPayment`: claimable draws on the shortfall paths emit nothing, but afking draws on those same paths DO emit `AfkingSpent`. The afking event is the milestone's headline-feature transparency signal — full observability of where afking principal gets spent — so the asymmetry is by design. The extra `LOG` rides shortfall-funded buys (off the `advanceGame` hot path) → marginal gas.

**Affected REQ-IDs:** AFPAY-07 (declared in `DegenerusGameStorage.sol`, visible to game + all modules; emitted at each afking debit).

### D-03 — `CURSE_COUNT_CAP = 20` points (LOCKED)

**Locked value.** The `uint8` curse counter (`mintPacked_` bits 215-222) saturates at **20 points** — 10 ghost-cashouts at +2 each (or 10 deity-smite stacks), for a −2000 bps maximum activity-score penalty.

**Double-duty.** The cap **is** the mandatory uint8-wrap guard: a `+= 2` increment must never wrap a `uint8` 254→0, so the SET (CURSE-03) and SMITE (SMITE-01) both check `curse >= CURSE_COUNT_CAP` and skip the SSTORE when already capped. Clean headroom above the **5-stack (10-point) smite ceiling** — a smiter cannot push past 10 points via smite, while the cashout path can reach the 20-point cap, so the two sources share one saturating field without either being able to wrap it.

**Affected REQ-IDs:** CURSE-07 (cap home, `MintStreakUtils`), CURSE-02 (the `curse * 100` bps APPLY the cap bounds), CURSE-03 / SMITE-01 (the increment sites guarded by the cap).

### D-04 — Protocol-addr skip kept (LOCKED)

**Locked behavior.** Both `smite()` and the cashout-curse SET (`_maybeCurse`) skip the protocol addresses `VAULT` / `SDGNRS` / `GNRUS` via **constant compares (no SLOAD)** — these addresses are never cursed.

**Rationale.** The sDGNRS redemption snapshot reads the activity score at `StakedDegenerusStonk.sol:932` (re-attested — see §3; `375-CONTEXT.md` cited `~:942`, which drifted −10). A curse on `SDGNRS` would corrupt that redemption-snapshot score. The skip also keeps the two curse sources consistent (cashout + smite skip the same set) and prevents a deity wasting 200 BURNIE smiting a non-player address. The skip is for the redemption-snapshot integrity reason; it is **independent of** the self-smite verdict (a deity may still self-smite — see Verification Item 2 — that is harmless and unrelated to the protocol-addr skip).

**Affected REQ-IDs:** CURSE-03 (the `_maybeCurse` infra bail), SMITE-01 (the smite protocol-addr bail).

### D-05 — Staleness day-basis = `_currentMintDay()` (LOCKED)

**Locked basis.** The `_maybeCurse` staleness compare — `lastEthDay + 5 > _currentMintDay()` — uses `_currentMintDay()`, **not** `_simulatedDayIndex()`. This is the basis already used by the `PLAN-CASHOUT-CURSE.md` §3 SET sketch and by the ticket cure-stamp, so the staleness check and the ticket stamp share one day basis.

**Rationale.** The ≤1-day skew between `_currentMintDay()` and `_simulatedDayIndex()` is immaterial against the 5-day staleness window (`PLAN-CASHOUT-CURSE.md` §Accepted edges). Low-stakes builder call (D-05 is Claude's-discretion in `375-CONTEXT.md`); user did not object.

**Affected REQ-IDs:** CURSE-03 (the `_maybeCurse` staleness compare).

### Verification Items (Plan 01 verdicts folded)

These two items had no decision to make — they were facts to confirm at SPEC. Plan 01 resolved both against `2bee6d6f`; the verdicts are folded here and cited to `375-ANCHOR-REATTESTATION.md`.

**`purchaseWith`-dead — VERDICT: DEAD → leave untouched at IMPL.** `DegenerusGameMintModule.sol` `purchaseWith` (def @ **858**, re-attested) is **not reachable in production** at `2bee6d6f`. Five total references: the def (`MintModule:858`), the interface entry (`IDegenerusGameModules:242`), and 3 stale doc-comments (`AdvanceModule:759`, `MintModule:1122`, `GameAfkingModule:1097`). The `.selector` / call-site / dispatch grep returned only a parenthetical inside a comment — **no `purchaseWith.selector`, no delegatecall dispatch stub, no call site** anywhere in `contracts/`. Since the function is `external` and reachable only through the Game's delegatecall dispatch table, and no dispatch stub references its selector, it is unreachable. **Consequence for AFPAY:** the waterfall lands inside the live buy host `_purchaseForWith` (`:1093`) and `_processMintPayment` (`DegenerusGame.sol:1054`), NOT via this dead `purchaseWith` entry. No live-site wiring required; leave `purchaseWith` untouched. (Source: `375-ANCHOR-REATTESTATION.md` §"`purchaseWith` Dead-Confirm".)

**Self-smite — VERDICT: HARMLESS-BY-DESIGN → no guard required.** A deity paying 200 BURNIE to `smite` their OWN address adds a curse stack to themselves. This is harmless: (1) the shared `uint8` curse counter only ever **lowers** the activity score (single APPLY @ `MintStreakUtils:320 scoreBps = bonusBps`, with `curse * 100` bps subtracted, floored at 0) — there is no game path where a lower score benefits a player; (2) `smite` burns the caller's OWN 200 BURNIE via `burnCoin(msg.sender, PRICE_COIN_UNIT/5)` (`BurnieCoin:572 onlyGame`) — a pure sink, no ETH/claimable/mint/prize-pool touch; (3) `_bountyEligible` (`MintStreakUtils:30`) does not read the curse counter, and the counter feeds only the score APPLY — so there is no bounty/keeper/score-floor path that a higher self-`curseCount` could unlock or inflate; (4) the 5-stack smite ceiling and the 1-ticket self-cure apply identically to self-smite, so no self-referential loop accrues anything positive. **No anti-self-smite guard is required.** (The D-04 protocol-addr skip still applies to VAULT/SDGNRS/GNRUS for the redemption-snapshot reason — unrelated to self-smite.) Matches the STRIDE register disposition (accept). (Source: `375-ANCHOR-REATTESTATION.md` §"Self-Smite Sanity".)

### Hard Floor (carried into every IMPL edit)

Every change in the 376 diff sits above this floor (`375-CONTEXT.md` `<specifics>`):

- **RNG-freeze intact.** All three work items read NO `rngWord` — AFPAY is ledger-only, CURSE/SMITE touch only the activity-score path (view-only read, score-lowering write on a successful access-controlled claim). No player-manipulable VRF-derived read or write is added. Proven empirically at SEC-01 (378).
- **SOLVENCY-01 centralized.** `claimablePool == Σ(claimableWinnings + afkingFunding)` is centralized in the PACK accessor layer (D-01 lands it FIRST, which makes the identity cleaner — one home instead of scattered debit/credit sites). afking already rides inside `claimablePool`; each afking debit pairs a `claimablePool -=` (pool-neutral, contract balance unchanged); the PACK `uint128` halves are width-safe (per-player ETH ≤ supply ≪ 2^128). Re-proven at SEC-02 (378), anchored on the accessor-layer home pinned in §3 (SOLVENCY).

---

## 2. CONTEXT.md → re-attested corrections the 376 diff MUST adopt

Plan 01 re-grounded every cited `file:line` on `2bee6d6f` (29 anchors across 13 files; full table in §3). **4 anchors drifted materially** from the pre-attestation `~:NNN` in `375-CONTEXT.md` and MUST be cited at the baseline line everywhere in this SPEC and at IMPL:

| # | Symbol | `375-CONTEXT.md` cited | Re-attested @ `2bee6d6f` | Note |
|---|---|---|---|---|
| 1 | `claimablePool` `uint128` decl | `~:838-839` | **`:365`** (decl) | The cited `~:838-839` is the `_setCurrentPrizePool` width-safety doc-comment (the `uint256→uint128` "~1.2e26 wei ≪ 2^128" prose), NOT the decl. The SOLVENCY invariant comment is at `:358`; the decl is at `:365`. The PACK §6 "same justification as `claimablePool` being `uint128`" reuses the `:838-842` width prose — but the **decl** itself is `:365`. |
| 2 | cure-site host fn | `_purchaseWithFor` `~:1285` | **`_purchaseForWith` @ `:1093`** | **Name transposition.** There is NO `_purchaseWithFor` symbol at the baseline. The live ETH-in buy host is `_purchaseForWith` (def `:1093`, body to `:1419`); the cited line `:1285` sits inside its body. CURSE-04 cure + the AFPAY waterfall land in `_purchaseForWith`. **IMPL MUST use the name `_purchaseForWith`** — steering 376 to `_purchaseWithFor` would name a non-existent symbol. |
| 3 | `_recordLootboxMintDay` | `~:983` | **`:1000`** (def; call site `:858`) | Drifts +17. The relocate-to-`MintStreakUtils`-base target (CURSE-05) is the def at `:1000`. |
| 4 | sDGNRS redemption activity-score read | `~:942` | **`:932`** | Drifts −10. `claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;` (inside the `if (claim.activityScore == 0)` snapshot). This read is the reason D-04 keeps the protocol-addr skip. |

All other anchors re-attested CONFIRMED at/within a few lines of their cite (the baseline is an ancestor of the 2026-06-06 doc-HEAD the CONTEXT.md `~:NNN` were grepped against). The 4 to-be-added symbols (`AfkingSpent`, `decurse`/`smite`, `CURSE_COUNT_CAP`, `MASK_8`/`CURSE_COUNT_SHIFT`) are correctly ABSENT at the baseline.

---

## 3. Re-attested anchor table (grounded on `2bee6d6f`)

This table is folded from `375-ANCHOR-REATTESTATION.md` so the SPEC is self-contained for the 376 diff. Every anchor is grounded on `2bee6d6f` (read FROM the baseline via `git grep` / `git show`, not from the working tree, which is ahead). Status = CONFIRMED (symbol at/within a few lines of the cite) or CORRECTED (baseline line differs materially — cite the baseline line). The 4 CORRECTED rows are the §2 corrections.

### `contracts/storage/DegenerusGameStorage.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| `_settleClaimableShortfall` (the `_settleShortfall` generalization target, AFPAY-01) | CONFIRMED | def **851**; paired `claimablePool -= uint128(shortfall)` **857** |
| `claimablePool` `uint128` decl | **CORRECTED** | decl **365** (cited `~:838-839` is the `_setCurrentPrizePool` doc-comment); SOLVENCY invariant comment **358** |
| SOLVENCY identity comment `claimablePool == Σ claimableWinnings[*] + Σ afkingFunding[*]` | CONFIRMED | **358** |
| `AfkingSpent` event decl (AFPAY-07/D-02) | ABSENT (expected) | — (added by AFPAY-07) |
| `PRICE_COIN_UNIT` (`decurse` 100 / `smite` 200 BURNIE basis) | CONFIRMED | **162** (`= 1000 ether`) |

### `contracts/DegenerusGame.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| `_processMintPayment` (AFPAY-02) | CONFIRMED | def **1054**; sole call site **474** |
| `_resolvePlayer` (auth chokepoint, self-or-approved-operator) | CONFIRMED | def **573** |
| `claimWinnings` (CURSE-03 SET host, the ghost-cashout +2) | CONFIRMED | def **1556** |
| public `playerActivityScore` view (CURSE-07) | CONFIRMED | def **2701** (delegates to `_playerActivityScore` **2709**) |
| post-gameOver claim-merge (PACK touches one slot) | CONFIRMED | **1575-1595**; dual zeroing + single `claimablePool -= uint128(payout)` **1589** |
| `decurse` / `smite` new Game dispatch stubs | ABSENT (expected) | insertion neighborhood = `claimAfkingBurnie:413` (delegatecall pattern to mirror) |

### `contracts/modules/DegenerusGameMintModule.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| `purchaseWith` (dead-confirm — see Verification Item 1) | CONFIRMED | def **858** (forwards to `_purchaseForWith`) — **DEAD** |
| **cure host `_purchaseForWith`** (CURSE-04 cure + AFPAY waterfall host) | **CORRECTED** | def **1093** (body to `:1419`); `375-CONTEXT.md` `_purchaseWithFor ~:1285` is a name transposition + the `:1285` line is inside the body |
| Lootbox shortfall `_settleClaimableShortfall` call (AFPAY-03) | CONFIRMED | call **1143**; `DirectEth → revert E()` guard `~1138`; `lootboxFreshEth`/`lootboxClaimableUsed` bookkeeping 1135-1146 |
| Presale box `_settleClaimableShortfall` call (AFPAY-04) | CONFIRMED | call **1489** |
| Ticket affiliate split (AFPAY-06) | CONFIRMED | `payAffiliate` branches **1655/1665/1675/1684**; `coinCost` **1600/1695**; bonus `coinCost/10` **1697** |
| plain standalone lootbox leg (CURSE-05 stamp target) | CONFIRMED | payment block 1135-1146 + ticket leg through `~1254` (all inside `_purchaseForWith`) |
| `IDegenerusGameModules` `purchaseWith` interface entry (dead ref) | CONFIRMED | `contracts/interfaces/IDegenerusGameModules.sol:242` |

### `contracts/modules/DegenerusGameWhaleModule.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| whale bundle `_settleClaimableShortfall` (AFPAY-04) | CONFIRMED | **263** |
| lazy pass `_settleClaimableShortfall` (AFPAY-04) | CONFIRMED | **490** |
| deity pass `_settleClaimableShortfall` (AFPAY-04) | CONFIRMED | **596** (all 3 EXACT — AFPAY-01's generalized `_settleShortfall` replaces all three at once) |
| `_recordLootboxMintDay` (relocate → `MintStreakUtils` base, CURSE-05) | **CORRECTED** | def **1000** (cited `~:983`); call site **858** |

### `contracts/modules/DegenerusGameDegeneretteModule.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| `_collectBetFunds` (AFPAY-05; preserve the `InvalidBet()` revert) | CONFIRMED | def **573** (within cited 579-588 window); call site **468**; `InvalidBet()` reverts 498-500/562-566 |

### `contracts/modules/DegenerusGameMintStreakUtils.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| `_playerActivityScore` (3-arg chokepoint — the curse-penalty host) | CONFIRMED | def **241** (`(player, questStreak, streakBaseLevel)`); 2-arg wrapper **327** |
| CURSE APPLY site `scoreBps = bonusBps` (CURSE-02) | CONFIRMED | **320** (EXACT — CURSE-02 subtracts `curse*100` bps here) |
| `packed` load (zero-new-SLOAD for CURSE-02) | CONFIRMED | **248** (`uint256 packed = mintPacked_[player];` — curse counter rides this SLOAD) |
| `_bountyEligible` | CONFIRMED | def **30** |
| `CURSE_COUNT_CAP` (CURSE-07/D-03 `= 20`) | ABSENT (expected) | — |

### `contracts/modules/DegenerusGamePayoutUtils.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| the 2 centralized claimable credits (PACK-01 routes through `_creditClaimable`) | CONFIRMED | `_addClaimableEth` `claimableWinnings[beneficiary] += weiAmount` **25** + paired `claimablePool += uint128(boxEth)` **39**; second credit `claimableWinnings[winner] += remainder` **63** |

### `contracts/modules/GameAfkingModule.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| afking auto-buy own spend (OUT of scope — no-double-draw boundary) | CONFIRMED | `_deliverAfkingBuy` def **777**; debit `afkingFunding[src] -= ethValue` + paired `claimablePool -= uint128(ethValue)` **~791-792**; `_processMintPayment` ref count in this module = **0** (auto-buy isolated from the manual chain) |

### `contracts/libraries/BitPackingLib.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| `AFFILIATE_BONUS_POINTS_SHIFT` (ends bit 214) | CONFIRMED | `= 209` (line 82), `MASK_6` → [209-214] |
| `LEVEL_UNITS_SHIFT` (= 228) | CONFIRMED | `= 228` (line 85), `MASK_16` → [228-243] |
| `[215-222]` free gap for `CURSE_COUNT_SHIFT = 215` | CONFIRMED (empirical) | header doc line 22: `[215-227] (unused)`; all 12 `mintPacked_` writers field-isolated RMW (`setPacked` keystone) → no clobber of 215-222 |
| `MASK_8` (CURSE-01) | ABSENT (expected) | — (existing masks MASK_1/2/6/16/24/32) |
| `CURSE_COUNT_SHIFT` (CURSE-01 `= 215`) | ABSENT (expected) | — |

### `contracts/DegenerusDeityPass.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| `ownerOf(deityId)` smite gate (soulbound, `tokenId = symbolId` 0-31) | CONFIRMED | `ownerOf(uint256 tokenId) external view` **335**; transfers `revert Soulbound()` 354-370 |

### `contracts/BurnieCoin.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| `burnCoin` (`onlyGame`; `decurse` 100 / `smite` 200 BURNIE sinks) | CONFIRMED | **572**; `onlyGame` modifier **497** |

### `contracts/StakedDegenerusStonk.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| redemption-snapshot activity-score read (the reason D-04 keeps the protocol-addr skip) | **CORRECTED** | **932** (cited `~:942`); `claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;` inside the `if (claim.activityScore == 0)` snapshot at 931 |

### `contracts/test/SettleClaimableShortfallTester.sol`

| Symbol | Status | @ `2bee6d6f` |
|---|---|---|
| `_settleShortfall`-signature consumer (test-side, free to commit) | CONFIRMED | calls `_settleClaimableShortfall(buyer, basis, shortfall)` **39** → update to the new `_settleShortfall(buyer, shortfall, allowClaimable) → (claimableUsed, afkingUsed)` signature |

**SOLVENCY accessor-invariant home (Verification Item 3 → SEC-02 anchor).** The `claimablePool == Σ(claimable + afking)` identity is centralized in the **PACK accessor layer** (D-01: `_creditClaimable` / `_debitClaimable` / `_creditAfking` / `_debitAfking`, each paired with `claimablePool`). The pre-existing scattered enforcement points the accessor layer subsumes re-attest to: the invariant statement @ `DegenerusGameStorage.sol:358` + the `claimablePool` decl @ **365** + the canonical `_settleClaimableShortfall` @ **851** (→ `_settleShortfall` at IMPL) + the 2 `DegenerusGamePayoutUtils` credits @ **25/39/63** + the `GameAfkingModule` afking credit/debit pair (`afkingFunding[fundDest] += msg.value` @ **337**, `afkingFunding[src] -= ethValue` + paired `claimablePool -=` @ **~791**). SEC-02 (378) anchors here — ONE home, not the scattered sites. (Source: `375-ANCHOR-REATTESTATION.md` §"SOLVENCY Accessor-Invariant Location".)

---

## 4. Producer-before-consumer edit-order map

The 376 diff is authored in two **independent tracks**. Track A touches the **claimable/afking balances mapping**; Track B touches the **`mintPacked_` curse counter** — a DIFFERENT storage slot. The two tracks may be authored in either relative order (they touch different slots — see the cross-check), but **WITHIN each track the producer precedes the consumer**.

### Track A — balances mapping (PACK accessor → repack → AFPAY waterfall → event)

**Order: PACK-01 → PACK-02 → AFPAY-01 → AFPAY-02..06 → AFPAY-07.**

1. **PACK-01** — Accessor layer: `_claimableOf` / `_afkingOf` reads + `_creditClaimable` / `_debitClaimable` / `_creditAfking` / `_debitAfking` (each paired with the `claimablePool` update). Route all `claimableWinnings` / `afkingFunding` refs (4 claimable credits + ~8 debits + ~80 reads; 31 afking refs) through it so SOLVENCY-01 lives in ONE place. Precedent: `PLAN-PLAYERQUESTSTATE-1SLOT-PACKING.md`.
2. **PACK-02** — Repack the two balances into one `uint256` mapping `[afking:high128 | claimable:low128]`; math in `uint128` halves, recombine via `(uint256(afking) << 128) | claimable` (NO naive full-word `packed += x` — 0.8's 256-bit check misses a 127→128 carry; no explicit overflow `require` needed since each half stays a clean `uint128`). Preserve the gameOver VAULT/SDGNRS/GNRUS afking half during claimable-zeroing (via the accessor). `src != player` (operator-funded auto-buy) cases stay two addresses (no regression).
3. **AFPAY-01** — Generalize `_settleClaimableShortfall` (`:851`) → `_settleShortfall(buyer, shortfall, allowClaimable) → (claimableUsed, afkingUsed)`: claimable to the 1-wei sentinel (only if `allowClaimable`), then the remainder from afking (no sentinel, to 0), revert if both short, pair every debit with `claimablePool -=`, drop the stale `basis` param. Covers lootbox + presale + the 3 whale sites at once. (Authored against the PACK accessors from step 1.)
4. **AFPAY-02..06** — The spend paths, authored ONCE against the accessors + the generalized helper:
   - AFPAY-02: `_processMintPayment` (`DegenerusGame.sol:1054`) — afking tier on all 3 pay-kinds; `prizeContribution = msg.value + claimableUsed + afkingUsed`.
   - AFPAY-03: lootbox shortfall (`MintModule:1126-1146`) — `_settleShortfall(buyer, shortfall, payKind != DirectEth)` (lifts the DirectEth→revert at `~1138`); `lootboxFreshEth += afkingUsed`, `lootboxClaimableUsed = claimableUsed`. **(Lands in `_purchaseForWith`, def `:1093`.)**
   - AFPAY-04: presale box (`MintModule:1489`) + whale/lazy/deity pass (`WhaleModule:263/490/596`) via the shared `_settleShortfall`.
   - AFPAY-05: Degenerette `_collectBetFunds` (`DegeneretteModule:573`) — cover the remainder from afking after the claimable-to-sentinel draw; keep the `InvalidBet()` revert.
   - AFPAY-06: the fresh/recycled affiliate split (`MintModule:1620-1692`) — `freshEth = costWei − claimableUsedTicket` so afking lands in fresh (byte-identical for the no-afking cases); fresh-rate affiliate incl. lootbox activity score; NO rebuy bonus (the bonus block reads `claimableWinnings` deltas → afking excluded automatically).
5. **AFPAY-07** — `AfkingSpent(address indexed player, uint256 amount)` declared in `DegenerusGameStorage.sol`, emitted at EACH afking debit per D-02 (both `_processMintPayment` AND `_settleShortfall`).

**Why accessor-first (D-01):** the SOLVENCY-01 invariant home (the accessor layer) exists BEFORE the afking spend path is written, so the waterfall is authored once with no raw-mapping churn and SEC-02 re-proves the identity at ONE home.

### Track B — `mintPacked_` curse counter (CURSE infra → SMITE)

**Order: CURSE-01 → CURSE-02 → CURSE-03 → CURSE-04 → CURSE-05 → CURSE-06 → CURSE-07 → SMITE-01.**

1. **CURSE-01** — `BitPackingLib`: add `CURSE_COUNT_SHIFT = 215` (uint8, the documented `[215-222]` free gap; `AFFILIATE_BONUS_POINTS` ends 214, `LEVEL_UNITS_SHIFT = 228`) + `MASK_8 = 0xFF`; update the layout doc comment. (Empirically clobber-free — §3 BitPackingLib row: all 12 `mintPacked_` writers field-isolated RMW.)
2. **CURSE-02** — APPLY in `_playerActivityScore` just before `scoreBps = bonusBps` (`:320`); `packed` already loaded at `:248` → zero new SLOAD: `penaltyBps = curse * 100; bonusBps = bonusBps > penaltyBps ? bonusBps - penaltyBps : 0;`. Propagates to every consumer + the public view + frozen snapshots. **(Producer for CURSE-03/SMITE-01 — the penalty must read the counter before anything writes it.)**
3. **CURSE-03** — SET: new `_maybeCurse(player)` from the public `claimWinnings` (`:1556`) after a successful `_claimWinningsInternal`. Cheapest-first bails: infra (D-04 VAULT/SDGNRS/GNRUS constant compares) → gameOver → non-stale (D-05 `lastEthDay + 5 > _currentMintDay()`) → deity-pass → whale/lazy pass → active afker → already at cap (D-03); else `curse += 2` (saturating) + SSTORE.
4. **CURSE-04** — CURE: reset `curseCount = 0` when `totalCost >= priceWei` in **`_purchaseForWith`** (the CORRECTED host name — `375-CONTEXT.md` `_purchaseWithFor` was a transposition), before the score calc at `:1285`, folded into the existing `mintPacked_` RMW with NO write-after-write clobber against the leg stamps.
5. **CURSE-05** — Wire the plain standalone lootbox leg (in `_purchaseForWith`, ~1170-1254) through `_recordLootboxMintDay` (relocated `WhaleModule` private → `MintStreakUtils` base; def **1000**, the CORRECTED line) so manual lootbox buyers stamp `DAY_SHIFT`.
6. **CURSE-06** — `decurse(address target)`: permissionless; revert if curse already 0; `coin.burnCoin(msg.sender, PRICE_COIN_UNIT / 10)` (100 BURNIE); clear `curseCount = 0`; `emit Decursed(msg.sender, target)`.
7. **CURSE-07** — `curseCountOf(address)` view; carries `CURSE_COUNT_CAP = 20` (D-03).
8. **SMITE-01** — `smite(uint256 deityId, address smitee)`: gate `IDegenerusDeityPass(DEITY).ownerOf(deityId) == msg.sender` (`:335`); validate BEFORE the burn (active-afker = sole immunity; `curseCount >= 5 stacks` ceiling; D-04 protocol-addr skip); `burnCoin(msg.sender, PRICE_COIN_UNIT / 5)` (200 BURNIE); `curseCount += 2` saturating at the shared cap; `emit Smited(deityId, smitee)`. **Lands with/after the CURSE infra** — it shares the counter (CURSE-01), the cap (D-03/CURSE-07), and the APPLY (CURSE-02), so the whole CURSE chain must precede it.

### Cross-check — CURE-vs-PACK-repack write-after-write safety

CURSE-04 (CURE) fires inside **`_purchaseForWith`** — a buy path that the **Track A** AFPAY waterfall also touches. This is safe:

- CURE mutates `mintPacked_[player]` **curse bits** (215-222) — the `mintPacked_` slot.
- The PACK repack (PACK-02) mutates the **balances mapping** — a DIFFERENT storage slot.

→ Track A (balances mapping) and Track B (`mintPacked_`) touch **DIFFERENT storage slots** → there is **no write-after-write conflict** between the CURE and the PACK repack, even though both execute on the same `_purchaseForWith` buy path. The two tracks are therefore **independent** and may be authored in either relative order. (Within Track B, CURSE-04's own fold into the `mintPacked_` RMW must additionally avoid clobbering the leg-specific stamps `recordMintData` / `_recordLootboxMintDay` — a Track-B-internal RMW discipline, not a cross-track hazard. Empirical clobber-freedom of bits 215-222 across all 12 `mintPacked_` writers is established in §3.)
