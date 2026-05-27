# 329 — Call-Graph Attestation: REDESIGNED Router + Advance Surface (BATCH-01, half 1)

> **RE-SPEC regeneration (v49.0 keeper-router REDESIGN).** This document REPLACES the stale
> pre-redesign `329-ATTEST-ROUTER-ADVANCE.md` (which attested the SUPERSEDED
> advance→open→buy / `doWork(maxCount)` / dual-stall-epoch / per-item bounty design). It
> re-attests the v49.0 REDESIGNED router (autoBuy → advance → autoOpen, dropped rngLock guards,
> dropped autoOpen try/catch + entry-gate, the unified single `creditFlip` in `doWork`, the D-07
> flat-per-tx model) against the frozen v48.0-closure HEAD.

## Scope

READ-ONLY grep-attestation of every `file:line` anchor cited in the v49.0 redesign docs for the
**core REDESIGNED router + advance-bounty surface** (the 5 locked changes RD-1..RD-5, the D-07
flat-per-tx deletion surface, GAS-03 satisfied-by-deletion, ROUTER-07/D-01a no-untrusted-ETH-send,
ADV-04 freeze, invariant-(c)/D-04a fallbacks, and the D-08 GASOPT-03/04/05 baselines) against the
frozen v48.0-closure baseline HEAD `0cc5d10fbc1232a6d2e7b0464fe21541b9812029` (`0cc5d10f`).

Requirements covered: **BATCH-01** (the 4 structural invariants, this surface half), **ROUTER-07**
(D-01a no-guard basis), **ADV-04** (invariant b, `totalFlipReversals` freeze), **GAS-03** (D-03/D-07
satisfied-by-deletion). The `degeneretteResolve` rename (D-05) is attested separately in
`329-ATTEST-DEGENERETTE-RESOLVE.md` (Plan 02).

Redesign docs attested against source:
- `330-ROUTER-REDESIGN-INTENT.md` — the 5 locked changes + Q1/Q2/Q5 resolutions + the autoBuy-gas
  analysis (the GASOPT-03/04/05 source) + the survivors-vs-reworked split.
- `329-CONTEXT.md` — RD-1..RD-5, D-07 flat-per-tx, D-08 GASOPT-03/04/05, D-01/D-01a re-grounded on
  the unified `creditFlip`, D-04/D-04a, the Claude's-Discretion grep items.

## Sources of truth (this attestation)

- `contracts/AfKing.sol` (889 lines @ 0cc5d10f) — the router's home: `autoBuy(maxCount)` (the
  `_autoBuy` refactor target), the buy loop, the per-tx bounty + `creditFlip`, the stall ladder +
  absolute-day epoch, the two consent gates, the CEI invariant.
- `contracts/DegenerusGame.sol` (@ 0cc5d10f) — `batchPurchase` (the RD-2 game-side guard) + the
  `bytes32("DGNRS")` KEEP-04 affiliate wiring + `autoOpen` / `_autoOpenBox` + `rngLocked` + the
  open-leg gas-units machinery + `currentDayView` + the `advanceGame` wrapper.
- `contracts/modules/DegenerusGameAdvanceModule.sol` (@ 0cc5d10f) — `advanceGame` + the 3 advance
  `creditFlip` sites + the KEPT stall+game-day epoch + the 30-min bypass + the death-clock +
  `_applyDailyRng` / `totalFlipReversals`.
- `contracts/storage/DegenerusGameStorage.sol` (@ 0cc5d10f) — `_queueTickets` + the
  `_livenessTriggered()` revert (the RD-5 entry-gate basis).
- `contracts/DegenerusVault.sol` / `contracts/StakedDegenerusStonk.sol` (@ 0cc5d10f) —
  `gameAdvance()` invariant-(c) fallback wrappers (read-only confirm).
- `contracts/modules/DegenerusGameMintModule.sol` (@ 0cc5d10f) — the GASOPT-01 `[rk]` hoist sites.
- Tests keyed on the `AutoBought` event (GASOPT-04 migration): `test/fuzz/AfKingConcurrency.t.sol`,
  `test/fuzz/AfKingSubscription.t.sol`, `test/fuzz/AfKingFundingWaterfall.t.sol`,
  `test/gas/SweepPerPlayerWorstCaseGas.t.sol`.

**Attestation-method note (CRITICAL — baseline-anchored, NOT the live tree).** The working tree's
`contracts/*.sol` is **DIRTY** — it carries the superseded held-330 IMPL diff
(`git status --porcelain -- 'contracts/*.sol'` lists `AfKing.sol`, `DegenerusGame.sol`, both
interfaces, `DegenerusGameAdvanceModule.sol`, `DegenerusGameMintModule.sol` as modified). The
COMMITTED `HEAD` tree is byte-identical to the baseline (`git diff --name-only 0cc5d10f HEAD --
'contracts/*.sol'` is EMPTY). Therefore **every line-number verdict below is resolved against the
frozen blob via `git show 0cc5d10f:contracts/<path> | grep -n`** — NOT the dirty working tree (which
would report held-330 line numbers, not baseline lines). Source is read from `contracts/` ONLY
(`feedback_contract_locations`). For every anchor whose cited line is a held-tree / redesign-doc
number, the table records BOTH the held line (the drift) AND the actual `0cc5d10f` line (the truth).

## Verdict legend

- `MATCH` — the anchor lands on the claimed line at `0cc5d10f`.
- `SHIFTED(±N)` — content present, `N` lines off the claimed line; the actual `0cc5d10f` line is
  recorded.
- `ABSENT` — content not found / materially diverged (surfaced as an IMPL blocker in the Roll-up).

---

## A. AfKing router anchors + RD-2 (drop the autoBuy-side rngLock guard) + D-07 (dead epoch)

`git show 0cc5d10f:contracts/AfKing.sol | grep -n`. Note: the v48 KEEP-04 rename ALREADY landed at
`0cc5d10f` — the keeper auto-buy entrypoint is `autoBuy(maxCount)` at the baseline (the redesign's
`_autoBuy` is the further internalization). Held-tree drift is recorded per the redesign-doc anchors.

