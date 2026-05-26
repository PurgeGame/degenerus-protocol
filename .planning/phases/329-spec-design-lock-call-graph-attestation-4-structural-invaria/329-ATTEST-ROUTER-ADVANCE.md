# 329 — Call-Graph Attestation: ROUTER (AfKing) + ADVANCE (AdvanceModule + DegenerusGame wrapper)

## Scope

READ-ONLY grep-attestation of every cited `file:line` anchor on the v49.0 **unified keeper "do-work"
router + advance-bounty rework** surface against the v48.0-closure baseline HEAD
`0cc5d10fbc1232a6d2e7b0464fe21541b9812029` (`0cc5d10f`). This is the **BATCH-01 attestation half** for
the core router/advance surface. Resolves the four load-bearing decision attestations
(**ROUTER-07 / D-01a** per-leg no-untrusted-ETH-send · **GAS-03 / D-03** dual-epoch ·
**ADV-04** `totalFlipReversals` freeze · **invariant (c) / D-04** free-fallback callers) plus the
Claude's-Discretion grep facts (the `advanceGame` return-decode site, the 3 advance-bounty `creditFlip`
classifications, the O(1) discovery-view predicates, the `maxCount` per-leg mapping, the D-06 baseline,
the v48 KEEP-04 affiliate-code passthrough survival, and the GASOPT-01 hoist sites).

ZERO `contracts/*.sol` mutation — paper-only. The break-even peg constants stay SPEC placeholders
(calibrated at Phase 331 GAS).

## Sources of truth (this attestation)

- `contracts/AfKing.sol` (888 lines) — the router's home: CEI invariant block, `BOUNTY_ETH_TARGET`,
  `depositFor`/`withdraw`/`poolOf`, `autoBuy` (→ internal `_autoBuy` at IMPL) + the daily-reset cursor,
  the two `claimableWinningsOf` GASOPT-02 hoist sites, the absolute-day stall ladder, the
  bounty + `creditFlip`, `_currentDay`, the `EmptyAutoBuy`/`NoSubscribersAutoBought` anti-spam reverts,
  the `batchPurchase` keeper-buy call site.
- `contracts/modules/DegenerusGameAdvanceModule.sol` (1902 lines) — the advance multiplier
  single-source-of-truth: `advanceGame`, `ADVANCE_BOUNTY_ETH`, the 3 caller-reward `creditFlip` sites
  + their bounty math, the game-day stall epoch, `_enforceDailyMintGate` + the 30-min universal bypass,
  the death-clock extend, `_applyDailyRng` + the `totalFlipReversals` nudge consume+reset.
- `contracts/DegenerusGame.sol` (2748+ lines) — the `advanceGame` wrapper (delegatecall decode site),
  `currentDayView`, `rngLocked`, `autoResolve`, `autoOpen` + the cursor loop, `batchPurchase` +
  `_batchPurchaseUnit` (the `bytes32("DGNRS")` affiliate-code wiring), the gas-peg constants, the
  `boxPlayers`/`boxCursor`/`lootboxRngWordByIndex` discovery state, the ETH send sites.
- `contracts/modules/DegenerusGameMintModule.sol` — GASOPT-01: `processFutureTicketBatch` +
  `processTicketBatch` and their repeated `ticketsOwedPacked[rk][player]` reads (`rk` loop-invariant).
- `contracts/DegenerusVault.sol` / `contracts/StakedDegenerusStonk.sol` — the invariant-(c)
  protocol-owned fallback `gameAdvance()` wrappers (read-only — confirm, do NOT modify).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — read for the D-05f liveness check
  (does any invariant REQUIRE losing Degenerette bets to be resolved?).

**Attestation-method note (baseline-anchored):** The working tree's `contracts/` is byte-identical to
baseline HEAD `0cc5d10fbc1232a6d2e7b0464fe21541b9812029` — `git diff --name-only 0cc5d10f HEAD --
'contracts/*.sol'` returns ZERO files. Every grep below is against the live tree and is implicitly
resolved at the baseline `0cc5d10f`. For belt-and-suspenders on any anchor,
`git show 0cc5d10f:contracts/<path> | grep -n` is equivalent. Read from `contracts/` ONLY — stale copies
elsewhere are ignored (`feedback_contract_locations`).

## Verdict legend

