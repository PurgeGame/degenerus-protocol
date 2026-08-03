# Known Issues

Pre-disclosure for audit wardens. **If a finding's mechanism + impact is described below, it is
already known and is not eligible.** This is a precise perimeter — each entry names the exact
mechanism and why it is by-design, defended, or out-of-scope. There are no vague blanket disclaimers.

Frozen subject: `contracts/` tree `7d9d31c5` @ tag `degenerus-c4a`. Pre-scanned with Slither v0.11.5
+ Aderyn 0.6.8; those findings are triaged in the automated-tools section below.

---

## 1. Design decisions (architectural, not vulnerabilities)

**Daily-advance assumption.** The protocol assumes the daily crank `mineFlip` — which drives
`advanceGame` to completion and pays the keeper bounty — is called each day. An escalating bounty
(≈0.005→0.03 ETH-equiv over ~2h) plus the fact that the advance delivers jackpot payments makes daily
calling economically rational. If skipped for multiple days the next call backfills gap days, **capped
at 120 iterations** for gas safety; gap days beyond 120 are skipped. A coinflip stake placed on a
skipped day never resolves — `_unlockRng` advances `dailyIdx` straight to the current day, so
`processCoinflipPayouts` is never called for that day and the stake stays permanently unclaimable. The
staked FLIP was already burned at deposit (as every coinflip stake is), so the loss is confined to the
affected bettor and never touches stETH solvency. Reaching >120 skipped days requires >120 consecutive
days with nobody calling `mineFlip` at all — a total abandonment under which FLIP is already valueless.

**Non-VRF entropy for the affiliate winner roll.** Deterministic seed (gas optimization). Worst case:
a player times purchases to direct affiliate credit to a different affiliate. No protocol value is
extracted. (Slither `arbitrary-send` family / event-only.)

**VRF-coordinator + price-feed swap governance.** Emergency rotation is sDGNRS-governed behind a
death-clock: a VRF-swap proposal cannot be created until VRF has stalled `ADMIN_STALL_THRESHOLD =
44 hours` (vault-owner path) / `COMMUNITY_STALL_THRESHOLD = 7 days` (0.5%-sDGNRS community path); the vote threshold decays 50%→5%
over a 168h lifetime and requires approve-weight > reject-weight. A proposal is auto-killed the
moment VRF recovers or a word is fulfilled after creation (see SECURITY.md role 1, "kill-on-recovery"). Feed swap
requires the feed unhealthy 2d (admin) / 7d (community); a down feed only suspends LINK→FLIP donation
credit (LINK donations still process). This is the intended trust model (see SECURITY.md).

**Growth-parimutuel scoring is claim-time-derived, and betting ignores the RNG lock.**
`DegenerusParimutuel` stores no settlement result: every claim re-derives its round's outcome
from three write-once ratchet entries — century levels are served from the append-only
achieved-pool history (`centuryPrizePools`), so the `_endPhase` restart-base overwrite of
`levelPrizePool[x00]` never distorts a settled round — with `ratchet(round+1) == 0` as the
unsettled predicate. Betting stays open through the daily RNG window by design: the market
consumes no randomness and no write a bet performs reaches VRF-consumed state (the quest credit
books to calendar-day+1; the one lock-sensitive path — topping a stake up from unclaimed
coinflip winnings — stays gated inside FLIP, so a mid-window bet must be wallet-funded). An
exact growth tie resolves UNDER (OVER must clear the line strictly). One fixed 1,000-FLIP bet
per address per round; backing both sides is EV-0 in a pooled book, not an exploit. Positions
unclaimed at game over tombstone with FLIP itself — there is no unwind path, by design.

**Lido stETH dependency.** Protocol revenue depends on staking yield, not the prize pool: yield surplus
above all pool obligations is split four ways (vault / sDGNRS / charity / buffer). The prize pool itself
is player buy-ins, and game RTP is player-relative — neither is yield-funded. If yield→0 that revenue
disappears but the protocol stays solvent (the solvency invariant `balance >= claimablePool` does not
depend on yield). Negative rebases are absorbed by an 8% buffer.

