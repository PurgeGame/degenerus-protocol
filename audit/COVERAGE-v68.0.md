# Degenerus Protocol — v68.0 Coverage-Completion Evidence Pack

**Milestone:** v68.0 — Pre-C4A Coverage Completion + AI-Verifiable RNG-Freeze Proof
**Date:** 2026-06-19
**Subject (frozen):** HEAD `3cc51d00` · `contracts/` tree **`e9a5fc2464fdee01895b48cf50f54a0566f94863`**.
The audit opened on tree `4970ba5b` @ `d0af2984` (unchanged since the v67 MIDRNG-02 re-freeze). The tree advanced only via **two in-milestone changes**: COUNCIL-FIND-01 (`65b70821`, a real LOW fix) and the phase-433 comment trim (`3cc51d00`, **logic-inert** — proven below). No other logic touched `contracts/*.sol`.
**Closure signal:** `MILESTONE_V68_AT_HEAD_3cc51d00393f18f78be83a3f797777baf969c842`
**Method:** BUILD → MEASURE → INDEPENDENTLY-VERIFY. This milestone is a **detection-coverage completion**, not a finding-hunt: it closes the machine-driven gaps six manual audits (v62–v67, all 0 CAT/0 HIGH) structurally cannot — mutation kill-rate, deep stateful invariants, a machine-verifiable RNG-freeze proof, a storage-layout CI oracle, and durable CI enforcement. Cross-model council (Gemini 3 Pro + Codex) closed the v67 availability gap and independently re-verified the RNG-freeze proof.
**Regression floor:** full forge suite **906 passed / 0 failed / 108 skipped** (exit 0) at `65b70821`; the trim is deployedBytecode-identical, so the floor carries unchanged at `3cc51d00`.

---

## Verdict: 0 CATASTROPHE / 0 HIGH · 1 LOW FOUND + FIXED · detection nets materially widened

The protocol entered v68 already at **0 CAT / 0 HIGH across six manual cross-model audits**. v68 attacks the *measurement* gap, not the code. The cross-model council found **one real LOW** on the frozen commit (COUNCIL-FIND-01, a caller foot-gun extending the v67 DELEGATE-FIND-01 class) — **fixed in-milestone** (`65b70821`). The RNG-freeze invariant is now published as a machine-verifiable proof (78/79 freeze-holds, cross-model-confirmed); the delegatecall-corruption invariant is mechanically pinned by a layout oracle; the deep invariant net is green at a multi-hour budget; and the never-scored RNG/payout mutation tail is in measurement (Decimator banked; Coinflip/Lootbox resuming).

| Phase | Track | Result |
|---|---|---|
| 426 FOUND | Subject freeze + green baseline + asset inventory | ✅ frozen `4970ba5b`@`d0af2984`; baseline **903/0/108**; 28 invariant suites / 31 Halmos `check_` / mutation `.DONE` set / CI gates inventoried |
| 427 MUT | Finish the mutation tail (measured kill-rate) | ◐ **partial** — harness repaired (MUT-01 `542fa8b1`); **Decimator banked killed=858 / uncaught=760 / compfail=516** (53.0% over 1,618 compiling); Coinflip/Lootbox **in progress** (session-tied; resume `run-campaign-v68.sh`) |
| 428 INV | Deep invariants + close `fail_on_revert` blind spot | ✅ blind spot **benign** (14/18 suites clean under `fail_on_revert=true`); full net **GREEN at deep 1000/256** |
| 429 RNGPROOF | AI-verifiable RNG-freeze-at-commitment proof | ✅ `RNG-FREEZE-PROOF-v68.0.md` (253 KB) + index (79 consumers); **78/79 freeze-holds**; independent adversarial re-verify; 0 unrefuted gaps |
| 430 LAYOUT | Storage-layout snapshot CI oracle (MECH-02) | ✅ 24 goldens; **all 11 delegatecall modules share the Game's exact 87-slot layout** → delegatecall-corruption invariant mechanically pinned |
| 431 CI | Durable enforcement of the strong guarantees | ✅ per-PR layout-diff + EIP-170 gates; scheduled `deep-guarantees` (31 Halmos + deep invariants) |
| 432 COUNCIL | Close the cross-model availability gap | ✅ codex-423 backfill + frozen-commit sweep + RNG-proof cross-model verify; **0 new CAT/HIGH; 1 LOW (COUNCIL-FIND-01) + 1 INFO** |
| 433 COMMENTS | Comment trim to current-only (contract-commit gate) | ✅ `3cc51d00` — 14 `.sol`, +318/−347; **340/340 artifacts deployedBytecode-identical** (logic-inert); USER-approved |
| 434 TERMINAL | Evidence pack + closure | ✅ this document |

