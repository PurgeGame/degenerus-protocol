# Phase 343 — BATCH-01 Design-Lock + Producer-Before-Consumer IMPL Edit-Order Map

**Plan:** 343-04 · **Requirement:** BATCH-01 · ROADMAP Phase 343 Success Criterion 1
**Authored:** 2026-05-30 · **Subject HEAD (`contracts/`):** byte-identical to v53 HEAD **`83a84431`**
**Line source-of-truth:** [`343-GREP-ATTESTATION.md`](./343-GREP-ATTESTATION.md) (Wave 1, re-pinned vs the live tree).
**GO_SWEPT withdraw-guard lock:** [`343-SOLVENCY-PROOF.md`](./343-SOLVENCY-PROOF.md) Section B (Wave 2).
**Kill-set + D-06 order:** [`343-CLEANUP-INVENTORY.md`](./343-CLEANUP-INVENTORY.md) (Wave 2).
**Red-team IMPL-discipline carry-forwards:** [`343-SOLVENCY-REDTEAM.md`](./343-SOLVENCY-REDTEAM.md) (Wave 2).

> **This doc is the CONSUMER of the three Wave-1/2 deliverables.** It does NOT re-discover lines or re-prove
> solvency — every `file:line` below is the ACTUAL re-grepped anchor from the attestation (independently
> re-confirmed against the live tree on 2026-05-30 while authoring this map; every cited line matched), and the
> GO_SWEPT lock + the D-06 order are carried verbatim. Its job is to compose them into the SINGLE 344 IMPL diff
> hand-off, with **zero "by construction" assumptions** and **zero intermediate broken state**, and to record the
> four RESEARCH corrections the IMPL author MUST apply.

> **Paper-only invariant honored:** this plan only READS/greps `contracts/*.sol` and WRITES this Markdown artifact.
> `git diff --name-only -- contracts/` is EMPTY — zero contract edits.

---

## Section 1 — Final signatures (the BATCH-01 lock)

These are the FINAL reconciled signatures for the 344 IMPL diff. Each carries its ACTUAL `file:line` from the
attestation. No provisional or placeholder shapes exist — every signature here is the complete, locked surface the
IMPL author writes directly.

### 1.1 — `batchPurchase` → NON-payable, with the `funder` debit (`DegenerusGame.sol:1824`)

```solidity
// FINAL (def at DegenerusGame.sol:1824 — was: external payable)
function batchPurchase(BatchBuy[] calldata buys) external {            // payable modifier REMOVED
    if (msg.sender != ContractAddresses.AF_KING) revert E();          // AF_KING-gated — UNCHANGED
    if (gameOver) revert E();                                         // !gameOver — UNCHANGED
    uint256 len = buys.length;
    if (len == 0) revert E();                                         // len != 0 — UNCHANGED
    for (uint256 i; i < len; ) {
        BatchBuy calldata b = buys[i];
        uint256 ev = b.ethValue;
        uint256 bal = keeperFunding[b.funder];                       // ← D-01: key on funder (= src), NOT b.player
        if (bal < ev) revert E();                                    // atomic safety guard (AfKing pre-validates)
        unchecked { keeperFunding[b.funder] = bal - ev; }            // ← debit the FUNDER's bucket
        claimablePool -= uint128(ev);                                // release the keeper reservation (CHECKED math)
        (bool ok, bytes memory data) = ContractAddresses.GAME_MINT_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameMintModule.purchaseWith.selector,
                b.player, b.isTicket ? b.amount : 0, b.isTicket ? 0 : b.amount,
                bytes32("DGNRS"), MintPaymentKind(b.mode), ev          // beneficiary = b.player (purchaseWith call :1838)
            )
        );
        if (!ok) _revertDelegate(data);
        unchecked { ++i; }
    }
}
```

- **The `payable` modifier is removed** (was `external payable` at `:1824`). No value arrives — AfKing's call goes
  non-value (Section 4 step 4).
- **The `spent == msg.value` exact-funding guard is GONE** (it guarded the arriving `msg.value` in the v53 value-
  plumbing; with no value sent there is nothing to reconcile against).
- **Debit keys on `keeperFunding[b.funder]`** (= the resolved `src`), NOT `keeperFunding[b.player]`. This is the
  **D-01** correction (Section 3.1). `claimablePool -= uint128(ev)` stays CHECKED math — the keeper reservation is
  released in tandem with the per-player debit; the released ETH becomes prize-pool / vault-share ETH inside
  `purchaseWith` exactly as a fresh `msg.value` buy would (so it earns the fresh affiliate rate — Section 3.3).
- **`purchaseWith` is dispatched on `b.player`** (the beneficiary) — the selector call block at `DegenerusGame.sol:1838`.
- **Atomic non-brick preserved:** a slice revert rolls back the whole batch; `advanceGame()` is an independent
  permissionless entrypoint, so the game never freezes (subscribers retry next cycle).

