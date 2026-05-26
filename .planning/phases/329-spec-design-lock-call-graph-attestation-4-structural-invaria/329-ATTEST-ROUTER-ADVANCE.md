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