- `MATCH` — anchor lands on the claimed line (or within a claimed multi-line range).
- `SHIFTED(±N)` — content present, N lines off the claimed line/range (record the actual line).
- `ABSENT` — content not found / materially diverged (surfaced as an IMPL blocker in the Roll-up).

---

## A. AfKing router anchors — reconciliation

| # | Anchor (claimed) | ACTUAL (`contracts/AfKing.sol`) | Verdict |
|---|---|---|---|
| A1 | CEI invariant block `:99-106` ("No reentrancy guard … keeper is never a payee" + caller-scoped writes + un-spoofable VAULT/SDGNRS identity) | `@custom:invariant Steady-state: sum(_poolOf) <= address(this).balance.` :99; `@custom:invariant No reentrancy guard — strict CEI everywhere; the keeper is` :100 / `never a payee in any contract it calls.` :101; `@custom:invariant Caller-scoped writes: every player-state mutator writes only` :102 … `exemption keys on the un-spoofable pinned ContractAddresses.VAULT / SDGNRS identity` :104-106 | **MATCH** (the full invariant block spans :99-106 verbatim; the no-guard / keeper-never-a-payee clause is :100-101) |
| A2 | `BOUNTY_ETH_TARGET` immutable peg `:263` | `uint256 public immutable BOUNTY_ETH_TARGET;` :263 (set in ctor `BOUNTY_ETH_TARGET = _bountyEthTarget;` :279) | **MATCH** (peg ETH target; re-pegged at GAS, placeholder at SPEC) |
| A3 | `depositFor(address)` permissionless ingress `:304` | `function depositFor(address player) external payable {` :304 (`_poolOf[player] += msg.value;` :307, no caller gate) | **MATCH** (the Pitfall-5 set-inflation surface) |
| A4 | `withdraw(uint256)` pool withdraw `:318` | `function withdraw(uint256 amount) external {` :318; `(bool ok, ) = msg.sender.call{value: amount}("");` :327; `if (!ok) revert EthSendFailed();` :328 | **MATCH** (ungated egress; sends to the CALLER — relevant to Section B) |
| A5 | `autoBuy(uint256 maxCount)` `:567` (→ internal `_autoBuy` at IMPL) + `if (maxCount == 0) revert EmptyAutoBuy();` `:569` | `function autoBuy(uint256 maxCount) external returns (uint256 bountyEarned) {` :567; `if (maxCount == 0) revert EmptyAutoBuy();` :569 (pre-guard `rngLocked` revert `AutoBuyAborted` :568) | **MATCH** |
| A6 | the resuming daily-reset cursor `:577` (`cursor = _autoBuyDay == today ? uint256(_autoBuyCursor) : 0;`) | `uint256 cursor = _autoBuyDay == today ? uint256(_autoBuyCursor) : 0;` :577; day-stamp `if (_autoBuyDay != today) { _autoBuyDay = today; }` :578-579; cursor persists `_autoBuyCursor = uint224(cursor);` :794. Storage: `_autoBuyDay` :215 / `_autoBuyCursor` :216 (one slot) | **MATCH** (buys-pending discovery reads this AfKing-local state — Section F) |
| A7 | two `claimableWinningsOf(player)` calls inside autoBuy `:691` + `:722` (GASOPT-02 hoist sites; lazy) | `uint256 claimable = IGame(ContractAddresses.GAME).claimableWinningsOf(player);` :691 (gated `if (sub.reinvestPct > 0)` :690 — the SUB-04 reinvest-quantity read); `uint256 cred = IGame(ContractAddresses.GAME).claimableWinningsOf(player);` :722 (gated `if ((sub.flags & FLAG_DRAIN_FIRST) == 0) … else { … }` :719 — the funding-waterfall read) | **MATCH** (both fire in ONE iteration only when `reinvestPct>0 && FLAG_DRAIN_FIRST`; GASOPT-02 hoists to one call/iteration, keeping the existing laziness) |
| A8 | stall ladder `:823-838` — `dayStart = today * 1 days + 82_620` (`:829`), bands 2h→6× / 1h→4× / 20m→2× (ABSOLUTE-day epoch, autoBuy's own multiplier) | `uint256 bountyMultiplier = 1;` :827; `{ uint256 dayStart = uint256(today) * 1 days + 82_620;` :829; `uint256 elapsed = block.timestamp > dayStart ? block.timestamp - dayStart : 0;` :830; `if (elapsed >= 2 hours) { bountyMultiplier = 6; } else if (elapsed >= 1 hours) { bountyMultiplier = 4; } else if (elapsed >= 20 minutes) { bountyMultiplier = 2; }` :831-837 | **MATCH** (ABSOLUTE-day epoch; cross-referenced in Section C / D-03) |
| A9 | bounty `:845` (`bountyEarned = batchLen * ((BOUNTY_ETH_TARGET * PRICE_COIN_UNIT * bountyMultiplier) / mp);`) | `bountyEarned = batchLen * ((BOUNTY_ETH_TARGET * PRICE_COIN_UNIT * bountyMultiplier) / mp);` :845 (per-item MARGINAL × `batchLen` — the GAS-02 per-item break-even pattern) | **MATCH** |
| A10 | `creditFlip(msg.sender, bountyEarned)` `:846` — the ONE `creditFlip` per tx, fired LAST (CEI) | `ICoinflip(ContractAddresses.COINFLIP).creditFlip(msg.sender, bountyEarned);` :846 (then `emit AutoBuyCompleted(...)` :847; `return bountyEarned;` :848). The `batchPurchase` external call is at :821, BEFORE the multiplier compute + the bounty `creditFlip` — `creditFlip` is the last external call (CEI) | **MATCH** |
| A11 | `_currentDay()` `:886-889` (`return uint32((block.timestamp - 82620) / 1 days);`) | `function _currentDay() internal view returns (uint32) {` :886; `return uint32((block.timestamp - 82620) / 1 days);` :887; `}` :888 | **MATCH** (function body :886-888; the `:889` upper bound is the closing brace of the contract — within the cited range) |
| A12 | anti-spam reverts `EmptyAutoBuy()` `:143` + `NoSubscribersAutoBought()` `:146` (the ROUTER-06 `NoWork()` revert-idiom precedent) | `error EmptyAutoBuy();` :143 (raised at :569); `error NoSubscribersAutoBought();` :146 (raised `if (!didWork) revert NoSubscribersAutoBought();` :806) | **MATCH** (the D-02 `NoWork()` revert-idiom precedent) |
| A13 | the `batchPurchase` keeper-buy call site (the v48 KEEP-04 two-tier 75/20/5 affiliate-code passthrough survival — confirm the code arg) | AfKing fires `IGame(ContractAddresses.GAME).batchPurchase{value: totalValue}(players, amounts, modes);` at **:821** — `batchPurchase` carries **NO** affiliate-code argument (AfKing's interface decl `:26-30` is `batchPurchase(address[], uint256[], uint8[])`). The affiliate code is wired entirely game-side: `DegenerusGame.sol:1781` `_purchaseFor(player, 0, msg.value, bytes32("DGNRS"), payKind);` inside `_batchPurchaseUnit` (:1773-1782, reached from `batchPurchase`'s per-player `try this._batchPurchaseUnit{value: slice}(...)`) | **MATCH + KEEP-04 SURVIVES** (the v48 KEEP-04 `bytes32("DGNRS")` two-tier wiring is LIVE at `0cc5d10f` — the `DegenerusGame.sol:1781` docstring confirms "primary 75% → SDGNRS, secondary 20% → VAULT"; v48 ATTEST cited `:1778` → **SHIFTED +3**). Because the affiliate wiring is game-side and AfKing only forwards `totalValue`, the `_autoBuy` internal refactor (router) **does NOT touch the affiliate-code path** — the ROUTER-05 passthrough survives unchanged.) |

