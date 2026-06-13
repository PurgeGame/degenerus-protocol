# Gas round-5 — applied ledger

17 findings applied across 3 high-traffic core contracts (DegenerusGame + DegenerusVault + GNRUS)
and their module/interface counterparts. All behavior-preserving: identical state transitions,
payouts, RNG seed-derivation chains, event contents/order, and revert conditions on every reachable
path. The 5 NEEDS_HUMAN_REVIEW / PARTIAL items were adjudicated in-packet before application; three
independent reviewer passes (one per packet) returned 17/17 FAITHFUL with zero unexplained hunks.

## Headline

**DegenerusGame runtime bytecode 20,493 → 19,143 bytes (EIP-170 headroom 4,083 → 5,433).** The
biggest single-round Game reclaim since the round-1 msg.data-forwarding pass — driven by GAME-08
(payment relocation) + LOOTBOX-12 (redemption thin-stub). Both relocate code into modules that sit
~5–8 KB under the ceiling.

## By contract

**DegenerusGame.sol (+ MintModule / storage)** — GAME-08, GAME-14, GAME-15, GAME-16, RT-CLAIMS-08, LOOTBOX-12
- GAME-08: `recordMint` + `_processMintPayment` relocated into MintModule as `_recordMintPayment` +
  `_processMintPayment(..., uint256 ethForLeg)`. Every one of the 5 former `msg.value` reads
  (DirectEth min, Claimable !=0 revert, Combined >amount revert, `ethUsed`, `remaining`) became the
  explicit `ethForLeg` parameter — the sole call site passes the same `value` it used to attach to
  the value-bearing self-call, so the binding is identical and no read can bind to the outer
  purchase tx's msg.value. The self-CALL (≈6,700 net G_callvalue on fresh-ETH mints) is gone.
  `recordMint`, `_processMintPayment`, `PURCHASE_TO_FUTURE_BPS`, and the `ClaimableSpent` decl drop
  from the Game; the interface decl drops too.
- GAME-14: the two sequential `claimablePool -= ...` RMWs merged to one
  `claimablePool -= uint128(claimableUsed) + uint128(afkingUsed)` (checked uint128 form) in the
  relocated body; emits unchanged in condition/content/order.
- GAME-15: new `DegenerusGameStorage._debitClaimableAndAfking` — one SLOAD, explicit low-half guard
  (`uint128(packed) < claimableAmount`), explicit high-half guard (`(packed >> 128) < afkingAmount`,
  which exactly replaces the old afking-sufficiency check), one SSTORE. The existing four
  claimable/afking helpers are untouched (modules share them). Call sites: `_claimWinningsInternal`
  and the relocated `_processMintPayment`.
- GAME-16: `degeneretteResolve`'s pre-loop probe folded into a do-while loop-peel — the probe SLOAD
  IS iteration 0's bet read; items 1..N load at the loop bottom. Same `BatchAlreadyTaken` revert
  before any state write, same empty-array guard.
- LOOTBOX-12 (subsumes RT-CLAIMS-08): `Game.resolveRedemptionLootbox` → `delegatecall(msg.data)`
  thin stub (same shape as `creditRedemptionDirect`). The full body — SDGNRS auth → amount==0 return
  → msg.value bound → stETH pull → frozen/unfrozen pool credit → 5-ETH chunk loop with per-chunk
  `rngWord = keccak256(abi.encode(rngWord))` rehash — moved byte-faithfully into LootboxModule's
  payable external; the per-chunk resolver became a private `_resolveRedemptionChunk` called in a
  plain internal loop (no `this.`-calls). The N per-chunk delegatecalls collapse to internal calls.
  The 403afc62 payable fix predates this and carries over. Module-direct calls now revert on the
  SDGNRS gate (tighter than before).

**DegenerusVault.sol (+ DegenerusVaultShare / IVaultCoin)** — VAULT-01, VAULT-02, VAULT-04, VAULT-06, VAULT-13, VAULT-08(burnCoin)
- VAULT-01: unreachable `deposit()` + `_pullSteth` + `onlyGame` modifier + vault-scope `Unauthorized`
  deleted (zero callers; value reaches the vault via receive()/direct stETH transfers/BurnieCoin
  internal escrow). Header diagram, KEY INVARIANTS, and the Deposit event natspec rewritten to
  describe what-IS. `IVaultCoin.vaultEscrow` decl trimmed (vault was the only importer); BurnieCoin
  untouched.
- VAULT-02: write-only `coinTracked` + its constructor sync + `_syncCoinReserves` deleted; `burnCoin`
  reads the live `coinToken.vaultMintAllowance()` directly. The deleted underflow guard is dominated
  by BurnieCoin's own allowance revert in the very next call. **The vault now has zero storage
  variables** (all state is constant/immutable).
- VAULT-04: dominated `claimable != 0` conjunct dropped from the `burnEth` shortfall gate.
- VAULT-06: new `_netClaimableWinnings()` dedups the 1-wei-sentinel normalization across `burnEth`
  and `_ethReservesView`; `_ethReservesView` composed from `_syncEthReserves`.
- VAULT-08 (burnCoin leg only — burnEth leg REJECTED): `DegenerusVaultShare.vaultBurn` returns the
  pre-decrement totalSupply (selector unchanged); `burnCoin` burns first and uses the return,
  eliminating a `totalSupply()` round-trip. `burnEth` keeps its own `totalSupply()` call — the
  reorder there would move the burn ahead of the deliberate claim/solvency sequence, so it was not
  applied.
