# Phase 343: SPEC — Design-Lock + Solvency Proof + Dead-Code/Gas Inventories + Call-Graph Attestation - Research

**Researched:** 2026-05-30
**Domain:** Solidity smart-contract audit SPEC (call-graph attestation + solvency proof + dead-code/gas inventory) for the v54.0 Game-side `keeperFunding` ledger + AfKing de-custody. Paper-only, ZERO `contracts/*.sol` mutation.
**Confidence:** HIGH (every anchor grep-pinned against the live working tree, which is byte-identical to v53 HEAD `83a84431` in `contracts/`)

## Summary

This is a paper-only SPEC phase. The mechanism is already DESIGN-LOCKED (CONTEXT.md Decisions A2 + B, D-CF-01..04, D-01..08, D-MR-01/02; PLAN-V54-KEEPER-FUNDING-GAME-LEDGER.md). The research job was **source-verification legwork**: grep-pin every cited `file:line` against the live tree, walk each solvency reservation site against actual code, confirm the de-custody kill-set is truly orphaned, and confirm the D-01 / D-MR-01 findings against source. I did not re-open any locked decision.

**The tree is verified byte-identical to v53 HEAD `83a84431` in `contracts/`** — `git diff --numstat 83a84431 HEAD -- contracts/` returns empty (HEAD = `3187d68e`, docs-only commits since). So the attestation greps the LIVE tree directly; no checkout. The whole verification ran on the working tree.

