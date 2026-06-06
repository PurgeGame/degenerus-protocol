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
