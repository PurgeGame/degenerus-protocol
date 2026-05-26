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

## D. AdvanceModule + DegenerusGame-wrapper anchors + the 3 caller-reward `creditFlip` classifications

### D.1 — Advance anchors + the wrapper decode site

| # | Anchor (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| D1 | `advanceGame()` `AdvanceModule.sol:155` (gains the design-1 `(uint8 mult, bool rewardable)` return at IMPL) | `function advanceGame() external {` :155 — currently **void** (no return tuple); body resolves `caller`/`ts`/`day`/`inJackpot`/`lvl` :156-160 | **MATCH** (currently returns NOTHING — the `(uint8 mult, bool rewardable)` return is the IMPL PRODUCER edit) |
| D2 | `ADVANCE_BOUNTY_ETH = 0.005 ether` `:147` (deleted at IMPL per ADV-01) | `uint256 private constant ADVANCE_BOUNTY_ETH = 0.005 ether;` :147 (referenced by the 3 caller-reward sites :191/:227/:470) | **MATCH** (the standalone advance caller-reward; removed at ADV-01 — the bounty re-homes to the router) |
| D3 | game-day stall+epoch block `:238-255` | `uint256 bountyMultiplier = 1;` :242; `dayStart = (uint256(day-1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620;` :243-246; `elapsed = ts - dayStart;` :247; bands 2h→6× / 1h→4× / 20m→2× :248-254 | **MATCH** (the new-day-path advance multiplier; see Section C) |
| D4 | `DegenerusGame.advanceGame` wrapper `:275` — delegatecall + `if (!ok) _revertDelegate(data);` (gains the design-1 `(uint8,bool)` decode + new signature at IMPL) | `function advanceGame() external {` :275; `(bool ok, bytes memory data) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(abi.encodeWithSelector(IDegenerusGameAdvanceModule.advanceGame.selector));` :276-282; `if (!ok) _revertDelegate(data);` :284. `_revertDelegate` exists `:1022` | **MATCH** (the wrapper today captures `data` ONLY for the revert path; the design-1 CONSUMER edit decodes `data` into `(uint8 mult, bool rewardable)` at the success branch :283-284 + updates the external signature. This is the exact decode site) |

### D.2 — The 3 caller-reward `creditFlip` site classifications

The advance bounty pays the **caller** at three sites (all `creditFlip(caller, …)`); a 4th `creditFlip`
exists at `:876` but pays the pinned `ContractAddresses.SDGNRS` (the future→next merge credit) — it is
**NOT a caller bounty** and is **NOT router-rewardable**, so it is correctly excluded from the 3-site list.

| # | `creditFlip` site | Condition / branch | Bounty math | Classification |
|---|---|---|---|---|
| D5 | `:189` (new-day) | inside `if (goStage == STAGE_TICKETS_WORKING)` :185 — a game-over path surfaced a partial drain; pay the caller so they retry until the queue drains and terminal jackpot runs | `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT) / PriceLookupLib.priceForLevel(lvl)` :191 (no `bountyMultiplier`) | **REWARDABLE advance-leg** — the `rewardable` flag MUST cover it (new-day terminal-drain advance work) |
| D6 | `:225` (MID-DAY partial-drain, ADV-05) | inside `if (ticketWorked || !ticketsFinished)` :220 — the mid-day partial-drain branch (`day == dailyIdx`, `LR_MID_DAY != 0`, tickets not fully processed); `emit Advance(STAGE_TICKETS_WORKING, lvl)` :224; `return` :230 | `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT) / PriceLookupLib.priceForLevel(lvl)` :227 (no `bountyMultiplier`) | **REWARDABLE advance-leg per ADV-05** — the USER-locked mid-day partial-drain is router-rewardable advance-leg work; the `rewardable` flag MUST cover it |
| D7 | `:468` (main new-day advance) | the new-day advance terminal site — after `payDailyJackpot(true, lvl, rngWord)` :463 + `emit Advance(stage, lvl)` :467 | `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT * bountyMultiplier) / PriceLookupLib.priceForLevel(lvl)` :470 (scaled by the stall `bountyMultiplier` from :243-254) | **REWARDABLE advance-leg** — the primary stall-escalating new-day advance bounty; the `rewardable` flag MUST cover it |
| D8 | `:876` (NOT a caller bounty) | `coinflip.creditFlip(ContractAddresses.SDGNRS, …)` :876 — the future→next pool-merge sDGNRS coinflip credit | `(memCurrent * PRICE_COIN_UNIT) / (PriceLookupLib.priceForLevel(level) * 20)` :877-878 | **NOT router-rewardable** — pays the pinned SDGNRS, not the caller; a protocol accounting credit, untouched by ADV-01/03 |