| # | Anchor (held-tree / redesign-doc claim) | ACTUAL @ 0cc5d10f (`git show 0cc5d10f:contracts/AfKing.sol`) | Verdict |
|---|---|---|---|
| A1 | CEI invariant comment "keeper never a payee" (claim `:100`) | `:100` `/// @custom:invariant No reentrancy guard — strict CEI everywhere; the keeper is` → `:101` `/// never a payee in any contract it calls.` (the invariant *block* opens at `:100`) | **MATCH** (`:100` is the block start; the "never a payee" clause wraps to `:101`) |
| A2 | `AutoBought` event decl (claim `:171`; held-tree decl `:186`) | `:171` `event AutoBought(address indexed player, uint32 day, uint256 cost);` | **MATCH** (held drift `:186 → :171`) |
| A3 | `AutoBought` emit (claim `:785`; held-tree emit `:954`) | `:785` `emit AutoBought(player, today, msgValue);` (immediately after the `:784` day-stamp) | **MATCH** (held drift `:954 → :785`) |
| A4 | `lastAutoBoughtDay` Sub field (claim `:81`) + day-stamp write (claim `:784`) | `:81` `uint32 lastAutoBoughtDay;` (inside `struct Sub`, single-slot); write `:784` `sub.lastAutoBoughtDay = today;`; the AlreadyAutoBoughtToday skip reads it `:627` `if (sub.lastAutoBoughtDay >= today)` | **MATCH** (the GASOPT-04 no-double-buy oracle replacement — already a storage field at baseline) |
| A5 | `BOUNTY_ETH_TARGET` immutable (claim `:263`) + ctor set (claim `:279`) | `:263` `uint256 public immutable BOUNTY_ETH_TARGET;`; ctor `:279` `BOUNTY_ETH_TARGET = _bountyEthTarget;` | **MATCH** (peg target; placeholder at SPEC, re-pegged at GAS) |
| A6 | subscribe-time `isOperatorApproved(fundingSource, subscriber)` — **KEEP** (claim `:401`; redesign-doc `:443`) | `:401` `!IGame(ContractAddresses.GAME).isOperatorApproved(fundingSource, subscriber)` inside the `fundingSource != address(0) && fundingSource != subscriber && …` guard → `:403 revert NotApproved();` | **MATCH** (held/doc drift `:443 → :401`; this is the alt-account funding-consent gate — GASOPT-05 KEEPS it) |
| A7 | `autoBuy(maxCount)` (claim `:567`) — the `_autoBuy` refactor target | `:567` `function autoBuy(uint256 maxCount) external returns (uint256 bountyEarned) {` | **MATCH** (the redesign internalizes this to `_autoBuy` called from `doWork`; the standalone parametered form stays UNREWARDED per D-07) |
| A8 | autoBuy entry rngLock guard — **RD-2 REMOVE** (claim `:568`; held-tree `:717`) | `:568` `if (IGame(ContractAddresses.GAME).rngLocked()) revert AutoBuyAborted(msg.sender, 1);` (error decl `:141 AutoBuyAborted(address caller, uint8 reason)`, "Reason 1 = RngLocked" `:140`) | **MATCH** (held drift `:717 → :568`; **RD-2: REMOVE** — Q1 RESOLVED SAFE, this was v46 batch-hygiene from Phase 317 `df4ef365`, NOT orphan-index defense; buys are freeze-safe by construction, orphan defended on the resolution side) |
| A9 | per-iteration `isOperatorApproved(player, address(this))` — **GASOPT-05 REMOVE** (claim `:676`; held-tree `:838`) | `:676` `if (!IGame(ContractAddresses.GAME).isOperatorApproved(player, address(this))) {` → `:677 emit PlayerSkipped(player, 5);` then `++cursor` skip | **MATCH** (held drift `:838 → :676`; GASOPT-05 removes — the SUB is the consent unit, revoke = `setDailyQuantity(0)` → loop tombstone-skip `:612 if (sub.dailyQuantity == 0)`, ~2.8k/player. BLOCKING-CONDITION: 333 SWEEP re-attests the 4 OPEN-E protections without `:676` before closure) |
| A10 | two in-loop `claimableWinningsOf(player)` STATICCALLs — GASOPT-02 hoist / **GASOPT-03 batched-read** targets (claim `:691`/`:722`; held-tree `:854`/`:888`) | `:691` `uint256 claimable = IGame(ContractAddresses.GAME).claimableWinningsOf(player);`; `:722` `uint256 cred = IGame(ContractAddresses.GAME).claimableWinningsOf(player);` (decl `:34`) | **MATCH** (held drift `:854/:888 → :691/:722`; GASOPT-03 collapses both per-player STATICCALLs into ONE batched `keeperSnapshot`/`batchPurchaseForKeeper` read; SUBSUMES GASOPT-02) |
| A11 | autoBuy stall ladder + ABSOLUTE-day epoch — **D-07 DEAD-after-redesign** (claim `:823-846`, epoch `:829`; held-tree epoch `:992-993`) | `:823-838` the SUB-03 stall-escalating multiplier block; `:829` `uint256 dayStart = uint256(today) * 1 days + 82_620;`; bands `:831 if (elapsed >= 2 hours) bountyMultiplier = 6;` / `:833 1 hours → 4` / `:835 20 minutes → 2` | **MATCH** (held drift `:992-993 → :829`; **D-07 DEAD** — only advance escalates; autoBuy's stall multiplier + its absolute-day epoch are deleted, leaving advance as the SOLE stall epoch) |
| A12 | per-tx bounty (claim `:845`) + in-callee `creditFlip` — **RD-4 PULL OUT** (claim `:846`) | `:845` `bountyEarned = batchLen * ((BOUNTY_ETH_TARGET * PRICE_COIN_UNIT * bountyMultiplier) / mp);`; `:846` `ICoinflip(ContractAddresses.COINFLIP).creditFlip(msg.sender, bountyEarned);` (comment `:840` "ONE gas-pegged creditFlip per tx (never per-item)") | **MATCH** (RD-4: the `creditFlip` `:846` is pulled OUT into `doWork`; under D-07 `bountyMultiplier` is gone for the buy leg → flat `1.5×`; the leg returns its raw buy-count to `doWork`) |
| A13 | `_currentDay()` (claim `:887`) | `:886` `function _currentDay() internal view returns (uint32) {` → `uint32((block.timestamp - 82620) / 1 days)` | **SHIFTED(-1)** (`:887 → :886`; content present, immaterial drift) |
| A14 | KEEP-04 affiliate passthrough: the keeper buy fires `IGame.batchPurchase` with NO affiliate arg; the `bytes32("DGNRS")` code is wired GAME-side (claim `DegenerusGame.sol:1778`) — **survives the `_autoBuy` refactor (ROUTER-05)** | AfKing keeper buy `:821` `IGame(ContractAddresses.GAME).batchPurchase{value: totalValue}(players, amounts, modes);` (interface decl `:26` carries `(address[],uint256[],uint8[])` — NO affiliate param). The code is hard-wired in the game's self-call wrapper: `DegenerusGame.sol:1781` `_purchaseFor(player, 0, msg.value, bytes32("DGNRS"), payKind);` (inside `_batchPurchaseUnit` `:1773`, onlySelf `:1777`, reached from `batchPurchase`'s per-player `this._batchPurchaseUnit{value: slice}` `:1749`) | **MATCH** + **WIRING-SITE drift** (the `bytes32("DGNRS")` code is at `DegenerusGame.sol:1781`, NOT `:1778` — **SHIFTED(+3)**, the v48 KEEP-04 wiring already landed at baseline). **ROUTER-05 SURVIVES:** the affiliate code is GAME-side in `_batchPurchaseUnit`, independent of AfKing's `autoBuy → _autoBuy` refactor; the keeper call site `:821` carries no affiliate arg and is untouched by RD-4 except for the bounty pull-out. Two-tier 75/20/5 (primary SDGNRS / secondary VAULT) preserved) |

