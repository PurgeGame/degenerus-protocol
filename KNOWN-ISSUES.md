# Known Issues

Pre-disclosure for audit wardens. **If a finding's mechanism + impact is described below, it is
already known and is not eligible.** This is a precise perimeter — each entry names the exact
mechanism and why it is by-design, defended, or out-of-scope. There are no vague blanket disclaimers.

Frozen subject: `contracts/` tree `19272c1f` @ tag `degenerus-c4a` (post-v75.0 hardening freeze).
Pre-audited with Slither v0.11.5 + 4naly3er (triaged DOCUMENT findings in the last section), eight
isolated as-built cluster audits (Phases 468–473, 0 findings), and a Codex cross-model adversarial
re-audit (Phase 475: 5 surfaces clean/by-design/refuted, 1 MEDIUM found → fixed in `93d17288`).

---

## 1. Design decisions (architectural, not vulnerabilities)

**All rounding favors solvency.** Every BPS calculation rounds down on payouts and up on burns;
stETH transfers retain 1–2 wei per operation. The solvency invariant `balance >= claimablePool` is
strengthened by rounding, never weakened. Wei-scale dust is not a finding. (Slither `[L-13]`,`[L-14]`)

**Daily-advance assumption.** The protocol assumes `advanceGame` is driven to completion each day.
An escalating bounty (≈0.005→0.03 ETH-equiv over ~2h) plus the fact that the advance delivers jackpot
payments makes daily calling economically rational. If skipped for multiple days the next call
backfills gap days, **capped at 120 iterations** for gas safety; gap days beyond 120 are skipped
(those coinflip stakes are frozen, not lost or burned). This requires a sustained 4-month outage.

**Non-VRF entropy for the affiliate winner roll.** Deterministic seed (gas optimization). Worst case:
a player times purchases to direct affiliate credit to a different affiliate. No protocol value is
extracted. (Slither `arbitrary-send` family / event-only.)

**VRF-coordinator + price-feed swap governance.** Emergency rotation is sDGNRS-governed behind a
death-clock: a VRF-swap proposal cannot be created until VRF has stalled `ADMIN_STALL_THRESHOLD =
44 hours` (vault-owner path) / `COMMUNITY_STALL_THRESHOLD = 7 days` (0.5%-sDGNRS community path); the vote threshold decays 50%→5%
over a 168h lifetime and requires approve-weight > reject-weight. A proposal is auto-killed the
moment VRF recovers or a word is fulfilled after creation (see §3 "kill-on-recovery"). Feed swap
requires the feed unhealthy 2d (admin) / 7d (community); a down feed only suspends LINK→FLIP donation
credit (LINK donations still process). This is the intended trust model (see SECURITY.md).

**Decimator settlement temporarily over-reserves claimablePool.** During settlement the full
decimator pool is reserved in `claimablePool` before individual winner claims are credited, so
`claimablePool == Σ claimableWinnings` is momentarily replaced by `claimablePool >= Σ claimableWinnings`
(over-reserved, never under). Restored when all decimator claims credit. The as-built fold uses a
single aggregate decrement; the invariant doc is the `>=` (over-reserve) form by design.

**Lido stETH dependency.** Prize-pool growth depends on staking yield; if yield→0 the positive-sum
margin disappears but the protocol stays solvent (the solvency invariant does not depend on yield).
Negative rebases are absorbed by an 8% buffer.

---

## 2. By-design rulings (KI-01) — locked, mechanism-and-impact specific

**RTP > 100% is intended.** Several games are calibrated above break-even by design (the protocol's
positive-sum stETH yield funds it). Specifically: the Degenerette activity-ROI curve runs 90%→99.9%;
the WWXRP-currency Degenerette RTP curve runs 70%→115%→118%→120% (70% floor). A finding that "EV/RTP
exceeds 100%" or "the house can lose on a spin" is not a bug — the pins are byte-fixed and were
re-derived at v73 close. Net protocol drain still respects solvency (curse/pay-floor S≥2 bounded).

**Positive-EV lootbox and coinflip are intended.** Lootbox open EV and coinflip payout schedules are
deliberately player-favorable (same yield-funded rationale). Do not file "player can profit in
expectation from opening boxes / flipping."