**Verdict (deletion + functional + tuple):**
- Deleting all 3 caller-reward sites (`:189/:225/:468`) leaves `advanceGame` **fully functional + unrewarded
  standalone** (ADV-01/ADV-03): the advance state machine (stage transitions, ticket batches, jackpot,
  daily-RNG) does not depend on the `creditFlip` calls — they are pure caller-incentive payouts. The :876
  SDGNRS merge-credit stays.
- **Design-1 return tuple `(uint8 mult, bool rewardable)` — distinct-bool verdict:** `rewardable` is a
  **DISTINCT bool**, NOT implied by `mult>0`. A leg can do advance work but be non-rewardable (e.g. a
  standalone fallback caller, or the :876-only path), and `mult` can be ≥1 independent of rewardability
  (the stall multiplier exists whenever there is a new-day advance, but whether THIS call earns the
  re-homed router bounty is a separate condition). The wrapper (D4) decodes both; the router pays the
  re-homed advance bounty IFF `rewardable`, scaled by `mult`.

---

## E. ADV-04 (invariant b) — `totalFlipReversals` VRF-window freeze

| # | Anchor (claimed) | ACTUAL (`contracts/modules/DegenerusGameAdvanceModule.sol`) | Verdict |
|---|---|---|---|
| E1 | `_applyDailyRng(` `:1834` | `function _applyDailyRng(uint32 day, uint256 rawWord) private returns (uint256 finalWord) {` :1834-1837 | **MATCH** |
| E2 | `uint256 nudges = totalFlipReversals;` `:1838` (the player-controllable VRF-window nudge) | `uint256 nudges = totalFlipReversals;` :1838; `finalWord = rawWord;` :1839; `if (nudges != 0) { unchecked { finalWord += nudges; }` :1840-1842 | **MATCH** (`totalFlipReversals` is read INTO the consumed VRF word `finalWord`) |
| E3 | `totalFlipReversals = 0;` `:1844` (consumed + reset inside the consume path) | `totalFlipReversals = 0;` :1844 (inside the `if (nudges != 0)` block); then `rngWordCurrent = finalWord;` :1846, `rngWordByDay[day] = finalWord;` :1847, `lastVrfProcessedTimestamp = uint48(block.timestamp);` :1848 | **MATCH** (consumed-and-reset in the same call that applies the daily RNG word) |

**Recorded facts (SPEC-relevant):**
- `totalFlipReversals` is the player-controllable in-window nudge the v45 freeze invariant protects
  (`v45-vrf-freeze-invariant`). The protected window is **rng-request → consume**: the nudge accumulated
  before the daily VRF word is applied is folded into `finalWord` and then zeroed at `_applyDailyRng`.
