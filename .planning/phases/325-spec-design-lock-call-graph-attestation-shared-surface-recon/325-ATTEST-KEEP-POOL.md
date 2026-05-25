# 325 — Call-Graph Attestation: KEEP (item 3) + POOL (item 4)

## Scope

READ-ONLY grep-attestation of every `file:line` anchor cited in the v48.0 plan docs for
**item 3 (KEEP — keeper autoBuy/autoOpen rename + VAULT-code attribution)** and **item 4 (POOL —
AfKing pool recovery)** against the v47.0-closure baseline HEAD
`da5c9d50989707c8964a9411e68c51ca1b1a25f2`. Resolves the three pure-attestation Claude's-Discretion
items that are grep facts: **KEEP-04** (VAULT registered affiliate code), **KEEP-05** (autoOpen
existing-vs-new), **POOL-05** (`AfKing.sol` interface-signature verbatim match + otherwise-unchanged).

Plan docs attested:
- `.planning/PLAN-V48-KEEPER-RENAME-AND-VAULT-CODE.md` (item 3)
- `.planning/PLAN-V48-AFKING-POOL-RECOVERY.md` (item 4)

## Sources of truth (this attestation)

- `contracts/AfKing.sol` (889 lines) — withdraw/poolOf/depositFor/subscribe/sweep + the keeper buy
- `contracts/DegenerusGame.sol` (2748 lines) — `batchPurchase`/`_batchPurchaseUnit` (the affiliate-code
  pass site) + the in-game crank entrypoints (rename targets)
- `contracts/DegenerusVault.sol` (983 lines) — inline IAfKingSubscribe, ctor subscribe, open receive(),
  the `gameXxx onlyVaultOwner` wrapper pattern
- `contracts/StakedDegenerusStonk.sol` (965 lines) — inline IAfKingSubscribe, ctor subscribe,
  receive() onlyGame, burnAtGameOver onlyGame + balanceOf(this)==0 early-return
- `contracts/DegenerusAffiliate.sol` (read for KEEP-04 — affiliate code registration / `_setReferralCode`)
- `contracts/modules/DegenerusGameGameOverModule.sol` (the gameover-drain hook for the POOL fix)

**Attestation-method note (baseline-anchored):** The working tree's `contracts/` is byte-identical
to baseline HEAD `da5c9d50989707c8964a9411e68c51ca1b1a25f2` — `git diff --name-only da5c9d50 HEAD
-- contracts/` returns ZERO files. Every grep is against the live tree and is implicitly resolved at
the baseline. Read from `contracts/` ONLY.

## Verdict legend

- `MATCH` — anchor lands on the claimed line.
- `SHIFTED(±N)` — content present, N lines off the claimed line/range.
- `ABSENT` — content not found / materially diverged (surfaced as an IMPL blocker).

---

## A. KEEP (item 3) — anchor reconciliation

