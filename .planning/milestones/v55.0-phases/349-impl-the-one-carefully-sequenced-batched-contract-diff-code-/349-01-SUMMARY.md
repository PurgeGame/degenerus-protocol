---
phase: 349-impl-the-one-carefully-sequenced-batched-contract-diff-code-
plan: 01
subsystem: code-size-reclaim (ARCH-04 Step 1 of the single batched v55.0 fold diff)
tags: [arch-04, code-size, claimAffiliateDgnrs, bingo-module, re-pin-attestation]
requires:
  - "the live tree's contracts/ == the v54 de-custody HEAD 20ca1f79 (SPEC baseline) — CONFIRMED EMPTY diff"
provides:
  - "claimAffiliateDgnrs heavy body relocated OUT of the DegenerusGame image into DegenerusGameBingoModule (the ~1.2 KB reclaim; only a ~80 B thin dispatch stub remains in the Game)"
  - "the re-pin attestation of every 349-touched anchor vs the live tree (for 349-02..05 to inherit)"
  - "the Task 3 R2/R3 insurance DECISION: deferred to 349-05 pending the authoritative forge build --sizes"
affects:
  - contracts/DegenerusGame.sol
  - contracts/modules/DegenerusGameBingoModule.sol
  - contracts/interfaces/IDegenerusGameModules.sol
tech-stack:
  added: []
  patterns:
    - "Game→module relocation via the existing GAME_BINGO_MODULE delegatecall dispatch-stub lane (mirror of claimBingo :328-344)"
key-files:
  created: []
  modified:
    - contracts/DegenerusGame.sol
    - contracts/modules/DegenerusGameBingoModule.sol
    - contracts/interfaces/IDegenerusGameModules.sol
decisions:
  - "R1 reclaim is a MOVE-WITH-THIN-STUB, not a true void — the SPEC's 'callable directly on the module, no Game stub' premise is broken for claimAffiliateDgnrs because its body makes onlyGame / onlyFlipCreditors external calls (Rule 1 auto-fix; reclaim intent fully preserved)"
  - "Task 3 (R2/R3 view-drop insurance) DEFERRED to 349-05 pending the measured forge build --sizes — R1 alone covers the stub budget in the central case; either path is SPEC-acceptable"
metrics:
  duration: ~7m (440s)
  completed: 2026-05-30
  tasks_completed: 3
  files_modified: 3
---

# Phase 349 Plan 01: Code-Size Reclaim FIRST (R1 claimAffiliateDgnrs → BingoModule) + Re-Pin Attestation Summary