**Primary recommendation:** The design is sound and every load-bearing claim checks out against source — but **line-number drift is pervasive** (D-MR-02 was right and is worse than the one example): of ~25 cited anchors, the majority are off by 1-15 lines, and TWO citations point at the wrong *kind* of thing (`DegenerusAffiliate.payAffiliate` does not exist — the function is `handleAffiliate`; `batchPurchase` is declared payable in exactly ONE interface, the AfKing-local `IGame`, not in `contracts/interfaces/`). The planner MUST consume the **Drift-Correction Table** below verbatim into `343-GREP-ATTESTATION.md` and re-pin every IMPL edit-order anchor to the *actual* line. **One genuine planning risk surfaced** (not a re-design, a gap the SPEC must close): the GameOver **final sweep zeroes `claimablePool` but does NOT iterate per-player `keeperFunding[*]`** — after the sweep, `keeperFunding[player]` mappings still hold nonzero values while `claimablePool == 0`, so a post-sweep `withdrawKeeperFunding` would underflow `claimablePool -= amount`. See **Common Pitfalls → Pitfall 1** and **Open Questions → Q1**.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BATCH-01 | SPEC design-lock — re-attest PLAN-V54 vs v53 HEAD (every `file:line`); lock final `batchPurchase` / `purchaseWith` / extended `keeperSnapshot` signatures + storage shape + deposit/withdraw/claim-merge wiring; produce SOLVENCY/CLEANUP/GAS inventories; confirm OPEN-E carry-over | Drift-Correction Table (every anchor re-pinned + matched text quoted); signatures confirmed against source (`purchaseWith` `:864`, `keeperSnapshot` `:2645`, `batchPurchase` `:1824`); storage shape confirmed ABSENT (new in 344); OPEN-E gate confirmed unchanged (`AfKing.sol:399-409`) |
| SOLVENCY-01 | PROVE every "free ETH = totalBal − reserved" site already reserves the keeper total via `claimablePool` | Reservation-Site Walk: all 4 sites read against source — `distributeYieldSurplus` (`:693` sums `claimablePool`), gameOver drain (`:98`/`:163` `reserved = claimablePool`), `adminStakeEthForStEth` (`:2117-2119` reserve keys off `claimablePool`), final sweep (`:215` zeroes `claimablePool`) |
| SOLVENCY-03 | sDGNRS redemption valuation unchanged + correct (keeper ETH invisible) | sDGNRS valuation walked at `:609-612`/`:769-772`/`:858-861` — `ethBal = address(this).balance` (sDGNRS's OWN balance), `claimableEth = game.claimableWinningsOf(this)` (owed to sDGNRS only); keeper ETH lives in the Game's balance, invisible. Same property as external AfKing pool today. |
| CLEANUP-01 | De-custody dead-code inventory — grep-attested kill-set vs v53 HEAD | Kill-Set Inventory: every target located + repo-wide caller grep done. `afKing.poolOf`/`withdraw` have exactly 2 external callers, both inside the v48 recovery legs being removed → truly orphaned after removal. `recoverAfKingPool` has 0 external callers. |
| GAS-01 | Gas-opportunity inventory for the keeper/funding blast radius | Blast-radius files enumerated + `/gas-scavenger` interface confirmed (D-02: run advisory at SPEC). Packing candidate (D-04) framing captured. |
</phase_requirements>

## User Constraints (from CONTEXT.md)

### Locked Decisions (do NOT re-open — verify against source, flag drift)
- **D-CF-01 (Decision A2):** `AfKing.subscribe` stays `payable`, forwards `msg.value` → `game.depositKeeperFunding{value}(subscriber)`; AfKing never retains ETH. Standalone `deposit`/`depositFor`/`receive` removed.
- **D-CF-02 (Decision B):** Post-gameOver `claimWinnings` (`_claimWinningsInternal`) also pays the caller's `keeperFunding` (lazy per-player merge); `withdrawKeeperFunding` always available (both zero the bucket → no double-spend).
- **D-CF-03:** No new aggregate — `keeperFunding` per-player total rides inside the existing `claimablePool` (`claimablePool == Σ claimableWinnings + Σ keeperFunding`). Inherits solvency wiring; prior-omission class structurally impossible.
- **D-CF-04:** `claimableWinnings` `{uint128 normal, uint128 keeper}` packing candidate DEFERRED to 345 GAS. 343 only documents/flags it.
- **D-01 (CRITICAL):** `BatchBuy` gains a `funder` field (= the resolved `src`). The Game's non-payable `batchPurchase` debits `keeperFunding[b.funder]` + `claimablePool -= uint128(ev)`, then `purchaseWith(b.player, …, ev)`. AfKing sets `funder: src` per slice. **SPEC MUST record this as a correction to REQUIREMENTS `AUTOBUY-02` and PLAN-V54 §4 (both say `b.player`).** The VAULT/SDGNRS exemption stays keyed on the un-spoofable `player`.
- **D-02:** Build GAS-01 by running `/gas-scavenger` now at SPEC — advisory candidate list ONLY (no validation/application; 345 runs `/gas-skeptic`).
- **D-03:** GAS-01 reach = touched files + the accounting spine the solvency proof walks. Codebase-wide CLEANUP-03 sweep stays in 345.
- **D-04:** Packing candidate documented in GAS-01 with PLAN-V54 §2 framing; flagged for 345 gas-skeptic, NOT evaluated/decided here.
- **D-05:** `AfKing.poolOf(player)` view → deleted entirely. Canonical balance = `game.keeperFundingOf(player)`.
- **D-06:** v48 stuck-pool recovery → hard-removed, but ONLY after CLEANUP-01 grep-attests each leg is truly orphaned.
- **D-07:** SOLVENCY-01/03 are paper-proven AND front-load a focused adversarial red-team (`/economic-analyst` and/or `/contract-auditor`) on the proof at SPEC. Scoped to the proof, not a full re-audit.
- **D-08:** Use the v50 / Phase-334 multi-doc pattern (separate `343-SOLVENCY-PROOF.md`, `343-GREP-ATTESTATION.md`, `343-CLEANUP-INVENTORY.md`, `343-GAS-INVENTORY.md`, `343-IMPL-EDIT-ORDER-MAP.md`, indexed by `343-SPEC-INDEX.md`).
- **D-MR-01:** Extended `keeperSnapshot` returns `keeperFunding[player]` keyed on the subscriber array → equals `keeperFunding[src]` ONLY when `src == player`. The OPEN-E `src ≠ player` slice needs `keeperFunding[src]` → recommended one extra `game.keeperFundingOf(src)` fallback staticcall (mirror `AfKing.sol:809`). SPEC must REFINE AUTOBUY-05's "ONE staticcall per player" claim to name this carve-out.
- **D-MR-02:** Line-number drift is real — re-pin EVERY cited anchor; do not trust doc-cited lines.

### Claude's Discretion
- Exact filenames/split of the multi-doc set (D-08) — keep the five concerns discrete.
- Whether the adversarial red-team (D-07) uses `/economic-analyst`, `/contract-auditor`, or both — scope it to the solvency proof.
- How aggressively `/gas-scavenger` is prompted (D-02) — advisory; 345 is the validation gate.

### Deferred Ideas (OUT OF SCOPE for 343)
- CLEANUP-03 codebase-wide unused-code sweep → 345.
- GAS-02 validation + application (gas-scavenger → gas-skeptic) → 345.
- `claimableWinnings` `{uint128 normal, uint128 keeper}` packing evaluation → 345 gas-skeptic (D-04).
- Generalized "any operator-approved party may spend my `claimableWinnings`" → out of v54.

## Project Constraints (from CLAUDE.md)

**No `./CLAUDE.md` exists in the working directory** (verified — `Read` returned "File does not exist"). No project-local directive file to enforce. The governing constraints come from CONTEXT.md / REQUIREMENTS.md / ROADMAP.md `feedback_*` tokens, treated with locked-decision authority:
- `feedback_verify_call_graph_against_source` — no "by construction" / "single fn reaches all paths" survives un-checked. (This phase's whole reason for existing.)
- `feedback_security_over_gas` — keeper bucket rides inside `claimablePool` to inherit correct solvency wiring; GAS-01 candidates trading an invariant are pre-marked for 345 rejection.
- `feedback_frozen_contracts_no_future_proofing` — pre-launch redeploy-fresh; no migration (no live AfKing pools).
- ZERO `contracts/*.sol` edits at SPEC (read/grep only).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Keeper-funding custody (the ETH) | Game (`DegenerusGame.sol` + `DegenerusGameStorage.sol`) | — | v54 moves custody FROM AfKing TO the Game's `keeperFunding` ledger; the reservation rides in `claimablePool` (a Game-tier aggregate). |
| Auto-buy orchestration (loop/skip/evict/snapshot) | AfKing (`AfKing.sol`) | Game (`batchPurchase`) | AfKing keeps the loop + `_resolveBuy` math; the Game owns the spend (`keeperFunding[funder] -= ev`). Boundary value-transfer eliminated. |
| Solvency reservation ("free ETH = totalBal − reserved") | Game modules (Jackpot/GameOver) + Game (`adminStakeEthForStEth`) | — | All free-ETH computations key off `claimablePool`; keeper total reserved automatically. No edits needed (D-CF-03). |
| sDGNRS redemption valuation | StakedDegenerusStonk (own-balance valuation) | Game (`claimableWinningsOf` read) | Values sDGNRS's OWN balance + what the Game owes sDGNRS; keeper ETH (in the Game's balance, not owed to sDGNRS) is invisible. Unchanged. |
| OPEN-E operator-funded consent | AfKing (`subscribe` gate) | Game (`isOperatorApproved`) | Consent gate is subscribe-time only; `src` resolution unchanged; the 4-protection disposition carries over. |
| Dead-code / gas sweep | (paper inventory only at 343) | — | 343 enumerates; 344 removes CLEANUP-02; 345 applies GAS-02 + CLEANUP-03. |

## Standard Stack

This is an internal contract refactor on an existing Foundry/Solidity codebase. No new external packages. **No Package Legitimacy Audit needed** (zero installs; paper-only SPEC).

| Component | Version / Location | Purpose | Notes |
|-----------|-------------------|---------|-------|
| Foundry / forge | `foundry.toml` (`src = "contracts"`, `test = "test"`) | build + test | `[VERIFIED: foundry.toml]` `forge-std` v1.15.0 submodule at `lib/forge-std`. |
| Subject contracts | `contracts/` (byte-identical to `83a84431`) | the audit subject | `[VERIFIED: git diff --numstat 83a84431 HEAD -- contracts/ → empty]` |
| Audit skills | `~/.claude/skills/{contract-auditor,economic-analyst,zero-day-hunter,gas-scavenger,gas-skeptic}/SKILL.md` | adversarial + gas passes | `[VERIFIED: ls + head SKILL.md]` — all five present. |

### Audit skill interfaces (for the planner to wire into plan tasks — D-02 / D-07)

| Skill | Role (from SKILL.md frontmatter) | Used at 343 by |
|-------|----------------------------------|----------------|
| `gas-scavenger` | "aggressive gas optimization … finds code removal candidates … intentionally reckless — produces recommendations for The Skeptic to validate." | D-02: run advisory at SPEC for the GAS-01 candidate list (NO validation here). |
| `gas-skeptic` | "rigorous validation … approves, rejects, or escalates each recommendation." | NOT run at 343 — it is the 345 validation gate (note this so the planner does not invoke it here). |
| `economic-analyst` | "game theory and mechanism design … finds points where actors might work against the system." | D-07: focused red-team on the solvency proof (deposit-then-spend / fresh-rate-labeling economics). |
| `contract-auditor` | "adversarial security auditor … thinks like an attacker with a 1000 ETH budget." | D-07: focused red-team on the solvency proof (reservation escape, un-brickable withdraw CEI). |
| `zero-day-hunter` | "novel attack surface hunter … find the bug 10 prior auditors missed." | NOT a 343 skill — it is part of the 347 TERMINAL 3-skill sweep. Note for the planner: do NOT pull it forward. |

**Planner action (D-07):** wire `/economic-analyst` and/or `/contract-auditor` into a 343 plan task, **scoped to the solvency proof** (the `claimablePool` reservation walk + the un-brickable withdraw CEI + the deposit-then-spend / fresh-rate economics), NOT a full re-audit. **Planner action (D-02):** wire `/gas-scavenger` into a 343 plan task as an **advisory candidate generator** over the blast-radius files (below); explicitly note its output is unvalidated and 345 is the gate.

## Architecture Patterns

### Data flow (v54 keeper auto-buy, post-refactor — conceptual)

```
SUBSCRIBE (payable)                          TOP-UP (direct)
  AfKing.subscribe{value}                       depositKeeperFunding{value}(player)
        |  forwards msg.value                          |
        v                                               v
  game.depositKeeperFunding{value}(subscriber) ---> keeperFunding[player] += value
                                                       claimablePool      += value   (reservation rides here)
        ...
AUTO-BUY (no value transfer)
  AfKing._autoBuy loop
    -> _resolveBuy(sub, player, mp)
         -> GAME.keeperSnapshot([player...])   (ONE staticcall/player; extended to also return keeperFunding[player])
    -> src = sub.fundingSource==0 ? player : sub.fundingSource   <-- resolves AFTER the snapshot read (D-MR-01)
    -> [OPEN-E carve-out] if src != player: extra GAME.keeperFundingOf(src) staticcall   (mirror :809 fallback)
    -> funding-skip gate: keeperFunding[src] < ethValue ? skip/auto-pause
    -> build BatchBuy{ funder: src, player, ethValue, amount, isTicket, mode }   (D-01: + funder field)
  -> GAME.batchPurchase(buys)                   <-- NON-payable (was {value: totalValue})
       per slice:
         keeperFunding[b.funder] -= ev   &   claimablePool -= ev        (D-01: funder, not player)
         delegatecall purchaseWith(b.player, …, ev)   <-- beneficiary = player; ETH becomes prize/vault share, FRESH affiliate rate
         revert => WHOLE batch rolls back (atomic non-brick; advanceGame() independent)

WITHDRAW (always)                            POST-GAMEOVER CLAIM (Decision B)
  withdrawKeeperFunding(amount)                 claimWinnings -> _claimWinningsInternal
    debit keeperFunding[msg.sender] +              pays claimableWinnings[caller] + keeperFunding[caller]
    claimablePool BEFORE .call (CEI)               zero both; debit claimablePool by sum
    re-entrant 2nd call reverts on debit         (no double-spend vs withdraw; both zero the bucket)
```

### Pattern 1: per-player mapping + uint128 reserved aggregate, master invariant
**What:** `claimableWinnings[player]` (per-player) + `claimablePool` (uint128 reserved total), master invariant `address(this).balance + steth.balanceOf(this) >= claimablePool`.
**Where (live):** invariant comment `DegenerusGame.sol:5` AND `:18` (TWO copies — both name the invariant); storage `claimablePool` declared `DegenerusGameStorage.sol:355`, comment block `:345-355`; `claimableWinnings` mapping `:402`.
**Reuse for `keeperFunding`:** identical shape; the systemwide total rides inside `claimablePool` (no new aggregate — D-CF-03).

### Pattern 2: un-brickable CEI withdraw (the `withdrawKeeperFunding` template)
**Where (live):** `AfKing.withdraw` `AfKing.sol:328-341` — `uint256 bal = _poolOf[msg.sender];` (`:330`), debit `_poolOf[msg.sender] = bal - amount;` (`:334`) BEFORE the external `.call`. A re-entrant second call reverts on the debit.
**Reuse:** `withdrawKeeperFunding` mirrors this but also moves `claimablePool` in tandem (PLAN-V54 §3).

### Pattern 3: deposit mirror
**Where (live):** `AfKing.depositFor` `AfKing.sol:314-318` — `if (msg.value == 0) return; _poolOf[player] += msg.value; emit Deposited(...)`.
**Reuse:** `depositKeeperFunding(address) payable` mirrors this + `claimablePool += msg.value`.

### Pattern 4: per-player snapshot fallback (the OPEN-E extra read template — D-MR-01)
**Where (live):** `AfKing.sol:809` — `(, , uint256[] memory cl) = GAME.keeperSnapshot(snap);` inside `_resolveBuy` (`:789`). The main loop comment at `:663-664` documents "GASOPT-03: ONE keeperSnapshot read per player."
**Reuse:** for the OPEN-E `src ≠ player` slice, mirror this with one extra `game.keeperFundingOf(src)` staticcall (common path unchanged).

### Anti-Patterns to Avoid
- **Trusting doc-cited lines.** Every doc citation in CONTEXT.md/PLAN-V54/REQUIREMENTS/ROADMAP is off by 1-15 lines (see Drift Table). Always re-grep.
- **Keying the Game-side debit on `b.player`.** REQUIREMENTS `AUTOBUY-02` and PLAN-V54 §4 literally say `keeperFunding[b.player] -= ev` — this is the D-01 bug. It MUST be `keeperFunding[b.funder]` or the OPEN-E operator-funded case mis-accounts / reverts.
- **Asserting strict `claimablePool == Σ claimableWinnings` across a keeper op.** The keeper total now permanently inflates `claimablePool`. New keeper tests must assert the `>=` inequality, not equality.

## Runtime State Inventory

> v54 is **pre-launch redeploy-fresh** (`feedback_frozen_contracts_no_future_proofing`); CONTEXT.md / REQUIREMENTS.md / PLAN-V54 §2 all state "no live AfKing pools, no migration." This is a contract-storage refactor, not a live rename/migration. The categories below are answered for completeness.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `AfKing._poolOf` mapping (slot 0, `AfKing.sol:214`) holds per-player prepaid ETH on-chain. **Pre-launch, no live pools** (PLAN-V54 §2: "no migration; no live AfKing pools"). | None — redeploy-fresh. New custody is `game.keeperFunding`. |
| Live service config | None — no off-chain service stores the renamed symbols. The keeper bot / frontend read `poolOf` → must switch to `game.keeperFundingOf` (D-05). | Off-chain read-path change (out of contract scope; note for integrators — none live). |
| OS-registered state | None — no OS-level registration. | None. |
| Secrets/env vars | None — no secret/env references the keeper ledger by name. | None. |
| Build artifacts | `forge-out/` + `artifacts/` hold compiled keeper/AfKing artifacts; stale after the 344 ABI change (`batchPurchase` payable→non-payable, `BatchBuy` +`funder`). | `forge build` regenerates at 344 — automatic, no manual step. |

**Nothing requiring a data migration** — verified by PLAN-V54 §2 + the redeploy-fresh posture. The only "state" is on-chain `_poolOf`, which has no live balances pre-launch.

## Call-Graph Attestation — Drift-Correction Table

> **This is the load-bearing deliverable for `343-GREP-ATTESTATION.md`.** Every anchor cited in CONTEXT.md / PLAN-V54 / REQUIREMENTS / ROADMAP, re-pinned to its ACTUAL current line in the live tree (byte-identical to `83a84431`), with the matched text quoted. `[VERIFIED: grep on live tree @ HEAD 3187d68e == 83a84431 in contracts/]` for every row.

### `contracts/DegenerusGame.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| `batchPurchase` def | `:1809` (ROADMAP/REQ/PLAN-V54 §4) | **`:1824`** | `function batchPurchase(BatchBuy[] calldata buys) external payable {` | DRIFT (+15). CONTEXT D-MR-02 already flags this. |
| `BatchBuy` struct | `:1796` | **`:1796`** ✓ | `struct BatchBuy {` (fields: `player; ethValue; amount; isTicket; mode`) | MATCH |
| `purchaseWith` selector call | `:1839` | **`:1838`** | `IDegenerusGameMintModule.purchaseWith.selector,` (call block `:1834-1848`) | DRIFT (−1) |
| `keeperSnapshot` | `:2645` | **`:2645`** ✓ | `function keeperSnapshot(address[] calldata players) external view returns (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables)` | MATCH |
| `_claimWinningsInternal` | `:1471` | **`:1462`** | `function _claimWinningsInternal(address player, bool stethFirst) private {` | DRIFT (−9). (`:1471` is a body line; the def is `:1462`.) |
| `adminStakeEthForStEth` | `:2113-2123` | **def `:2109`; reserve calc `:2116-2119`** | `function adminStakeEthForStEth(uint256 amount) external {` | DRIFT (−4) |
| master-invariant comment | `:18` | **`:5` AND `:18`** | `*      - address(this).balance + steth.balanceOf(this) >= claimablePool` (TWO copies) | PARTIAL — `:18` matches; note the SECOND copy at `:5` must also be updated. |
| bare `receive()` | `:2915` | **`:2915`** ✓ | `receive() external payable {` | MATCH |
| `_processMintPayment` `prizeContribution=cost` | `:969/:982/:1003` | **`:968` / `:981` / `:1003`** | `:968 prizeContribution = amount;` / `:981 prizeContribution = amount;` / `:1003 prizeContribution = msg.value + claimableUsed;` | DRIFT (−1, −1, 0) — PLAN-V54 §10 reference; informational. |

### `contracts/storage/DegenerusGameStorage.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| invariant comment | `:344-352` | **comment `:345-354`; decl `:355`** | `:348 INVARIANT: claimablePool >= sum(claimableWinnings[*])` … `:355 uint128 internal claimablePool;` | DRIFT (+1). `claimableWinnings` mapping decl at `:402`. |
| `keeperFunding` mapping | (new in 344) | **ABSENT** | — (grep returns nothing) | CONFIRMED NEW |

### `contracts/AfKing.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| `_poolOf` slot 0 | `:214` | **`:214`** ✓ | `mapping(address => uint256) private _poolOf; // slot 0` | MATCH |
| `receive()` | `:298-341` | **`:298`** | `receive() external payable {` (`:298-302`) | MATCH (range start) |
| `deposit()` | `:298-341` | **`:305`** | `function deposit() external payable {` | within range |
| `depositFor()` | `:298-341` | **`:314`** | `function depositFor(address player) external payable {` | within range |
| `withdraw()` | `:298-341` | **`:328`** | `function withdraw(uint256 amount) external {` (`:328-341`, CEI debit `:334`) | within range |
| `subscribe` OPEN-E gate | `:400-409` | **gate `:399-409`; def `:381`** | `:404 fundingSource != address(0) && :405 fundingSource != subscriber && :406 !GAME.isOperatorApproved(fundingSource, subscriber)` → `:407 revert NotApproved();` | DRIFT (−1 on range start). Full sig `:381-387` (6 params incl `address fundingSource`). |
| `subscribe` msg.value credit | `:412-415` | **`:412-415`** ✓ | `:413 _poolOf[subscriber] += msg.value;` | MATCH |
| `poolOf` view | `:493` | **`:492`** | `function poolOf(address player) external view returns (uint256) {` → `:493 return _poolOf[player];` | DRIFT (−1; def `:492`, return `:493`) |
| `src` resolution | `:686` (D-01) / `:682` (DECUSTODY-03) | **`:686`** | `address src = sub.fundingSource == address(0) ? player : sub.fundingSource;` | MATCH `:686`. **DECUSTODY-03's `:682` is DRIFT (−4).** |
| funding-skip gate | `:695` / `:696` | **`:695`** | `if (_poolOf[src] < ethValue) {` then `:696 if (player == ContractAddresses.VAULT \|\| player == ContractAddresses.SDGNRS) {` | MATCH — `:695` is the gate, `:696` the VAULT/SDGNRS exemption keyed on **`player`** (un-spoofable), confirming D-01. |
| CEI debit `_poolOf[src] -= ethValue` | `:719` | **`:719`** ✓ | `_poolOf[src] -= ethValue;` | MATCH |
| `BatchBuy` struct (AfKing) | `:20` | **`:20`** ✓ | `struct BatchBuy {` (fields IDENTICAL to Game's `:1796`) | MATCH |
| `buys[]` build | `:726` | **`:726`** ✓ | `buys[batchLen] = BatchBuy({ player: …, ethValue: …, amount: …, isTicket: …, mode: uint8(payKind) });` | MATCH |
| batched call | `:768` | **`:768`** ✓ | `GAME.batchPurchase{value: totalValue}(buys);` | MATCH — this is the `{value:}` → non-value change site. |
| `IGame` interface | `:40` | **`:40`** | `interface IGame {` | MATCH |
| `IGame.batchPurchase` payable ABI | `:43` | **`:43`** ✓ | `function batchPurchase(BatchBuy[] calldata buys) external payable;` | MATCH — **the ONLY interface decl of `batchPurchase` (see CLEANUP note).** |
| `IGame.keeperSnapshot` ABI | `:56` | **`:56`** ✓ | `function keeperSnapshot(address[] calldata players) external view returns (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables);` | MATCH |
| "ABI-identical" doc note | `:16` | **`:16` / `:30`** | `:16 …(identical field order/types ⇒ ABI-compatible)…` ; `:30 Signatures match contracts/DegenerusGame.sol verbatim: batchPurchase` | MATCH — both comments update on the non-payable + `funder` change. |
| per-player snapshot fallback | `:809` | **`:809`** ✓ | `(, , uint256[] memory cl) = GAME.keeperSnapshot(snap);` (inside `_resolveBuy` def `:789`) | MATCH |
| `sum(_poolOf) <= balance` invariant doc | (CLEANUP) | **`:117`** | `/// @custom:invariant Steady-state: sum(_poolOf) <= address(this).balance.` | FOUND (additional kill-set item) |

### `contracts/modules/DegenerusGameJackpotModule.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| `distributeYieldSurplus` | `:691-707` | **def `:688`; body `:688-718`; `claimablePool` in obligations `:693`** | `:688 function distributeYieldSurplus(uint256) external {` ; `:691 uint256 obligations = _getCurrentPrizePool() + :692 _getNextPrizePool() + :693 claimablePool + …` | DRIFT (−3 on def). The `claimablePool` term is at `:693`. |

### `contracts/modules/DegenerusGameGameOverModule.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| drain pre-refund reserve | `:98-99` | **`:98-99`** ✓ | `:98 uint256 reserved = uint256(claimablePool); :99 uint256 preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0;` (fn `handleGameOverDrain` def `:86`) | MATCH |
| drain post-refund reserve | `:164` | **`:163`** | `uint256 postRefundReserved = uint256(claimablePool);` (`:164 available = totalFunds > postRefundReserved ? …`) | DRIFT (−1) |
| final sweep | `:215` | **`:215`** ✓ | `claimablePool = 0;` (fn `handleFinalSweep` def `:202`; `GO_SWEPT` latch `:206-208`) | MATCH — **but see Pitfall 1: sweep does NOT touch per-player `keeperFunding`.** |

### `contracts/StakedDegenerusStonk.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| redemption valuation #1 | `:612` | **`:609-612`** ✓ | `:609 uint256 ethBal = address(this).balance; :610 stethBal = steth.balanceOf(address(this)); :611 claimableEth = _claimableWinnings(); :612 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;` | MATCH |
| redemption valuation #2 | `:772` | **`:769-772`** ✓ | identical formula at `:772` | MATCH |
| redemption valuation #3 | `:861` | **`:858-861`** ✓ | identical formula at `:861` | MATCH |
| `_claimableWinnings` helper | (supporting) | **`:955`** | `uint256 stored = game.claimableWinningsOf(address(this));` (`:956`) — keeper ETH NOT owed to sDGNRS ⇒ invisible | FOUND (proves SOLVENCY-03) |
| `burnAtGameOver` AfKing leg | `:533` | **def `:535`; withdraw leg `:539`** | `:539 afKing.withdraw(afKing.poolOf(address(this)));` | DRIFT (def `:535`, the actual kill-line `:539`). `:533` is the doc-comment start. |
| `receive()` AF_KING relaxation | (CLEANUP / DECUSTODY-04) | **`:439-445`** | `:441 msg.sender != ContractAddresses.AF_KING` inside `receive()` (`:439`) | FOUND |

### `contracts/DegenerusVault.sol`

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| `recoverAfKingPool()` | `:512` | **def `:516`; body `:517`** | `:516 function recoverAfKingPool() external {` → `:517 afKing.withdraw(afKing.poolOf(address(this)));` | DRIFT (def `:516`; `:512` is the doc-comment start). |

### `contracts/DegenerusAffiliate.sol` — **NAME DRIFT (not just line drift)**

| Symbol | Doc-cited | **Actual** | Matched text | Status |
|--------|-----------|------------|--------------|--------|
| fresh/recycled affiliate tiers | `payAffiliate:493-505` | **fn is `handleAffiliate` `:36` (interface); constants `:164-165`; doc `:18-21`** | `:164 REWARD_SCALE_FRESH_L1_3_BPS = 2_500;` `:165 REWARD_SCALE_FRESH_L4P_BPS = 2_000;` `:18-21 Fresh ETH 25%/20%; Recycled 5%; isFreshEth flag` | **NAME DRIFT — `payAffiliate` does not exist.** The function is `handleAffiliate`. Used by PLAN-V54 §10 / AUTOBUY-03 to justify the SEPARATE bucket (fresh-rate labeling). SPEC must correct the name. |

## Solvency Reservation-Site Walk (the SOLVENCY-01 / SOLVENCY-03 proof — read against source)

> For each "free ETH = totalBal − reserved" site: HOW it computes "reserved" + whether it sums `claimablePool` (the variable the keeper total rides inside per D-CF-03).

### SOLVENCY-01 sites

| # | Site | file:line (actual) | How "reserved" is computed | Keeper total reserved? |
|---|------|--------------------|----------------------------|------------------------|
| 1 | `JackpotModule.distributeYieldSurplus` | `:688` def; `:690-705` | `totalBal = balance + steth.balanceOf(this)`; `obligations = _getCurrentPrizePool() + _getNextPrizePool() + claimablePool + _getFuturePrizePool() + yieldAccumulator` (`:691-695`) **+ pending pools** `_getPendingPools()` (`:703`); `if (totalBal <= obligations) return;` | **YES** — `obligations` sums `claimablePool` at `:693`. Keeper total (riding inside `claimablePool`) is included automatically. The prior-omission class ([[project_yield_surplus_omits_pending_pools]]) is structurally impossible — same variable. ✓ |
| 2 | `GameOverModule.handleGameOverDrain` (pre-refund) | `:86` def; `:98-99` | `reserved = uint256(claimablePool)`; `preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0` | **YES** — `reserved = claimablePool` (`:98`). Keeper ETH not drained to the terminal jackpot. ✓ |
| 3 | `GameOverModule.handleGameOverDrain` (post-refund) | `:163-164` | `postRefundReserved = uint256(claimablePool)`; `available = totalFunds > postRefundReserved ? … : 0` | **YES** — `reserved = claimablePool` (`:163`), recomputed after refunds grew it. ✓ |
| 4 | `DegenerusGame.adminStakeEthForStEth` | `:2109` def; `:2114-2123` | `stethSettleable = claimableWinnings[VAULT] + claimableWinnings[SDGNRS]` (`:2116-2117`); `reserve = claimablePool > stethSettleable ? claimablePool - stethSettleable : 0` (`:2118-2120`); `if (ethBal <= reserve) revert; stakeable = ethBal - reserve;` | **YES** — `reserve` keys off `claimablePool` (minus the two stETH-settleable claimable buckets, which keeper funding is NOT). Keeper ETH never staked-away. ✓ **Note:** keeper funding is NOT stETH-settleable, so it correctly stays inside the ETH reserve. |
| 5 | `GameOverModule.handleFinalSweep` | `:202` def; `:215` | `claimablePool = 0` (plus zeroes `claimableWinnings[VAULT/SDGNRS/GNRUS]` `:211-214`) | **YES for the aggregate** — `claimablePool = 0` sweeps the keeper reservation. **⚠️ BUT does NOT zero per-player `keeperFunding[*]` — see Pitfall 1 / Open Q1.** |

**Verdict:** All 5 SOLVENCY-01 sites reserve `claimablePool` (inclusive of the keeper total) **with zero edits** — D-CF-03 holds against source. **No reservation site lets the keeper total escape.** The one gap is the *sweep ↔ per-player withdraw* interaction (Pitfall 1), which is a 344-IMPL design detail, not a SOLVENCY-01 reservation-escape.

### SOLVENCY-03 site (sDGNRS redemption valuation)

`StakedDegenerusStonk.sol` `:612` / `:772` / `:861` all compute:
```
totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue
  where ethBal       = address(this).balance        // sDGNRS's OWN balance
        stethBal     = steth.balanceOf(address(this))
        claimableEth = _claimableWinnings()          // :955 → game.claimableWinningsOf(address(this)) - 1
```
**Proof:** the valuation reads sDGNRS's OWN balance + ONLY what the Game owes **sDGNRS** (`claimableWinningsOf(sDGNRS)`). Keeper ETH lives in the **Game's** balance and is owed to **subscribers** (not sDGNRS), so it is invisible to this valuation — **exactly the same property the external AfKing pool has today** (AfKing's pool ETH was never in sDGNRS's balance either). **No redemption-valuation edit needed.** ✓ `[VERIFIED: grep + read StakedDegenerusStonk.sol:609-612,769-772,858-861,955-958]`

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reserved-ETH accounting for the keeper bucket | A new `keeperFundingPool` aggregate + bespoke reservation wiring at 5 sites | Ride inside the existing `claimablePool` (D-CF-03) | Every "free ETH" site already sums `claimablePool` (proven above). A new aggregate re-creates the prior-omission bug class. |
| Un-brickable withdraw | A fresh CEI withdraw with custom reentrancy guard | Mirror `AfKing.withdraw` `:328-341` (debit-before-send) | Carries the USER-LOCKED "never strands ETH" invariant already audited in v46/v48. |
| Deposit entrypoint | A new payable router | Mirror `AfKing.depositFor` `:314-318` | Same zero-value-no-op + emit shape; proven. |
| OPEN-E `keeperFunding[src]` read | A snapshot restructure to batch all `src` into the list | One extra `keeperFundingOf(src)` staticcall on the rare slice (mirror `:809`) | Common path stays single-staticcall (GASOPT-03); restructure deferred to 345 (D-MR-01 alt). |

**Key insight:** the entire design's safety comes from reusing audited patterns (`claimablePool`, `AfKing.withdraw` CEI, `depositFor`, the `:809` fallback). The SPEC's job is to attest those reuse-sites exist and behave as claimed — which they do.

## CLEANUP-01 Dead-Code Kill-Set Inventory (grep-attested)

> Every de-custody orphan, with its actual location AND a repo-wide caller grep proving it is truly orphaned after the batched removal. `[VERIFIED: grep on live tree]`.

| # | Kill-set item | Location (actual) | Remaining external callers (repo-wide, non-test) | Orphaned after removal? |
|---|---------------|-------------------|--------------------------------------------------|-------------------------|
| 1 | `AfKing._poolOf` mapping (slot 0) | `AfKing.sol:214` | Internal only (`:300,:307,:317,:330,:334,:413,:493,:695,:719`) — all inside AfKing fns being deleted/rewired | YES (all internal refs are in the kill-set or rewired) |
| 2 | `AfKing.receive()` | `AfKing.sol:298` | None external | YES |
| 3 | `AfKing.deposit()` | `AfKing.sol:305` | None | YES |
| 4 | `AfKing.depositFor()` | `AfKing.sol:314` | **grep `\.depositFor(`: 0 hits** | YES |
| 5 | `AfKing.withdraw()` | `AfKing.sol:328` | `afKing.withdraw(...)` at **`StakedDegenerusStonk.sol:539`** + **`DegenerusVault.sol:517`** — BOTH inside the v48 recovery legs (#9, #10) also being removed | YES — orphaned once #9/#10 removed (D-06 gate) |
| 6 | `AfKing.poolOf()` view | `AfKing.sol:492` | `afKing.poolOf(...)` at **`StakedDegenerusStonk.sol:539`** + **`DegenerusVault.sol:517`** — same two recovery legs only | YES — orphaned once #9/#10 removed (D-05) |
| 7 | Local CEI debit `_poolOf[src] -= ethValue` | `AfKing.sol:719` | n/a (statement, removed with the rewire) | YES |
| 8 | `IGame.batchPurchase` **payable** ABI | `AfKing.sol:43` (the ONLY interface decl) | Called once at `AfKing.sol:768` (`{value:}` → non-value). **NOT declared in `contracts/interfaces/`** (only a comment at `IDegenerusGameModules.sol:237`). | n/a — ABI changes payable→non-payable in place at `:43` + the Game def `:1824` + call `:768` |
| 9 | `DegenerusVault.recoverAfKingPool()` | `DegenerusVault.sol:516` | **grep `recoverAfKingPool`: 0 external callers** (only its own def) | YES — fully orphaned (D-06) |
| 10 | `StakedDegenerusStonk.burnAtGameOver` AfKing-withdraw leg | `StakedDegenerusStonk.sol:539` (within fn `:535`) | The leg is a statement; `burnAtGameOver` itself stays (it also burns sDGNRS) — only the `afKing.withdraw(...)` line is removed | YES (the line; the fn body remains) |
| 11 | sDGNRS `receive()` AF_KING relaxation | `StakedDegenerusStonk.sol:441` (within `receive()` `:439`) | After #10, AfKing never sends ETH back to sDGNRS → the `msg.sender != AF_KING` branch is dead | YES — narrow the guard to GAME-only |
| 12 | `sum(_poolOf) <= address(this).balance` invariant doc | `AfKing.sol:117` | Doc comment | YES (stale once `_poolOf` deleted) |
| 13 | Stale `_poolOf`-referencing comments | `AfKing.sol:84,117,143,193,370,447` | Doc comments | YES (update/remove with the rewire) |
| 14 | `Deposited` event (if now unused) | `AfKing.sol` (emitted at `:301,:308,:318,:414`) — **all four emit sites are in kill-set fns #2,#3,#4 + the `subscribe` credit being rewired** | grep within AfKing | **FLAG for 344:** likely fully orphaned after the de-custody (the subscribe credit moves to `game.depositKeeperFunding` → `KeeperFunded`). Confirm at IMPL. |

**Kill-set integrity gate (D-06):** items #5, #6 are orphaned ONLY after #9, #10 are removed in the same batched diff. The producer-before-consumer order must remove the recovery legs (Vault/sDGNRS) BEFORE (or atomically with) deleting `poolOf`/`withdraw`, else an intermediate state has a dangling reference. (This is fine in ONE batched diff — note it for the 344 edit-order map.)

**New AfKing IGame ABI to ADD (consumer of the new Game fns):** `AfKing.sol`'s `IGame` interface (`:40-56`) needs `depositKeeperFunding`, `withdrawKeeperFunding`, `keeperFundingOf`, and the extended `keeperSnapshot` return — and the `batchPurchase` decl at `:43` goes non-payable. This is an ADD, not a kill, but lives in the same interface block.

## GAS-01 Gas-Opportunity Inventory — Scope & Framing (advisory, D-02)

> 343 produces the **candidate list only** via `/gas-scavenger` (no validation/application — that is 345 under `/gas-skeptic`). This section scopes the blast radius and records the locked framing.

**Blast-radius files for `/gas-scavenger` (D-03 reach = touched files + the accounting spine the solvency proof walks):**
- `contracts/DegenerusGame.sol` (`batchPurchase` `:1824`, `_claimWinningsInternal` `:1462`, `keeperSnapshot` `:2645`, `adminStakeEthForStEth` `:2109`; the new deposit/withdraw/`keeperFundingOf`)
- `contracts/storage/DegenerusGameStorage.sol` (`claimablePool` `:355`, `claimableWinnings` `:402`; the new `keeperFunding`)
- `contracts/AfKing.sol` (the de-custodied loop + `_resolveBuy` + the `:809` fallback + the `IGame` block)
- `contracts/interfaces/IDegenerusGame*.sol` (signature updates)
- `contracts/modules/DegenerusGameJackpotModule.sol` (`distributeYieldSurplus` `:688`)
- `contracts/modules/DegenerusGameGameOverModule.sol` (drain `:86`, sweep `:202`)
- `contracts/StakedDegenerusStonk.sol` + `contracts/DegenerusVault.sol` (the recovery-leg removals)
- (read-only for the proof) the sDGNRS valuation `:609-612/769-772/858-861`

**Locked framing the inventory must carry forward (D-04 — the packing candidate):**
- `claimableWinnings` `{uint128 normal, uint128 keeper}` packing: width-safe (uint128 ≫ ETH supply; `claimablePool` already uint128) but **zero hot-path benefit** (an auto-buy touches one player slot + `claimablePool` either way) and ~15+ access-site blast radius on the central accounting variable (~9 credit + ~6 debit + `_processMintPayment` / `_settleClaimableShortfall` / `claimWinnings` / `claimableWinningsOf` / StakedStonk reads). Trades against `feedback_security_over_gas`. **Flag for 345 gas-skeptic; default = keep the separate mapping.** Do NOT evaluate/decide here.
- The ~9k/buy already saved by removing the per-batch value call is the baseline; GAS-01 enumerates wins BEYOND that, each tagged behavior-identical / same-results.

**Note for the planner:** `/gas-scavenger` is aggressive-by-design — expect candidates that 345 will reject. The 343 deliverable is the raw list + the packing framing, NOT a vetted set.

## Common Pitfalls

### Pitfall 1: Final sweep zeroes `claimablePool` but NOT per-player `keeperFunding[*]` → post-sweep withdraw underflows
**What goes wrong:** `GameOverModule.handleFinalSweep` (`:215`) sets `claimablePool = 0` and zeroes `claimableWinnings[VAULT/SDGNRS/GNRUS]` — but it does NOT iterate per-player mappings (it can't — unbounded). After the sweep, a player who never withdrew still has `keeperFunding[player] != 0` while `claimablePool == 0`. `withdrawKeeperFunding` debits `claimablePool -= uint128(amount)` → **underflow revert** (or, if unchecked, corruption). Symmetrically `_claimWinningsInternal` already guards this: it checks `_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0` at `:1463` and reverts (so the Decision-B keeper merge is naturally blocked post-sweep). `withdrawKeeperFunding` has no such guard in the PLAN-V54 §3 sketch.
**Why it happens:** the sweep is the 30-day forfeiture lifecycle (GAMEOVER-02 says "both withdraw/claim paths stay open until that sweep") — but the PLAN-V54 `withdrawKeeperFunding` sketch (§3) does the `claimablePool -= amount` unconditionally, with no `GO_SWEPT` check.
**How to avoid (SPEC must specify this):** `withdrawKeeperFunding` must either (a) revert post-sweep via the same `GO_SWEPT` latch that `_claimWinningsInternal:1463` uses, OR (b) the sweep must be understood as the hard cutoff and the SPEC must state that withdraw reverts once `GO_SWEPT` is set. This is a **design detail the 343 SPEC must lock** (it's within the locked mechanism, not a re-design) and the 344 edit-order map must carry. **This is the single genuine planning risk surfaced.**
**Warning signs:** any TST that withdraws after `handleFinalSweep` without expecting a revert.

### Pitfall 2: Keying the Game-side debit on `b.player` (the D-01 bug, already locked)
**What goes wrong:** REQUIREMENTS `AUTOBUY-02` + PLAN-V54 §4 literally say `keeperFunding[b.player] -= ev`. For the OPEN-E operator-funded case (`fundingSource != subscriber`), `src ≠ player`, so the funding lives in `keeperFunding[src]` (operator) but the debit hits `keeperFunding[player]` (subscriber, empty) → revert / mis-account.
**How to avoid:** D-01 is locked — debit `keeperFunding[b.funder]`. The SPEC MUST record the correction to AUTOBUY-02 + PLAN-V54 §4 and add the `funder` field to BOTH `BatchBuy` structs (`AfKing.sol:20` + `DegenerusGame.sol:1796`). Confirmed against source: `src` resolves at `AfKing.sol:686`; the VAULT/SDGNRS exemption at `:696` stays keyed on `player`.

### Pitfall 3: `keeperSnapshot` carries `keeperFunding[player]`, not `keeperFunding[src]` (D-MR-01, already locked)
**What goes wrong:** the extended `keeperSnapshot` is keyed on the per-player subscriber array. `src` resolves at `AfKing.sol:686` AFTER `_resolveBuy`'s snapshot read (`:809`). So for OPEN-E (`src ≠ player`), the snapshot does NOT carry the funder's balance.
**How to avoid:** D-MR-01 locked — one extra `game.keeperFundingOf(src)` staticcall for the rare operator-funded slice (mirror `:809`). The SPEC must REFINE AUTOBUY-05's "ONE staticcall per player" to name this carve-out. Confirmed against source: read-order is `keeperSnapshot` at `:809` (inside `_resolveBuy` `:789`) THEN `src` at `:686` (in `_autoBuy`).

### Pitfall 4: Stale line numbers in the IMPL edit-order map
**What goes wrong:** the 344 diff is authored against doc-cited lines that are off by 1-15 (and two are name-drifted). An edit lands at the wrong line or references a non-existent `payAffiliate`.
**How to avoid:** the 343 `343-GREP-ATTESTATION.md` MUST carry the Drift-Correction Table above; the `343-IMPL-EDIT-ORDER-MAP.md` must cite ACTUAL lines.

## State of the Art

| Old (v53) | New (v54) | When | Impact |
|-----------|-----------|------|--------|
| AfKing custody: `_poolOf[player]` + per-auto-buy `batchPurchase{value: totalValue}` value transfer across the AfKing→Game boundary | Game-side `keeperFunding[player]` riding inside `claimablePool`; non-payable `batchPurchase` (pure in-contract reclassification) | v54.0 (this milestone) | Structurally retires the entire v52 ETH/claimable-plumbing bug class (no boundary value transfer). |
| `BatchBuy{player, ethValue, amount, isTicket, mode}` | `BatchBuy{funder, player, ethValue, amount, isTicket, mode}` (D-01) | v54.0 | The funder (`src`) and beneficiary (`player`) split is now explicit in the struct; debit keys on `funder`. |
| v48 stuck-pool recovery (`recoverAfKingPool`, `burnAtGameOver` AfKing leg, sDGNRS `receive()` AF_KING relaxation) | Removed (D-06) — VAULT/sDGNRS funding is now game-side `keeperFunding`, withdrawable directly | v54.0 | Dead-code removal; the [[v48-afking-pool-recovery]] mechanism is MOOT. |

**Deprecated/outdated:**
- `DegenerusAffiliate.payAffiliate` — **never existed**; the function is `handleAffiliate` (`:36`). Any doc referencing `payAffiliate` is wrong.
- The cited `batchPurchase :1809` — actual `:1824`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The working tree at HEAD `3187d68e` is byte-identical to v53 HEAD `83a84431` in `contracts/`, so greps on the live tree are valid attestations. | (all) | LOW — `[VERIFIED: git diff --numstat 83a84431 HEAD -- contracts/ → empty]`. Not an assumption, a verified fact. Listed for transparency. |
| A2 | No on-chain `_poolOf` balances are live (pre-launch redeploy-fresh), so no data migration is needed. | Runtime State Inventory | MEDIUM — sourced from PLAN-V54 §2 + `feedback_frozen_contracts_no_future_proofing` (project docs), not independently verified on-chain. If a live pool existed, withdraw-before-redeploy would be required. The planner/USER already locked "no live AfKing pools." |
| A3 | The `Deposited` event (AfKing) is fully orphaned after de-custody. | CLEANUP-01 #14 | LOW — all 4 emit sites are in kill-set fns; flagged for IMPL confirmation, not asserted as final. |

**Most claims in this research are `[VERIFIED]` against source** (grep on the live tree). The only true assumption is A2 (no live pools), which is a project-locked decision, not new research.

## Open Questions

1. **Does `withdrawKeeperFunding` need a `GO_SWEPT` guard? (Pitfall 1)**
   - What we know: the final sweep (`GameOverModule:215`) zeroes `claimablePool` but not per-player `keeperFunding[*]`. `_claimWinningsInternal:1463` already reverts post-sweep via `_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK)`. The PLAN-V54 §3 `withdrawKeeperFunding` sketch has no such guard.
   - What's unclear: whether the SPEC intends withdraw to revert post-sweep (the forfeiture cutoff) or whether the sketch is simply incomplete.
   - Recommendation: the 343 SPEC must LOCK this — recommended: `withdrawKeeperFunding` reverts once `GO_SWEPT` is set (same latch as `_claimWinningsInternal:1463`), consistent with GAMEOVER-02's "both paths open until that sweep." This is within the locked mechanism (a CEI/lifecycle detail), not a re-design. **Surface this to the D-07 adversarial red-team** as a charged probe.

2. **Should the SPEC's `343-IMPL-EDIT-ORDER-MAP.md` enumerate the two-copy invariant comment (`DegenerusGame.sol:5` AND `:18`)?**
   - What we know: the master invariant comment appears TWICE in `DegenerusGame.sol` (`:5` and `:18`); PLAN-V54 §5 #1 cites only `:18`.
   - Recommendation: update BOTH copies in the 344 diff; the edit-order map should list both lines.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `git` | attestation vs `83a84431` | ✓ | (repo) | — |
| `grep` | call-graph attestation | ✓ | — | — |
| Foundry / `forge` | (344+ build; not 343) | (not probed — 343 is paper-only) | forge-std v1.15.0 | — |
| `/gas-scavenger` skill | GAS-01 advisory list (D-02) | ✓ | `~/.claude/skills/gas-scavenger/SKILL.md` | — |
| `/economic-analyst` skill | SOLVENCY red-team (D-07) | ✓ | `~/.claude/skills/economic-analyst/SKILL.md` | — |
| `/contract-auditor` skill | SOLVENCY red-team (D-07) | ✓ | `~/.claude/skills/contract-auditor/SKILL.md` | — |

**No missing dependencies.** 343 is paper-only (read/grep + skill invocations); no external services, no installs.

## SPEC Deliverable Precedent (D-08 — modeled on real files)

> `[VERIFIED: ls of the precedent dirs]`. The planner should model the 343 multi-doc set on these.

**v50 Phase-334** (`.planning/milestones/v50.0-phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/`):
- `334-SPEC-INDEX.md` (the index — D-08's `343-SPEC-INDEX.md`)
- `334-GREP-ATTESTATION.md` (the call-graph attestation — D-08's `343-GREP-ATTESTATION.md`)
- `334-IMPL-EDIT-ORDER-MAP.md` (the producer-before-consumer map — D-08's `343-IMPL-EDIT-ORDER-MAP.md`)
- `334-DESIGN-LOCK-AFKING.md` + `334-DESIGN-LOCK-WHALE-MINTDIV.md` (the design-lock docs)
- `334-WHALE04-FREEZE-PROOF.md` + `334-MINTDIV01-REACHABILITY-VERDICT.md` (the proof/verdict docs — the precedent for D-08's `343-SOLVENCY-PROOF.md`)
- (also: `334-RNGAUDIT-STRUCTURE-SKETCH.md`, `334-CONTEXT.md`, `334-RESEARCH.md`, `334-DISCUSSION-LOG.md`, `334-VERIFICATION.md`, `334-0{1..4}-PLAN.md`/`SUMMARY.md`)

**v49 Phase-329** (`.planning/milestones/v49.0-phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/`):
- `329-SPEC.md` (the monolithic SPEC — the alternative D-08 rejects in favor of the multi-doc split)
- `329-ATTEST-DEGENERETTE-RESOLVE.md` + `329-ATTEST-ROUTER-ADVANCE.md` (the call-graph attestation precedent — `329-ATTEST-*.md` pattern)
- (also: `329-CONTEXT.md`, `329-REVIEW.md`, `329-VERIFICATION.md`, `329-DISCUSSION-LOG.md`, `329-0{1..3}-PLAN.md`/`SUMMARY.md`)

**Recommended 343 set (D-08 — planner may split/merge, keep five concerns discrete):**
`343-SPEC-INDEX.md` · `343-GREP-ATTESTATION.md` (the Drift Table) · `343-SOLVENCY-PROOF.md` (the Reservation-Site Walk + SOLVENCY-03 + the Pitfall-1 lock + OPEN-E carry-over) · `343-CLEANUP-INVENTORY.md` (the Kill-Set) · `343-GAS-INVENTORY.md` (the `/gas-scavenger` output + packing framing) · `343-IMPL-EDIT-ORDER-MAP.md` (producer-before-consumer, ACTUAL lines).

## Sources

### Primary (HIGH confidence — grep/read on the live tree, byte-identical to `83a84431`)
- `contracts/DegenerusGame.sol` — `batchPurchase:1824`, `BatchBuy:1796`, `purchaseWith call:1838`, `keeperSnapshot:2645`, `_claimWinningsInternal:1462`, `adminStakeEthForStEth:2109`, invariant `:5`/`:18`, `receive:2915`, `_processMintPayment:968/981/1003`
- `contracts/storage/DegenerusGameStorage.sol` — `claimablePool:355`, comment `:345-354`, `claimableWinnings:402`, `keeperFunding` ABSENT
- `contracts/AfKing.sol` — `_poolOf:214`, `receive:298`, `deposit:305`, `depositFor:314`, `withdraw:328`, `subscribe:381`, OPEN-E gate `:399-409`, msg.value credit `:413`, `poolOf:492`, `src:686`, funding-skip `:695/:696`, CEI debit `:719`, `BatchBuy:20`, build `:726`, call `:768`, `IGame:40`, `batchPurchase ABI:43`, `keeperSnapshot ABI:56`, fallback `:809`, invariant doc `:117`
- `contracts/modules/DegenerusGameJackpotModule.sol` — `distributeYieldSurplus:688`, `claimablePool` term `:693`
- `contracts/modules/DegenerusGameGameOverModule.sol` — drain `:86`/`:98`/`:163`, sweep `:202`/`:215`
- `contracts/StakedDegenerusStonk.sol` — valuation `:612`/`:772`/`:861`, `_claimableWinnings:955`, `burnAtGameOver:535`, AfKing leg `:539`, `receive` AF_KING `:441`
- `contracts/DegenerusVault.sol` — `recoverAfKingPool:516`, leg `:517`
- `contracts/DegenerusAffiliate.sol` — `handleAffiliate:36`, fresh constants `:164/:165`, doc `:18-21` (corrects the `payAffiliate` name drift)
- `contracts/modules/DegenerusGameMintModule.sol` — `purchaseWith:864`, `_purchaseForWith:1042`, ethValue param `:870`/`:1048`
- `contracts/interfaces/IDegenerusGameModules.sol` — `batchPurchase` comment-only `:237` (no payable decl here)
- `test/fuzz/{JackpotSingleCallCorrectness:187, StakedStonkRedemption:850/880, FarFutureSalvageSwap:111/112, YieldSurplusSolvency:114/134}`, `test/fuzz/invariant/MultiLevel.inv.t.sol:73`, `test/halmos/GameFSM.t.sol:97-99` — strict-equality + inequality assertions
- `git diff --numstat 83a84431 HEAD -- contracts/` → empty (tree byte-identical)
- `foundry.toml` (`src=contracts`, `test=test`, forge-std v1.15.0)
- `~/.claude/skills/{contract-auditor,economic-analyst,zero-day-hunter,gas-scavenger,gas-skeptic}/SKILL.md`
- Precedent dirs `.planning/milestones/v50.0-phases/334-*/` + `.planning/milestones/v49.0-phases/329-*/`

### Secondary (project docs — the locked design, not independently re-derived)
- `.planning/PLAN-V54-KEEPER-FUNDING-GAME-LEDGER.md` (§2-§10), `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` §"Phase 343", `343-CONTEXT.md`

## Metadata

**Confidence breakdown:**
- Call-graph attestation / Drift Table: **HIGH** — every anchor grep-pinned with matched text on the byte-identical tree.
- Solvency Reservation-Site Walk (SOLVENCY-01/03): **HIGH** — all 5 reservation sites + the sDGNRS valuation read against source; `claimablePool`-keyed reservation confirmed at each.
- CLEANUP-01 kill-set: **HIGH** — repo-wide caller grep proves `poolOf`/`withdraw`/`recoverAfKingPool` orphaned after the v48-recovery removal.
- D-01 / D-MR-01 findings: **HIGH** — confirmed against source (`src:686`, exemption-on-`player`:696, snapshot-read-order `:809` before `src:686`).
- Pitfall 1 (sweep ↔ withdraw underflow): **HIGH that the gap exists** (sweep `:215` zeroes only the aggregate; `_claimWinningsInternal:1463` has the `GO_SWEPT` guard the withdraw sketch lacks); **MEDIUM on the fix** (the SPEC/USER must lock revert-vs-other — surfaced as Open Q1).
- A2 (no live pools): **MEDIUM** — project-locked decision, not on-chain-verified.

**Research date:** 2026-05-30
**Valid until:** until the next `contracts/` mutation (i.e., the 344 IMPL diff). The attestation is a point-in-time snapshot of `83a84431`; re-run the greps if the subject HEAD moves before 344.