**Section A roll-up:** 13 anchors — **13 MATCH / 0 SHIFTED / 0 ABSENT** (one cross-contract note: the
affiliate-code wiring lives at `DegenerusGame.sol:1781`, SHIFTED +3 vs the v48 ATTEST `:1778` — IMPL must
re-anchor there, not in AfKing). **0 IMPL blockers.**

---

## B. ROUTER-07 / D-01a — per-leg no-untrusted-ETH-send (the no-guard basis)

The D-01 disposition (NO `nonReentrant` guard on `doWork`) rests on a **checked fact**, not an assumption:
each routed leg routes player value through the pull-pattern `claimableWinnings` ledger and sends ETH only
to `ContractAddresses.*` pinned protocol contracts (or back to the keeper-contract), never a synchronous
push to an untrusted address. Per the no-"by construction" rule (`feedback_verify_call_graph_against_source`),
each leg is grep-shown below.

| # | doWork leg | ETH send target (grep) | Player-value routing | Verdict |
|---|---|---|---|---|
| B1 | **advance** (`IGame.advanceGame()` → `AdvanceModule.advanceGame`) | `grep -n '\.call{value\|\.transfer(\|\.send('` over `DegenerusGameAdvanceModule.sol` returns **ZERO** sites — the advance path makes NO direct ETH send at all. Jackpot winnings credit the pull ledger (`claimablePool += uint128(claimableDelta);` :894) | Winners are paid via `claimablePool` / `claimableWinnings` (pull). The only money-out is the keeper bounty via `creditFlip` (flip-credit). | **NO UNTRUSTED SEND** |
| B2 | **autoOpen** (`IGame.autoOpen(maxCount)` :1636 → `_autoOpenBox` :1705 → `_openLootBoxFor` :729) | The leg's only money-out is the keeper bounty `if (reward != 0) coinflip.creditFlip(msg.sender, reward);` :1676. The box-open (`_openLootBoxFor`) materializes winnings into the player's pull ledger; the only in-path external value-hop in the mint→lootbox path is the **fixed-recipient pinned VAULT** value-hop (`DegenerusGameMintModule:1066`, per the `_batchPurchaseUnit` OPEN-C docstring :1721-1730), made AFTER state writes (CEI), recipient cannot pass the AF_KING gate | Player winnings → `claimableWinnings` (pull). | **NO UNTRUSTED SEND** |
| B3 | **_autoBuy** (internal, the `autoBuy` body :567 → `IGame.batchPurchase` :821 → game-side `_batchPurchaseUnit`) | AfKing's only ETH send in the buy path is the **unspent-value refund back to `msg.sender`** — but `msg.sender` to `batchPurchase` is the **keeper-contract AfKing itself** (pinned `AF_KING`), and game-side the single refund `(bool ok, ) = payable(msg.sender).call{value: msg.value - spent}("");` `DegenerusGame.sol:1763` sends to that same keeper-contract. The per-player mint→lootbox→prize-pool path credits the pull ledger; per-player slices move into the `try this._batchPurchaseUnit{value: slice}` sub-call frame (a failed slice stays in the contract, refunded once) | Player value flows through `claimableWinnings` (pull) + the per-player isolation try/catch; the only push is back to the pinned keeper-contract. | **NO UNTRUSTED SEND** |
| B4 | **keeper bounty (all three legs)** | advance: `creditFlip(caller, …)` `AdvanceModule:189/225/468`; autoOpen: `creditFlip(msg.sender, reward)` `DegenerusGame:1676`; _autoBuy: `creditFlip(msg.sender, bountyEarned)` `AfKing:846`. ALL pay as `coinflip.creditFlip(...)` flip-credit — never liquid ETH/BURNIE; `burnForKeeper` (not in these legs) burns | The bounty is minted FLIP CREDIT to the player/keeper — **the keeper is never a payee** of an ETH send. `creditFlip` fires LAST in each leg (CEI ordering — AfKing `:846` after `batchPurchase` `:821`). | **KEEPER-NEVER-A-PAYEE + creditFlip-LAST (CEI) CONFIRMED** |