**WWXRP is intentionally worthless as a token.** `WWXRP` is a pure mint/burn game-reward ERC-20 with
no backing asset and no redemption path: `mintPrize` creates unbacked WWXRP, `burnForGame` destroys
it, and `vaultMintTo` mints from a fixed uncirculating reserve. WWXRP's value is *not* any
redeemability — it is that holding it confers a near-unfarmable whale-pass position in Degenerette.
Mint-without-backing / uncollateralized supply is documented design, not a finding.

**capBucketCounts cap imprecision is by-design-fine.** The jackpot bucket-count cap can be imprecise
at the margin but **never overfills a solo bucket by more than 1** — the imprecision cannot create an
extra full payout slot. CLOSED; do not re-flag bucket-count exactness.

**Lootbox live-open-level is not manipulable.** A box's EV is frozen at *deposit* (level/boon/deity
parameters are fixed then); the permissionless auto-opener removes any open-timing edge. Waiting to
open, or steering the open day/level, changes nothing. Do not re-flag day/level/wait-to-open steering.

**Presale over-credit is WONTFIX (bounded).** PRESALE-01 can over-credit, but the amount is bounded,
presale-only, and the presale itself is 50-ETH-capped. Accepted.

**Redemption-dust lootbox drop is anti-farm, not a bug.** On sDGNRS redemption a lootbox half below
0.01 ETH is dropped into `claimable[SDGNRS]` rather than spawning a dust box. This is deliberate
anti-dust-farming; the value accrues to sDGNRS, not lost.

**Afking pass-eviction inclusive boundary is intended.** A pass is kept while
`currentLevel <= validThroughLevel` and evicted at `+1` — one level more lenient than a strict
boundary, by design. Not an off-by-one.

**claimBingo has no level guard.** `claimBingo(address, uint24 level, …)` has no level gate because
bingo traits pre-resolve to `currentLevel+5` and 8-color ownership self-gates the claim; the
`uint24 level` argument is informational. The as-built version is sender-or-approved with
player-keyed dedup (see §3 permissionless boundary). Not a missing-guard finding.

**Genesis admin self-break is a NON-finding.** An admin (or anyone) breaking their *own* game at
genesis, when `sDGNRS.votingSupply() == 0` (no engaged community yet), is not a vulnerability — there
is no victim. An admin-power finding must exhibit an **engaged-community victim**: a snapshot with
`votingSupply > 0`. Genesis-only griefs are out of scope.

---

## 3. v74 cross-model (Phase 475) dispositions — defended / by-design

### (a) The > 120-day VRF-DEATH deadman fallback (accepted super-fallback — do NOT submit)

**Mechanism.** When the game has not sealed a day for more than 120 days
(`_vrfDeadmanFired ≡ _simulatedDayIndex() − dailyIdx > 120`, `DegenerusGameStorage.sol:1534-1536`;
`dailyIdx` is uint24 and always `<= _simulatedDayIndex()` so no underflow), the terminal release no
longer waits for Chainlink. `_getHistoricalRngFallback` (`DegenerusGameAdvanceModule.sol:1444-1468`)
commits a fallback word from sealed historical `rngWordByDay` admixed with `block.prevrandao`; the
`reverseFlip` nudge is cancelled-and-consumed (`unchecked fallbackWord -= totalFlipReversals`,
`:1395`, against the `+=` in `_applyDailyRng :2023-2030`).

**Why a block proposer's 1-bit `prevrandao` grind over the terminal distribution is accepted:** this
path is reachable **only** after a catastrophic, unrecovered Chainlink VRF death — VRF itself dead
**and** the 44h-gated governance coordinator-swap having failed to land a replacement for **> 120
days**. At that point the only alternatives are (1) brick the contract forever with funds trapped, or
(2) release funds under a slightly-grindable-but-VRF-derived terminal word. The owner ruling (v68
precedent) is that fund-recovery beats a permanent brick. The deadman only removes a delay that would
otherwise have elapsed anyway; it adds no new advance-chain composition and steers nothing on a live
chain. RNG steering on a *live* Chainlink coordinator remains fully in scope — this exclusion is the
dead-coordinator terminal fallback only.

### (b) Post-gameover ticket insertion & sDGNRS-box sizing — structurally prevented (invariants)

These two vectors were examined by the cross-model pass and are *prevented by construction*, framed
here as invariants so a warden does not re-derive them as issues:

- **No queue-window / post-reveal ticket ever resolves a manipulable jackpot.** The per-sink liveness
  gate was removed from `_queueEntries` / `_queueEntriesScaled` / `_queueEntryRange` (the advance
  chain itself queues through them), but those sinks keep the far-future `rngLocked` revert
  (`DegenerusGameStorage.sol:670,714,775`) and the *purchase entry points* still revert under
  liveness/game-over (`DegenerusGameMintModule.sol:942,1102,1362,1826`). The write→read ticket-slot
  swap freezes at RNG-request time (`_swapAndFreeze`, `:437,1762-1765`), so any ticket queued during
  an open RNG window lands in the *write* slot and cannot resolve against the current word.
  Lootboxes cannot be opened after game-over. Result: no player ticket can enter the
  liveness/game-over window, and none queued during an RNG window resolves against a known word.
- **The sDGNRS level-start box is sized strictly before its word is requested.** The once-per-level
  box (`GameAfkingModule.sol:1174-1202`) reads a LIVE `cl = _claimableOf(SDGNRS)`, sizes
  `box = min(cl/20, 6 ether)` floored at `mp`, and runs inside `_runSubscriberStage`
  (`DegenerusGameAdvanceModule.sol:385`) which executes **before** `rngGate` (`:428`) — so
  `rngWordByDay[processDay]` is not even requested when `box` is fixed. The `currentLevel >
  _sdgnrsBonusLevel` latch (`:1174`) prevents re-sizing after the word becomes knowable. Inflating
  sDGNRS's own claimable before the read only enlarges sDGNRS's own self-funded box (positive-EV
  lootbox is by-design) and cannot steer an unknown word; the `cl > mp` guard keeps the 1-wei sentinel.

---

## 4. Carried items — defended / out-of-scope (NOT accepted vulnerabilities)

**Mid-day re-roll single-writer `requestId` guard — RE-CHECKED against the as-built fold.** This batch
removed `retryLootboxRng` and folded mid-day stalled-RNG recovery into the daily advance
(`MIDDAY_RNG_STALL_TIMEOUT = 4h`). Re-check result: the carried `== 0` single-writer guard still
holds. Mid-day abandon-and-promote (`DegenerusGameAdvanceModule.sol:316-329`) fires only when the
reserved bucket is empty and `rngWordCurrent == 0`; `_finalizeRngRequest`'s `isRetry` path preserves
the reserved bucket index (`lootboxRngIndex − 1`, skipping `_lrAdvanceIndexClearPending`); and a stale
mid-day `requestId` can never be honored later because `rawFulfillRandomWords` drops it via
`requestId != vrfRequestId || rngWordCurrent != 0` (`:1941`). No entropy reroll, no double-resolution.
Defended — not a finding.

**423 VRF rotation-timer governance-malice — out of scope.** A malicious sDGNRS-governance majority
abusing the coordinator-swap path is out of scope per the trust model (governance malice requires the
engaged community to vote against its own interest, and is bounded by the 44h death-clock + decaying
threshold). The rotation backstop is non-resettable on the 120/365-day horizon. See SECURITY.md role 1.

**Affiliate floor-of-sum rounding — immaterial.** The combined `payAffiliateCombined` roll uses a
floor-of-sum instead of a sum-of-floors, but the divergence is at most ~3 FLIP of quest-rounding per
transaction (a coin credit, not ETH-backed value). Immaterial; documented, not eligible.

**Genesis + dead-VRF gap-backfill state-corruption — latent, not mainnet-reachable, tracked.** Under a
*genesis-only* scenario where the very first VRF request never fulfills for multiple wall-clock days
(`dailyIdx` stuck at 0 while `day` advances — a dead-VRF-at-genesis stall), the new gap-backfill stages
(`STAGE_GAP_BACKFILLED`/`STAGE_SUBS_BACKFILL_DEFERRED`) can drive the level/`purchaseStartDay` coupling
into a corrupt state and revert Panic 0x11. It is **not reachable on mainnet**: async Chainlink VRF
fulfils the genesis request within minutes, sealing day 1 before any multi-day gap can form, so the
real-flow invariants hold (`day >= purchaseStartDay`; the 0→1 level increment precedes consolidation;
BAF only runs in the jackpot phase at `lvl >= 1`). It is exposed only by synchronous-mock-VRF /
real-15-min-day-testnet timing, and only at genesis where `votingSupply() == 0` (no victim — see §2
genesis-admin-self-break). The Sepolia exposure was fixed in the *sim repo's* VRF fulfiller (not the
contract); the proper contract-side fix (decouple the transition-commit from `_requestRng`) is
tracked-deferred, and the `lvl != 0` BAF guard was rejected (it would mask the corrupt state). forge
fuzz (async-ordered) is green; the 3 genesis-stall Hardhat guards that reproduce it under mock-VRF are
`it.skip`'d with this reason (`test/edge/BackfillIdempotency.test.js`, `test/edge/LastPurchaseDayRace.test.js`).