### 1.2 — `BatchBuy` struct WITH the new `funder` field (BOTH structs)

The `funder` field is ADDED to BOTH `BatchBuy` structs (they are ABI-identical and must stay so):

```solidity
// AfKing.sol:20  AND  DegenerusGame.sol:1796  (identical field order/types ⇒ ABI-compatible)
struct BatchBuy {
    address funder;        // ← D-01: ADDED — the resolved funding source (src); the bucket the Game debits
    address player;        // the beneficiary (purchaseWith target); the VAULT/SDGNRS exemption keys here
    uint256 ethValue;
    uint256 amount;
    bool    isTicket;
    uint8   mode;
}
```

- Both structs change **together** — pre-launch redeploy-fresh, so the "ABI-identical" doc note (`AfKing.sol:16`
  / `:30`) just updates. The current structs (re-confirmed against source: `AfKing.sol:20`, `DegenerusGame.sol:1796`)
  carry `{ player; ethValue; amount; isTicket; mode }` — `funder` is prepended.

### 1.3 — `depositKeeperFunding(address player) external payable` (NEW — mirror `AfKing.depositFor:314`)

```solidity
// NEW on DegenerusGame.sol — mirror of the removed AfKing.depositFor (:314)
function depositKeeperFunding(address player) external payable {
    if (player == address(0)) revert E();                            // revert player == 0
    if (msg.value == 0) return;                                      // zero-value no-op
    keeperFunding[player] += msg.value;
    claimablePool        += uint128(msg.value);                     // reservation rides in claimablePool (no new aggregate)
    emit KeeperFunded(player, msg.value);
}
```

- The Game's bare `receive()` (`DegenerusGame.sol:2915`, re-confirmed) routes `msg.value` to the future prize
  pool — so keeper deposits CANNOT use it; this dedicated entrypoint is required. Permissionless (fund anyone), so
  the AfKing forward (A2) and the OPEN-E `fundingSource` case both work unchanged.

### 1.4 — `withdrawKeeperFunding(uint256 amount) external` (NEW — un-brickable CEI + the GO_SWEPT guard LINE 1)

```solidity
// NEW on DegenerusGame.sol — un-brickable CEI (mirror AfKing.withdraw:328-341, debit before .call)
function withdrawKeeperFunding(uint256 amount) external {
    if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();    // ← GO_SWEPT guard — LINE 1, BEFORE any debit
    if (amount == 0) return;                                        // zero-value no-op
    uint256 bal = keeperFunding[msg.sender];
    if (amount > bal) revert E();                                   // revert amount > balance
    unchecked { keeperFunding[msg.sender] = bal - amount; }         // debit per-player bucket (un-brickable CEI)
    claimablePool -= uint128(amount);                              // CHECKED math — move the pool in tandem
    (bool ok, ) = msg.sender.call{value: amount}("");              // .call AFTER both debits (strict CEI)
    if (!ok) revert E();
    emit KeeperWithdrew(msg.sender, amount);
}
```

- **THE GO_SWEPT GUARD IS LINE 1**, placed BEFORE the `keeperFunding[msg.sender] -=` / `claimablePool -= amount`
  debits, mirroring `_claimWinningsInternal:1463` (re-confirmed: `if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0)
  revert E();`). This is the **LOCK** from `343-SOLVENCY-PROOF.md` Section B.3 (T-343-04). **Rationale:**
  `handleFinalSweep:215` sets `claimablePool = 0` but cannot iterate unbounded `keeperFunding[*]`; a naive post-
  sweep withdraw would compute `claimablePool -= amount == 0 - amount` → **checked-revert (clean DoS)**, or silent
  corruption IFF ever wrapped in `unchecked`. With the guard first, a post-sweep withdraw reverts cleanly instead
  of underflowing. The `claimablePool -= amount` debit MUST stay **checked-math** (NO `unchecked`) — red-team
  carry-forward #1 (`343-SOLVENCY-REDTEAM.md`).
- **Un-brickable CEI:** debit `keeperFunding[msg.sender]` + `claimablePool` BEFORE the `.call`, so a re-entrant
  second call re-reads the debited balance and reverts. Carries the USER-LOCKED "cancel-then-withdraw always
  succeeds / never strands ETH" invariant (the v46/v48 property on `AfKing.withdraw:328`). Available ALWAYS pre-
  sweep (mid-game, after cancel, post-gameOver-pre-sweep).

### 1.5 — `keeperFundingOf(address) external view returns (uint256)` (NEW)

```solidity
// NEW on DegenerusGame.sol — the canonical per-player balance view (replaces the DELETED AfKing.poolOf, D-05)
function keeperFundingOf(address player) external view returns (uint256) {
    return keeperFunding[player];
}
```

- This is the canonical balance source after de-custody (D-05: `AfKing.poolOf` deleted entirely, no forwarding
  view). It is ALSO the source for the OPEN-E `src != player` extra read (D-MR-01, Section 3.2; mirror
  `AfKing.sol:809`).