**One-liner:** Re-pinned every 349-touched anchor against the live tree (== `20ca1f79`, zero drift), then relocated the ~1.2 KB `claimAffiliateDgnrs` heavy body out of the `DegenerusGame` image into `DegenerusGameBingoModule` (leaving a thin delegatecall dispatch stub — NOT a true void, because the body makes `onlyGame`/`onlyFlipCreditors` calls that must run in the Game's context), clearing the 218 B EIP-170 headroom before any ARCH-03 stub is added in 349-05. All edits uncommitted (contract-boundary hold).

---

## ⛔ Git posture — NOTHING COMMITTED (mandatory for this whole phase)

Per the v55.0 milestone discipline and the executor's hard constraint, **NO git mutation ran** — no `git commit`, `git add`, `git rm`, `git stash`, `git reset`, `git checkout -- <file>`, or `git restore`. The single batched 349 contract diff is HELD for explicit USER approval; the orchestrator owns that commit gate (deferred past 349-05). Only read-only `git diff` / `git status` / `git log` + `grep`/read + the repo's read-only structural-check scripts were used. This SUMMARY is written with the Write tool and left **uncommitted**.

---

## Task 1 — [BLOCKING-FIRST] Re-Pin Attestation (the 343/344 hand-off discipline) — INHERITED BY 349-02..05

### Baseline gate (the SPEC-baseline floor)

```
$ git diff --numstat 20ca1f79 HEAD -- contracts/      → EMPTY (0 files)
$ git diff --name-only 20ca1f79 HEAD -- contracts/     → EMPTY
30 commits since 20ca1f79 — ALL docs-only (.planning/ markdown)
$ grep -rn "subsFullyProcessed" contracts/             → 0 matches (CONFIRMED-NEW; 349 authors it)
```

- **`git diff --numstat 20ca1f79 HEAD -- contracts/` is EMPTY** ⇒ the live working tree's `contracts/` is byte-identical to the v54 de-custody HEAD `20ca1f79` (the v55.0 audit baseline). The 348 grep-attestation is therefore CURRENT; this re-grep is the discipline floor, not a known-drift fix. The "baseline non-empty → re-derive" branch was NOT hit.
- **`subsFullyProcessed` absent repo-wide (0)** — CONFIRMED-NEW; 349 (Step 4 of the edit-order map) authors it.
- Plan verify command emitted: **`BASELINE-CLEAN subsFullyProcessed-ABSENT`** ✅

### Re-pinned anchors — every symbol the 349 diff touches (matched line + text, drift noted)

**ZERO line-number drift vs the 348-GREP-ATTESTATION `20ca1f79` snapshot — every anchor MATCHES** (this plan ran before any edit landed; the lines below are the pre-edit live-tree lines downstream plans 349-02..05 inherit. Note: this plan's own R1 edit shifts the Game's lines BELOW `:1553` upward by ~46 — see the "post-edit drift" note at the end; 349-02..05 MUST re-pin against the *post-349-01* tree, not these pre-edit lines, for anything below the reclaim site).

#### DegenerusGame.sol — ARCH-04 reclaim sites + the dispatch lane (pre-edit)

| Anchor | SPEC line | Live (pre-edit) | Matched text | Status |
|---|---|---|---|---|
| `claimAffiliateDgnrs` def (R1 MOVE) | :1553 | **:1553** | `function claimAffiliateDgnrs(address player) external {` (body `:1553-1596`) | MATCH |
| `previewSellFarFutureTickets` def (R2) | :2113 | **:2113** | `function previewSellFarFutureTickets(` (thin `return _quoteFarFutureSwap(...)`) | MATCH |
| `playerActivityScore` def (R3) | :2676 | **:2676** | `function playerActivityScore(` (thin wrapper; `questView.playerQuestStates` + `_playerActivityScore`) | MATCH |
| `claimBingo` dispatch stub (the MOVE-lane template) | :328-343 | **:328-344** | `function claimBingo(` → `.GAME_BINGO_MODULE` `:334` → `abi.encodeWithSelector(...)` → `if (!ok) _revertDelegate(data);` `:343` | MATCH |
| `.GAME_BINGO_MODULE` in the claimBingo stub | :334 | **:334** | `.GAME_BINGO_MODULE` | MATCH |
| `_revertDelegate` private helper def | :1051 | **:1051** | `function _revertDelegate(bytes memory reason) private pure {` | MATCH |
| `afkingFundingOf` (the v54 ledger accessor — confirm present, REUSE) | :1540 | **:1540** | `function afkingFundingOf(address player) external view returns (uint256) {` → `return afkingFunding[player];` | MATCH |

#### DegenerusGame.sol — the move's dependency map (what travels vs what stays)

| Symbol | Live line | Disposition | Why |
|---|---|---|---|
| `AFFILIATE_DGNRS_DEITY_BONUS_BPS` (`private constant`) | :164 | **MOVED** → BingoModule | 1 decl + 1 use (in `claimAffiliateDgnrs`); 0 other users repo-wide |
| `AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH` (`private constant`) | :167 | **MOVED** → BingoModule | same |
| `AFFILIATE_DGNRS_MIN_SCORE` (`private constant`) | :170 | **MOVED** → BingoModule | same |
| `AffiliateDgnrsClaimed` event | :1444 (decl) | **MOVED** → BingoModule | 1 decl + 1 emit; 0 other emitters repo-wide |
| `_resolvePlayer` (`private`) | :478 | **STAYS in Game + COPY added to BingoModule** | 18 call sites in the Game (used by many fns); the moved body also needs it |
| `_requireApproved` (`private`) | :472 | **STAYS in Game + COPY added to BingoModule** | 2 uses in the Game; `_resolvePlayer` (both copies) needs it |

#### Symbols the moved body relies on — all INHERITED by BingoModule (no new imports needed for these)

`DegenerusGameBingoModule is DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils` — both inherit `DegenerusGameStorage`; `DegenerusGameMintStreakUtils` already imports `BitPackingLib` + `PriceLookupLib`.

| Symbol | Where (inherited) |
|---|---|
| `affiliate` (`IDegenerusAffiliate` constant) | DegenerusGameStorage:145 |
| `coinflip` (`IBurnieCoinflip` constant) | DegenerusGameStorage:139 |
| `dgnrs` (`IStakedDegenerusStonk` constant) | DegenerusGameStorage:147 |
| `level` (`uint24 public`) | DegenerusGameStorage:245 |
| `mintPacked_` | DegenerusGameStorage:433 |
| `affiliateDgnrsClaimedBy` / `levelDgnrsAllocation` / `levelDgnrsClaimed` | DegenerusGameStorage:985 / :990 / :993 |
| `operatorApprovals` (read by `_requireApproved`) | DegenerusGameStorage:974 |
| `PRICE_COIN_UNIT` | DegenerusGameStorage:162 |
| `BitPackingLib` / `PriceLookupLib` | imported by DegenerusGameMintStreakUtils:5/6 |
| `IStakedDegenerusStonk.Pool.Affiliate` enum member | interface :12 (BingoModule already imports `IStakedDegenerusStonk`) |
| `E()` error | DegenerusGameStorage:205 |
| `NotApproved()` error | **NOT inherited** — declared only at DegenerusGame.sol:94 → a copy ADDED to the BingoModule (see Task 2 deviation) |

#### The other 349-scope anchors (for 349-02..05 — re-pinned, all MATCH; pre-edit lines, untouched by THIS plan)

| Anchor (file) | SPEC line | Live | Status |
|---|---|---|---|
| `IDegenerusGameBingoModule` interface | IDegenerusGameModules.sol :424 | **:424** | MATCH (THIS plan adds `claimAffiliateDgnrs` to it) |
| R3 caller `WhaleModule` | DegenerusGameWhaleModule.sol :875 | **:875** | MATCH (UNCHANGED — no retarget) |
| R3 caller `DecimatorModule` | DegenerusGameDecimatorModule.sol :704 | **:704** | MATCH (UNCHANGED) |
| R3 caller `BurnieCoin` | BurnieCoin.sol :620 | **:620** | MATCH (UNCHANGED) |
| R3 caller `StakedDegenerusStonk` | StakedDegenerusStonk.sol :913 | **:913** | MATCH (UNCHANGED); interface decl `:29` |
| `transferFromPool` (`onlyGame`) | StakedDegenerusStonk.sol :478 | **:478** | MATCH — **load-bearing for the Task 2 Rule-1 fix** |
| `onlyGame` modifier (`msg.sender == ContractAddresses.GAME`) | StakedDegenerusStonk.sol :336 | **:336** | MATCH |
| `creditFlip` (`onlyFlipCreditors`) | BurnieCoinflip.sol :859 | **:859** | MATCH |
| `onlyFlipCreditors` (GAME-allowed; GAME_BINGO_MODULE NOT in the set) | BurnieCoinflip.sol :194 | **:194** | MATCH — **load-bearing for the Task 2 Rule-1 fix** |
| `GAME_BINGO_MODULE` constant | ContractAddresses.sol :33 | **:33** | MATCH |
| `GAME` constant | ContractAddresses.sol :47 | **:47** | MATCH |

> **The downstream AdvanceModule / AfKing / LootboxModule / Storage / EV-cap anchors** (the 349-02..05 surface — `subscribe` `:324`, OPEN-E gate `:343-352`, `_resolveBuy` `:727-863`, `rngGate` `:1152`/call `:274`, `requestLootboxRng` `:1016`, index advances `:1089`/`:1629`, the `abi.encode` seed `LB:534`, `lootboxDay` `LB:514`, the EV-cap map/helper `LB:459`/`Storage:1469`/`:1326`, etc.) were re-attested in full by 348-GREP-ATTESTATION §1-§2 against this same `20ca1f79` tree and remain valid — **THIS plan does not touch any of them** (it touches only `DegenerusGame.sol` above `:2113`, the BingoModule, and the BingoModule interface). 349-02..05 inherit the 348 attestation for those, re-pinning vs the post-349-01 tree per the note below.

### ⚠ Post-349-01 drift note for 349-02..05 (MUST re-pin against the CURRENT tree, not these pre-edit lines)

This plan's R1 edit is a **net −46 lines** in `DegenerusGame.sol` (24 ins / 70 del). Everything in `DegenerusGame.sol` **below the old `:1553`** shifts UP by ~46 lines. Verified post-edit:
- `previewSellFarFutureTickets` (R2): `:2113` → **now :2067**
- `playerActivityScore` (R3): `:2676` → **now :2630**

`DegenerusGameBingoModule.sol`, `IDegenerusGameModules.sol`, and every OTHER contract file are also now off their `20ca1f79` lines (the BingoModule grew +114; the interface +10). **349-02..05 MUST run `git diff --numstat 20ca1f79 HEAD -- contracts/` (now NON-empty) and re-pin every anchor vs the live post-349-01 tree** — the `20ca1f79` lines in 348-GREP-ATTESTATION are stale for the touched files. (The AdvanceModule / AfKing / Storage / Lootbox lines are still valid since THIS plan didn't edit those files — but the discipline is: re-grep, never trust transcribed lines once the tree moved.)

---

## Task 2 — [R1 RECLAIM FIRST] MOVE claimAffiliateDgnrs → DegenerusGameBingoModule

**Status: DONE (with a Rule-1 auto-fix — see deviation).** The ~1.2 KB heavy body left the Game image; a thin ~80 B dispatch stub remains.

### What landed

1. **BingoModule (`contracts/modules/DegenerusGameBingoModule.sol`, +114 lines):**
   - `claimAffiliateDgnrs(address player)` — the body relocated **byte-for-byte** (same signature; same 4 cross-contract calls `affiliate.affiliateScore` / `affiliate.totalAffiliateScore` / `dgnrs.transferFromPool(Pool.Affiliate,…)` / `coinflip.creditFlip`; same `PriceLookupLib.priceForLevel`; same nested-mapping R/W; same deity-bonus branch; same `emit AffiliateDgnrsClaimed`).
   - The 3 `private constant`s (`AFFILIATE_DGNRS_DEITY_BONUS_BPS` / `…_CAP_ETH` / `…_MIN_SCORE`) — moved verbatim.
   - The `AffiliateDgnrsClaimed` event — moved verbatim.
   - `_resolvePlayer` + `_requireApproved` private helpers — byte-identical copies (the Game keeps its own for its 18/2 other callers; `operatorApprovals` is inherited from storage).
   - `error NotApproved()` — added (it was Game-private at `:94`, NOT inherited; needed by the moved `_requireApproved`).
2. **Game (`contracts/DegenerusGame.sol`, 24 ins / 70 del = −46 net):**
   - DELETED the `claimAffiliateDgnrs` body (`:1553-1596`), the 3 `private constant`s (`:164/167/170`), the `AffiliateDgnrsClaimed` event (`:1444`).
   - ADDED a thin delegatecall dispatch stub (shaped exactly like `claimBingo` `:328-344`) targeting `IDegenerusGameBingoModule.claimAffiliateDgnrs.selector` on `GAME_BINGO_MODULE`.
   - `_resolvePlayer` (18 callers) + `_requireApproved` (2 callers) RETAINED in the Game (grep-confirmed still used) — NOT deleted.
3. **Interface (`contracts/interfaces/IDegenerusGameModules.sol`, +10/−1):**
   - Added `function claimAffiliateDgnrs(address player) external;` to `IDegenerusGameBingoModule` so the Game stub's `abi.encodeWithSelector(IDegenerusGameBingoModule.claimAffiliateDgnrs.selector, …)` resolves and compiles.

### Verification (read-only)

- Plan verify command `grep -c "function claimAffiliateDgnrs" Game ==0 && BingoModule ==1`: now **Game=1 (the thin stub), BingoModule=1 (the body)** — the literal `==0` assertion is intentionally NOT satisfied because of the Rule-1 fix (the stub is required for reachability; the reclaim INTENT — heavy body out of the Game — is fully met). Proof the heavy body left: `grep -c "affiliate.affiliateScore\|levelDgnrsAllocation\|levelDgnrsClaimed"` = **0 in the Game, 3 in the BingoModule.**
- `scripts/check-delegatecall-alignment.sh` → **PASS 54/54** (new stub `DegenerusGame.sol:1545 IDegenerusGameBingoModule -> GAME_BINGO_MODULE` ALIGNED).
- `scripts/check-interface-coverage.sh` → **PASS** (all interface functions have matching implementations).
- `scripts/check-raw-selectors.sh` → **PASS** (2 pre-existing justified sites; no new raw selectors).
- Residual `claimAffiliateDgnrs` / constant / event mentions in the Game are ALL relocation comments (not live code) — grep-confirmed.
- The authoritative `forge build` is NOT run here (it runs over the whole diff at 349-05); the structural checks above are the available read-only gates.

---

## Task 3 — [R2/R3 INSURANCE] DECISION: DEFERRED to 349-05

**Decision: DEFER R2 (`previewSellFarFutureTickets`) and the R3 wrapper (`playerActivityScore`) to 349-05, pending the measured `forge build --sizes`.** `:2113`/`:2676` (now `:2067`/`:2630` post-R1) are left UNCHANGED in this plan.

**Rationale (both paths are SPEC-acceptable per 348-CODE-SIZE-PLAN §4 / the plan action):**
- R1 alone reclaims ~1.2-1.35 KB, which **exceeds the ~1.0-1.5 KB stub budget in the central case** (Scenario B: 24,275 B, 301 B margin). The worst-case breach (+82 B) only fires if R1 reclaims its low-end AND stubs hit their high-end *simultaneously*.
- This plan has **no `forge build`** — the authoritative size measurement happens over the whole diff at 349-05. Dropping `view` from two public view functions (an ABI-visible mutability change with off-chain `eth_call` consumers) is cleaner to land WITH that real measurement, only if it's actually needed, rather than pre-emptively here.
- 349-05 owns the final `forge build --sizes` gate; if the measured post-fold size approaches 24,576 it lands R2 + the R3 wrapper then (both free of the caller-retarget), and/or the reserve set.

**The R3 953 B caller-retarget is NOT attempted here** (explicit plan constraint). The R3 4 external callers are UNCHANGED — verified:
- `DegenerusGameWhaleModule.sol:875`, `DegenerusGameDecimatorModule.sol:704`, `BurnieCoin.sol:620`, `StakedDegenerusStonk.sol:913` (+ its interface decl `:29`) — all byte-identical to `20ca1f79`.

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] R1 is a MOVE-WITH-THIN-STUB, not the "true void / no Game stub" the SPEC specified**
- **Found during:** Task 2.
- **Issue:** The SPEC (348-CODE-SIZE-PLAN §2 R1 / §5 note 1; 348-IMPL-EDIT-ORDER-MAP §3 Step 1a) and the plan `must_haves` mandate moving `claimAffiliateDgnrs` to the BingoModule with **NO Game stub** ("callable directly on the GAME_BINGO_MODULE address"). But `claimAffiliateDgnrs`'s body makes two **privileged** external calls: `dgnrs.transferFromPool` (gated `onlyGame` ⇒ `msg.sender == ContractAddresses.GAME`, StakedDegenerusStonk.sol:336/478) and `coinflip.creditFlip` (gated `onlyFlipCreditors`, a set that includes `GAME` but **NOT** `GAME_BINGO_MODULE`, BurnieCoinflip.sol:194/859). A **direct** call to the module address makes the outbound `msg.sender` the module address → **both gates revert** → the function would be permanently unreachable/broken. (The existing `claimBingo` is likewise reachable only via the Game's delegatecall stub for the same reason — `delegatecall` preserves the Game as the outbound `msg.sender`.)
- **Fix:** Kept the heavy body in the BingoModule (the ~1.2 KB reclaim) BUT left a **thin delegatecall dispatch stub** in the Game (shaped exactly like `claimBingo` `:328-344`, ~80 B). This is the codebase's *existing, standard* dispatch pattern — NOT new architecture (so it is a Rule 1 fix, not a Rule 4 escalation). The reclaim intent (heavy logic out of the Game image; headroom cleared before the ARCH-03 stubs) is fully preserved — net Game change is −46 lines / the heavy body's bytecode is gone, only the cheap stub remains.
- **Files modified:** `contracts/DegenerusGame.sol` (thin stub instead of full deletion), `contracts/modules/DegenerusGameBingoModule.sol` (body relocated), `contracts/interfaces/IDegenerusGameModules.sol` (selector declared for the stub).
- **Impact on the running-total:** marginally less reclaim than a true void (≈ −80 B stub retained), still well within Scenario A/B margins — R1 still clears the stub budget in the central case. 349-05's `forge build --sizes` is the authoritative confirmation.
- **Commit:** none (contract-boundary hold; uncommitted).