---

## 5. Documentation-correction notes (stale NatSpec / comments — code is correct)

The frozen tree's comments are **not** being re-touched this milestone, so these stale-NatSpec items
are disclosed rather than edited. In each, the code reverts/behaves correctly; only the `@custom:reverts`
annotation or a comment names the wrong error. **None is a vulnerability.** (Catalogued in Phase 472 §4.)

1. `DegenerusGameGameOverModule.sol:73` — annotated `@custom:reverts ZeroValue`; code reverts
   `Invariant` (rngWord==0, `:95`) / `TransferFailed` (`:263,267,272`).
2. `DegenerusGameWhaleModule.sol:182` — `MinQuantityRequired` annotated as value-mismatch; it actually
   fires on `passLevel % 100 == 0 && quantity < 2` (`:252`).
3. `DegenerusGameWhaleModule.sol:401` — names only `OnlyDelegatecall`; also reverts
   `InvalidLevelForPass` / `DeityPassConflict` / `PassNotExpired` (`:439,445,451`).
4. `DegenerusGameWhaleModule.sol:553-554` — conflates `InvalidSymbol` (`:562`) with `SymbolTaken`
   (`:563`); `GameOver` (`:561`) mislabeled as value-mismatch.
5. `DegenerusGame.sol:543` — `newThreshold == 0` reverts `ZeroValue` (`:546`), not `OnlyVault`.
6. `DegenerusGame.sol:1698` — also reverts `Insolvent` / `TransferFailed` (`:1712`), not only `OnlySDGNRS`.
7. `DegenerusGame.sol:1830/1851` — bundle conditions revert `ZeroAddress`/`ValueMismatch` (`:1837,1838`)
   and `ZeroValue`/`Insolvent`/`TransferFailed` (`:1855`), not as annotated.
8. `DegenerusGameStorage.sol:2225` — the `Sub` comment `// --- config (48 bits) ---` is stale; after
   the `reinvestPct` removal the config group is 40 bits.
9. `DegenerusAdmin.sol:748` — the `vote()` NatSpec still says "Reverts if VRF has recovered
   (stall < 20h)"; as-built it **kills** (not reverts) on recovery and the threshold is **44h**
   (post-475 fix). Code is correct; the comment is stale.

---

## 6. Observability / indexer-parity delta (not a contract finding)

**Standard buys now emit `AffiliateEarningsRecorded`, not the legacy `Affiliate(...)`.** The
purchase-path affiliate roll was folded into `payAffiliateCombined`, which emits exactly one
`AffiliateEarningsRecorded(…, combined=true)` (`DegenerusAffiliate.sol:648`) and early-returns before
any emit when `sumScaled == 0` (`:643`). Standard ticket/lootbox buys no longer emit
`Affiliate(amount, code, sender)`. An indexer deriving buy-path affiliate volume from `Affiliate(...)`
must switch to `AffiliateEarningsRecorded`. The foil-pack path still co-emits both legacy `Affiliate`
and the new event. `claimBingo` retargets `FirstQuadrantBingo`/`FirstSymbolBingo`/`BingoClaimed` to
the resolved `player` (not `msg.sender`). Observability-only; no value flow changed.

---

## 7. Automated tool findings (pre-disclosed)

The full machine-readable baseline for the frozen tree is committed in `audit/automated/` — Slither
0.11.5 (2,555 results / 101 detectors; the 130 "High" are dominated by `uninitialized-state` false
positives from the shared-storage delegatecall architecture) + Aderyn 0.6.8 (9 High / 21 Low), each
category mapped to its disposition there. The notes below are the standing per-category triage.