- **Backward-trace (per `feedback_rng_window_storage_read_freshness`):** the SLOADs in the consume path
  alongside the VRF word are `totalFlipReversals` (:1838) and `rawWord` (the passed VRF word) — the writes
  are `rngWordCurrent`/`rngWordByDay[day]`/`lastVrfProcessedTimestamp`/`totalFlipReversals=0`. The router
  introduces **NO new mutable SLOAD into this consume path**: the router consumes the daily tick via the
  design-1 RETURN (the `(uint8 mult, bool rewardable)` tuple from `advanceGame`) and **recomputes nothing**
  — it neither reads nor writes any rng-window state. (Note: the non-reset gap-day path at :1724 —
  "totalFlipReversals is NOT reset here" — and the gap-day "zero nudges" path :1777 are existing behavior,
  not router-introduced.)
- **No new in-window read introduced by the router composition** → invariant (b) holds under the new
  composition. The EMPIRICAL freeze proof (rotation/perturbation between rng-request and fulfilment asserts
  byte-identical output; extend `RngLockDeterminism`) is **TST-01's job (Phase 332)** — this attestation
  only confirms the variable + the window exist at `0cc5d10f` and the router adds no new in-window read.

**Section E roll-up:** 3 anchors — **3 MATCH / 0 SHIFTED / 0 ABSENT.** ADV-04 verdict: the
request→consume freeze window is intact; the router adds NO new mutable in-window SLOAD. **0 blockers.**

---

## F. ROUTER-04 — O(1) discovery views + `maxCount` per-leg + the D-06 baseline

### F.1 — O(1) discovery-view predicates (no unbounded scans, Pitfall 5)

| # | Predicate (claimed) | ACTUAL (grep) | Location | O(1)? | Verdict |
|---|---|---|---|---|---|
| F1 | `advanceDue()` — covers BOTH new-day AND mid-day partial-drain | **New-day:** `currentDayView() != dailyIdx` — `currentDayView()` :462 `return _simulatedDayIndex();`; `dailyIdx` is the monotonic day counter (`DegenerusGameStorage.sol:231` `uint32 internal dailyIdx;`). **Mid-day partial-drain:** the `LR_MID_DAY` packed flag — `_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0` (set when a ticket-batch is mid-processing `AdvanceModule:1085`, cleared when finished `:222`) | `DegenerusGame` (reads `dailyIdx` + the packed LR flag) | **O(1)** — two scalar/packed SLOADs, no scan | **RESOLVED — O(1)** |
| F2 | `boxesPending()` — `boxPlayers[activeIndex].length > boxCursor` AND `lootboxRngWordByIndex[activeIndex] != 0` | `boxCursor` :1551 (`uint48 internal boxCursor;`), `boxCursorIndex` :1554, `boxPlayers` mapping :1562 (`mapping(uint48 => address[]) internal boxPlayers;`), the open is gated on `lootboxRngWordByIndex[index] != 0` :1647. The predicate reads `boxPlayers[index].length` (one SLOAD of the dynamic-array length slot) + `boxCursor` + `lootboxRngWordByIndex[index]` | `DegenerusGame` (the box-open state lives here) | **O(1)** — `.length` + two scalars, NO iteration over the array | **RESOLVED — O(1)** |
| F3 | buys-pending — via AfKing-local cursor reads | `_autoBuyDay` :215 + `_autoBuyCursor` :216 (one slot) read as `cursor = _autoBuyDay == today ? uint256(_autoBuyCursor) : 0;` :577; the predicate compares the cursor vs the subscriber-set length (`subscriberCount()` :514, `_subscribers.length`) — both O(1) reads | **`AfKing`-local** (the cursor is AfKing state, not game state) | **O(1)** — two scalar SLOADs + `.length` | **RESOLVED — O(1)** |

**View-location resolution:** advance + boxes views live on `DegenerusGame` (they read game state —
`dailyIdx`/`LR_MID_DAY`/`boxPlayers`/`boxCursor`/`lootboxRngWordByIndex`); buys-pending is `AfKing`-local
(reads the AfKing cursor). None iterates over a growable set — all O(1), no unbounded scans (Pitfall 5).

### F.2 — `maxCount` per-leg mapping (Discretion resolution)