---

## 2. Accepted issues & scope boundaries

**Presale over-credit is WONTFIX (bounded).** PRESALE-01 can over-credit, but the amount is bounded,
presale-only, and the presale itself is 50-ETH-capped. Accepted.

**Degenerette recirc EV-cap allocation is resolve-order-dependent — accepted.** Degenerette ETH-spin
recirculated boxes draw the per-account per-level 10 ETH lootbox EV cap at resolve time
(`resolveLootboxDirect` → `_applyEvMultiplierWithCap`), and `resolveDegeneretteBets` is permissionless
with caller-selected `betIds` order. A player holding multiple unresolved wins whose bet-time-frozen
activity scores differ can therefore choose (by ordering, by deferring resolution across a level
boundary, or by leaving low-multiplier outcomes unresolved) which frozen multiplier (90–145%) consumes
the cap — worst-case ≈ 10 ETH × (145% − 100%) ≈ 4.5 ETH of reward basis. Accepted because the cap's
bound holds under **every** ordering: the bonus subsidy can never exceed 10 ETH × 45% = 4.5 ETH per
account per level, which a single max-score box reaches with no ordering game at all. No cross-player
or pool exposure beyond that budgeted subsidy; a third party choosing a pessimal order for someone
else is unprofitable grief; and selective non-resolution is self-defeating — resolution is
permissionless and keeper transactions settle outstanding bets regardless. Only re-orderings that
break the 4.5 ETH per-account-per-level bonus bound are eligible findings.

**A lone sub-`2^shift` ticket balance on a thanos level rounds to nothing — bounded, accepted.**
The drain divides an accumulated `(player, level)` entry balance by `2^shift` exactly once, over
`owed * 100 + rem` scaled units (`_snapOwedPacked`). A balance below `2^shift` scaled units therefore
truncates to zero, and the probabilistic remainder settle cannot recover it because `rem == 0` always
loses the roll. `_callTicketPurchase` fails such a purchase closed, but only below
`SNAP_CHECK_MAX_UNITS` (16 scaled units = 0.04 tickets): reading the exponent costs a cold SLOAD of a
slot no purchase otherwise touches, so every buy at or above that gate skips the check. A buy of `q`
scaled units with `16 <= q < 2^shift`, which is the buyer's whole balance at that level, is accepted
and pays full price for zero entries.

Reachable only at `shift >= 5` (a smaller exponent cannot zero 16 units) and only where
`TICKET_MIN_BUYIN_WEI` admits such a `q` — it floors a legal buy at `ceil(1e18 / priceWei)` scaled
units, so 100 units at the 0.01 ETH intro price and 5 at the 0.24 ETH century price. The loss is
bounded by the buy itself: at most `2^shift - 1` scaled units, under 0.64 tickets even at the
maximum exponent of 8, so **≈ 0.153 ETH worst case per (player, level)** at the highest ticket price.
Any player already holding entries at that level is unaffected, because the divide is applied to the
accumulated balance, not per purchase.

Accepted rather than fixed: closing it means an exponent read on every ticket purchase, for a case
that needs a shift of 5 or more — itself undeclarable until projected demand reaches 40M entries at
the target level — *and* a lone sub-`2^shift` position. Findings that break the bound above (a loss
larger than the buy, a player with an accumulated balance losing it, or truncation at `shift < 5`)
are eligible; the bounded case described here is not.

**Genesis admin self-break is a NON-finding.** An admin (or anyone) breaking their *own* game at
genesis, when `sDGNRS.votingSupply() == 0` (no engaged community yet), is not a vulnerability — there
is no victim. An admin-power finding must exhibit an **engaged-community victim**: a snapshot with
`votingSupply > 0`. Genesis-only griefs are out of scope.