**Arbitrary-send-eth.** `_payoutWithStethFallback` / `_payoutWithEthFallback` / `_payEth` send ETH via
`.call{value:}` to `msg.sender` or player addresses read from game state — all access-controlled.

**events-maths.** `resolveRedemptionLootbox` decrements `claimablePool` without a dedicated event;
higher-level redemption events capture the context (the variable is a running tally, not a balance).

**Centralization `[M-2]`.** Critical admin functions (VRF/feed swap) require sDGNRS governance; the
remaining `onlyOwner` functions are operational (staking) or deity-pass metadata. Admin cannot drain
game funds — ETH flows are contract-controlled.

**Chainlink feed `[M-3]`.** LINK/ETH feed values LINK donations only; swap is governance-gated; a
stale/down feed suspends FLIP donation credit but processes the donation.

**No SafeERC20 `[M-5]/[M-6]/[L-19]`.** `.transfer()`/`.transferFrom()` with return-value checks; only
known tokens (stETH, FLIP, LINK, wXRP) that return bool per standard are touched. SafeERC20 adds
~2,600 gas/call for no benefit here.

**abi.encodePacked `[L-4]`.** 35 instances; entropy inputs are fixed-width (uint256/address) — no
collision; SVG string results are not used as keys.

**Division-by-zero `[L-7]`.** 27 instances; all divisors have implicit guards (non-zero BPS, supply
checks revert on zero, level-derived non-zero during active game).

**External-call gas `[L-9]`.** 11 `.call{value:}("")` forward all gas; recipients are player addresses
(self-grief only) or known protocol contracts with minimal `receive()`. CEI followed.

**Burn / zero-address `[L-12]`.** 67 instances; FLIP/sDGNRS/GNRUS burn mechanics are intentional;
internal paths use `msg.sender` / contract-to-contract addresses.

**Unchecked downcasting `[L-18]`.** 50 instances; each preceded by range validation or mathematically
guaranteed to fit (BPS < 10,000 → uint16, timestamps < 2^48 → uint48).

**Missing address(0) `[NC-2]`.** Coinflip `bountyOwedTo` comes from game logic (always valid player);
the DeityPass renderer setter is admin-only. Neither loses funds if zero.

**Magic numbers / event indexing / old+new values / long functions / setter validation / unchecked
arithmetic** (`[NC-6]`,`[NC-10]`,`[NC-11]`,`[NC-13]`,`[NC-16]`,`[NC-17]`,`[GAS-7]`): documented
conventions — named constants where readability matters, indexes on filter-key fields only, new-value
events for infrequent admin ops, NatSpec-bannered long game functions, governance-checked critical
setters, strategic unchecked blocks within the proven < 16.7M ceiling.

---

## 8. ERC-20 deviations

FLIP and DGNRS are ERC-20 with intentional deviations. **sDGNRS and GNRUS are soulbound (not ERC-20)
— filing ERC-20-compliance issues against them is invalid.**

**DGNRS blocks transfer to its own contract address.** `_transfer` reverts `Unauthorized()` when
`to == address(this)` — DGNRS held by the contract is indistinguishable from the sDGNRS-backed
reserve. Prevents accidental lockup. EIP-20 does not restrict recipients; intentional.

**The game bypasses FLIP `transferFrom` allowance.** `DegenerusGame` (a compile-time immutable
constant) can `transferFrom` without prior approval — the trusted-contract pattern enabling
no-pre-approval gameplay. All other callers require standard allowance.

**FLIP transfer/transferFrom may auto-claim pending coinflip winnings.** Before a transfer with
insufficient balance, the sender's pending coinflip FLIP is auto-claimed from the trusted (immutable)
Coinflip contract, minting before the transfer. Non-standard but intentional UX; the Coinflip contract
is immutable and trusted.

**FLIP sent to VAULT is burned, not transferred.** `_transfer` special-cases `to == VAULT`: tokens are
burned (totalSupply reduced) and added to the vault's virtual mint allowance (`balanceOf[VAULT]` is
always 0; the reserve lives in `_supply.vaultAllowance`). Emits `Transfer(from, address(0))`.
Intentional virtual-reserve architecture.
