# Phase 339 — Grep-Attestation Table + Producer-Before-Consumer Edit-Order Map

**Plan:** 339-03 · **Task 2** · **SC5** · **BATCH-01** · **D-13**
**Frozen baseline:** the v50.0-closure HEAD **`812abeee`**.

---

## PART 1 — GREP-ATTESTATION TABLE (D-13): every cited file:line vs 812abeee

### 1.1 The empty-diff shortcut — stated AND verified

```
$ git diff --stat 812abeee HEAD -- contracts/
(empty)
$ git rev-parse HEAD
d022cc9e3aa4adbd79aaf18bf0756d1c5d826119
$ git log --oneline 812abeee..HEAD
d022cc9e docs(339-02): complete claimBingo BINGO design-lock plan
d5860ef9 docs(339-02): author tier-precedence acceptance contract ...
1db9fcb3 docs(339-02): author BINGO design-lock ...
832e9a72 docs(339-01): complete BINGO-06 freeze proof + soundness attestation plan
79f0487d docs(339-01): record traitBurnTicket write-site soundness attestation ...
5189240f docs(339-01): record BINGO-06 RNG-freeze-safety proof ...
743c20ae docs(339): finalize phase plan ...
... (all docs(339...) / docs(state) / docs(milestone) — NO contracts/ commit)
```

**`git diff --stat 812abeee HEAD -- contracts/` is EMPTY** — every commit since `812abeee` is a v51 planning doc. Therefore **grepping current HEAD `d022cc9e` == grepping `812abeee` for `contracts/`.** This is the shortcut.

But per the cross-cutting **"no by-construction claim survives un-checked"** rule (`feedback_verify_call_graph_against_source`), the shortcut alone is NOT sufficient: each anchor is shown line-by-line below, read from source at HEAD.

### 1.2 Per-anchor attestation table

Legend — **Kind:** MOD = a Phase-340 modification target · NEW = a Phase-340 net-new symbol · REF = reference-pattern citation (copied, not edited) · READ = read-side consumer surface (NOT a writer).