**2. [Rule 3 - Blocking issue] IDegenerusGameModules.sol edited (not in the plan's files_modified list)**
- **Found during:** Task 2 (as a consequence of deviation 1).
- **Issue:** The Game's new dispatch stub references `IDegenerusGameBingoModule.claimAffiliateDgnrs.selector`. That selector must be declared in the `IDegenerusGameBingoModule` interface or the Game won't compile (blocking). The plan listed only `DegenerusGame.sol` + `DegenerusGameBingoModule.sol`.
- **Fix:** Added `function claimAffiliateDgnrs(address player) external;` to `IDegenerusGameBingoModule` (interfaces/IDegenerusGameModules.sol). `check-interface-coverage.sh` PASSES with it. This is the standard module-interface pattern (every dispatch stub's selector is interface-declared).
- **Files modified:** `contracts/interfaces/IDegenerusGameModules.sol`.
- **Commit:** none (uncommitted).

### Authentication gates
None.

---

## Known Stubs
The Game's `claimAffiliateDgnrs` is now a **thin delegatecall dispatch stub** (intentional, per deviation 1 — the standard module-dispatch pattern). It is NOT a placeholder/empty stub: it forwards to the live BingoModule body via the GAME_BINGO_MODULE delegatecall lane, which is the reachable, behavior-preserving path. No data-stubbing, no "coming soon", no empty returns.

---

## Threat Flags
None new. The move stays within the existing threat register:
- **T-349-01-CEIL** (deploy-size): R1 reclaim landed FIRST (the heavy body out of the Game). 349-05's `forge build --sizes` is the final proof < 24,576.
- **T-349-01-MOVE** (mis-account): the body is byte-preserved (same calls / mappings / deity branch); the Rule-1 thin-stub fix actually *strengthens* correctness (a true void would have bricked the function). The `onlyGame`/`onlyFlipCreditors` context is preserved via the delegatecall.
- **T-349-01-DRIFT** (stale anchor): Task 1 re-pinned every anchor; baseline EMPTY vs `20ca1f79`; the post-349-01 drift note hands 349-02..05 the re-pin obligation.

---

## Self-Check: PASSED

- `contracts/modules/DegenerusGameBingoModule.sol` — exists; `function claimAffiliateDgnrs` present (1); body byte-identical to the original; constants/event/helpers/error present. ✅
- `contracts/DegenerusGame.sol` — exists; heavy body GONE (`affiliate.affiliateScore`/`levelDgnrsAllocation`/`levelDgnrsClaimed` = 0); thin dispatch stub present (aligned 54/54). ✅
- `contracts/interfaces/IDegenerusGameModules.sol` — exists; `claimAffiliateDgnrs` selector declared; interface-coverage PASS. ✅
- `.planning/phases/349-…/349-01-SUMMARY.md` — this file (written, uncommitted). ✅
- **No commit hashes** — by design (contract-boundary hold; the orchestrator owns the single batched-diff commit gate after the USER approval at 349-05). `git status` shows the 3 contract files + this SUMMARY as uncommitted working-tree changes.
- Baseline gate re-confirmed CLEAN before edits; R3's 4 callers UNCHANGED; R2/R3 wrappers deferred (UNCHANGED). ✅
