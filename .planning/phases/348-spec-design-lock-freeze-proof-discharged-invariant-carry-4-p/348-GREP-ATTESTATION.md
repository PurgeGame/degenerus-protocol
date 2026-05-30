# 348-GREP-ATTESTATION — Call-Graph Attestation + Drift-Correction Table (v55 milestone scope)

**Phase:** 348 — SPEC (Design-Lock + Freeze Proof + Discharged-Invariant Carry + §4 Placement + Code-Size/GAS Inventories + Attestation)
**Plan:** 348-01 · **Authored:** 2026-05-30
**Subject HEAD:** `f353a50b` (working tree) — `contracts/` byte-identical to the v54 de-custody HEAD **`20ca1f79`**
**Role:** the load-bearing **UPSTREAM PRODUCER** deliverable. Every other 348 doc (the FREEZE-PROOF, the
PLACEMENT-DECISION, the INVARIANT-CARRY, the CODE-SIZE-PLAN, the GAS-INVENTORY, the IMPL-EDIT-ORDER-MAP) and the
349 IMPL diff cite the ACTUAL lines re-pinned here — never the drifted doc-cited lines.

---

## 0. Baseline identity — the working tree IS `20ca1f79` (no checkout needed)

```
$ git diff --numstat 20ca1f79 HEAD -- contracts/
              (empty)
```

`git diff --numstat 20ca1f79 HEAD -- contracts/` returns **EMPTY**. The 9 commits since `20ca1f79`
(`f353a50b 7f96e97e 8cc39e8a d9f8d285 67331b31 022df021 ea67c36f 91167565 106cf06c`) are **docs-only**
(`.planning/` markdown). Therefore the working tree's `contracts/` is **byte-identical** to the v54 HEAD
**`20ca1f79`**, and **grep/read against the live working tree IS a valid attestation against `20ca1f79`** — no
`git checkout` / detached-HEAD step is required. Every `file:line` below was grep/read-verified on the live tree;
the matched source text is quoted verbatim. (`20ca1f79` is the v55.0 audit baseline per PROJECT.md / ROADMAP.md.)

**Method:** for each anchor cited across `PLAN-V55-AFKING-IN-GAME-REDESIGN.md` + `PLAN-V55-REVERT-FREE-CHAIN-PROOF.md`
+ `348-CONTEXT.md` `<canonical_refs>`, I grepped the symbol on the live tree, read the matched line, and recorded:
**Doc-cited line → Actual line → Matched source text (quoted) → Status**. Status legend:
`MATCH` (doc line == actual line) · `DRIFT(±N)` (line-number drift) · `PATTERN-DRIFT` (the cited grep-*pattern* was
wrong, resolved below) · `FOUND` (re-pinned from a doc-cited range/approximate). I did **not** transcribe doc-cited
lines blindly; only the live-verified line is authoritative.

---

## 1. Drift corrections (beyond simple line numbers) — READ FIRST

### 1a. ⚠ Box-seed PATTERN-DRIFT — RESOLVED (the one confirmed drift CONTEXT.md flagged)

`PLAN-V55-AFKING-IN-GAME-REDESIGN.md` §0-Correction-1 cites the box seed at `DegenerusGameLootboxModule.sol:534`
(range `:530-551`), and `PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` §4 cites the same `LB:534`. `348-CONTEXT.md`
`<canonical_refs>` flagged that **the grep-pattern claim `keccak256(abi.encodePacked` did NOT match `:534`.**

**RESOLUTION — the seed at `:534` is `abi.encode`, NOT `abi.encodePacked`:**

| Symbol | Doc-cited | Actual | Matched source text (quoted) | Status |
|---|---|---|---|---|
| `openLootBox` box seed | `:534` (pattern `keccak256(abi.encodePacked`) | **`:534`** | `uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));` | **PATTERN-DRIFT → RESOLVED** (line MATCHES; the *pattern* was wrong — it is `abi.encode`) |
| PRESALE box seed (`abi.encodePacked` lives HERE only) | — | **`:643-644`** | `keccak256(` / `abi.encodePacked(rngWord, keccak256("PRESALE_BOX"), player, amount)` | FOUND |

- The `openLootBox` (afking-relevant) seed at `:534` is **`keccak256(abi.encode(rngWord, player, day, amount))`** —
  the `abi.encode` form. The line number `:534` is CORRECT; only the cited *grep-pattern* (`abi.encodePacked`) was
  wrong.