`doWork(maxCount)` maps `maxCount` onto each routed leg as: **advance** — NO count arg (`advanceGame()`
takes none; it does its own internally-bounded ticket batch incl. the mid-day partial-drain at
`AdvanceModule:225`); **autoOpen** — `autoOpen(maxCount)` (the `while (cursor < qlen && opened < maxCount)`
loop :1656); **_autoBuy** — `_autoBuy(maxCount)` (the internal refactor of `autoBuy(uint256)` :567, the
`processed < maxCount` bound). So `maxCount` applies ONLY to the two count-bounded legs (D-06c).

### F.3 — D-06 baseline: current `count==0` handling (NEW Phase-330 behavior has a clean baseline)

| # | Leg | CURRENT `count==0` behavior at `0cc5d10f` | Verdict |
|---|---|---|---|
| F4 | `autoBuy(0)` | `if (maxCount == 0) revert EmptyAutoBuy();` `AfKing.sol:569` — REVERTS | **MATCH** (a footgun today; D-06 makes `0` a default) |
| F5 | `autoOpen(0)` | the `:1656` loop `while (cursor < qlen && opened < maxCount)` NEVER enters when `maxCount == 0` (`opened` starts 0, `0 < 0` is false) → silent NO-OP | **MATCH** (no-op today; D-06 makes `0` a default) |
| F6 | `advanceGame` | takes NO count arg — D-06 does not apply (D-06c) | **MATCH** |