| # | Anchor (file:line) | Cited content | Confirmed at HEAD≡812abeee? | Kind | Drift correction |
|---|--------------------|---------------|-----------------------------|------|------------------|
| 1 | `storage/DegenerusGameStorage.sol:416` | `mapping(uint24 => address[][256]) internal traitBurnTicket;` | ✅ exact | MOD-adjacent (3 new mappings appended near here) | none |
| 2 | `storage/DegenerusGameStorage.sol:285` | `bool public gameOver;` | ✅ exact | READ (claimBingo cutoff) | none |
| 3 | `DegenerusTraitUtils.sol:17-39` | trait byte `[QQ][CCC][SSS]` (Q 7-6, C 5-3, S 2-0) | ✅ exact (`Format: [QQ][CCC][SSS]` at :21) | REF (traitId derivation) | none |
| 4 | `DegenerusGame.sol:2701` | `address[] storage arr = traitBurnTicket[lvlSel][traitSel];` | ✅ exact | **READ** (`sampleTraitTickets`, view) — NOT a writer (D-13/339-01) | reclassified read-side |
| 5 | `DegenerusGame.sol:2730` | `address[] storage arr = traitBurnTicket[targetLvl][traitSel];` | ✅ exact | **READ** (`sampleTraitTicketsAtLevel`, view) — NOT a writer | reclassified read-side |
| 6 | `DegenerusGame.sol:2813` | `address[] storage a = traitBurnTicket[lvl][trait];` | ✅ exact | **READ** (`getTickets`, view) — NOT a writer | reclassified read-side |
| 7 | `DegenerusGame.sol:280/309/521/...` | `.GAME_*_MODULE.delegatecall(...)` dispatch | ✅ exact (`.GAME_ADVANCE_MODULE.delegatecall` :280/:309; `.GAME_MINT_MODULE` :521/:546/:568/:599; `.GAME_LOOTBOX_MODULE` :620/:637; `.GAME_WHALE_MODULE` :672) | REF (claimBingo wiring shape) | none — 8 modules per the :76 header |
| 8 | `StakedDegenerusStonk.sol:291` | `uint16 private constant CREATOR_BPS = 2000;` | ✅ exact | REF (the missing 2000 in the BPS-sum) | **the BPS-sum's missing 2000 lives at :291, NOT in the :294-298 block the plan/CONTEXT framed as the set** |
| 9 | `StakedDegenerusStonk.sol:295` | `uint16 private constant AFFILIATE_POOL_BPS = 3500;` | ✅ exact | **MOD** (REBAL 3500→3000) | none |
| 10 | `StakedDegenerusStonk.sol:297` | `uint16 private constant REWARD_POOL_BPS = 500;` | ✅ exact | **MOD** (REBAL 500→1000) | none |
| 11 | `StakedDegenerusStonk.sol:464` | `function poolBalance(Pool pool) external view returns (uint256)` | ✅ exact | REF (claimBingo reads Pool.Reward balance) | none |
| 12 | `StakedDegenerusStonk.sol:485` | `function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred)` | ✅ exact (clamps `amount→available` :491-493, returns clamped) | REF (claimBingo sDGNRS draw; clamped-return = dgnrsPaid) | none |
| 13 | `modules/DegenerusGameJackpotModule.sol:112` | `event JackpotDgnrsWin(address indexed winner, uint256 amount);` | ✅ exact | **MOD** (JACK delete; sole emit :1350) | none |
| 14 | `modules/DegenerusGameJackpotModule.sol:191` | `uint16 private constant FINAL_DAY_DGNRS_BPS = 100;` | ✅ exact | **MOD** (JACK delete; sole use :1343) | none |
| 15 | `modules/DegenerusGameJackpotModule.sol:617` | `isFinalDay ? lvl + 1 : lvl,` | ✅ exact | READ/preserved (lvl+1 ticket-index gate — UNTOUCHED) | none |
| 16 | `modules/DegenerusGameJackpotModule.sol:654` | `traitBurnTicket[lvl]` (jackpot bucket reader) | ✅ exact | **READ** (NOT a writer; shares the read pattern BINGO uses) | reclassified read-side (D-13/339-01) |
| 17 | `modules/DegenerusGameJackpotModule.sol:1339-1352` | `if (isFinalDay) { ... poolBalance(Pool.Reward) ... transferFromPool(...) ... emit JackpotDgnrsWin(...) }` | ✅ exact (reward calc :1343, emit :1350) | **MOD** (JACK delete the whole branch) | containing fn is `_handleSoloBucketWinner` (:1305), NOT `_paySoloBucket` as plan/CONTEXT named it |
| 18 | `modules/DegenerusGameJackpotModule.sol:1350` | `emit JackpotDgnrsWin(w, reward);` | ✅ exact | **MOD** (JACK delete; sole emit) | none |
| 19 | `modules/DegenerusGameJackpotModule.sol:1085/1095/1135/1161/1190/1312` | the isFinalDay callers (`_processDailyEth`/`_processBucket`/`_handleSoloBucketWinner`) | ✅ exact (:1085 doc, :1095/:1161/:1312 params, :1135/:1190 calls) | READ/preserved (carry isFinalDay for non-Pool.Reward purposes — UNTOUCHED) | function names: `_processDailyEth` (:1088), `_processBucket` (:1154), `_handleSoloBucketWinner` (:1305) |
| 20 | `modules/DegenerusGameDegeneretteModule.sol:1145-1155` | `_awardDegeneretteDgnrs` `transferFromPool(Pool.Reward,…)` reference pattern | ✅ exact (fn def :1135; `poolBalance(Pool.Reward)` :1145-1146; empty-pool guard `if (poolBalance == 0) return;` :1148; `transferFromPool(Pool.Reward,…)` :1154-1155) | REF (the exact sDGNRS-from-Pool.Reward + clamped-return model claimBingo copies) | **CONTEXT cited :1135-1159; plan cited :1145-1155; the precise call is :1154-1155, guard :1148 — region drift only, REF not MOD** |
| 21 | `modules/DegenerusGameMintModule.sol:1322` | `coinflip.creditFlip(buyer, lootboxFlipCredit);` | ✅ exact | REF (the BURNIE flip-credit model claimBingo copies) | **CONTEXT cited :1319; actual is :1322 — line drift, REF not MOD** |
| 22 | `modules/DegenerusGameMintModule.sol:603-643` | the SOLE `traitBurnTicket` WRITER (inline-asm append, slot at :611, keyed by RNG-resolved traitId :586-587) | ✅ confirmed (`traitBurnTicket.slot` at :611; the only append in `contracts/`) | **WRITER** (the authoritative producer of every `traitBurnTicket` entry) | **D-13/339-01 correction: this is the producer; anchors #4/#5/#6/#16 are all READ-side, NOT writers** |