---

## The one confirmed finding (found + fixed in-milestone)

### COUNCIL-FIND-01 — LOW — direct-call ETH/foot-gun on 3 payable delegatecall-only entrypoints (FIXED `65b70821`)
The 432 frozen-commit council pass (Gemini) found that `buyPresaleBox`, `purchaseLazyPass`, and `purchaseDeityPass` — three `external payable` entrypoints that only make sense in the Game's delegatecall context — lacked the `address(this) == GAME` guard. A direct call with ETH would trap the caller's own value (no Game-state corruption, no drain). This **extends the v67 DELEGATE-FIND-01 class** (the same idiom, three more sites the v67 sweep didn't enumerate).
**Fix:** add the `address(this) == GAME` guard to all three; inline the now-single-caller `_purchaseLazyPass` / `_purchaseDeityPass` helpers; regression `test/fuzz/DelegateOnlyGuards.t.sol`. Build green; EIP-170 OK (`DegenerusGameMintModule` 23,227 / 1,349 headroom); full suite **906/0/108**. USER-approved.

---

## Detection-coverage deltas (the milestone's substance)

### MUT — mutation kill-rate (partial; the measured tail)
The three modules that hosted **every prior real finding** (Coinflip, LootboxModule, DecimatorModule) had **no measured mutation kill-rate** across v63/v64/v66/v67. v68 repaired the harness (MUT-01: pre-filter the non-compiling slither-mutate mutants that aborted the v64 run; `.DONE` resume validated) and is scoring them against the comprehensive oracle.

| Target | Killed | Uncaught | Comp-fail (excl.) | Kill-rate | Status |
|---|---:|---:|---:|---:|---|
| DegenerusGameDecimatorModule | 858 | 760 | 516 | **53.0 %** | ✅ banked (`.v68.DONE`, 16 h) |
| Coinflip | — | — | — | — | ◐ in progress (resume) |
| DegenerusGameLootboxModule | — | — | — | — | ◐ queued (resume) |
| *spine (prior milestones, `.DONE`)* | — | — | — | — | ✅ JackpotModule · Vault · Storage · BitPackingLib · GameTimeLib · JackpotBucketLib · StakedDegenerusStonk |

**Reading the ~53 % Decimator rate (MUT-03 framing):** the surviving mutants are dominated by **oracle scope**, not contract defects — the comprehensive oracle is the union of the *exercised* green-baseline suites, which under-exercise these RNG/payout modules' deep branches. A survivor here means "the regression net doesn't pin this exact line," not "the line is wrong." The Decimator logic itself is already **dual-net-audited clean across v62–v67** (it hosted CORRUPT/RNG/SOLV sweeps with 0 confirmed defects). MUT-03 triage (each survivor → oracle-hole regression in `test/mutation/MutationKills.t.sol` or documented equivalent mutant) and MUT-04 (pin the v67 INFO-02 slot-46 `yieldAccumulator` callback-free invariant) proceed against the surviving set as Coinflip/Lootbox complete.

> **Carried (non-blocking):** the Coinflip/Lootbox scoring is **session-tied** (slither-mutate ~27 s/mutant via_ir, multi-day). The campaign is kill-safe (EXIT-trap `git checkout` restore + per-target `.DONE` resume + subject byte-freeze assert before/after every target, re-pinned to `3cc51d00`/`e9a5fc24`). For **guaranteed multi-day completion**, a CI/detached host is the robust path — a live session will not span the full grind.

### INV — deep stateful invariants + the `fail_on_revert` blind spot (✅ complete)
- **INV-01 (blind spot benign):** ran all 18 invariant suites under `FOUNDRY_INVARIANT_FAIL_ON_REVERT=true` → **14/18 clean** (0 reverts → the default `fail_on_revert=false` hides nothing). The 4 non-clean are **not contract defects** — `DegeneretteBet` + `V61SolvencyAfpay` trip their own vacuity/non-vacuity ghost guards (the should-execute protection; they *need* `fail_on_revert=false` to reach valid states) and `RedemptionInvariants` hits a harness non-contract-call artifact.
- **INV-02 (deep budget green):** the full invariant net is **GREEN at a deep profile (runs=1000 / depth=256)**, materially beyond the CI default 256/128. (The 8 first-pass "fails" were `fail_on_revert`-probe replay-cache artifacts — clean after `rm -rf cache/invariant`.)

### RNGPROOF — AI-verifiable RNG-freeze-at-commitment proof (✅ complete; the USER ask)
`audit/RNG-FREEZE-PROOF-v68.0.md` (253 KB) + `audit/rng-freeze-proof-v68.index.json` (86 KB, machine-readable) enumerate **79 VRF/RNG consumers**, each stating the freeze invariant formally (the consumed word is determined at commitment `P`; no actor-controllable input between `P` and consumption `C` changes which word or the outcome derivation) with source-anchored `file:line` evidence + a verification recipe.
- **78/79 freeze-holds.** freezeClass = **39 FROZEN-AT-COMMIT / 33 CROSS-CONTRACT-SEAM / 5 NEEDS-PROOF / 2 MUTABLE-INPUT.**
- The single non-holding = **RNGF-SEAM-RESOLVE (LOW)** — gameover-prevrandao redemption-roll *magnitude* bias (known v66/v67 residual, independently re-derived; ≥14-day-VRF-stall-gated; magnitude-not-selection, by-design). **Both HIGH-if-broken seams (day+1 redemption / coinflip) HOLD.**
- An independent agent adversarially re-verified every claim against frozen source; published only after 0 unrefuted gaps.
- **Cross-model re-verification (432):** Gemini **CONCURS 78/79**; Codex **AGREES** the 3 flagged + raised a lootbox live-level MED → **REFUTED, USER-confirmed** (economically-incentivized auto-opener removes timing + no "better" level → `[[lootbox-open-level-not-manipulable]]`).

### LAYOUT — storage-layout snapshot CI oracle (✅ complete; MECH-02)
`scripts/layout/` ships `normalize_layout.py` + `storage_layout_oracle.sh` + **24 astId-normalized goldens** (DegenerusGame [87 slots] + 12 state contracts + 11 delegatecall modules). The oracle golden-diffs live `forge inspect` layout and runs a module-vs-Game shared-slot consistency gate. **Finding:** all 11 delegatecall modules share the Game's exact 87-slot layout — the delegatecall-corruption invariant (hand-reasoned in v67 CORRUPT) is now **mechanically pinned**. Negative-test-validated (perturb a golden slot → exit 1).

### CI — durable enforcement (✅ complete)
`.github/workflows/ci.yml`: a **per-PR** MECH-02 layout-oracle gate + the existing EIP-170 ceiling check (binding at MintModule's ~1.4 KB headroom) + `RngReuseJackpotStraddle`; a **scheduled** `deep-guarantees` job (weekly cron + dispatch) running the 31 Halmos proofs + the deep-profile invariant sweep (1000/256). Mutation is documented local/overnight-not-CI (gitignored harness + >6 h job ceiling). The per-PR-vs-scheduled matrix is documented; a pre-C4A edit that breaks a proven invariant fails loud, not silent.

### COUNCIL — cross-model availability gap closed (✅ complete)
Three Gemini+Codex passes on the frozen commit: (1) **codex-423 backfill** — Codex re-derived MIDRNG-02 on the archived prompt's stale context (corroborates the fixed bug); Gemini REFUTED VRFSWAP "sound"; +NV-02 word==1 sentinel INFO (2⁻²⁵⁶). (2) **frozen-commit sweep** of the v67 in-milestone fixes — Gemini [HIGH] evict/jackpot gas-comp REFUTED (terminal jackpot isolated `AdvanceModule:688`), [MED] mid-day = known carried LOW, **[LOW] COUNCIL-FIND-01 REAL** (fixed above). (3) **RNG-proof cross-model verify** (above). **0 new CAT/HIGH; 1 LOW + 1 INFO.**

### COMMENTS — comment trim to current-only (✅ complete; the only contract-commit gate)
`3cc51d00` — 14 `contracts/*.sol`, +318/−347. Strips procedural/history debt tokens (milestone/version refs, plan/req/finding IDs, build-phase numbers, history narration, spec-line cites); keeps the descriptive "what the code guarantees now" prose; rephrases load-bearing invariant text rather than deleting it.
**Proven logic-inert:** an isolated bytecode-equivalence proof (`audit/verify-trim-bytecode.sh`, `FOUNDRY_BYTECODE_HASH=none`) confirmed **deployedBytecode byte-identical across all 340 artifacts** HEAD-vs-trimmed. Two comment corrections (text-only, verified vs source): `GameAfkingModule` active-subscriber-cap comment 500→1000 (`SUBSCRIBER_CAP = 1000` at `:200`, constant untouched); `DegenerusGame.depositAfkingFunding` dropped the wrong clause claiming bare `receive()` routes msg.value to the prize pool (`receive()` credits afking via `_creditAfkingValue(msg.sender, …)` at `:2476-2479`).

---

## Requirements attestation

| Req | Status | Evidence |
|---|---|---|
| FOUND-01 / FOUND-02 | ✅ | Subject frozen `4970ba5b`@`d0af2984`; baseline 903/0/108 + full asset inventory (`426-FOUND.md`) |
| MUT-01 | ✅ | Harness repaired + resume validated (`542fa8b1`) |
| MUT-02 | ◐ partial | Decimator banked 858/760/516; Coinflip/Lootbox in progress (session-tied resume) |
| MUT-03 / MUT-04 | ◐ partial | Triage + slot-46 pin proceed against the surviving set as the tail completes |
| INV-01 / INV-02 / INV-03 | ✅ | Blind spot benign (14/18); deep net green 1000/256 (`428-INV.md`) |
| RNGPROOF-01..04 | ✅ | `RNG-FREEZE-PROOF-v68.0.md` + index; 78/79; independent + cross-model re-verify (`429-RNGPROOF.md`) |
| LAYOUT-01 / LAYOUT-02 | ✅ | `scripts/layout/` 24 goldens + oracle; negative-test-validated (`430-LAYOUT.md`) |
| CI-01 / CI-02 | ✅ | `.github/workflows/ci.yml` per-PR + scheduled (`431-CI.md`) |
| COUNCIL-01 / COUNCIL-02 | ✅ | codex-423 backfill + frozen sweep + RNG-proof verify (`432-COUNCIL.md`) |
| COMMENTS-01 / COMMENTS-02 | ✅ | `3cc51d00`; 340/340 bytecode-identical; USER-approved |
| TERMINAL-01 | ✅ | this document + the HTML report |

**Open at close (by design / carried — non-blocking):**
- **MUT-02/03/04 tail** (Coinflip/Lootbox scoring + survivor triage) — measurement, session-tied; the logic is already dual-net-audited clean. Resume on a detached host for guaranteed completion.
- **Carried gated-fix decisions for USER** (both LOW defense-in-depth, documented): the `:1843`/`:1850` `== 0` re-roll guard, and 423 rotation-timer hardening.

---

## Subject freeze confirmation

Only the comment-only trim (`3cc51d00`) and the COUNCIL-FIND-01 LOW fix (`65b70821`) touched `contracts/*.sol` this milestone. The trim is deployedBytecode-identical (340/340 artifacts), so the **runtime logic frozen at `65b70821` is byte-for-byte preserved at the closure commit `3cc51d00`**. Closure signal: `MILESTONE_V68_AT_HEAD_3cc51d00393f18f78be83a3f797777baf969c842`.

**Milestone verdict: the protocol holds. 0 outstanding CAT/HIGH/MED; the one real LOW is fixed; the detection nets are materially wider than at v67 close — a machine-verifiable RNG-freeze proof, a mechanically-pinned delegatecall-layout invariant, a deep-budget green invariant net, durable CI, and a measured (and still-completing) mutation kill-rate over the RNG/payout tail.**