- **`abi.encodePacked` appears at exactly ONE site in the module — `:644`, the PRESALE box seed**
  (`abi.encodePacked(rngWord, keccak256("PRESALE_BOX"), player, amount)`). `grep -n "abi.encodePacked"
  contracts/modules/DegenerusGameLootboxModule.sol` returns ONLY `:644`. The PRESALE box is a distinct path, NOT
  the afking-open path.
- The identical `abi.encode(rngWord, player, day, amount)` seed shape also appears at the three
  `resolveLootboxDirect`/`resolveRedemptionLootbox`-family sites `:768`, `:801` and the doc-comment `:1012` — all
  `abi.encode`, none `abi.encodePacked`. (The deity-bingo seed at `:1887` is `abi.encode(rngWordByDay[day], deity,
  day, slot)` — a different surface, listed for completeness.)

**Downstream consequence (load-bearing):** FREEZE-03's claim *"the seed = `keccak256(rngWord, player, day, amount)`"*
is **TRUE at `:534`** — but the **FREEZE-PROOF (348-03) MUST cite `abi.encode`, not `abi.encodePacked`.** The afking
open must mirror this exact `abi.encode(rngWord, player, day, amount)` construction (per obligation 3, seeding the
**stamped** day). The encoding difference is not cosmetic: `abi.encode` (32-byte left-padded fields) vs
`abi.encodePacked` (tight-packed) produce **different hash preimages**, so a downstream doc or the 349 edit that
copied the `abi.encodePacked` pattern would compute a **different seed** and break box-outcome equivalence with
`openLootBox`. Pattern-drift resolved here so that error cannot propagate.

### 1b. OPEN-E subscribe-time gate — LINE DRIFT (re-pinned)

The docs cite the subscribe-time OPEN-E `fundingSource` operator-approval gate at `AfKing.sol:400-409`. **It is not
there.** Re-pinned:

| Symbol | Doc-cited | Actual | Matched source text (quoted) | Status |
|---|---|---|---|---|
| `subscribe(...)` definition | ~`:400` | **`:324`** | `function subscribe(` (params `player, drainGameCreditFirst, useTickets, dailyQuantity, reinvestPct, fundingSource`; `:331` `) external payable {`) | DRIFT(−76) |
| OPENE-04 non-zero/non-self `fundingSource` gate | `:400-409` | **`:343-352`** | `// OPENE-04 — a non-zero, non-self fundingSource must have operator-approved` (`:343`) → `if (` / `fundingSource != address(0) &&` (`:347`) / `fundingSource != subscriber &&` (`:348`) / `!GAME.isOperatorApproved(fundingSource, subscriber)` (`:349`) `) {` / `revert NotApproved();` (`:351`) | **DRIFT → re-pinned `:343-352`** |
| SUB-02 self-consent gate (the other subscribe-time OPEN-E read) | — | **`:335-341`** | `// SUB-02 — self-consent (player == 0 or msg.sender) or operator-approval.` (`:335`) → `if (!GAME.isOperatorApproved(subscriber, msg.sender)) {` (`:338`) | FOUND |

(Matches the CONTEXT.md re-pin hint: subscribe def ~:324–331, the OPENE-04 gate ~:343–352.) The CONSENT carry-over
(349-owned) attests these as the OPEN-E surface that folds into `GameAfkingModule.subscribe`.

### 1c. `src`/funder resolution — LINE DRIFT (re-pinned)

The docs cite the per-iteration `src`/funder resolution at `AfKing.sol:682`. **It is at `:624`.**

| Symbol | Doc-cited | Actual | Matched source text (quoted) | Status |
|---|---|---|---|---|
| OPENE-02 once-per-iter funder resolution | `:682` | **`:624`** | `address src = sub.fundingSource == address(0) ? player : sub.fundingSource;` | **DRIFT(−58) → re-pinned `:624`** |

(Comment `:620-623` confirms the VAULT/SDGNRS exemption stays keyed on the un-spoofable `player`, never `src`.)

### 1d. `_resolveBuy` body extent — re-pinned

`348-CONTEXT.md` + the proof cite `_resolveBuy` "body to `:795`". The function **`_resolveBuy` opens at `:727`
(MATCH)** but its body extends to **`:863`** — the next function (`doWork`) opens at `:864`. The slice-builder
validation logic the proof relies on (`effectiveQty` `:756/:759`, `cost` `:761`, `LOOTBOX_MIN` skip `:772`, the
`claimableUse`/`ev`/payKind derivation `:787-794`, the named-revert comment `:766-767`/`:781-782`) all sit within
`:727-863`. Re-pin: **`_resolveBuy` = `:727-863`** (not `:727-795`).