**Out-of-leg ETH sends (confirmed NOT reachable from the doWork legs):** `DegenerusGame.sol:1907`
(`pullRedemptionReserve` → pinned `ContractAddresses.SDGNRS`), `:2213`/`:2230`/`:2251`
(`_payoutWithStethFallback` / `_payoutWithEthFallback` — the redemption/claim withdrawal helpers, where
`to` is the player who triggered the pull, NOT a push during keeper work). None is on the advance /
autoOpen / _autoBuy path.

**Formal no-guard basis (recorded verbatim for `329-SPEC.md`):**
> *keeper-never-a-payee + no untrusted ETH send + one-category structural early-return + `creditFlip`-last
> CEI ordering*

No leg pushes ETH to an untrusted address; there is no untrusted control-flow handoff anywhere in the
composition, so there is nothing to re-enter through and a `nonReentrant` guard would guard nothing
(D-01). The empirical `router→game→creditFlip` double-pay regression backstop stays a Phase 332 TST-02
success criterion regardless (D-01b).

**Section B roll-up:** 0 untrusted-push legs found → **0 ROUTER-07 blockers**. The no-guard disposition
rests on a checked fact.

---

## C. GAS-03 / D-03 — dual day-start epoch + GASOPT-01 hoist

### C.1 — Dual epoch attestation (intentionally distinct → no physical merge, D-03a)