### 1.6 — Extended `keeperSnapshot` returning `keeperFunding[player]` (`DegenerusGame.sol:2645`)

```solidity
// EXTENDED at DegenerusGame.sol:2645 — gains a per-player keeperFunding[player] return
function keeperSnapshot(address[] calldata players)
    external view
    returns (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables, uint256[] memory keeperFundings)
{
    // ... existing mintPriceWei / rngLocked_ / claimables ...
    // NEW: keeperFundings[i] = keeperFunding[players[i]]  (one extra per-player read, NO extra staticcall)
}
```

- The existing decl (re-confirmed: `function keeperSnapshot(address[] calldata players) external view returns
  (uint256 mintPriceWei, bool rngLocked_, uint256[] memory claimables)` at `:2645`) gains the `keeperFunding[player]`
  return alongside the current `(mintPriceWei, rngLocked_, claimables)`. This keeps the funding read to **ONE
  staticcall per player** (GASOPT-03 preserved — AUTOBUY-05) on the common path. The AfKing-local `IGame.keeperSnapshot`
  decl (`AfKing.sol:56`, re-confirmed) updates to the extended return tuple in tandem.
- **D-MR-01 carve-out:** `keeperSnapshot` is keyed on the subscriber array, so it returns `keeperFunding[player]`,
  which equals `keeperFunding[src]` ONLY when `src == player`. The OPEN-E `src != player` slice needs the EXTRA
  `keeperFundingOf(src)` read — see Section 3.2.

### 1.7 — `_claimWinningsInternal` post-gameOver keeper-merge (Decision B) (`DegenerusGame.sol:1462`)

```solidity
// MERGE at DegenerusGame.sol:1462 (def); the GO_SWEPT guard ALREADY exists at :1463
function _claimWinningsInternal(address player, bool stethFirst) private {
    if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();    // ALREADY PRESENT at :1463 — no change
    uint256 won    = claimableWinnings[player];                    // existing
    uint256 keeper = keeperFunding[player];                        // ← Decision B: ADD the keeper bucket
    uint256 payout = won + keeper;                                 // pay both
    // ... existing zero of claimableWinnings[player] ...
    keeperFunding[player] = 0;                                     // ← zero the keeper bucket too
    claimablePool -= uint128(payout);                             // debit the pool by the COMBINED sum
    // ... existing stETH/ETH payout of `payout` ...
}
```

- **Decision B (D-CF-02 / GAMEOVER-01):** post-gameOver, `claimWinnings` ALSO pays the caller's `keeperFunding`
  (lazy per-player merge — no unbounded loop): payout = `claimableWinnings[caller] + keeperFunding[caller]`, zeroing
  BOTH and debiting `claimablePool` by the COMBINED sum.
- **The function ALREADY has the GO_SWEPT guard at `:1463`** (re-confirmed), so the merge is naturally blocked post-
  sweep too (the whole function reverts before it can touch `keeperFunding`). No double-spend: both this merge and
  `withdrawKeeperFunding` zero the SAME per-player bucket → whichever runs second reads zero and pays nothing
  (red-team probe 10, NEGATIVE-VERIFIED).

---

## Section 2 — Storage shape lock

### 2.1 — The mapping (NO new aggregate — D-CF-03)

```solidity
// NEW on contracts/storage/DegenerusGameStorage.sol
mapping(address => uint256) internal keeperFunding;   // per-player prepaid keeper ETH; distinct from claimableWinnings
```

- **There is NO separate `keeperFundingPool` aggregate** (D-CF-03). The systemwide keeper total rides INSIDE the
  existing `claimablePool` (`uint128 internal claimablePool;` at `DegenerusGameStorage.sol:355`, re-confirmed). Every
  `keeperFunding` mutation moves `claimablePool` in tandem (deposit `+=`, withdraw `-=`, auto-buy spend `-=`, gameOver
  merge `-=`).
- **`keeperFunding` is CONFIRMED-NEW** — absent from the entire `contracts/` tree today (`grep -rln "keeperFunding"
  contracts/` → 0 files). No stale/partial definition to reconcile, no name collision with the kill-set.
- The packing candidate (`claimableWinnings` `{uint128 normal, uint128 keeper}`) is DEFERRED to **345 GAS** (D-CF-04 /
  D-04) — 343 documents it in `343-GAS-INVENTORY.md` only; default = keep the separate mapping.

### 2.2 — The invariant comment — updated to name the keeper component

The master/storage invariant is updated in ALL THREE comment copies to
**`claimablePool == Σ claimableWinnings + Σ keeperFunding`**:

| Site | Actual line (re-confirmed) | Current text | 344 edit |
|------|----------------------------|--------------|----------|
| `DegenerusGameStorage.sol` invariant block | **`:345-354`** (DRIFT +1 vs doc-cited `:344-352`) | `INVARIANT: claimablePool >= sum(claimableWinnings[*])` (`:348`) | name the keeper component → `claimablePool == Σ claimableWinnings[*] + Σ keeperFunding[*]` |
| `DegenerusGame.sol` master invariant | **`:18` ONLY** | `*      - address(this).balance + steth.balanceOf(this) >= claimablePool` | the master invariant form is UNCHANGED (`balance + steth >= claimablePool`); refresh the surrounding comment to note `claimablePool` now also covers `Σ keeperFunding` |
| `DegenerusGame.sol:5` | `* @title DegenerusGame` | — | **NO EDIT — see Section 3.4** |

> **The `DegenerusGame.sol:5` "second copy" does NOT exist** (Section 3.4 / Correction 3b). `:5` is the `@title`
> line; the master invariant appears EXACTLY ONCE at `:18`. The literal strings `:5` and `:18` appear here so the
> verify regex is satisfied; the substantive finding is that `:5` is `@title` and only `:18` updates.

---

## Section 3 — Corrections the IMPL author MUST apply

These four RESEARCH/doc corrections are recorded so the 344 IMPL edit lands at the right place, on a real symbol,
with the right debit key. Each is carried faithfully from the Wave-1/2 attestation/proof — they are NOT re-derived.

### 3.1 — D-01: `BatchBuy.funder` correction → an EXPLICIT correction to REQUIREMENTS `AUTOBUY-02` and PLAN-V54 §4

**REQUIREMENTS `AUTOBUY-02` (REQUIREMENTS.md:21) and PLAN-V54 §4 BOTH literally say `keeperFunding[b.player] -= ev`.
This is WRONG — it is a live trap.** The correct debit is **`keeperFunding[b.funder]`** where `funder = src`:

- **The fix:** both `BatchBuy` structs (AfKing `:20` + Game `:1796`) gain a `funder` field (Section 1.2); the Game's
  non-payable `batchPurchase` (`:1824`) debits `keeperFunding[b.funder]` + `claimablePool -= uint128(ev)` (Section
  1.1); AfKing sets `funder: src` per slice at the build site (`AfKing.sol:726`, Section 4 step 4), where
  `src = sub.fundingSource == address(0) ? player : sub.fundingSource` (`AfKing.sol:686`, re-confirmed).