**Section A verdict:** 14 anchors — **12 MATCH / 2 SHIFTED (A13 `-1`, A14 wiring-site `+3`) / 0
ABSENT.** Every held-tree drift recorded (`:186→:171`, `:954→:785`, `:443→:401`, `:717→:568`,
`:838→:676`, `:854/:888→:691/:722`, `:992-993→:829`, `:1778→:1781`). RD-2 (drop the autoBuy `:568`
guard) and D-07 (the autoBuy `:823-838` stall ladder + `:829` epoch dead) located; KEEP-04 affiliate
passthrough survives the `_autoBuy` refactor (ROUTER-05).

---

## B. RD-2 game-side guard + Q5 dependent grep + ROUTER-07 / D-01a per-leg + single-`creditFlip` no-untrusted-ETH-send

### B.1 — RD-2 game-side `batchPurchase` guards

`git show 0cc5d10f:contracts/DegenerusGame.sol | grep -n`.

| # | Anchor (held-tree / redesign-doc claim) | ACTUAL @ 0cc5d10f | Verdict |
|---|---|---|---|
| B1 | `batchPurchase(...)` definition (claim `:1731`) | `:1731` `function batchPurchase(` … `:1735) external payable {`; AF_KING-only gate `:1736` `if (msg.sender != ContractAddresses.AF_KING) revert E();` | **MATCH** |
| B2 | rngLock pre-check — **RD-2 REMOVE** (claim `:1737`; held-tree `:1693`) | `:1737` `if (rngLockedFlag) revert RngLocked();` | **MATCH** (held/doc drift `:1693 → :1737`; **RD-2: REMOVE** — removing only the AfKing `:568` guard would just revert deeper here) |
| B3 | gameOver pre-check — **RD-2 KEEP** (claim `:1738`; held-tree `:1694`) | `:1738` `if (gameOver) revert E();` | **MATCH** (held drift `:1694 → :1738`; **KEEP** — terminal state, unrelated to the freeze) |

### B.2 — Q5 dependent grep (PERFORMED): does removing the `:1737` game-side rngLock pre-check affect any caller besides the keeper?

`batchPurchase` is **defined ONCE** in the codebase (`DegenerusGame.sol:1731`) and is **gated
AF_KING-only** at `:1736` (`if (msg.sender != ContractAddresses.AF_KING) revert E();`). Grep across
every `contracts/**/*.sol` at `0cc5d10f` for an external `.batchPurchase{`-form invocation:

| Caller (file:line @ 0cc5d10f) | Form |
|---|---|
| `contracts/AfKing.sol:821` | `IGame(ContractAddresses.GAME).batchPurchase{value: totalValue}(players, amounts, modes);` — **the keeper, the ONLY external caller** |
| (no other file) | NOT declared in either interface (`IDegenerusGame.sol` / `IDegenerusGameModules.sol` have no `batchPurchase` row) — no other contract holds a typed `batchPurchase` handle |

The only other `batchPurchase` mentions are the definition site, the `_batchPurchaseUnit` self-call
(`:1749`, internal), and comments. **Q5 VERDICT: NO other dependent.** Because `batchPurchase` is
AF_KING-gated (`:1736`) and the sole external caller is `AfKing.sol:821` (the keeper), removing the
`:1737` rngLock pre-check affects **only the keeper path**. There is no non-keeper `batchPurchase`
caller that silently loses freeze protection. Normal-player mint flows through a DIFFERENT,
unrelated entrypoint (`_purchaseFor` reached via the public mint path, NOT `batchPurchase`), so it is
unaffected. RD-2 is safe to land on this surface (T-329-03 mitigated).

### B.3 — ROUTER-07 / D-01a: per-leg + single unified `creditFlip` no-untrusted-ETH-send

`doWork` (parameterless, on `AfKing.sol`) sequences exactly one category per call (autoBuy → advance
→ autoOpen, RD-1) and, after the one-category early-return, fires **exactly ONE** `creditFlip` (RD-4
unification). Each row is grep-shown to (a) route player value through the `claimableWinnings` pull
ledger and (b) send ETH only to a pinned `ContractAddresses.*` contract — never a push to
`msg.sender` / an untrusted address.

| Leg / site | ETH-send target + player-value path @ 0cc5d10f | No untrusted push? |
|---|---|---|
| **autoBuy leg** (`_autoBuy`) | The only value transfer is `AfKing.sol:821` `IGame(ContractAddresses.GAME).batchPurchase{value: totalValue}(...)` — to the **pinned `ContractAddresses.GAME`**. Player value source is the subscriber's own `_poolOf[src]` (the funding waterfall) and `claimableWinningsOf(player)` (`:691/:722`, the pull ledger). No `.call`/`.transfer`/`.send` to a player address in the buy path. | **YES** (pinned GAME only) |
| **advance leg** (`advanceGame`) | Delegatecalls the pinned `GAME_ADVANCE_MODULE` from the `DegenerusGame.advanceGame` wrapper (`:275`); the module's rewards are `creditFlip` ledger credits (the 3 sites `AdvanceModule:189/225/468`), NOT ETH pushes. No ETH leaves to an untrusted address in the advance leg. | **YES** (no untrusted ETH send; ledger only) |
| **autoOpen leg** (`autoOpen`) | Opens via the pinned `GAME` self-path (`_autoOpenBox → _openLootBoxFor`); lootbox winnings accrue to `claimableWinnings` (pull ledger — players withdraw later), never pushed in-loop. The redesign removes the in-callee `creditFlip` (`DegenerusGame:1676`) entirely (RD-4 pull-out). | **YES** (pull ledger; no untrusted push) |
| **the SINGLE unified `doWork` `creditFlip`** (RD-4) | One `ICoinflip(ContractAddresses.COINFLIP).creditFlip(msg.sender, bountyEarned)` — to the **pinned `ContractAddresses.COINFLIP`**; the payee is the keeper-caller and the payment is minted FLIP CREDIT (a ledger entry on a pinned trusted contract), never liquid BURNIE / an ETH push. Fired LAST, after the one-category early-return (CEI). | **YES** (pinned COINFLIP; flip-credit ledger) |
| **keeper-never-a-payee** | The AfKing CEI invariant `:100-101` states it verbatim ("the keeper is never a payee in any contract it calls"); the bounty is paid to `msg.sender` as flip-credit on COINFLIP, not as an ETH transfer the keeper-contract receives. | n/a (the no-guard premise) |