| # | Epoch formula (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| C1 | **AfKing absolute-day** epoch `today * 1 days + 82_620` (`AfKing.sol:829`) — autoBuy's own stall multiplier | `uint256 dayStart = uint256(today) * 1 days + 82_620;` `AfKing.sol:829` where `today = _currentDay()` (`:887` `(block.timestamp - 82620) / 1 days`). Resets at the 22:57 UTC boundary each midnight | **MATCH** |
| C2 | **AdvanceModule game-day** epoch `(day-1 + DEPLOY_DAY_BOUNDARY) * 1 days + 82_620` (`AdvanceModule.sol:243-246`) — the advance liveness multiplier | `uint256 dayStart = (uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620;` `AdvanceModule.sol:243-246`; `uint256 elapsed = ts - dayStart;` :247; bands 2h→6× / 1h→4× / 20m→2× :248-254. Keeps growing across a multi-day stall (`day` = the lagging `dailyIdx`) | **MATCH** |

**Verdict (D-03a, recorded for SPEC):** the two formulas do NOT duplicate the same number — they
**intentionally measure different things**: AfKing's autoBuy multiplier = elapsed since the start of the
*current absolute day* (correct for a per-day buying window; resets at each midnight boundary);
AdvanceModule's advance multiplier = elapsed since the start of the *lagging game-day `dailyIdx`*
(correct for advance-liveness escalation; keeps growing across a multi-day stall). **Design-1 satisfies
GAS-03 by single-sourcing the ADVANCE multiplier in `AdvanceModule` and returning it via the
`(uint8 mult, bool rewardable)` tuple** — the router consumes the returned value and never recomputes, so
the money-path "no-recompute / no off-by-one" goal (Pitfall 4) is met. AfKing's autoBuy epoch is left
**UNTOUCHED** (a different category's self-contained, correct, non-duplicated multiplier). They need NOT be
physically merged. A future auditor seeing the divergence should read this attestation: it is intentional,
not a bug.

### C.2 — GASOPT-01 nested-mapping storage-pointer hoist (gas-only, behavior-identical)

| # | Site (claimed) | ACTUAL (`contracts/modules/DegenerusGameMintModule.sol`) | Verdict |
|---|---|---|---|
| C3 | `processFutureTicketBatch` `:393` — `rk` loop-invariant; repeated `ticketsOwedPacked[rk][player]` reads | `function processFutureTicketBatch(` :393; `uint24 rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl);` :398 (set ONCE before the `while (idx < total && used < writesBudget)` :429 player loop); `ticketsOwedPacked[rk][player]` reads/writes at :431, :441, :453, :463, :498 | **MATCH** (`rk` is loop-invariant — computed once at :398; CONTEXT cited `:398`, the function header is `:393` so the body anchor is consistent. Hoisting `mapping(address=>uint40) storage owedMap = ticketsOwedPacked[rk]` drops the outer keccak per ticket — **behavior-identical, gas-only**) |
| C4 | `processTicketBatch(uint24 lvl)` `:670` — `rk` loop-invariant; repeated `ticketsOwedPacked[rk][player]` reads | `function processTicketBatch(uint24 lvl) external returns (bool finished) {` :670; `uint24 rk = _tqReadKey(lvl);` :671 (set ONCE before the `while (idx < total && used < writesBudget)` :697 player loop); `ticketsOwedPacked[rk][player]` reads/writes at :741, :748, :754 (+ the `_zeroOwedRemainder` helper hoist target :769/:822) | **MATCH** (`rk` is loop-invariant — computed once at :671; CONTEXT cited `:671` → **MATCH** [the plan's "SHIFTED −1" note refers to the function-header vs key-line offset]. Same hoist, behavior-identical, gas-only) |

**Section C roll-up:** 4 anchors — **4 MATCH / 0 SHIFTED / 0 ABSENT.** GAS-03 verdict: epochs
intentionally distinct, design-1 single-sources the advance multiplier, no physical merge (D-03a).
GASOPT-01 hoist is gas-only behavior-identical at both sites. **0 IMPL blockers.**

---