---

## 3. Accepted out-of-scope risk: the > 120-day VRF-death deadman fallback (do NOT submit)

**Mechanism.** When the game has not sealed a day for more than 120 days
(`_vrfDeadmanFired ≡ _simulatedDayIndex() − dailyIdx > 120`, `DegenerusGameStorage.sol:1926-1928`;
`dailyIdx` is uint24 and always `<= _simulatedDayIndex()` so no underflow), the terminal release no
longer waits for Chainlink. `_getHistoricalRngFallback` (`DegenerusGameAdvanceModule.sol:1928-1952`)
commits a fallback word from sealed historical `rngWordByDay` admixed with `block.prevrandao`; the
`reverseFlip` nudge is cancelled-and-consumed (`unchecked fallbackWord -= totalFlipReversals`,
`:1627`, against the consumption in `_applyDailyRng :2314-2330`).

**Why a block proposer's 1-bit `prevrandao` grind over the terminal distribution is accepted:** this
path is reachable **only** after a catastrophic, unrecovered Chainlink VRF death — VRF itself dead
**and** both the 44h-gated (vault-owner) and the week-gated (community) governance coordinator-swap
paths having failed to land a replacement for **> 120 days**. At that point the only alternatives are (1) brick the contract forever with funds trapped, or
(2) release funds under a slightly-grindable-but-VRF-derived terminal word. The owner ruling is that fund-recovery beats a permanent brick. The deadman only removes a delay that would
otherwise have elapsed anyway; it adds no new advance-chain composition and steers nothing on a live
chain. RNG steering on a *live* Chainlink coordinator remains fully in scope — this exclusion is the
dead-coordinator terminal fallback only.

---

## 4. Out-of-scope & immaterial items

**423 VRF rotation-timer governance-malice — out of scope.** A malicious sDGNRS-governance majority
abusing the coordinator-swap path is out of scope per the trust model (governance malice requires the
engaged community to vote against its own interest, and is bounded by the 44h death-clock + decaying
threshold). The rotation backstop is non-resettable on the 120/365-day horizon. See SECURITY.md role 1.

**Affiliate floor-of-sum rounding — immaterial.** The combined `payAffiliateCombined` roll uses a
floor-of-sum instead of a sum-of-floors, but the divergence is at most ~3 FLIP of quest-rounding per
transaction (a coin credit, not ETH-backed value). Immaterial; documented, not eligible.

---

## 5. Automated tool findings (pre-disclosed)

The full machine-readable Slither/Aderyn baseline is maintained internally — Slither 0.11.5 (3,322
results / 101 detectors over 148 contracts at tree `7d9d31c5`; 171 High / 442 Medium / 383 Low /
2,274 Informational / 52 Optimization, and the "High" tier is dominated by 131 `uninitialized-state`
false positives from the shared-storage delegatecall architecture — the deployed-module compilation
units plus the new `DegenerusGameLens` unit, see below) + Aderyn 0.6.8 (9 High / 20 Low, unchanged).
Slither totals are sensitive to the scan environment (solc/toolchain resolution), so the absolute
count is not comparable across machines — re-runs should compare category triage, not the total.
These counts were measured directly at tree `7d9d31c5`, not carried forward from an earlier scan,
and the previously tagged tree was re-scanned in the same environment (reproducing its recorded
3,143 / 156 High exactly), so the delta below is a measured diff rather than a comparison against a
recorded figure.

The delta against the previously tagged tree (`4e616db4`) is **+179 results and +15 High**, spanning
six changes: the `extsload` observability lens, the module observability events, the foil daily
quest moving to the final-jackpot RNG request, the static boon tables, the council-review fixes, and
the seat push-mint. Keyed line-insensitively on (check, impact, subject function), every addition is
attributable:

- **The new `DegenerusGameLens` compilation unit (~160 of the additions).** The lens imports
  `DegenerusGameMintStreakUtils`, which pulls `DegenerusGameStorage` into its compilation unit, so
  the long-triaged shared-storage class fires through a second compilation path: **+13 High**
  `uninitialized-state` (the same false-positive family, 118 → 131 — the fields are written by the
  deployed modules exactly as the standing triage describes), ~130 Informational `unused-state` on
  storage fields the lens unit never touches, Informational `assembly` on its `extsload` word
  decoders, and one `missing-inheritance`. No new code defect is involved. One `unused-return`
  Medium covers the viewer deliberately discarding two data-source flags it no longer needs for
  selection.
- **The foil-quest request-side roll (+2 High, plus a few Medium/Low).** The High pair is
  `weak-prng` on the pre-existing `lvl % 10` / `lvl % 100` decimator-window arithmetic (12 → 14),
  newly flagged only because its result now flows into the `rollDailyQuest` external call; these
  are level-index gates, nothing random is drawn from them — the same benign class as
  `requestLootboxRng`'s time-of-day gate. The rest are `incorrect-equality` on the intended
  exact-day gate and mod comparisons, one `uninitialized-local` on the deliberate default-false
  `finalJackpotRequest`, and one `timestamp` taint artifact.
- **The static boon tables REMOVED findings.** Deleting the eligibility locals cleared two
  `uninitialized-local` Mediums (`deityEligible`, `deityPassCount`), and dropping the now-dead
  `_isDecimatorWindow()` helper cleared one High `uninitialized-state` on `decWindowOpen`
  (132 → 131), which downgraded to an Informational `unused-state` in that unit.