**Formal no-guard basis (recorded verbatim):** *keeper-never-a-payee + no untrusted ETH send +
one-category structural early-return + single-`creditFlip`-last CEI ordering* (AfKing CEI `:100`).
Under RD-4 there is exactly ONE `creditFlip` in `doWork`, CEI-last, fed by legs that return raw
counts/mult and never self-credit — nothing to re-enter through, so **NO `nonReentrant` guard on
`doWork`** (D-01, re-grounded; the unified model makes the case STRONGER). **No leg pushes ETH to an
untrusted address → no ROUTER-07 BLOCKER.** D-01b's `router→game→creditFlip` double-pay regression
(TST-02) stays and is now near-trivial: legs structurally cannot credit; only `doWork` credits once
after the early-return.

**Section B verdict:** 3 game-side guard anchors **MATCH**; the Q5 dependent grep PERFORMED → **NO
other `batchPurchase` dependent** (AF_KING-gated, sole caller `AfKing.sol:821`); the per-leg +
single-`creditFlip` no-untrusted-ETH-send attestation holds for all 4 rows → **ROUTER-07 no-guard
basis HOLDS, 0 blockers.**

---

## C. D-07 deletion surface + GAS-03 + GASOPT-03/04/05 baselines + GASOPT-01

### C.1 — D-07 dead-surface + GAS-03 satisfied-by-deletion

| # | Dead surface @ 0cc5d10f | Disposition |
|---|---|---|
| C1 | AfKing autoBuy stall ladder + absolute-day epoch `:823-838` (epoch `:829` `today * 1 days + 82_620`; bands 2h→6× / 1h→4× / 20m→2×) | **DEAD-after-redesign (D-07).** Only advance escalates → autoBuy's stall multiplier + its absolute-day epoch are deleted. The buy leg's reward flattens to `1.5×` (no `bountyMultiplier` term). |
| C2 | DegenerusGame autoOpen gas-units bounty machinery — `AUTO_OPEN_BOX_GAS_UNITS` (claim `:1546`) + the open-leg `_ethToBurnieValue` conversion in the bounty path (claim `:1666`) | **DEAD-after-unification (D-07/RD-4).** The open leg folds onto the shared per-tx base (`× PRICE_COIN_UNIT / mp`), reward `1×` pro-rated below the open knee; the gas-units conversion is removed (the `:1546`/`:1539`/`:1545` constants + the `:1666` conversion are grepped in Section E). |

**GAS-03 VERDICT: SATISFIED BY DELETION (D-03 dissolved by D-07).** Dropping the autoBuy stall
multiplier (C1) removes AfKing's stall ladder + its absolute-day epoch. **Advance becomes the SOLE
stall epoch** (the KEPT `AdvanceModule:241-253` game-day epoch — Section D). There are no longer two
stall epochs to "collapse / single-source" → the original D-03 (keep both, single-source via
design-1) is MOOT. No dual-epoch reconciliation is needed.

### C.2 — D-08 GASOPT-03/04/05 baselines

| # | GASOPT baseline @ 0cc5d10f | Notes |
|---|---|---|
| C3 | **GASOPT-03** — batched keeper read: the two per-player `claimableWinningsOf` STATICCALLs `AfKing:691`/`:722` (held `:854`/`:888`) → ONE NEW game-side `batchPurchaseForKeeper`/`keeperSnapshot` (~2-3k/player) | **SUBSUMES GASOPT-02** (the per-iteration `claimableWinningsOf` hoist is the subset) — fold GASOPT-02 into GASOPT-03. New function + interface surface (Plan 03 / Phase 330). |
| C4 | **GASOPT-04** — drop the per-player `AutoBought` event: decl `:171` + emit `:785` (~1.5k/player); the replacement is the existing `lastAutoBoughtDay` storage stamp `:81`/`:784` | **NON-TRIVIAL test-oracle migration (must land WITH the event removal in 330).** The buy oracle `bytes32 SWEPT_SIG = keccak256("AutoBought(address,uint32,uint256)")` is keyed across **4 test files** (drained via `getRecordedLogs()`): `AfKingConcurrency.t.sol:62`, `AfKingSubscription.t.sol` (uses the `lastAutoBoughtDay` offset + the `NoSubscribersAutoBought` tail), `AfKingFundingWaterfall.t.sol:63` (the `cost`/msgValue stream), `SweepPerPlayerWorstCaseGas.t.sol:73`. **Hardest case:** the no-double-buy invariant `_countAutoBoughtFor(sub)==1` (`AfKingConcurrency.t.sol:129`, `SweepPerPlayerWorstCaseGas.t.sol:130/268`) must be re-expressed in `lastAutoBoughtDay` + pool/balance-delta terms WITHOUT weakening SAFE-03 / H-CANCEL-SWAP. Tests already read `lastAutoBoughtDay` via `_lastAutoBoughtDayOf` (the storage stamp is present). The "no off-chain/frontend consumer" condition rests on the USER's confirmation (they own the keeper). |
| C5 | **GASOPT-05** — remove the per-iteration `isOperatorApproved(player, address(this))` `:676` (held `:838`, ~2.8k/player); **KEEP** the subscribe-time `isOperatorApproved(fundingSource, subscriber)` `:401` (held/doc `:443`) | The SUB is the consent unit; revoke = `setDailyQuantity(0)` → loop tombstone-skip `:612 if (sub.dailyQuantity == 0)` (matches OPEN-E "consent-gate-at-subscribe + trust-the-sub"). **BLOCKING-CONDITION:** the 333 SWEEP must re-attest the 4 OPEN-E protections hold WITHOUT `:676` BEFORE closure; if it fails, the removal is reverted before the milestone ships. |

### C.3 — GASOPT-01 hoist sites (behavior-identical, gas-only)

| # | Anchor (held-tree / CONTEXT claim) | ACTUAL @ 0cc5d10f (`DegenerusGameMintModule.sol`) | Verdict |
|---|---|---|---|
| C6 | `processFutureTicketBatch(` repeated `ticketsOwedPacked[rk][player]` reads — `rk` loop-invariant (claim `:393`; CONTEXT held `:398`) | `:393` `function processFutureTicketBatch(`; `rk` computed once `:398` `uint24 rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl);`; reads/writes at `:431` / `:441` / `:453` / `:463` / `:498` | **MATCH** (CONTEXT held-line `:398` is the `rk` assignment; the fn is at `:393`; `rk` is invariant across the player loop → hoistable) |
| C7 | `processTicketBatch(uint24 lvl)` repeated `ticketsOwedPacked[rk][player]` — `rk` loop-invariant (claim `:670`; CONTEXT held `:671`) | `:670` `function processTicketBatch(uint24 lvl) external returns (bool finished) {`; `rk` once `:671` `uint24 rk = _tqReadKey(lvl);`; reads/writes at `:741` / `:748` / `:754` (+ `:769`/`:822`) | **MATCH** (CONTEXT held-line `:671` is the `rk` assignment; `rk` is invariant → hoistable; behavior-identical, gas-only) |