- VAULT-13: `gameDegeneretteBet`'s overpay guard deleted — the game-side `_collectBetFunds` reverts
  `InvalidBet` on overpay with the identical widening formula on every ETH path. `_combinedValue`'s
  own vault-balance check stays.

**GNRUS.sol** — TOKENS-01, TOKENS-02, TOKENS-05, TOKENS-06, TOKENS-08(b+c)
- TOKENS-01: the `levelResolved` mapping + its `pickCharity` check + write +
  `REJECT_LEVEL_ALREADY_RESOLVED` deleted. Idempotence is enforced by `currentLevel` monotonicity
  alone (its sole writer is the `level + 1` advance, strictly increasing; a resolved level can never
  match again). **−22,100 gas per level transition inside the advanceGame chain** (cold SLOAD +
  zero→nonzero SSTORE removed) — a direct worst-case-ceiling reduction. GNRUS storage layout shifts
  (hasVoted → slot 3).
- TOKENS-02: unreachable post-flush cap-checks + the entire `_futureBitmapAfter` helper +
  `CapExceeded` deleted. The 20-slot cap is structural (every bitmap bit is forced into positions
  0..19 by the `slot < 20` guard), so `popcount > 20` could never fire.
- TOKENS-05: observationally-redundant `pendingEdit` zero-writes removed (cancel branch +
  flush-loop delete). Every read is gated on the `pendingEditSet` bit, so a stale value is
  unobservable; the bit-clear remains the sole sentinel. Resolves the ceiling-vs-net trade in favor
  of the worst-case advance-chain execution bound (refunds don't lower the ceiling).
- TOKENS-06: `burn()` writes the cached `burnerBal - amount` (checked — the underflow revert is the
  over-burn guard) instead of re-SLOADing the slot; freshness proven across the intervening claim
  call (empty receive(), no GNRUS-balance writer in the window).
- TOKENS-08 (b)+(c) only — (a) omitted: the flush phase (including both packed-field writes) is
  wrapped in `if (pSet != 0)` so the common no-pending-edits level skips two RMWs and a 20-iteration
  no-op loop; both `pickCharity` loops use a running `mask <<= 1`. Sub-change (a) (winner-loop early
  break) was omitted — it would trade worst-case for typical-case gas in the advance chain.

## Test recalibrations (no logic change)

- `test/gas/KeeperLeversAndPacking.t.sol` (forge): G5 probe grep repinned to the do-while shape
  (`uint256 betPacked = degeneretteBets[...]` + `if (betPacked == 0) revert BatchAlreadyTaken();`).
- `test/repro/V62RedemptionReentrancy.t.sol` (forge): dropped the module-side
  `resolveRedemptionLootbox` no-op mock — the lootbox leg now runs fully unmocked through the
  relocated module body, so the V62-03 net covers the real end-to-end path.
- `test/access/AccessControl.test.js`: recordMint + vault deposit revert-probes rewritten to send
  the removed selectors as raw calldata (no fallback → revert) instead of calling deleted ABI
  methods.
- `test/unit/DegenerusVault.test.js`: deposit describe → funding; stETH funded via direct mint to
  the vault (the production channel); plain-ETH send exercises receive().
- `test/governance/CharityAllowlist.test.js` + `test/integration/CharityGameHooks.test.js`:
  levelResolved getter assertions removed; the duplicate-resolve test now asserts
  `PickCharityRejected(REJECT_LEVEL_NOT_ACTIVE)` (the monotonicity guard); idempotence test asserts
  the currentLevel advance.
- LOOTBOX-12 relocation repins (6 source-grep assertions across
  `test/edge/LootboxAutoResolveRegression.test.js` [03b]/[03d]/[04e],
  `test/unit/EventSurfaceUnification.test.js` [03c],
  `test/unit/LootboxAutoResolveSilentColdBust.test.js` [02b],
  `test/unit/LootboxWholeTicket.test.js` [06f]): the redemption-path `_resolveLootboxCommon`
  call moved from the `resolveRedemptionLootbox` external body into the new private
  `_resolveRedemptionChunk` helper (args byte-identical: 11 positional, index=0,
  emitLootboxEvent=false, payColdBustConsolation=false), so each pin's body extraction is
  redirected to `_resolveRedemptionChunk`. The two `LootboxAutoResolveMintBoostRegression`
  byte-identity pins ([03a] MintModule, [03b] Storage; `git show HEAD:… | cmp`) self-resolve on
  the contract commit — verified post-commit.

## Validation
- forge: 837/0/110 (the 2 round-5 forge recalibrations re-pass; the 3 chronic VRFPath reds stay
  repaired from round 4).
- JS name-set diff (full suite, working tree vs clean-HEAD baseline worktree): zero new reds after
  the 6 lootbox repins; the only pre-commit delta is the 2 self-resolving byte-identity pins.
  Baseline carries 136 pre-existing reds (settleFlipModeChange, setAutoRebuy*, RngStall VRF-timing,
  gas-benchmark drift, DegenerusStonk pool-BPS, DGNRSLiquid deployWithGameOver, etc.).
- DegenerusGame deployedBytecode 19,143 bytes (EIP-170 headroom 5,433).

## Not applied
- VAULT-08 burnEth leg — REJECTED (reorder around the claim/solvency sequence).
- TOKENS-08 sub-change (a) — omitted (worst-case-for-typical trade in the advance chain).