### 1.3 Drift corrections — consolidated

All drift is **informational** — the cited surfaces are confirmed present at the cited lines; none is a contract-drift between `812abeee` and HEAD (that diff is empty). The corrections clarify read-vs-write classification, the BPS-set composition, and a function name / a few reference-pattern line numbers:

1. **The BPS-sum's missing 2000 is `CREATOR_BPS=2000` at `:291`** — the plan/CONTEXT framed the pool-BPS set as the `:294-298` block (which sums to only 8000). The complete set includes `CREATOR_BPS` (:291) one line above the block → 10000. (See `339-REBAL-JACK-ATTESTATION.md` §1.2.) This is a **completeness correction**, not a contract drift.
2. **`DegenerusGame.sol:2701/2730/2813` + `JackpotModule:654` are READ-side, NOT writers.** The plan/CONTEXT D-02 cited them as `traitBurnTicket` "write-sites"; on source inspection all four are `view`/read consumers. The SOLE writer is **`DegenerusGameMintModule.sol:603-643`** (D-13/339-01). Reference-pattern + soundness anchor reclassification — carried into the edit-order map below (the producer is MintModule's writer; the consumer is the new claimBingo read path).
3. **The JACK deletion's containing function is `_handleSoloBucketWinner` (`:1305`), NOT `_paySoloBucket`.** The branch/constant/event/gate/caller lines are all confirmed at the cited line numbers — only the function name differs. (See `339-REBAL-JACK-ATTESTATION.md` §2.4.)
4. **REF line shifts (informational, NOT modification targets):**
   - DegeneretteModule `transferFromPool(Pool.Reward,…)` ref — CONTEXT cited `:1135-1159`, plan cited `:1145-1155`; the precise call is **:1154-1155**, the empty-pool guard `if (poolBalance == 0) return;` is **:1148**, the fn def is **:1135**. A reference pattern claimBingo COPIES, never edits.
   - MintModule `creditFlip` ref — CONTEXT cited `:1319`, actual is **:1322**. A reference pattern claimBingo COPIES, never edits.
5. **The REBAL amount derivations are `:354-359`** (CREATOR on :354), not the plan/CONTEXT `:355-359`. Informational region shift; the derivations are the `(INITIAL_SUPPLY * X_POOL_BPS)/BPS_DENOM` block grounding the supply-unchanged claim.

**No anchor moved between `812abeee` and HEAD** (the contracts/ diff is empty). The above are plan-text-vs-source clarifications captured so no "by construction" citation ships uncorrected into IMPL 340.

---

## PART 2 — PRODUCER-BEFORE-CONSUMER EDIT-ORDER MAP for IMPL 340 (D-13)

This is the **binding edit-order for BATCH-02 at Phase 340** — the single batched `contracts/*.sol` diff must be authored in this order so that at no intermediate point does a symbol reference a not-yet-defined producer (no intermediate broken state). Each step is internally complete; the four steps together are the whole v51 contract diff.

### Step 1 — PRODUCERS (storage + new module + module address)

1a. **Append the 3 storage mappings to `contracts/storage/DegenerusGameStorage.sol`** (near the `traitBurnTicket` decl `:416`), all keyed by `uint24` level (per the design-lock):
   - `bingoClaimed` (per-player `u8` quadrant mask)
   - `firstQuadrant` (systemwide `u8`)
   - `firstSymbol` (systemwide `u32`)
   Pre-launch redeploy-fresh → appending to the SHARED layout is safe, no migration (`feedback_frozen_contracts_no_future_proofing`).

1b. **Create `contracts/modules/DegenerusGameBingoModule.sol`** — the new module implementing `claimBingo`'s body: validation, traitId derivation `(quadrant<<6)|(c<<3)|symInQ`, the 8-color `traitBurnTicket[level][traitId][slots[c]]` ownership read (a strict READ-only consumer — NO write to `traitBurnTicket`; the sole writer remains `DegenerusGameMintModule.sol:603-643`), the 3-tier reward cascade (per `339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md`), the `transferFromPool(Pool.Reward,…)` clamped-return draw + `coinflip.creditFlip(…)`, the empty-pool no-op, the `gameOver` cutoff, and the three leaderboard events.

1c. **Add `GAME_BINGO_MODULE` to `contracts/ContractAddresses.sol`** (the module-constant block `:13-31`; freely modifiable per `feedback_contractaddresses_policy`).

*Why first:* the storage mappings + the module + its address constant are the producers the entrypoint will reference. They must exist before Step 2 wires to them.

### Step 2 — CONSUMER WIRING (entrypoint + interface)

2a. **Add the `DegenerusGame.claimBingo` external entrypoint** that `ContractAddresses.GAME_BINGO_MODULE.delegatecall(...)`s — mirroring the established dispatch shape (`.GAME_*_MODULE.delegatecall` at `DegenerusGame.sol:280/309/521/...`).

2b. **Add the `claimBingo` signature to the interface** (`IDegenerusGame` or equivalent).

*Why second:* the entrypoint references `GAME_BINGO_MODULE` (Step 1c) and delegatecalls into code (Step 1b) that uses the new storage (Step 1a). All three producers exist by now → no dangling reference.

### Step 3 — ISOLATED: REBAL

3. **`StakedDegenerusStonk` constructor rebalance** — `:295` `AFFILIATE_POOL_BPS` 3500→3000 and `:297` `REWARD_POOL_BPS` 500→1000. Net-zero, BPS-sum stays 10000 (per `339-REBAL-JACK-ATTESTATION.md` §1). Self-contained constant edit; order-independent relative to BINGO.

### Step 4 — ISOLATED: JACK

4. **`JackpotModule` final-day Pool.Reward deletion** — delete the `:1339-1352` `isFinalDay` branch, the `FINAL_DAY_DGNRS_BPS=100` constant (`:191`), and the `JackpotDgnrsWin` event decl (`:112`). Cleanly orphaned (sole use/emit inside the deleted branch); the rest of the isFinalDay plumbing is preserved (per `339-REBAL-JACK-ATTESTATION.md` §2). Self-contained deletion; order-independent relative to BINGO.

### Why this order yields no intermediate broken state

- **Producer-before-consumer:** the storage mappings, the module body, and the module address constant (Step 1) all exist before the `DegenerusGame.claimBingo` entrypoint + interface signature reference them (Step 2). Authoring the entrypoint first would reference an undefined `GAME_BINGO_MODULE` and call into non-existent module code.
- **REBAL + JACK are isolated** (Steps 3 & 4): they touch different files (`StakedDegenerusStonk.sol`, `DegenerusGameJackpotModule.sol`) and share no symbol with the BINGO producers/consumers. They are order-independent relative to BINGO and to each other, so they are listed last; the REBAL Pool.Reward doubling and the JACK final-day removal are the economic co-requisites of the BINGO surface, and all four land in ONE batched diff.
- **Single coherent module file:** the JACK deletion (Step 4) and the BINGO module's `traitBurnTicket` read pattern share `DegenerusGameJackpotModule.sol` (the read-side `:654` lives there; the deletion is in `_handleSoloBucketWinner`), so the read-only consumer and the final-day deletion land coherently.

**This is the binding edit-order for BATCH-02 at Phase 340.** Any other authoring order risks a compile-time dangling reference between steps.

---

## Summary

| Part | Result |
|------|--------|
| Empty-diff shortcut (D-13) | `git diff 812abeee HEAD -- contracts/` EMPTY — grep HEAD == grep 812abeee |
| Per-anchor table | 22 anchors confirmed line-by-line at HEAD≡812abeee; read-vs-write + REF-vs-MOD classified |
| Drift corrections | CREATOR_BPS@:291 completeness · read-side reclassification (#4/5/6/16) · `_handleSoloBucketWinner` name · REF line shifts (Degenerette :1154-1155/:1148, creditFlip :1322, derivations :354-359) — all informational, NOT contract drift |
| Edit-order map | 4 steps: producers (storage+module+ContractAddresses) → consumer (entrypoint+interface) → REBAL → JACK; binding for **BATCH-02** at Phase 340 |

**SC5 + D-13 discharged.**

---
*Phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc · Plan 03 Task 2*
*Authored: 2026-05-28 · Frozen baseline: 812abeee (contracts/ diff vs HEAD d022cc9e empty)*