---

## 2. Per-file Drift-Correction Tables (every milestone-scope anchor, matched text quoted)

### 2.1 `contracts/modules/DegenerusGameLootboxModule.sol`

| Symbol / claim | Doc-cited | Actual | Matched source text (quoted) | Status |
|---|---|---|---|---|
| `_applyEvMultiplierWithCap` def | `:459` (`:459-495`) | **`:459`** | `function _applyEvMultiplierWithCap(` | MATCH |
| EV-cap map READ (in the helper) | `:473` | **`:473`** | `uint256 usedBenefit = lootboxEvBenefitUsedByLevel[player][lvl];` | MATCH |
| EV-cap remaining (10-ETH clamp) | — | **`:474-476`** | `uint256 remainingCap = usedBenefit >= LOOTBOX_EV_BENEFIT_CAP` / `? 0` / `: LOOTBOX_EV_BENEFIT_CAP - usedBenefit;` | FOUND |
| EV-cap exhausted → no-write 100%-EV | `:478-481` | **`:478-481`** | `if (remainingCap == 0) {` / `// Cap exhausted: apply 100% EV (neutral)` / `return amount;` | MATCH |
| EV-cap map WRITE (RMW at open) | `:488` | **`:488`** | `lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion;` | MATCH |
| `openLootBox` def | — | **`:503`** | `function openLootBox(address player, uint48 index) external {` | FOUND |
| `lootboxRngWordByIndex[index]` read (open) | `:510` | **`:510`** | `uint256 rngWord = lootboxRngWordByIndex[index];` | MATCH |
| open-time `_simulatedDayIndex()` (the day the afking open must NOT copy) | `:513` | **`:513`** | `uint32 currentDay = _simulatedDayIndex();` | MATCH |
| **frozen buy-day read `lootboxDay[index][player]`** (FREEZE-03 template) | `:514` | **`:514`** | `uint32 day = lootboxDay[index][player];` | MATCH |
| **box seed (the afking open mirrors this — `abi.encode`)** | `:534` | **`:534`** | `uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));` | **PATTERN-DRIFT → RESOLVED (§1a)** |
| frozen EV-cap consume (`adj`, "no cap SLOAD/SSTORE here") | `:549-551` | **`:549-551`** | `uint256 scaledAmount = evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS` / `? (amount * evMultiplierBps) / 10_000` / `: (uint256(adj) * evMultiplierBps) / 10_000 + (amount - uint256(adj));` | MATCH |
| other open-time `_simulatedDayIndex()` sites (NOT to be copied) | `:766/:799/:836/:868` | **`:766`, `:799`, `:836`, `:868`** | `:766` `uint32 day = _simulatedDayIndex();` · `:799` `uint32 day = _simulatedDayIndex();` · `:836` `day = _simulatedDayIndex();` · `:868` `uint32 day = _simulatedDayIndex();` | MATCH |
| `resolveLootboxDirect` def (open-time-day template — DON'T copy) | — | **`:763`** | `function resolveLootboxDirect(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external {` | FOUND |
| `resolveRedemptionLootbox` def | — | **`:796`** | `function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external {` | FOUND |
| PRESALE box seed (`abi.encodePacked` — the ONLY packed seed) | — | **`:643-644`** | `keccak256(` / `abi.encodePacked(rngWord, keccak256("PRESALE_BOX"), player, amount)` | FOUND (§1a) |

**FREEZE-03 entropy-side guard:** `grep -nE "block\.(timestamp|number|prevrandao|coinbase|difficulty|chainid|basefee|gaslimit)|blockhash" contracts/modules/DegenerusGameLootboxModule.sol`
returns **ZERO matches**. There is **no `block.timestamp` / `block.number` / `block.prevrandao` / `block.coinbase`
/ `blockhash`** anywhere in the module — confirmed for the `:534` draw and the whole file. The only `day`-dependence
in the seed is the `day` term, which the afking open will source from the **stamped** buy-day (obligation 3), never
open-time. FREEZE-03 determinism holds on the entropy side.

### 2.2 `contracts/storage/DegenerusGameStorage.sol`

| Symbol / claim | Doc-cited | Actual | Matched source text (quoted) | Status |
|---|---|---|---|---|
| `LOOTBOX_EV_BENEFIT_CAP = 10 ether` | `:1326` | **`:1326-1327`** | `uint256 internal constant LOOTBOX_EV_BENEFIT_CAP =` (`:1326`) / `10 ether;` (`:1327`) | MATCH (decl `:1326`) |
| `lootboxEvBenefitUsedByLevel` map decl | `:1469` (`:1468-1469`) | **`:1468-1469`** | `mapping(address => mapping(uint24 => uint256))` (`:1468`) / `internal lootboxEvBenefitUsedByLevel;` (`:1469`) | MATCH (name on `:1469`) |
| `_settleClaimableShortfall` def (proof §1 #2 / §3 / class B) | `:841` | **`:841`** | `function _settleClaimableShortfall(address buyer, uint256 basis, uint256 shortfall) internal {` | MATCH |
| shortfall `revert E()` (`basis <= shortfall`) | `:843` | **`:843`** | `if (basis <= shortfall) revert E();` | MATCH |
| `claimablePool -= uint128(shortfall)` (class-B solvency sub) | `:847` | **`:847`** | `claimablePool -= uint128(shortfall);` | MATCH |

### 2.3 `contracts/AfKing.sol`

| Symbol / claim | Doc-cited | Actual | Matched source text (quoted) | Status |
|---|---|---|---|---|
| `isOperatorApproved` interface decl | `:43` | **`:43`** | `function isOperatorApproved(address owner, address operator) external view returns (bool);` | MATCH |
| `validThroughLevel` Sub field decl | `:103` | **`:103`** | `uint32 validThroughLevel;` | MATCH |
| `fundingSource` Sub field decl | `:106` | **`:106`** | `address fundingSource;` | MATCH |
| `LOOTBOX_MIN` immutable decl | `:269` | **`:269`** | `uint256 internal immutable LOOTBOX_MIN;` | MATCH |
| `subscribe(...)` def | ~`:400` | **`:324`** | `function subscribe(` | DRIFT(−76) → §1b |
| SUB-02 self-consent OPEN-E read | — | **`:338`** | `if (!GAME.isOperatorApproved(subscriber, msg.sender)) {` | FOUND → §1b |
| **OPENE-04 subscribe-time `fundingSource` gate** | `:400-409` | **`:343-352`** | `// OPENE-04 — a non-zero, non-self fundingSource must have operator-approved` / `fundingSource != address(0) &&` / `fundingSource != subscriber &&` / `!GAME.isOperatorApproved(fundingSource, subscriber)` | **DRIFT → re-pinned (§1b)** |
| `s.validThroughLevel` write at subscribe (pass-gating, AFSUB) | — | **`:371`** | `s.validThroughLevel = uint32(GAME.lazyPassHorizon(subscriber));` | FOUND |
| per-iteration `currentLevel > validThroughLevel` crossing | — | **`:571`** | `if (currentLevel > sub.validThroughLevel) {` | FOUND |
| **OPENE-02 `src`/funder resolution** | `:682` | **`:624`** | `address src = sub.fundingSource == address(0) ? player : sub.fundingSource;` | **DRIFT(−58) → re-pinned (§1c)** |
| **`_resolveBuy` def** (slice builder = obligation-1 substrate) | `:727` (body to `:795`) | **`:727`** (body to **`:863`**) | `function _resolveBuy(` | MATCH (body extent re-pinned §1d) |
| `effectiveQty = sub.dailyQuantity` | `:756` | **`:756`** | `uint256 effectiveQty = sub.dailyQuantity;` | MATCH |
| reinvest `effectiveQty` bump | `:759` | **`:758-759`** | `uint256 reinvestQty = (claimable * sub.reinvestPct) / 100 / mp;` (`:758`) / `if (reinvestQty > effectiveQty) effectiveQty = reinvestQty;` (`:759`) | MATCH |
| **`cost = mp * effectiveQty`** (the §7 cost-unit reconciliation anchor) | `:761` | **`:761`** | `uint256 cost = mp * effectiveQty;` | MATCH |
| ticket-floor comment (`:766-767`) | `:766-767` | **`:766-767`** | `// autoBuy. Ticket mode needs no floor skip: one ticket is >= the ticket buy-in floor,` (`:766`) | MATCH |
| **`LOOTBOX_MIN` transient skip** | `:772` | **`:772-774`** | `if (cost < LOOTBOX_MIN) {` (`:772`) / `lootboxSkip = true;` (`:773`) / `return (...);` (`:774`) | MATCH |
| **named-revert comment (1-wei sentinel / shortfall avoidance)** | `:781-782` | **`:781-782`** | `// ... leave >= 1 wei (the GAME's Claimable branch needs claimable` (`:781`) / `// strictly > cost, and the claimable shortfall settle needs basis > shortfall).` (`:782`) | MATCH |
| 1-wei sentinel clamp | — | **`:790`** | `if (claimable > 0 && claimableUse >= claimable) claimableUse = claimable - 1;` | FOUND |
| `ev = cost − claimableUse` | — | **`:791`** | `ethValue = cost - claimableUse;` | FOUND |
| enum-typed payKind derivation | — | **`:792-794`** | `payKind = ethValue == 0` / `? MintPaymentKind.Claimable` / `: (claimableUse == 0 ? MintPaymentKind.DirectEth : MintPaymentKind.Combined);` | FOUND |
| `MintPaymentKind` enum decl (∈ {0,1,2}) | — | **`:9`** | `enum MintPaymentKind {` | FOUND |
| `dailyQuantity == 0` revert (quantity ≥ 1 at subscribe) | `:332` | **`:332`** | `if (dailyQuantity == 0) revert InvalidDailyQuantity();` | MATCH |

### 2.4 `contracts/modules/DegenerusGameAdvanceModule.sol`

| Symbol / claim | Doc-cited | Actual | Matched source text (quoted) | Status |
|---|---|---|---|---|
| `_enforceDailyMintGate` def | `:973` | **`:973`** | `function _enforceDailyMintGate(` | MATCH |
| `_enforceDailyMintGate(...)` call site (advance) | `:191` | **`:191`** | `_enforceDailyMintGate(caller, purchaseLevel, dailyIdx);` | MATCH |
| **`requestLootboxRng` def** (FREEZE-02 — mid-day index advance) | `:1016` | **`:1016`** | `function requestLootboxRng() external {` | MATCH |
| **RNG-request index advance `_lrRead(LR_INDEX...) + 1` (site A)** | `:1089` (`:1086-1090`) | **`:1089`** | `_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK) + 1` (inside `_lrWrite(` `:1086`, comment `:1085` "Advance lootbox index so new purchases target the NEXT RNG") | MATCH |
| **RNG-request index advance `_lrRead(LR_INDEX...) + 1` (site B)** | `:1629` (`:1626-1630`) | **`:1629`** | `_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK) + 1` (inside `_lrWrite(` `:1626`) | MATCH |
| **`rngGate` def** | `:1152` | **`:1152`** | `function rngGate(` | MATCH |
| `rngGate(...)` call site (the STAGE insertion point is immediately BEFORE this) | `:274` | **`:274`** | `(uint256 rngWord, uint32 gapDays) = rngGate(` | MATCH |
| **STAGE insertion point** (D-348-01: new STAGE step before the `rngGate` call) | ~`:273` | **`:272-273`** | `// RNG: use existing word or request new one` (`:272`) / `bool bonusFlip = (inJackpot && jackpotCounter == 0) || lvl == 0;` (`:273`) — the new STAGE inserts here, immediately before the `rngGate(` call at `:274` | FOUND |

(For FREEZE-02 D-348-02: `LR_INDEX` is read via `_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)` and advanced only at the
two RNG-request `_lrWrite(... +1)` sites `:1089`/`:1629`. The FREEZE-PROOF (348-03) owns proving the required-path
process STAGE reads `LR_INDEX` once and cannot interleave a `requestLootboxRng` advance while `!subsFullyProcessed`
— this attestation pins the sites that proof reasons over.)

### 2.5 `contracts/DegenerusGame.sol` — ARCH-04 reclaim-target SITES (this doc PINS; 348-02 MEASURES bytes)

| Symbol (reclaim target) | Doc-cited | Actual | Matched source text (quoted) | Status |
|---|---|---|---|---|
| `claimAffiliateDgnrs` (→ `BingoModule`, the clean ~1.3KB win) | `:1553` | **`:1553`** | `function claimAffiliateDgnrs(address player) external {` | MATCH |
| `previewSellFarFutureTickets` (→ lens / drop-`view`) | `:2113` | **`:2113`** | `function previewSellFarFutureTickets(` | MATCH |
| `playerActivityScore` (→ lens / drop-`view`) | `:2676` | **`:2676`** | `function playerActivityScore(` | MATCH |

(Per D-348-08 these are SITES only; `forge build --sizes` / per-function byte measurement + the running-total
edit-order arithmetic live in 348-02 CODE-SIZE-PLAN. The slice-builder fold's host functions in `Game` — the
`batchPurchase`/`purchaseWith` revert primitives the proof §3 cites — are re-pinned in the proof itself; this
attestation owns the v55-scope anchors enumerated in `348-CONTEXT.md` `<canonical_refs>`.)

---

## 3. Anchor coverage vs the plan's must-haves (self-audit)

| Must-have anchor group | Status in this doc |
|---|---|
| Empty-diff baseline vs `20ca1f79` recorded | ✅ §0 (`git diff --numstat` empty; working tree = v54 baseline) |
| Box-seed drift RESOLVED (`abi.encode` at `:534`; `abi.encodePacked` = PRESALE box `:644`) | ✅ §1a + §2.1 |
| FREEZE-03: `lootboxDay[index][player]` `:514`; open-time `_simulatedDayIndex()` `:513/:766/:799/:836/:868`; no `block.*` in the draw | ✅ §2.1 + entropy-side guard |
| FREEZE-02: `requestLootboxRng` `:1016`; index advance `:1089` AND `:1629`; `rngGate` `:1152` | ✅ §2.4 |
| EV-cap: `_applyEvMultiplierWithCap` `:459`; `lootboxEvBenefitUsedByLevel` `:1469`; `LOOTBOX_EV_BENEFIT_CAP` `:1326` | ✅ §2.1 + §2.2 |
| Slice-builder: `_resolveBuy` `:727`; named-revert comment `:781-782`; `LOOTBOX_MIN` skip `:772`; `LOOTBOX_MIN` decl `:269`; `cost = mp*effectiveQty` `:761` | ✅ §2.3 + §1d |
| OPEN-E / set-mutation: `isOperatorApproved` `:43`; subscribe-time OPEN-E gate (re-pinned `:343-352`); `validThroughLevel` `:103`; `fundingSource` `:106`; `src`/funder resolution (re-pinned `:624`) | ✅ §1b + §1c + §2.3 |
| ARCH-04 sites: `claimAffiliateDgnrs` `:1553`; `previewSellFarFutureTickets` `:2113`; `playerActivityScore` `:2676` | ✅ §2.5 |

---

## 4. Call-graph attestation — no "by construction" survives un-checked

Per the audit-discipline maxim (`feedback_verify_call_graph_against_source`): **no "by construction" /
"single fn reaches all paths" claim in any v55 PLAN doc survives un-checked into the FREEZE-PROOF, the
PLACEMENT-DECISION, the IMPL-EDIT-ORDER-MAP, or the 349 IMPL diff without a live-source grep/read backing it.**
Every `file:line` cited across `PLAN-V55-AFKING-IN-GAME-REDESIGN.md` + `PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` +
`348-CONTEXT.md` was re-pinned above against the live `contracts/` tree (== `20ca1f79`) with the matched source
text quoted. Three drifts were corrected (the box-seed pattern §1a, the OPEN-E subscribe gate §1b, the `src`
resolution §1c) plus the `_resolveBuy` body extent (§1d); all other anchors MATCH. The proof §1/§3 revert-primitive
call-graph (the `batchPurchase`/`purchaseWith`/`_processMintPayment`/`_settleClaimableShortfall` reachable set) is
attested in `PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` itself; this doc additionally re-confirmed the `Storage:841/843/847`
shortfall-settle anchors that the proof's class-A discharge + class-B residual both lean on.

**The afking process-pass / open-pass that 349 builds, and every downstream 348 proof/decision/inventory doc, MUST
cite the ACTUAL lines in §1–§2 — not the drifted doc-cited lines.** In particular: the open seed is
`keccak256(abi.encode(rngWord, player, day, amount))` at `:534` (NOT `abi.encodePacked`); the frozen buy-day
template is `lootboxDay[index][player]` at `:514`; the OPEN-E gate is `:343-352`; the funder resolution is `:624`.

**Valid until:** the subject HEAD's `contracts/` moves off `20ca1f79`. Re-run this attestation
(`git diff --numstat 20ca1f79 <new HEAD> -- contracts/` + re-grep every anchor) before 349 IMPL if any
`contracts/*.sol` commit lands between now and the 349 diff. As of `f353a50b` the tree is byte-identical to
`20ca1f79`, so this attestation is current.

---

*Zero `contracts/*.sol` edits — `git diff --name-only -- contracts/` is empty. Paper-only SPEC attestation; the only
CLI used was `git diff` + `grep`/read (read-only). Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p · Plan: 348-01.*