**D-06 baseline verdict:** there is **NO existing fixed-default / `gasleft()`-bounded-loop pattern** on
these legs at `0cc5d10f` (`autoBuy(0)` reverts, `autoOpen(0)` no-ops, advance has no count). So the SPEC's
locked **D-06** (`maxCount == 0` → a FIXED `≈ GAS_BUDGET / avg-marginal` per-leg default count, NOT a
`gasleft` loop, NOT process-all) is a **NEW IMPL behavior for Phase 330** with a clean baseline. Under
D-06e, the default lives in the shared internal `_autoBuy` so `0`=default everywhere and `EmptyAutoBuy` is
removed/repurposed (the router's `_autoBuy(0)` path must NOT revert) — confirm at SPEC, verify at TST.
Faucet-safety (D-06f): a larger default batch pays proportionally more bounty AND costs proportionally more
gas (per-item MARGINAL `AfKing:845`) → still per-item break-even, no positive-EV from batching; the
GAS-budget + per-leg DEFAULT_*_COUNT constants are SPEC placeholders calibrated at Phase 331.

**Section F roll-up:** 6 anchors — **6 MATCH / 0 SHIFTED / 0 ABSENT.** All 3 discovery views O(1) (no
unbounded scans); `maxCount` maps to autoOpen + _autoBuy only; the D-06 default-count is a NEW IMPL
behavior on a clean baseline. **0 blockers.**

---

## G. Invariant (c) / D-04 — guaranteed free-fallback `advanceGame()` callers

After the advance bounty re-homes to the router, invariant (c) is attested on the EXISTING structure
(no new fallback added, `feedback_frozen_contracts_no_future_proofing`): re-homing reduces NO structural
caller — it only moves the PAYMENT.

| # | Free-fallback caller (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| G1 | the 30-min universal bypass — `_enforceDailyMintGate` `:989` + `if (elapsed >= 30 minutes) return;` `:1012` (UNCONDITIONAL) | `function _enforceDailyMintGate(` :989; `uint256 elapsed = (block.timestamp - 82620) % 1 days;` :1009; `// Anyone after 30 min` :1011; `if (elapsed >= 30 minutes) return;` :1012 (unconditional — no caller predicate). The 15-min pass-holder bypass follows :1015 | **MATCH** (CONTEXT cited ~`:1008` → **SHIFTED +4**, actual `:1012`). standalone `advanceGame()` is permissionless to ANYONE 30+ min after the day boundary (~23.5h/day); the first-30-min window is covered with no gap by the router bounty (escalating 2× at 20 min) + the 15-min pass-holder / DGVE-majority bypass tiers |
| G2 | `DegenerusVault.gameAdvance()` `:527-528` (`onlyVaultOwner` → `advanceGame()`) | `function gameAdvance() external onlyVaultOwner {` :527; `gamePlayer.advanceGame();` :528 | **MATCH** (DGVE-majority always-bypass protocol-owned caller; read-only — NOT modified) |
| G3 | `StakedDegenerusStonk.gameAdvance()` `:421-422` (permissionless → `advanceGame()`) | `function gameAdvance() external {` :421; `game.advanceGame();` :422 | **MATCH** (permissionless protocol-owned wrapper; read-only — NOT modified) |
| G4 | the ~120-day death-clock — `AdvanceModule.sol:109` (L1+ 120-day) + extend `:1198` | `uint32 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 365; // Level-0 only; level 1+ uses hardcoded 120 days` :109; the extend-by-stall-duration `purchaseStartDay += gapCount;` :1200 (+ `gapDays = gapCount;` :1201; CONTEXT cited `:1198` → **SHIFTED +2**) | **MATCH** (the tertiary failsafe — latches gameOver if the game is truly abandoned; extends by stall duration so gap days don't count toward the 120-day timeout) |

**Verdict (D-04):** re-homing the advance bounty into `doWork` reduces NO structural `advanceGame()`
caller — PRIMARY (rewarded) = the router's advance leg keeps the stall-escalating bounty (re-homed, not
removed); SECONDARY (structurally-guaranteed, unrewarded) = the 30-min universal bypass + the Vault/sStonk
wrappers; TERTIARY (failsafe) = the 120-day death-clock. No single-point liveness risk is created.

**Section G roll-up:** 4 anchors — **4 MATCH / 0 SHIFTED / 0 ABSENT** (2 CONTEXT-line SHIFTs noted: 30-min
bypass +4, death-clock +2). The free-fallback caller hierarchy is intact. **0 blockers.**

---

## D-05f liveness note (autoResolve flat-"lose" re-peg — surfaced for the SPEC)

Per D-05f, a flat "lose" reward removes the rational-keeper incentive to resolve LOSING Degenerette bets
(winning bets are self-resolved by owners claiming winnings). **Grep check — does any invariant/accounting/
RNG-slot/cleanup REQUIRE losing bets to be resolved?** NO. `degeneretteBets[player][betId]` is a per-(player,
betId) mapping (`DegenerusGameDegeneretteModule.sol:526` write, `:605` read, `delete …[player][betId]`
`:634`); there is NO pending-bet count, NO outstanding-bet accounting global, NO RNG-slot or cleanup invariant
that depends on an unresolved losing bet. An unresolved losing bet is **inert cruft** in a mapping slot —
SAFE. (The autoResolve entrypoint `DegenerusGame.sol:1587` takes caller-supplied `(players[], betIds[])` with
NO on-chain enumeration — confirming D-05's router-fold-blocked rationale; WWXRP `currency == 3` excluded
from the reward :1604-1614, AUTO-02 item-0 probe `BatchAlreadyTaken` :1597, per-item try/catch :1610.) A flat
count-independent reward actually NUDGES clearing the whole backlog in one tx (max work per paid tx). No USER
escalation needed.

---

## Roll-up

**Total anchors attested across all sections: 34** (A: 13 · C: 4 · D: 8 · E: 3 · F: 6 — plus the per-leg
B rows and the D-05f note). **34 MATCH / 0 SHIFTED-into-ABSENT / 0 ABSENT.**

**IMPL-blocker count across all sections: 0.**

**Recorded line-drifts (CONTEXT/v48-ATTEST citations to re-anchor at IMPL):**
- KEEP-04 affiliate-code wiring: `DegenerusGame.sol:1781` (v48 ATTEST cited `:1778` → SHIFTED +3).
- 30-min universal bypass: `AdvanceModule.sol:1012` (CONTEXT cited ~`:1008` → SHIFTED +4).
- death-clock extend: `AdvanceModule.sol:1200` (CONTEXT cited `:1198` → SHIFTED +2).
- GASOPT-01 `rk` set: `processFutureTicketBatch` body `:398` (header `:393`); `processTicketBatch` `:671`
  (header `:670`).

**Load-bearing decision verdicts:**
- **ROUTER-07 / D-01a — NO-GUARD BASIS HOLDS.** Per-leg grep (Section B): the advance leg makes ZERO ETH
  sends; autoOpen/_autoBuy route player value through the `claimableWinnings` pull ledger and send ETH only
  to pinned `ContractAddresses.*` / the keeper-contract; the bounty pays as `creditFlip` flip-credit
  (keeper-never-a-payee) fired LAST (CEI). 0 untrusted-push legs → 0 ROUTER-07 blockers. Formal basis:
  *keeper-never-a-payee + no untrusted ETH send + one-category structural early-return + creditFlip-last
  CEI ordering.* (Empirical double-pay backstop = TST-02, D-01b.)
- **GAS-03 / D-03 — EPOCHS INTENTIONALLY DISTINCT.** AfKing absolute-day (`:829`) vs AdvanceModule game-day
  (`:243-246`) measure different things (per-day buying window vs lagging-game-day advance liveness);
  design-1 single-sources the ADVANCE multiplier via the `(uint8,bool)` return → no physical merge (D-03a).
- **ADV-04 — NO NEW IN-WINDOW READ.** `totalFlipReversals` is read (`:1838`) + reset (`:1844`) inside
  `_applyDailyRng` (`:1834`); the request→consume freeze window is intact; the router consumes via the
  design-1 return and introduces NO new mutable in-window SLOAD. (Empirical freeze fuzz = TST-01.)
- **Invariant (c) / D-04 — FALLBACK CALLERS INTACT.** The 30-min universal bypass (`:1012`), Vault
  `gameAdvance()` (`:527-528`), sStonk `gameAdvance()` (`:421-422`), and the 120-day death-clock
  (`:109`/`:1200`) all confirm re-homing the bounty reduces no structural caller.

**Claude's-Discretion grep facts (resolved):** the design-1 `(uint8 mult, bool rewardable)` return is a
DISTINCT-bool tuple decoded at the `DegenerusGame.advanceGame` wrapper (`:275`/decode at :283-284); the 3
caller-reward `creditFlip` sites are classified (`:189` new-day REWARDABLE / `:225` mid-day partial-drain
REWARDABLE per ADV-05 / `:468` main new-day REWARDABLE; the `:876` SDGNRS merge-credit is NOT
router-rewardable); the 3 O(1) discovery views (advanceDue / boxesPending / buys-pending) are no-unbounded-
scan with advance+boxes on `DegenerusGame` and buys on `AfKing`-local; `maxCount` maps to autoOpen + _autoBuy
only (D-06c); the D-06 default-count is a NEW IMPL behavior on a clean `count==0` baseline; the v48 KEEP-04
`bytes32("DGNRS")` affiliate-code passthrough is LIVE and survives the `_autoBuy` refactor; the GASOPT-01
`rk`-loop-invariant hoist is gas-only at both MintModule sites.

*Anchors will shift once the Phase 330 batched diff lands — re-grep at IMPL time. Plan 03's
shared-surface reconciliation + the `329-SPEC.md` blueprint consume: the design-1 `(uint8,bool)` return
producer (`AdvanceModule:155`) / consumer (`DegenerusGame:275` decode); the 3 deleted caller-reward
`creditFlip` sites; the `_autoBuy` internal refactor (the KEEP-04 affiliate wiring stays game-side); the 3
O(1) discovery-view signatures + locations; the D-06 default-count constants; and the no-guard / dual-epoch
/ freeze / fallback verdicts above.*