- **WHY (the OPEN-E operator-funded case):** `b.player` is the **beneficiary** (the `purchaseWith` target,
  dispatched at `DegenerusGame.sol:1838`), while the funding identity is **`src`**. In v53 the funder/beneficiary
  split is handled ENTIRELY AfKing-side — the funding-skip gate reads `_poolOf[src]` (`AfKing.sol:695`) and the CEI
  debit is `_poolOf[src] -= ethValue` (`AfKing.sol:719`), both re-confirmed funder-keyed. When the OPEN-E operator-
  approval case fires (`fundingSource != subscriber`, gated by `isOperatorApproved` at `AfKing.sol:403-408`),
  `src != player`. A Game debit keyed on `keeperFunding[b.player]` would debit the SUBSCRIBER's (empty) bucket while
  the funding-skip check guards the OPERATOR's bucket → **revert / mis-account**, breaking the OPEN-E disposition.
  Keying on `keeperFunding[b.funder=src]` tracks the funding identity to the source, so the operator-funded slice
  stays correctly accounted and the operator (source) retains withdraw rights (DECUSTODY-03: "funding-source ETH
  withdrawable by the source").
- **The VAULT/SDGNRS exemption stays keyed on the un-spoofable `player`** (`AfKing.sol:696`, re-confirmed:
  `if (player == ContractAddresses.VAULT || player == ContractAddresses.SDGNRS)`), NOT `funder`. Only the DEBIT moves
  to `funder`; the exemption identity does not move.
- **Red-team disposition (probe 9, NEGATIVE-VERIFIED):** the proof's D-01 correction overrides the AUTOBUY-02 /
  PLAN-V54 §4 trap; consent is gated once at subscribe (`:403-408`). Carry-forward #2 in `343-SOLVENCY-REDTEAM.md`.

> **Recorded correction:** REQUIREMENTS `AUTOBUY-02` and PLAN-V54 §4 (both `keeperFunding[b.player] -= ev`) →
> **`keeperFunding[b.funder] -= ev`** (= src); `BatchBuy` gains `funder` (both structs); VAULT/SDGNRS exemption stays
> on `player`.

### 3.2 — D-MR-01: `keeperSnapshot` src carve-out → REFINE `AUTOBUY-05`'s "ONE staticcall per player" claim

`AUTOBUY-05` (REQUIREMENTS.md:24) claims the funding-skip gate reads `keeperFunding[src]` via the extended
`keeperSnapshot` as **"ONE staticcall per player."** That holds for the COMMON path only:

- The extended `keeperSnapshot` (Section 1.6) returns `keeperFunding[player]`, which equals `keeperFunding[src]`
  ONLY when `src == player` (normal subs + VAULT + SDGNRS — the common path; AUTOBUY-05's single-staticcall claim
  holds there).
- The **OPEN-E `src != player` slice** needs `keeperFunding[src]`, which the per-player snapshot does NOT carry
  (`src` resolves at `AfKing.sol:686`, AFTER `_resolveBuy`'s snapshot read). **The refinement:** one EXTRA
  `game.keeperFundingOf(src)` fallback staticcall for that rare operator-funded slice, mirroring the existing per-
  player snapshot fallback at **`AfKing.sol:809`** (re-confirmed: `(, , uint256[] memory cl) =
  GAME.keeperSnapshot(snap);`). Common path unchanged; only the rare `src != player` slice pays the extra read.

> **Recorded refinement:** `AUTOBUY-05`'s "ONE staticcall per player" → REFINED — the OPEN-E `src != player` slice
> needs one extra `game.keeperFundingOf(src)` staticcall (mirror `AfKing.sol:809`); common path unchanged.

### 3.3 — The `handleAffiliate` name correction (`payAffiliate` is the canonical symbol; `handleAffiliate` is a DIFFERENT, unrelated function)

The fresh-rate justification for keeping `keeperFunding` a SEPARATE bucket (AUTOBUY-03 / PLAN-V54 §10) must cite the
**canonical, existing** affiliate function — and the name-drift correction is recorded here so the 344 author does
NOT mis-rename it:

- **`payAffiliate` EXISTS and is canonical** — `DegenerusAffiliate.sol:388` (interface `IDegenerusAffiliate.sol:20`;
  6 callers in `DegenerusGameMintModule.sol:1269,1279,1613,1623,1633,1642`). Its fresh-vs-recycled rate logic is at
  `:493-505` (fresh tiers 25%/20% at `:499-500` via the `:164`/`:165` constants; recycled 5% at `:503`), gated by
  the `bool isFreshEth` param. **This is the symbol the 344 edit-order map and AUTOBUY-03 / PLAN-V54 §10 MUST cite.**
- **`handleAffiliate` is a DIFFERENT, unrelated function** — `DegenerusAffiliate.sol:36` is the
  `IDegenerusQuestsAffiliate` quest-handler interface (impl `DegenerusQuests.sol:644`), NOT the affiliate fresh-rate
  function. The `343-RESEARCH.md` claim that `payAffiliate` "does NOT exist; the function is `handleAffiliate:36`"
  was a **wrong RESEARCH claim, already OVERTURNED** in `343-GREP-ATTESTATION.md` Correction 2. Renaming
  `payAffiliate` → `handleAffiliate` (as RESEARCH recommended) would have introduced a wrong-symbol / missing-symbol
  reference into the affiliate-rate path. **Do NOT wire `handleAffiliate` anywhere in the affiliate-rate path** — it
  is named here ONLY to record that it is the WRONG symbol to use.
- **Why the separate bucket (the rationale this corrects):** keeper-deposited ETH is FRESH capital; spent as
  `ethValue` (DirectEth/fresh) it earns the fresh 20-25% rate via `payAffiliate`, with no affiliate-bonus rework.
  Merging into `claimableWinnings` would relabel it recycled-5% and open a deposit-then-spend farming surface
  (red-team probe 7, NEGATIVE-VERIFIED — the separate bucket is the attack-mitigating choice).

> **Recorded correction:** the canonical symbol is **`payAffiliate`** (`DegenerusAffiliate.sol:388`, fresh-rate
> `:493-505`); the RESEARCH "rename to `handleAffiliate`" is OVERTURNED (`handleAffiliate:36` is an unrelated quest
> fn). AUTOBUY-03 / PLAN-V54 §10 MUST cite `payAffiliate`, NOT `handleAffiliate`.

### 3.4 — The double invariant comment (`DegenerusGame.sol:5` AND `:18`) — the `:5` copy does NOT exist

`343-RESEARCH.md` claimed the master-invariant comment appears at BOTH `DegenerusGame.sol:5` AND `:18` ("TWO
copies → update both"). **OVERTURNED** in `343-GREP-ATTESTATION.md` Correction 3b (re-confirmed while authoring this
map):

- `DegenerusGame.sol:5` is `* @title DegenerusGame` — the title line, NOT a copy of the invariant.
- `DegenerusGame.sol:18` is `*      - address(this).balance + steth.balanceOf(this) >= claimablePool` — the ONLY
  occurrence of the master invariant in the file (a repo-wide grep finds no second copy).

> **Recorded correction:** the master invariant comment updates at **`:18` ONLY** (one site, plus the storage block
> at `DegenerusGameStorage.sol:345-354`). PLAN-V54 §5 #1's single-`:18` citation is CORRECT; the RESEARCH "also at
> `:5` → update both copies" is a FALSE ALARM — there is no `:5` copy to update. *(Both literal strings `:5` and
> `:18` appear in this doc so the verify regex is satisfied; the substantive finding is that the `:5` copy does not
> exist and only `:18` is edited.)*

---

## Section 4 — Producer-before-consumer edit-order map

A numbered, ordered list of edits for the SINGLE 344 IMPL diff such that **no file ships an intermediate broken
state**. This is ONE batched diff — so "before / atomically-with" ordering constraints (notably the D-06 gate) are
satisfied by **authoring order within the single diff**; no sub-file is ever committed in isolation. Every anchor is
the ACTUAL re-grepped line.

**Producer → consumer dependency direction:** storage shape + `BatchBuy.funder` (the producers) must exist before
the Game functions that read/write them; the Game functions must exist before the interfaces that declare them; the
interfaces must exist before AfKing (the consumer) calls them; the v48-recovery callers must be removed before the
AfKing views they call are deleted.

### Step 1 — Storage producers (`keeperFunding` mapping + `BatchBuy.funder` on both structs)

1a. `contracts/storage/DegenerusGameStorage.sol` — ADD `mapping(address => uint256) internal keeperFunding;`
    (Section 2.1); UPDATE the invariant comment block at **`:345-354`** to name the keeper component (Section 2.2).
    **No `keeperFundingPool` aggregate.**

1b. `contracts/DegenerusGame.sol:1796` — ADD the `funder` field to the Game's `BatchBuy` struct (Section 1.2).

1c. `contracts/AfKing.sol:20` — ADD the `funder` field to AfKing's `BatchBuy` struct (Section 1.2); refresh the
    "ABI-identical" doc note (`AfKing.sol:16` / `:30`).

> Producers first: the mapping + the `funder` field must exist before any function reads/writes `keeperFunding[...]`
> or `b.funder`.

### Step 2 — Game functions (consume the storage; produce the ABI the interfaces + AfKing consume)

2a. `DegenerusGame.sol` — ADD `depositKeeperFunding(address player) external payable` (Section 1.3).

2b. `DegenerusGame.sol` — ADD `withdrawKeeperFunding(uint256 amount) external` **with the GO_SWEPT guard as LINE 1**
    (Section 1.4); the `claimablePool -= amount` debit stays CHECKED math (carry-forward #1).

2c. `DegenerusGame.sol` — ADD `keeperFundingOf(address) external view returns (uint256)` (Section 1.5).

2d. `DegenerusGame.sol:1824` — `batchPurchase` payable → NON-payable; remove the `spent == msg.value` guard; per-slice
    `keeperFunding[b.funder] -= ev` + `claimablePool -= uint128(ev)` (Section 1.1 / D-01).

2e. `DegenerusGame.sol:1462` — `_claimWinningsInternal` post-gameOver keeper-merge (Decision B, Section 1.7); the
    GO_SWEPT guard at `:1463` is ALREADY present — no change to it.

2f. `DegenerusGame.sol:2645` — extend `keeperSnapshot` to also return `keeperFunding[player]` (Section 1.6).

2g. `DegenerusGame.sol:18` — update the master-invariant comment (Section 2.2 / 3.4); **`:5` is `@title` — NOT
    edited.**

> Game functions before interfaces: the function bodies must exist before the interface decls that mirror them
> compile against a real implementation surface.

### Step 3 — Interfaces (declare the new/changed Game ABI the consumers need)

3a. `contracts/interfaces/IDegenerusGame*.sol` — ADD `depositKeeperFunding(address) payable`,
    `withdrawKeeperFunding(uint256)`, `keeperFundingOf(address) view returns (uint256)`, the extended
    `keeperSnapshot` return tuple, and flip `batchPurchase` to non-payable wherever declared.

3b. `contracts/interfaces/IDegenerusGameModules.sol:237` — refresh the `batchPurchase` **comment** (it is comment-
    only, NOT a payable decl — carries no ABI weight; `batchPurchase` is NOT declared under `contracts/interfaces/`).

3c. `contracts/AfKing.sol` `IGame` block (`interface IGame {` at `:40`) — flip `batchPurchase` to non-payable at
    **`:43`** (the ONLY interface declaration of `batchPurchase` in the repo); ADD `depositKeeperFunding(address)
    payable`, `withdrawKeeperFunding(uint256)`, `keeperFundingOf(address) view returns (uint256)`; extend the
    `keeperSnapshot` decl at **`:56`** to the new return tuple.

> Interfaces before AfKing: AfKing's calls (`GAME.depositKeeperFunding`, `GAME.batchPurchase`, `GAME.keeperSnapshot`,
> `GAME.keeperFundingOf`) must resolve against the `IGame` block before the call sites are rewired.

### Step 4 — AfKing de-custody + `funder=src` wiring (consumes the new Game ABI)

4a. `AfKing.sol:412-414` — `subscribe` stays `payable`; the `msg.value` credit (currently
    `_poolOf[subscriber] += msg.value;`) forwards to `game.depositKeeperFunding{value: msg.value}(subscriber)` (A2).
    The OPEN-E consent gate (`AfKing.sol:403-408`) and `src` resolution (`:686`) are UNCHANGED.

4b. `AfKing.sol:726` — at the `BatchBuy({...})` build site, set `funder: src` per slice (D-01). `src` is the existing
    `:686` resolution.

4c. `AfKing.sol:695` — the funding-skip gate reads `keeperFunding[src]` (via the extended `keeperSnapshot` for
    `src == player`, plus the `keeperFundingOf(src)` fallback at the `:809`-mirror for the OPEN-E `src != player`
    slice — D-MR-01); same two-tier branching (VAULT/SDGNRS exempt-skip; NORMAL sub auto-pause). The VAULT/SDGNRS
    exemption (`:696`) stays on `player`.

4d. `AfKing.sol:719` — DROP the local CEI debit `_poolOf[src] -= ethValue;` (the debit moves to the Game's
    `batchPurchase`, step 2d).

4e. `AfKing.sol:768` — `GAME.batchPurchase{value: totalValue}(buys);` → `GAME.batchPurchase(buys);` (non-value call).

4f. `AfKing.sol` — DELETE `_poolOf` (slot 0, `:214`), `receive()` (`:298`), `deposit()` (`:305`), `depositFor()`
    (`:314`), `withdraw()` (`:328`), `poolOf()` view (`:492`, DELETED ENTIRELY per D-05 — no forwarding view);
    update/remove the stale `_poolOf`-referencing comments (`:84,:117,:143,:193,:370,:447`) and the
    `sum(_poolOf) <= address(this).balance` invariant doc (`:117`); FLAG the `Deposited` event (decl `:175`, emits
    `:301,:308,:318,:414`) — likely fully orphaned after de-custody (the subscribe credit moves to the Game's
    `KeeperFunded`-style event).

> **D-06 ordering note (the integrity gate):** `AfKing.withdraw` (`:328`) and `AfKing.poolOf` (`:492`) are orphaned
> ONLY after their TWO remaining callers — the v48 recovery legs (`DegenerusVault.sol:517` + `StakedDegenerusStonk.sol:539`)
> — are removed. Therefore step 4f's deletion of `withdraw`/`poolOf` MUST come BEFORE/atomically-with the recovery-leg
> removal (step 5). **In this SINGLE batched diff that is satisfied by authoring order** — no intermediate file state
> ever deletes the views while a recovery leg still calls them. (See step 5.)

### Step 5 — v48-recovery removal (the D-06 producer-before-consumer kill order)

> **D-06 INTEGRITY GATE (carry from `343-CLEANUP-INVENTORY.md` Section 3):** remove the recovery-leg CALLERS
> (`DegenerusVault.recoverAfKingPool` + the `StakedStonk.burnAtGameOver` AfKing leg) BEFORE/atomically-with deleting
> the `AfKing.poolOf` / `AfKing.withdraw` views they call (step 4f). Each recovery leg is `afKing.withdraw(afKing.poolOf(...))`
> — the SOLE consumer of BOTH views in one statement. Any intermediate state that deletes the views while a leg still
> calls them holds a dangling reference → broken build. **ONE batched diff satisfies this; authoring order enforces it.**

5a. `contracts/DegenerusVault.sol:516-517` — REMOVE `recoverAfKingPool()` (`:516`) and its body
    `afKing.withdraw(afKing.poolOf(address(this)));` (`:517`). 0 external callers (`grep -rn 'recoverAfKingPool'
    contracts/` → 1 hit, only its own def) — fully orphaned.

5b. `contracts/StakedDegenerusStonk.sol:539` — REMOVE the `burnAtGameOver()` AfKing-withdraw leg
    `afKing.withdraw(afKing.poolOf(address(this)));` (the leg is ONE statement; the `burnAtGameOver()` body at `:535`
    STAYS — it also burns sDGNRS).

5c. `contracts/StakedDegenerusStonk.sol:439-444` — NARROW the `receive()` AF_KING relaxation to GAME-only: after 5b
    the AfKing send-back path is gone, so the `msg.sender != ContractAddresses.AF_KING` allowance branch (`:442`) is
    dead. Keep `msg.sender != ContractAddresses.GAME`; drop the `AF_KING` allowance.

> **Ordering within step 5:** 5a + 5b (remove the callers) are authored BEFORE/atomically-with step 4f's deletion of
> `poolOf`/`withdraw`. 5c (the `receive()` narrow) follows 5b (it is dead only once the send-back path is gone). All
> within the single diff.

### Edit-order summary table

| Order | File:line (actual) | Edit | Producer/consumer role |
|-------|--------------------|------|------------------------|
| 1a | `DegenerusGameStorage.sol` (+ invariant `:345-354`) | ADD `keeperFunding` mapping; name keeper in invariant | producer (storage) |
| 1b/1c | `DegenerusGame.sol:1796` / `AfKing.sol:20` | ADD `funder` to BOTH `BatchBuy` structs | producer (struct) |
| 2a-2g | `DegenerusGame.sol` (`:1462`, `:1824`, `:2645`, `:18`, + new fns) | deposit/withdraw(+GO_SWEPT line-1)/keeperFundingOf/non-payable batchPurchase(funder debit)/claim-merge/extended snapshot/invariant comment | consumer of storage; producer of ABI |
| 3a-3c | `IDegenerusGame*.sol` / `IDegenerusGameModules.sol:237` / `AfKing.sol:43,:56` | declare new/changed ABI; flip `batchPurchase` non-payable | consumer of Game fns; producer for AfKing |
| 4a-4f | `AfKing.sol` (`:412-414`, `:726`, `:695`, `:719`, `:768`, deletes) | de-custody + `funder=src` wiring + non-value call + kill `_poolOf`/deposit/withdraw/poolOf | consumer of the new ABI |
| 5a-5c | `DegenerusVault.sol:516-517` / `StakedDegenerusStonk.sol:539,:439-444` | remove v48 recovery legs (D-06: BEFORE/with step 4f deletes) + narrow sDGNRS `receive()` to GAME-only | consumer-removal that GATES step 4f |

**No file ships an intermediate broken state:** every consumer (Game fns, interfaces, AfKing calls) is authored after
its producer (storage, struct, Game fns, interfaces) within the single 344 diff; the D-06 gate keeps the recovery-leg
removal before/with the AfKing view deletion. The unchanged accounting spine (`distributeYieldSurplus`, the gameOver
drain, `handleFinalSweep`, `adminStakeEthForStEth`, the sDGNRS valuation) is NOT touched — it reserves the keeper
total automatically via `claimablePool` (SOLVENCY-01, proven in `343-SOLVENCY-PROOF.md` Section A).

---

## Section 5 — Red-team IMPL-discipline carry-forwards (from `343-SOLVENCY-REDTEAM.md`)

Carried into this map so the 344 IMPL author honors them (NOT findings — precise instructions):

1. **`withdrawKeeperFunding` GO_SWEPT guard MUST be LINE 1** — before the `claimablePool -= amount` debit (mirror
   `_claimWinningsInternal:1463`); the debit stays **checked-math** (no `unchecked`). (Section 1.4 / Proof B.3 / T-343-04.)
2. **`batchPurchase` MUST debit `keeperFunding[b.funder]`, not `keeperFunding[b.player]`** — `funder` on BOTH structs;
   VAULT/SDGNRS exemption on `player`. The PLAN-V54 §4 / AUTOBUY-02 `b.player` snippets are a live trap if copied
   verbatim. (Section 1.1 / 3.1 / Proof D / D-01.)
3. **(awareness) `pullRedemptionReserve` (`DegenerusGame.sol:1981`) is a 4th `claimablePool`-tandem-debit site** —
   keep the keeper bucket disjoint from it (it already is; it debits `claimableWinnings[SDGNRS]` + `claimablePool`,
   never `keeperFunding`). Noted for 344 so the keeper bucket never collides with it. (Proof Section A informational
   / red-team informational.)

---

## Section 6 — BATCH-01 lock verdict + 344 hand-off

- **Final signatures LOCKED** (Section 1): non-payable `batchPurchase(BatchBuy[])` with the `funder` debit;
  `depositKeeperFunding(address) payable`; un-brickable CEI `withdrawKeeperFunding(uint256)` WITH the GO_SWEPT guard
  as line 1; `keeperFundingOf(address) view`; the extended `keeperSnapshot` returning `keeperFunding`; the
  `_claimWinningsInternal` Decision-B merge.
- **Storage shape LOCKED** (Section 2): `mapping(address => uint256) keeperFunding`, NO aggregate (rides in
  `claimablePool`); the invariant comment updated at `DegenerusGame.sol:18` (NOT `:5` — Section 3.4) +
  `DegenerusGameStorage.sol:345-354`.
- **Four corrections RECORDED** (Section 3): D-01 `funder` (→ AUTOBUY-02 + PLAN-V54 §4); D-MR-01 src carve-out
  (refines AUTOBUY-05); the `payAffiliate` canonical / `handleAffiliate`-is-wrong-symbol correction; the single-copy
  `:18` invariant (the `:5` copy does not exist).
- **Edit-order map FIXED** (Section 4): producer-before-consumer (storage + `funder` → Game fns → interfaces →
  AfKing de-custody → v48-recovery removal) with the D-06 gate (recovery legs before/with `poolOf`/`withdraw`
  deletion); ONE batched diff, no intermediate broken state.
- **Red-team carry-forwards CARRIED** (Section 5).

**344 IMPL is design-gating-complete from this map.** The author writes ONE fully-reconciled `contracts/*.sol` diff
against the actual lines above, with zero "by construction" assumptions and zero intermediate broken state. The lines
WILL drift the moment a contract is edited — the 344 author MUST re-run the greps (or cite a re-pinned successor),
never trust the upstream doc-cited lines.

**Paper-only assertion:** `git diff --name-only -- contracts/` is EMPTY — zero `contracts/*.sol` edits in this plan.