| # | Anchor (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| K1 | `AfKing.sol` `sweep` (the auto-buy work entrypoint → rename `autoBuy`) | `AfKing.sol:567` `function sweep(uint256 maxCount) external returns (uint256 bountyEarned)`; rngLocked pre-guard `:568` `if (IGame(GAME).rngLocked()) revert SweepAborted(msg.sender, 1);` | **MATCH** (the keeper auto-buy entrypoint is `sweep` at :567 — the `autoBuy` rename target) |
| K2 | the in-game mass-resolve/open crank entrypoint names (the rename targets) | `DegenerusGame.sol`: `crankBets(...)` :1587 ("Permissionlessly resolve a caller-supplied list of Degenerette bets" — the bet-resolve work → `autoResolve`); `crankBoxes(uint256 maxCount)` :1636 ("Permissionlessly open queued lootboxes" → `autoOpen`); plus self-call helpers `_crankResolveBet` :1684, `_crankOpenBox` :1705, and `enqueueBoxForCrank` :1570 | **MATCH** (the rename spans `AfKing.sweep` + `DegenerusGame.{crankBets,crankBoxes,_crankResolveBet,_crankOpenBox,enqueueBoxForCrank}` — a wide mechanical diff, exactly as the plan scopes) |
| K3 | the call site where AfKing's auto-buy passes the affiliate code into the game purchase — confirm it is currently `0` (the KEEP-03 wiring target) | AfKing's keeper buy fires `IGame(GAME).batchPurchase{value: totalValue}(players, amounts, modes)` at **AfKing.sol:821** — `batchPurchase` carries NO affiliate-code argument (interface decl `AfKing.sol:26-30`: `batchPurchase(address[], uint256[], uint8[])`). The affiliate code `bytes32(0)` is hard-coded in the game's self-call wrapper: `DegenerusGame.sol:1778` `_purchaseFor(player, 0, msg.value, bytes32(0), payKind);` (inside `_batchPurchaseUnit` :1773-1778, reached from `batchPurchase`'s per-player `try this._batchPurchaseUnit{value: slice}(...)` :1748-1752) | **MATCH** + **WIRING-SITE CORRECTION** (the affiliate code IS `0` today, as claimed — but it is `bytes32(0)` at **DegenerusGame.sol:1778**, NOT in AfKing.sol. AfKing's `batchPurchase` has no affiliate param at all. So KEEP-03's wiring target is `DegenerusGame.sol:1778` `_batchPurchaseUnit`, where `bytes32(0)` → VAULT's registered code) |
| K4 | `creditFlip` minted-bounty + `BOUNTY_ETH_TARGET` peg (KEEP-02, KEPT) | `AfKing.sol`: `uint256 public immutable BOUNTY_ETH_TARGET;` :263 (set in ctor :279); the keeper bounty is `bountyEarned = batchLen * ((BOUNTY_ETH_TARGET * PRICE_COIN_UNIT * bountyMultiplier) / mp);` :845 paid as ONE `ICoinflip(COINFLIP).creditFlip(msg.sender, bountyEarned);` :846 (minted FLIP CREDIT, never liquid BURNIE — the v46 illiquidity faucet-lock); ICoinflip.creditFlip decl :63 | **MATCH** (KEEP-02 KEPT: the minted `creditFlip` bounty + ETH-pegged `BOUNTY_ETH_TARGET` both present and unchanged by item 3) |
| K5 | **KEEP-04** — does a *registered* affiliate code with `owner == VAULT` exist (distinct from VAULT's address-derived default)? | **YES.** `DegenerusAffiliate.sol` ctor seeds `affiliateCode[AFFILIATE_CODE_DGNRS] = AffiliateCodeInfo({ owner: ContractAddresses.VAULT, kickback: 0 });` at **:247-250**, where `AFFILIATE_CODE_DGNRS = bytes32("DGNRS")` :181. The ctor also sets VAULT's own `playerReferralCode` to it: `_setReferralCode(ContractAddresses.VAULT, AFFILIATE_CODE_DGNRS);` :254. **Naming caveat:** the two custom codes are cross-named — `AFFILIATE_CODE_DGNRS`=`"DGNRS"` is owned by **VAULT** (:247-250), while `AFFILIATE_CODE_VAULT`=`"VAULT"` :180 is owned by **SDGNRS** (:243-246). A code passed as `bytes32("DGNRS")` resolves via `_resolveCodeOwner` (:712-720) to `owner == VAULT` (registered, custom, NOT address-derived). Separately, passing `AFFILIATE_CODE_VAULT`=`"VAULT"` also routes the *referrer* to VAULT via the `_setReferralCode` lock branch (:702-703) but that code's registered owner is SDGNRS. | **RESOLVED: YES** — a registered `owner==VAULT` code exists (`bytes32("DGNRS")`). **No setup step required.** KEEP-03's wiring should pass `bytes32("DGNRS")` (the VAULT-owned registered code) so revenue routes to VAULT per the foreclosure intent. (SPEC/Plan 03 should disambiguate which literal to wire given the cross-naming.) |
| K6 | KEEP-03 foreclosure semantics — `_setReferralCode` :436/:449/:463-476 (unreferred AfKing-joiner permanently captured by VAULT; mutable-default also converts; real human kept) | `DegenerusAffiliate.sol`: `_setReferralCode` body :698-708; foreclosure resolution block :408-476. A blank/invalid referral locks to VAULT (`REF_CODE_LOCKED` :421/:430, referrer→VAULT :702-703). A first valid code stores permanently :436. A player on the MUTABLE VAULT-default is converted to a passed registered code while `_vaultReferralMutable` holds (:449-460; `_vaultReferralMutable` :692-695 = code is REF_CODE_LOCKED/VAULT-default AND `game.lootboxPresaleActiveFlag()` :2244). A player who already holds a real human code: the passed code is ignored (the `!infoSet` fall-through uses the stored code :463-476) | **MATCH** (foreclosure semantics land at :436/:449/:463-476 as claimed; the mutability window is gated by `lootboxPresaleActiveFlag` — relevant to WHEN the AfKing-passed VAULT code can convert a mutable default) |

### KEEP-05 resolution — `autoOpen` existing-vs-new

**RESOLVED: EXISTING (a rename, not a new capability).** Opening subscribers'/queued lootboxes is
already a live permissionless keeper capability — `DegenerusGame.sol:1636`
`function crankBoxes(uint256 maxCount) external` ("Permissionlessly open queued lootboxes via the
parameterless cursor", CRANK-03; walks `boxPlayers[activeIndex]` from `boxCursor`, gated on
`lootboxRngWordByIndex[index] != 0`), with the self-call helper `_crankOpenBox(uint48 index, address
player)` :1705. So `autoOpen` is the rename of `crankBoxes`/`_crankOpenBox`. (Note: the box-open
work lives in `DegenerusGame`/modules, NOT in `AfKing.sol` — `AfKing.sweep` does the auto-BUY;
box-opening is a separate in-game permissionless crank. The rename spans both contracts.)

---

## B. POOL (item 4) — anchor reconciliation

| # | Anchor (claimed) | ACTUAL (contracts/AfKing.sol unless noted) | Verdict |
|---|---|---|---|
| L1 | `_poolOf` slot 0 (~:195) | `mapping(address => uint256) private _poolOf; // slot 0` at **:195** | **MATCH** |
| L2 | `withdraw(uint256)` (~:318) — debits `_poolOf[msg.sender]`, no game-state gate | `function withdraw(uint256 amount) external` at **:318**; `_poolOf[msg.sender]` debit :320-324 (CEI unchecked :323-324); no `rngLocked`/`gameOver` guard | **MATCH** (ungated egress for a normal player — confirms "not stuck" for humans) |
| L3 | `msg.sender.call{value}` send (~:327) — the sDGNRS blocker | `(bool ok, ) = msg.sender.call{value: amount}("");` at **:327**; `if (!ok) revert EthSendFailed();` :328 (`EthSendFailed` error :114) | **MATCH** (sends to the CALLER; sDGNRS-as-caller would receive via its `receive()` → the onlyGame revert is the documented blocker) |
| L4 | `depositFor(address)` (~:304) — permissionless ingress | `function depositFor(address player) external payable` at **:304**; `_poolOf[player] += msg.value;` :307; ZeroAddress guard :305; permissionless (no caller gate) | **MATCH** (the ingress vector that lands ETH in `_poolOf[VAULT]`/`_poolOf[SDGNRS]`) |
| L5 | `poolOf(address) returns (uint256)` getter | `function poolOf(address player) external view returns (uint256) { return _poolOf[player]; }` at **:503-504** | **MATCH** (the read the recovery call needs: `afKing.poolOf(address(this))`) |
| L6 | `subscribe(...)` 6-arg | `function subscribe(address player, bool drainGameCreditFirst, bool useTickets, uint8 dailyQuantity, uint8 reinvestPct, address fundingSource) external payable` :376-383 | **MATCH** |
| L7 | sweep `rngLocked`-gated (~:568) — donated ETH stranded once sweeps stop | `function sweep(uint256 maxCount)` :567; `if (IGame(GAME).rngLocked()) revert SweepAborted(msg.sender, 1);` at **:568**; the `drainGameCreditFirst` funding waterfall `if (_poolOf[src] < msgValue)` :744 + debit `_poolOf[src] -= msgValue;` :767 | **MATCH** (the only consumer of `_poolOf` ETH is the sweep waterfall; rngLocked-gated → ends with the game → donated VAULT/SDGNRS pool ETH strands) |
| L8 | sStonk inline `IAfKingSubscribe` (:57) declares ONLY `subscribe` today | `StakedDegenerusStonk.sol:57-67` `interface IAfKingSubscribe { function subscribe(address player, bool, bool, uint8, uint8, address) external payable; }` — single member | **MATCH** (declares only `subscribe`; the POOL fix ADDS `withdraw`/`poolOf` here) |
| L9 | VAULT inline `IAfKingSubscribe` (:76) declares ONLY `subscribe` today | `DegenerusVault.sol:76-86` `interface IAfKingSubscribe { function subscribe(address player, bool, bool, uint8, uint8, address) external payable; }` — single member | **MATCH** (declares only `subscribe`; the POOL fix ADDS `withdraw`/`poolOf` here) |
| L10 | sStonk `receive()` onlyGame (~:433) | `receive() external payable onlyGame { ... }` at **:433** (`onlyGame` modifier :336) | **MATCH** (the blocker: AfKing-as-caller ≠ GAME → revert; the fix relaxes to also accept `AF_KING`) |
| L11 | sStonk `burnAtGameOver()` onlyGame (~:525) + `balanceOf(this)==0` early-return (~:526-527) | `function burnAtGameOver() external onlyGame` :525; `uint256 bal = balanceOf[address(this)];` :526; `if (bal == 0) return;` :527; burns own balance :528-533 | **MATCH** (the AfKing pull must go BEFORE :527's early-return, or in a sibling onlyGame call, so a zero-pool-token sDGNRS still recovers its ETH pool — exactly the plan's ordering requirement) |
| L12 | sStonk ctor subscribe (~:384) | `afKing.subscribe(address(this), true, false, 1, 2, address(0));` at **:384** (drainGameCreditFirst=true, no `{value:}` — never seeds pool ETH) | **MATCH** |
| L13 | VAULT open `receive()` (~:497) | `DegenerusVault.sol:497` `receive() external payable { emit Deposit(msg.sender, msg.value, 0, 0); }` — accepts from any sender, no auth | **MATCH** (VAULT can receive the recovered ETH back; only lacks the `withdraw` call — `recoverAfKingPool()` follows the existing `gameXxx onlyVaultOwner` wrapper pattern, e.g. `gameOpenLootBox` :550, `gameResolveDegeneretteBets` :619) |
| L14 | VAULT ctor subscribe (~:471) | `afKing.subscribe(address(this), true, false, 1, 0, address(0));` at **:471** (drainGameCreditFirst=true, no `{value:}`) | **MATCH** |
| L15 | the gameover-drain hook the POOL recovery folds into | `DegenerusGameGameOverModule.sol:142` `dgnrs.burnAtGameOver();` (the existing onlyGame invocation at gameOver); `handleFinalSweep()` :192 (`+ 30 days` gate :194) | **MATCH** (BTOMB + POOL both hook the existing gameover-drain; POOL folds `afKing.withdraw(afKing.poolOf(this))` into `burnAtGameOver` before the :527 early-return) |

### POOL-05 resolution — `AfKing.sol` interface adds match verbatim + AfKing otherwise unchanged

**RESOLVED: VERBATIM MATCH, AfKing.sol unchanged.**
- Planned interface add `withdraw(uint256)` ⟺ `AfKing.sol:318` `function withdraw(uint256 amount)
  external` — **verbatim** (param `uint256 amount`, `external`, no return). The interface decl
  `function withdraw(uint256) external;` matches the selector.
- Planned interface add `poolOf(address) returns (uint256)` ⟺ `AfKing.sol:503` `function
  poolOf(address player) external view returns (uint256)` — **verbatim** (param `address`, `external
  view`, `returns (uint256)`). The interface decl `function poolOf(address) external view returns
  (uint256);` matches the selector.
- **`AfKing.sol` needs NO other change** for item 4: `withdraw`/`poolOf`/`depositFor`/`_poolOf`
  already exist and are sufficient; the recovery is implemented entirely in VAULT
  (`recoverAfKingPool()`) and sStonk (`receive()` relaxation + the pull folded into
  `burnAtGameOver`). (Item 3's RENAME does touch `AfKing.sol` — `sweep`→`autoBuy` — but that is a
  separate work item; item 4 alone leaves AfKing untouched.)

### sStonk `receive()` relaxation accounting-safety (POOL SPEC check)

`StakedDegenerusStonk.sol:433` `receive() external payable onlyGame` does NOT write a running
reserve counter — reserves are read live via `address(this).balance` (e.g. the submit/preview/resolve
bases at :844/:598/:758 read `address(this).balance` directly). So an `AF_KING`-sourced ETH credit
through a relaxed `receive()` is NOT mis-attributed or double-counted; it simply lands in the balance
and flows out through the deterministic burn / `handleFinalSweep` payouts. (The `receive()` body
emits no `Deposit`-with-counter — grep confirms no reserve-counter SSTORE in `receive()`.)

---

## C. Roll-up

- **KEEP (item 3) anchors:** 6 attested — **6 MATCH / 0 SHIFTED / 0 ABSENT**, with one
  **WIRING-SITE CORRECTION** (K3): the affiliate code `0` is at `DegenerusGame.sol:1778`
  (`_batchPurchaseUnit` → `_purchaseFor(..., bytes32(0), ...)`), NOT in `AfKing.sol` —
  `AfKing.batchPurchase` carries no affiliate argument. The KEEP-03 wiring target is therefore
  `DegenerusGame.sol:1778`.
- **POOL (item 4) anchors:** 15 attested — **15 MATCH / 0 SHIFTED / 0 ABSENT.**

**IMPL-blocker count for items 3+4: 0.**

**Discretion-item resolutions (explicit):**
- **KEEP-04: YES** — a registered code with `owner == VAULT` EXISTS (`bytes32("DGNRS")` =
  `AFFILIATE_CODE_DGNRS`, seeded at `DegenerusAffiliate.sol:247-254`). **No register-one setup step
  required.** Caveat for SPEC/Plan 03: the two custom codes are cross-named (`"DGNRS"`→owner VAULT;
  `"VAULT"`→owner SDGNRS) — disambiguate the literal to wire. Recommend wiring the VAULT-owned
  registered code `bytes32("DGNRS")` at `DegenerusGame.sol:1778`.
- **KEEP-05: EXISTING** — `autoOpen` is a RENAME of the live permissionless `crankBoxes`
  (`DegenerusGame.sol:1636`) / `_crankOpenBox` (:1705); not a new capability.
- **POOL-05: VERBATIM MATCH** — `withdraw(uint256)` (AfKing.sol:318) + `poolOf(address) returns
  (uint256)` (AfKing.sol:503) match the planned interface adds exactly; `AfKing.sol` needs no other
  change for item 4.

*Anchors will shift once the Phase 326 batched diff lands — re-grep at IMPL time. Plan 03's
shared-surface reconciliation consumes: the `DegenerusGame.sol:1778` affiliate-wiring site (item 3),
the renamed crank entrypoints (item 3) co-edited with the item-2 `pullRedemptionReserve` surface in
the same file, the sStonk `receive()` + `burnAtGameOver` (item 4) co-edited with the item-2
`_submitGamblingClaimFrom` in the same file, and the two inline `IAfKingSubscribe` interface adds.*