**Section C verdict:** D-07 dead surface located (C1 `AfKing:823-838`/`:829`; C2 the autoOpen
gas-units machinery — grepped in Section E); **GAS-03 = SATISFIED BY DELETION** (advance is the sole
stall epoch); GASOPT-03/04/05 baselines recorded with the GASOPT-04 4-file test-oracle list + the
no-double-buy hardest-case note + the GASOPT-05 333-SWEEP blocking-condition; GASOPT-01 hoist sites
(C6 `:393`/`:398`, C7 `:670`/`:671`) **MATCH**.

---

## D. Advance anchors + RD-4 unified-bounty 3-site pull-out + the design-1 return

`git show 0cc5d10f:contracts/modules/DegenerusGameAdvanceModule.sol` and
`git show 0cc5d10f:contracts/DegenerusGame.sol`.

### D.1 — advance anchors + the design-1 (uint8 mult, bool rewardable) return

| # | Anchor (claim) | ACTUAL @ 0cc5d10f | Verdict |
|---|---|---|---|
| D1 | `advanceGame()` module entry (claim `AdvanceModule:155`) | `:155` `function advanceGame() external {`; `:156 address caller = msg.sender;` `:158 uint32 day = _simulatedDayIndexAt(ts);` | **MATCH** (gains the design-1 `(uint8 mult, bool rewardable)` return at IMPL) |
| D2 | `ADVANCE_BOUNTY_ETH` constant (claim `AdvanceModule:147`) | `:147` `uint256 private constant ADVANCE_BOUNTY_ETH = 0.005 ether;` | **MATCH** (deleted at IMPL per ADV-01 once the bounty moves to `doWork`) |
| D3 | KEPT stall + GAME-DAY epoch block (claim `AdvanceModule:241-253`; epoch `:244-246`) | `:241 uint256 bountyMultiplier = 1;` → `:243-246` `uint256 dayStart = (uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620;`; bands `:248 2 hours → 6` / `:250 1 hours → 4` / `:252 20 minutes → 2` | **MATCH** (the GAME-DAY epoch — distinct from AfKing's absolute-day epoch `:829`; this is the SOLE surviving stall epoch after D-07, NEW-DAY path only) |
| D4 | `DegenerusGame.advanceGame` wrapper — delegatecall, returns NOTHING today, the design-1 decode site (claim `DegenerusGame:275`) | `:275 function advanceGame() external {` → `:276-282` delegatecall `GAME_ADVANCE_MODULE` via `IDegenerusGameAdvanceModule.advanceGame.selector`; `:283 if (!ok) _revertDelegate(data);` — **no `returns` clause, `data` is discarded on success** | **MATCH** (the IMPL producer edit: add `returns (uint8 mult, bool rewardable)` to both the module fn `:155` and this wrapper, and decode `data` here at `:283` instead of discarding it) |

### D.2 — RD-4 unified-bounty: ALL creditFlip sites the unified model pulls out (3 advance + autoOpen + autoBuy) + the non-advance gameover-RNG site

| # | creditFlip site @ 0cc5d10f | Firing condition (grepped) | Classification |
|---|---|---|---|
| U1 | `AdvanceModule:189` (bounty math `:191`, no `bountyMultiplier`) | inside `_handleGameOverPath`'s `goStage == STAGE_TICKETS_WORKING` branch (`:185`) — a partial-drain during the game-over ticket sequence; comment `:186-188` "pay caller the advance bounty so they retry until the queue is drained" | **REWARDABLE advance-leg** (caller-rewarded partial-drain; mult=1, no escalation) — **PULL OUT into doWork** |
| U2 | `AdvanceModule:225` (bounty math `:227`, no `bountyMultiplier`) | inside the MID-DAY path (`:202 if (day == dailyIdx)`) when `_runProcessTicketBatch` did work (`ticketWorked || !ticketsFinished` `:219`) | **REWARDABLE advance-leg (ADV-05), mult=1** (D-07: mid-day partial-drain — NO escalation; `:227` applies no multiplier) — **PULL OUT into doWork** |
| U3 | `AdvanceModule:468` (bounty math `:470` **applies `bountyMultiplier`**) | the NEW-DAY advance leg (the path that computes the stall ladder `:241-253` and scales by it `:470`) | **REWARDABLE advance-leg, mult = stall ladder (1/2/4/6)** — **PULL OUT into doWork** (the `2× × mult` advance reward of D-07) |
| U4 | `DegenerusGame.autoOpen:1676` `if (reward != 0) coinflip.creditFlip(msg.sender, reward);` | the open leg, after the loop, paying `_ethToBurnieValue(AUTO_OPEN_BOX_GAS_UNITS * AUTO_GAS_PRICE_REF, …)` per opened box (`:1665-1666`) | **REWARDABLE open-leg in-callee creditFlip** — **PULL OUT into doWork** (flat `1×` pro-rated below the knee under D-07; the gas-units conversion `:1665-1666` is deleted) |
| U5 | `AfKing:846` `ICoinflip(ContractAddresses.COINFLIP).creditFlip(msg.sender, bountyEarned);` (math `:845`) | the buy leg, after the batched `batchPurchase`, per-tx bounty | **REWARDABLE buy-leg in-callee creditFlip** — **PULL OUT into doWork** (flat `1.5×` under D-07; the `bountyMultiplier` term `:845` deleted) |
| U6 | `AdvanceModule:876` `coinflip.creditFlip(ContractAddresses.SDGNRS, (memCurrent * PRICE_COIN_UNIT) / …)` | the gameover-RNG-fallback "merge next → current" path; **payee is `ContractAddresses.SDGNRS`, NOT the keeper-caller** | **NOT-an-advance-leg-reward** — a game-economic SDGNRS credit on the gameover-RNG path; **STAYS** (not a doWork bounty; the caller is not paid) |

**RD-4 unified verdict:** after the rework there is **exactly ONE `creditFlip` site (in `doWork`)**.
The 5 pull-out sites (U1/U2/U3 advance + U4 autoOpen + U5 autoBuy) move OUT; each leg returns its raw
reward basis (advance returns `(uint8 mult, bool rewardable)`; autoOpen/autoBuy return raw counts) and
**never self-credits**. U6 (the SDGNRS gameover credit) is left in place — it is not a keeper bounty.
This single-`creditFlip`-in-`doWork` shape is the re-grounding that STRENGTHENS D-01 (the no-guard
basis): legs structurally cannot credit, so the only CEI-last credit is the one in `doWork`.

**design-1 return verdict:** `(uint8 mult, bool rewardable)` — `mult` = the stall ladder (NEW-DAY path
U3, `1/2/4/6`), `1` for the mid-day partial-drain (U2) and the gameover partial-drain (U1) per D-07
(NO mid-day escalation, confirmed by the absence of a `bountyMultiplier` term at `:191`/`:227`);
`rewardable` = the distinct bool the gameover-only-false path uses (KEEP per the redesign — harmless,
worthless coin by design). Deleting/pulling the advance creditFlip trio leaves `advanceGame`
functional + UNREWARDED standalone (ADV-01/ADV-03) — the bounty is the only thing removed; the
ticket-drain / day-advance logic is untouched.

**Section D verdict:** D1-D4 **MATCH**; the RD-4 6-site classification complete (5 pull-out + 1
non-advance SDGNRS stay-put); single-`creditFlip`-in-`doWork` + `(uint8 mult, bool rewardable)` +
mid-day-`mult=1` verdicts recorded. 0 blockers.

---

## E. RD-3/RD-5 — autoOpen rngLock-block + try/catch-drop + the entry-gate (the exactly-two-revert-sources basis)

`git show 0cc5d10f:contracts/DegenerusGame.sol` + `git show 0cc5d10f:contracts/storage/DegenerusGameStorage.sol`.

### E.1 — the current autoOpen shape (the stranded-tail hazard if try/catch drops without an entry-gate)

| # | Anchor (claim) | ACTUAL @ 0cc5d10f | Verdict |
|---|---|---|---|
| E1 | `autoOpen(uint256 maxCount)` (claim `:1636`) | `:1636 function autoOpen(uint256 maxCount) external {` | **MATCH** |
| E2 | the word-gate skip (RD-3 relevance) | `:1647 if (lootboxRngWordByIndex[index] == 0) return;` — already skips an index with no VRF word (not-ready OR orphaned by mid-day rotation), but there is **NO explicit `rngLocked()` entry-gate** today | **MATCH** (this is the per-index word-gate, NOT the rngLock block — RD-3 ADDS the rngLock-awareness so the leg no-ops during the freeze yet still opens mid-day-resolved rounds whose word has landed) |
| E3 | `++cursor` BEFORE the try/catch (claim `:1659`) | `:1656 while (cursor < qlen && opened < maxCount)` → `:1658-1660 unchecked { ++cursor; }` (the cursor advances FIRST) | **MATCH** (the stranded-tail hazard: the cursor is already advanced before the box is attempted) |
| E4 | `try this._autoOpenBox(index, player)` (claim `:1664`) | `:1664 try this._autoOpenBox(index, player) {` | **MATCH** (the external self-call whose CALL gas RD-5 recovers) |
| E5 | `catch {}` (claim `:1672`) | `:1672 } catch {}` (an empty catch — a reverting box is silently skipped with the cursor already advanced → stranded until a manual open) | **MATCH** |
| E6 | `boxCursor = uint48(cursor)` (claim `:1675`) | `:1675 boxCursor = uint48(cursor);` | **MATCH** |
| E7 | in-callee `creditFlip(msg.sender, reward)` (claim `:1676`) | `:1676 if (reward != 0) coinflip.creditFlip(msg.sender, reward);` | **MATCH** (the RD-4 pull-out site U4) |
| E8 | `_autoOpenBox(uint48 index, address player)` external onlySelf (claim `:1705`) | `:1705 function _autoOpenBox(uint48 index, address player) external {` → `:1706 if (msg.sender != address(this)) revert E();` → `:1707 _openLootBoxFor(player, index);` | **MATCH** (RD-5 makes this INTERNAL, drops the `this.`/try-catch) |
| E9 | `_openLootBoxFor(address, uint48)` (claim `:729`) | `:729 function _openLootBoxFor(address player, uint48 lootboxIndex) private {` (reaches `_queueTickets` via the lootbox-resolution delegatecall path) | **MATCH** |

### E.2 — the EXACTLY-TWO open-path revert sources (the entry-gate correctness proof)

| Source | Anchor @ 0cc5d10f | Note |
|---|---|---|
| (1) **rngLock** | game-side `DegenerusGame.sol:1737 if (rngLockedFlag) revert RngLocked();` (the batchPurchase path) + the predicate `rngLocked() :2413 return rngLockedFlag;`. For the OPEN path specifically the relevant freeze is RD-3's design intent: the open leg should no-op during the freeze. | rngLock is the first excluded source the entry-gate replicates |
| (2) **the deliberate terminal-jackpot liveness control** | `contracts/storage/DegenerusGameStorage.sol:571 if (_livenessTriggered()) revert E();` inside `_queueTickets` (`:560`), comment `:568-570` "terminal jackpot must not be manipulable by adding tickets after the VRF word that resolves it becomes known"; `_livenessTriggered() :1213`. Reached via `_autoOpenBox → _openLootBoxFor :729 → … → _queueTickets :560`. | INTENTIONAL — KEPT for DIRECT `openLootBox` callers. **Path note:** the file is `contracts/storage/DegenerusGameStorage.sol` (CONTEXT/redesign wrote the bare "DegenerusGameStorage:571"; `:571` is CORRECT, the path prefix is `storage/`) |

**Note on the third `_queueTickets` revert (`:573`):** `_queueTickets` ALSO has
`:573 if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();` — but this is the
FAR-FUTURE (`targetLevel > level + 5`, `:572`) rngLock revert. A lootbox open queues CURRENT-level
tickets (not far-future), so `:573` does not fire on the open path; and it is itself an rngLock
revert (source 1) — so the open path's revert sources remain exactly {rngLock, liveness}.

**RD-5 entry-gate verdict:** the redesign's
`autoOpen(...) { if (rngLocked() || _livenessTriggered()) return; … _autoOpenBox(index, player) /* INTERNAL */ }`
replicates BOTH excluded revert sources **pre-loop** → brick-proof (neither flips mid-tx; no half-walk
marooning since the cursor only advances inside a guaranteed-non-reverting body), and the
terminal-jackpot guard (`storage:571`) stays intact for DIRECT `openLootBox` callers. **USER-accepted
trade (recorded):** the entry-gate trusts rngLock + liveness are the ONLY open-path revert sources,
now and forever (frozen contract; the trace is high-confidence) — the try/catch was the
catch-all-unknowns version. Without the entry-gate, dropping try/catch bricks: an atomic loop
reverting at queue position K rolls back `boxCursor`..K and never advances the cursor → whole tail
frozen. **The entry-gate is MANDATORY if the try/catch goes** (T-329-04 mitigated).

### E.3 — RD-3 boxesPending() rngLock-awareness

`boxesPending()` (the open-discovery predicate `doWork` routes on) returns **false during rngLock** so
the open leg no-ops during the freeze, but STILL returns true for **mid-day-resolved rounds** whose
word has landed and we are not currently locked. The O(1) state it reads (all on DegenerusGame):
`boxPlayers[index]` (`:1562`), `boxCursor` (`:1551`), `boxCursorIndex` (`:1554`),
`lootboxRngWordByIndex[index]` (the word-gate `:1647`). Form: `boxPlayers[activeIndex].length >
boxCursor AND lootboxRngWordByIndex[activeIndex] != 0 AND !rngLocked()` — no unbounded scan
(Pitfall 5). **Verdict:** rngLock-aware, mid-day-resolved-openable, O(1) — RD-3 satisfied.

**Section E verdict:** E1-E9 **MATCH**; the exactly-two-revert-sources attested
(rngLock + `storage/DegenerusGameStorage.sol:571` liveness, `_livenessTriggered :1213`); the
entry-gate-replicates-both + brick-proof + USER-accepted-trade verdict recorded; boxesPending
rngLock-aware (RD-3) confirmed. 0 blockers.

---

## F. ADV-04 (invariant b) totalFlipReversals freeze + ROUTER-04 O(1) discovery views

`git show 0cc5d10f:contracts/modules/DegenerusGameAdvanceModule.sol`.

### F.1 — the totalFlipReversals VRF-window nudge (frozen request → consume)

| # | Anchor (claim) | ACTUAL @ 0cc5d10f | Verdict |
|---|---|---|---|
| F1 | `_applyDailyRng(` (claim `:1834`) | `:1834 function _applyDailyRng(` (the daily-RNG consumer; reached from advanceGame's normal-RNG path `:1205 currentWord = _applyDailyRng(day, currentWord);`) | **MATCH** |
| F2 | read `nudges = totalFlipReversals` (claim `:1838`) | `:1838 uint256 nudges = totalFlipReversals;` (read INTO the consumed word) | **MATCH** |
| F3 | reset `totalFlipReversals = 0` (claim `:1844`) | `:1844 totalFlipReversals = 0;` | **MATCH** |
| F4 | the additional in-window read (claim `:270`) — enumerate per `feedback_rng_window_storage_read_freshness` | `:270 cw += totalFlipReversals;` (a second read of the nudge into the consumed word `cw`, inside advanceGame's RNG-apply region) | **MATCH** (enumerated: there are TWO in-window reads of `totalFlipReversals` — `:270` and `:1838` — both into the consumed word; the reset `:1844` closes the window) |

**ADV-04 recorded fact:** the protected freeze window is **rng-request → consume**. `totalFlipReversals`
is a player-controllable nudge accumulated BEFORE the request and consumed (`:270` / `:1838`) + reset
(`:1844`) at apply time. **The REDESIGNED router introduces NO new mutable in-window SLOAD into the
advance-consume:** under RD-1 (autoBuy → advance → autoOpen) **autoBuy runs at day-open BEFORE the
advance leg requests the day's word** (rngLock is false at day-open), so autoBuy is structurally
PRE-ENTROPY — it cannot mutate any value the advance-consume reads inside the window. The advance leg
consumes via the design-1 return and recomputes nothing new; autoOpen runs AFTER and is rngLock-blocked
(RD-3) so it never executes during the freeze. **The empirical freeze proof is TST-01's job** (Q4:
autoBuy-during-rngLock safe, autoOpen-blocked-during-rngLock, no new in-window read).

### F.2 — ROUTER-04 O(1) discovery views (all O(1), no unbounded scan — Pitfall 5)

| View | Predicate form @ 0cc5d10f basis | Lives on | rngLock behavior |
|---|---|---|---|
| `advanceDue()` | `currentDayView() :462 (= _simulatedDayIndex() :463) != dailyIdx` (new-day) **OR** a mid-day partial-drain pending (`LR_MID_DAY != 0` / unprocessed read slot) | DegenerusGame | true regardless of rngLock (advance is liveness-critical) |
| `boxesPending()` | `boxPlayers[activeIndex].length > boxCursor AND lootboxRngWordByIndex[activeIndex] != 0 AND !rngLocked()` (RD-3) | DegenerusGame | **false during rngLock**; true for mid-day-resolved rounds (word landed, not locked) |
| buys-pending | AfKing-local cursor reads (`autoBuyProgress() :527` day/cursor) — active subscribers remain ahead of the keeper cursor | AfKing (local) | **TRUE even during rngLock** (RD-2: autoBuy no longer aborts on rngLock; buys queue pre-entropy) |

**Verdict:** each view is O(1) (no unbounded scan); advance/boxes views live on DegenerusGame, buys
on AfKing-local; the rngLock behaviors encode RD-2 (buys-pending true during lock) + RD-3
(boxesPending false during lock).

**Section F verdict:** F1-F4 **MATCH**; both in-window reads (`:270`, `:1838`) enumerated + the reset
(`:1844`); the request→consume window + the autoBuy-runs-pre-entropy / no-new-in-window-SLOAD verdict
recorded (TST-01 handoff); the 3 discovery views are O(1) with the RD-2/RD-3 rngLock behaviors. 0
blockers.

---

## G. Invariant (c) / D-04a — the existing structural free-fallback advanceGame() callers

`git show 0cc5d10f:contracts/modules/DegenerusGameAdvanceModule.sol` +
`git show 0cc5d10f:contracts/DegenerusVault.sol` + `git show 0cc5d10f:contracts/StakedDegenerusStonk.sol`.

| # | Free-fallback caller path | Anchor @ 0cc5d10f | Verdict |
|---|---|---|---|
| G1 | the 30-min UNCONDITIONAL universal bypass | `AdvanceModule:1012 if (elapsed >= 30 minutes) return;` (inside `_enforceDailyMintGate :989`; elapsed = `(block.timestamp - 82620) % 1 days` `:1009`; pass-holder tier at 15 min `:1014-1015`) | **MATCH** (after 30 min ANYONE can advance the daily mint gate permissionlessly) |
| G2 | `DegenerusVault.gameAdvance()` | `DegenerusVault.sol:527 function gameAdvance() external onlyVaultOwner` | **MATCH** (owner-gated wrapper fallback — read-only confirmed, NOT modified) |
| G3 | `StakedDegenerusStonk.gameAdvance()` | `StakedDegenerusStonk.sol:421 function gameAdvance() external` (permissionless) | **MATCH** (permissionless wrapper fallback — read-only confirmed, NOT modified) |
| G4 | the ~120-day death-clock (tertiary) | `AdvanceModule:109 DEPLOY_IDLE_TIMEOUT_DAYS = 365` (L0; "level 1+ uses hardcoded 120 days"); the death-clock EXTEND on stall: `:1199-1200 purchaseStartDay += gapCount;` ("gap days don't count toward the 120-day inactivity timeout") + the 120-day daysRemaining `:1898` | **MATCH** + **held-anchor drift** (CONTEXT/redesign cited "extend ~:1233/:1296"; the actual death-clock constant is `:109` and the extend-on-stall is `:1199-1200` + `:1898` — the cited `:1233/:1296` are within the gameover-RNG-fallback region but the death-clock mechanism proper is `:109`/`:1199-1200`. Death-clock present and intact, line-cited drift recorded) |

**D-04a amendment (recorded):** under autoBuy-HIGHEST-priority (RD-1), while subscriber buys pend the
router's REWARDED advance leg is BLOCKED (one-category-per-call routes to autoBuy first). Buys drain
monotonically — finite subscriber set, the AfKing cursor advances each call — so advance runs once
buys clear. Therefore **first-30-min advance during a buy backlog relies on these bypass tiers (G1
30-min permissionless + G2 Vault + G3 sStonk), NOT the router bounty**; the original D-04 claim ("the
router bounty covers the first 30 min") is AMENDED. Re-homing the bounty into `doWork` removes NO
structural caller — it only moves WHERE the payment is made. Worst-case advance waits until buys drain
or the 30-min permissionless fallback opens — a bounded delay, ACCEPTED (the death-clock tolerates it;
daily mechanics tolerate ≤30-min). **Invariant (c) holds under the new order; no single-point liveness
risk introduced.**

**Section G verdict:** G1-G3 **MATCH**; G4 death-clock present (held-cited `:1233/:1296` drift to the
actual `:109`/`:1199-1200`/`:1898` recorded — not a blocker, the mechanism is intact); the D-04a
autoBuy-first amendment recorded. 0 blockers.

---

## Roll-up

**Aggregate anchor tally across all sections:**

| Section | Anchors | MATCH | SHIFTED | ABSENT |
|---|---|---|---|---|
| A (AfKing router + RD-2 + D-07) | 14 | 12 | 2 (A13 `-1`, A14 wiring `+3`) | 0 |
| B (RD-2 game-side + Q5 + ROUTER-07) | 3 + Q5 + 5 no-send rows | 3 | 0 | 0 |
| C (D-07 deletion + GASOPT baselines) | 7 | 7 (C6/C7 MATCH; C1-C5 dead/baseline rows) | 0 | 0 |
| D (advance + RD-4 unification + design-1) | 4 + 6 creditFlip rows | 10 | 0 | 0 |
| E (RD-3/RD-5 autoOpen + revert sources) | 9 + 2 revert rows | 11 | 0 | 0 |
| F (ADV-04 freeze + discovery views) | 4 + 3 view rows | 7 | 0 | 0 |
| G (invariant-c / D-04a fallbacks) | 4 | 3 | 1 (G4 death-clock cited-line drift) | 0 |

**TOTAL IMPL-BLOCKER COUNT (across all sections): 0.** No anchor is ABSENT / materially diverged;
the only drift is immaterial line-number shifts (A13 `_currentDay` `-1`, A14 `bytes32("DGNRS")`
wiring `+3` [v48 KEEP-04 already landed], the held-tree drifts recorded per anchor, and G4's
death-clock cited `:1233/:1296` → actual `:109`/`:1199-1200`/`:1898`).

**Discretion / locked-change verdicts:**

- **Q5 (dependent batchPurchase grep): NO OTHER DEPENDENT.** `batchPurchase` is defined once
  (`DegenerusGame:1731`), AF_KING-gated (`:1736`), sole external caller `AfKing.sol:821` → removing
  the `:1737` rngLock pre-check (RD-2) affects only the keeper path.
- **ROUTER-07 (D-01a): NO-GUARD BASIS HOLDS.** Per-leg + the single unified `doWork` `creditFlip` all
  send ETH only to pinned `ContractAddresses.*` (GAME/COINFLIP) and route player value through the
  `claimableWinnings` pull ledger; keeper-never-a-payee; exactly one CEI-last `creditFlip`. NO
  `nonReentrant` guard. 0 untrusted-push legs → 0 ROUTER-07 blocker.
- **GAS-03 / D-03: SATISFIED BY DELETION.** Advance (`AdvanceModule:241-253` game-day epoch) is the
  SOLE stall epoch after D-07 drops AfKing's autoBuy stall ladder + absolute-day epoch
  (`:823-838`/`:829`). No dual-epoch to collapse.
- **ADV-04 (invariant b): NO NEW IN-WINDOW READ.** `totalFlipReversals` frozen request→consume
  (`:270`/`:1838` reads, `:1844` reset); autoBuy runs pre-entropy at day-open under RD-1 → the
  redesigned router adds no new mutable in-window SLOAD. (Empirical: TST-01.)
- **RD-5 entry-gate: REPLICATES BOTH REVERT SOURCES.** The exactly-two open-path revert sources
  (rngLock + `storage/DegenerusGameStorage.sol:571` `_livenessTriggered`) are both excluded pre-loop
  by `if (rngLocked() || _livenessTriggered()) return` → brick-proof, terminal-jackpot guard intact
  for direct opens. USER-accepted frozen-contract trade.
- **Invariant (c) / D-04a: FALLBACK CALLERS INTACT.** The 30-min bypass (`:1012`), `DegenerusVault.
  gameAdvance` (`:527`), `StakedDegenerusStonk.gameAdvance` (`:421`), and the ~120-day death-clock
  (`:109`/`:1199-1200`) all present; under autoBuy-first the rewarded advance leg is blocked while
  buys pend → these tiers cover first-30-min, NOT the bounty. No structural caller removed.
- **RD-4 unification: 6 creditFlip sites → 1 in doWork.** 5 pull-out (U1/U2/U3 advance + U4 autoOpen
  + U5 autoBuy), 1 stays (U6 SDGNRS gameover-RNG, not a keeper bounty); legs return raw counts/mult
  and never self-credit.
- **design-1 return: `(uint8 mult, bool rewardable)`** — decode at the `DegenerusGame.advanceGame`
  wrapper (`:275`/`:283`, currently discards `data`); mid-day & gameover partial-drains `mult=1`
  (no escalation), new-day `mult` = stall ladder.
- **KEEP-04 affiliate (ROUTER-05): SURVIVES.** `bytes32("DGNRS")` at `DegenerusGame:1781` (game-side
  `_batchPurchaseUnit`), independent of the AfKing `_autoBuy` refactor; two-tier 75/20/5 preserved.
- **GASOPT-01 hoist sites: MATCH.** `processFutureTicketBatch` (`:393`/`rk:398`) +
  `processTicketBatch` (`:670`/`rk:671`) — `[rk]` loop-invariant, behavior-identical gas-only.
- **GASOPT-03/04/05 baselines: ATTESTED.** GASOPT-03 batched read (`claimableWinningsOf :691/:722` →
  `keeperSnapshot`, SUBSUMES GASOPT-02); GASOPT-04 drop `AutoBought` (`:171`/`:785` → `lastAutoBoughtDay`
  `:81`/`:784`, 4-file test-oracle migration, no-double-buy `_countAutoBoughtFor==1` hardest case);
  GASOPT-05 drop per-iteration `isOperatorApproved` (`:676`), KEEP subscribe-time (`:401`),
  333-SWEEP-re-attests-4-OPEN-E-protections BLOCKING-CONDITION.

*Anchors will shift once the Phase 330 re-IMPL batched diff lands — re-grep at IMPL time. Plan 03's
reconciliation consumes: the survivors-vs-reworked edit-order map, the design-1 decode site
(`DegenerusGame:275`), the 6→1 creditFlip unification, the RD-5 entry-gate basis
(`storage/DegenerusGameStorage.sol:571`), the GASOPT-03 new-function/interface surface, and the
GASOPT-04 test-oracle migration scope.*