- **The seat push-mint (+10, ZERO High, nothing removed).** `_grantSeatCoin` now calls the seat
  token, so the three pass-purchase entrypoints carry an external call: **+4 Medium**
  `reentrancy-no-eth` and **+4 Low** `reentrancy-events` across `purchaseDeityPass` (×2 each, one
  per `_grantSeatCoin` leg), `purchaseLazyPass`, and `purchaseWhalePass`. The callee is
  `AFKING_SUB_TOKEN`, a protocol contract whose mint writes storage and emits `Transfer` with no
  ERC-721 receiver callback, so it cannot re-enter; each call site is also the final statement of
  its function. The remaining two are Informational on the token itself: `costly-loop` on
  `_mintSeat` (reached from the vault tranche's bounded mint loop) and `missing-inheritance`
  (it implements the ERC-721 surface without declaring an interface, as it always has).

The High tier is composition-identical to the prior tagged tree across every other check (6
`arbitrary-send-eth`, 6 `reentrancy-balance`, 5 `delegatecall-loop`, 3 `encode-packed-collision`,
3 `reentrancy-eth`, 2 `incorrect-exp`, 1 `shadowing-state`); only `uninitialized-state`
(118 → 131) and `weak-prng` (12 → 14) moved, as attributed above. The 14 `weak-prng` include the two
`DegenerusParimutuel` entries (`_openVolumeRound()` and `volumeBetCredit()`, each reading
`block.timestamp % 86400` to decide whether the day's betting window is open) — a time-of-day gate,
not a source of randomness: nothing is drawn from it, and the same benign pattern is already
triaged for `requestLootboxRng` and `_bountyEligible`.
CI re-runs both
analyzers on every push (`.github/workflows/ci.yml`); the standing per-category triage — why each is
by-design, defended, or not-applicable — is below.

**Arbitrary-send-eth.** `_payoutWithStethFallback` / `_payoutWithEthFallback` / `_payEth` send ETH via
`.call{value:}` to `msg.sender` or player addresses read from game state — all access-controlled.

**incorrect-exp (High ×2) — both false positives.** One is in `node_modules/@openzeppelin` (out of
scope). The other, `otherSlot = slot ^ 1` in `DegenerusQuests._questCompleteWithPair`, is a deliberate
XOR toggle between the two quest slots (0↔1), not a mistyped `**`.

**shadowing-state (High ×1).** `DegenerusGameMintModule.JACKPOT_LEVEL_CAP` re-declares the same
constant value as `DegenerusGameMintStreakUtils.JACKPOT_LEVEL_CAP`. Both are `constant` with identical
values, so no storage is shadowed and no read can diverge — a duplicate literal, not a state bug.

**locked-ether (Medium ×3).** The flagged contracts are `delegatecall` modules (Boon, Whale, …) plus a
test mock. A module never holds ETH: it executes in `DegenerusGame`'s context, so `payable` entrypoints
there are the *game's* payable surface and the game has the withdrawal paths.

**low-level-calls (Informational ×14) — ENS self-naming.** Fourteen constructors make one best-effort
`setName(string)` call to `ContractAddresses.ENS_REVERSE_REGISTRAR` (`address(0)` in this subject, so
unreachable here). The return value is intentionally discarded so a missing or hostile registrar can
never revert a deployment; each site carries a raw-selector justification comment. Zero authority,
constructor-only — see SECURITY.md role 5. Aderyn additionally reports the discard as a "Redundant
Statement" Low (the `ok;` no-op that silences the unused-variable warning).

**events-maths.** `resolveRedemptionLootbox` decrements `claimablePool` without a dedicated event;
higher-level redemption events capture the context (the variable is a running tally, not a balance).

**encode-packed-collision.** `AFKingSubscriptionToken._renderSvgInternal` concatenates SVG fragments
with `abi.encodePacked(string, ...)`; the bytes render a tokenURI image and are never hashed for
identity, keys, or authorization.

**erc20-interface.** `DegenerusVault`'s local `IAFKingSubscriptionToken.transferFrom` declares the
seat token's ERC-721 transfer (three args, no bool return); the detector pattern-matches the ERC-20
function name. The target is an ERC-721 — there is no ERC-20 interface to mismatch.

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

## 6. ERC-20 deviations

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

**FLIP sent to VAULT or sDGNRS is burned, not transferred.** `_transfer` special-cases both. `to ==
VAULT` de-circulates the tokens (totalSupply reduced) into the vault's virtual mint allowance
(`balanceOf[VAULT]` stays 0; the reserve lives in `_supply.vaultAllowance`). `to == SDGNRS` de-circulates
them into sDGNRS's redemption backing (`coinflip.creditSdgnrsBacking`). Both reduce totalSupply and emit
`Transfer(from, address(0))`. Intentional virtual-reserve architecture.

**FLIP *minted* to VAULT or sDGNRS never enters `totalSupply` either.** `_mint` mirrors the same two
intercepts: a mint to VAULT lands in `vaultAllowance`, and a mint to SDGNRS (e.g. a box-spin FLIP win on
sDGNRS's own self-subscription) routes straight to `coinflip.creditSdgnrsBacking` with **zero** supply
mutation — nothing was circulating, so nothing is de-circulated, and no `Transfer` event is emitted for
that leg. Consequence: neither address can ever hold a `balanceOf` FLIP balance, by construction on both
the transfer and the mint side. `totalSupply + vaultAllowance = supplyIncUncirculated` still holds.

**sDGNRS's FLIP backing is staked, not held.** `creditSdgnrsBacking` places incoming FLIP on the *next*
day's coinflip stake (day-keyed like every other deposit) rather than crediting `claimableStored`
directly. sDGNRS's redeemable FLIP backing is therefore `claimableStored` (the genesis seed reserve,
which redemption burns drain first) **plus** the rolling auto-rebuy carry, and it moves with coinflip
outcomes. This is by design: FLIP is the game's own coin, its backing role is redemption-side only, and
the 0-take-profit perpetual rebuy makes the position structurally roll rather than pay out. No ETH or
stETH solvency term depends on it.
