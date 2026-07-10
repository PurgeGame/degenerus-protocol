# Known Issues

Pre-disclosure for audit wardens. **If a finding's mechanism + impact is described below, it is
already known and is not eligible.** This is a precise perimeter — each entry names the exact
mechanism and why it is by-design, defended, or out-of-scope. There are no vague blanket disclaimers.

Frozen subject: `contracts/` tree `d5e9f58a` @ tag `degenerus-c4a`. Pre-scanned with Slither v0.11.5
+ Aderyn 0.6.8; those findings are triaged in the automated-tools section below.

---

## 1. Design decisions (architectural, not vulnerabilities)

**Daily-advance assumption.** The protocol assumes the daily crank `mintFlip` — which drives
`advanceGame` to completion and pays the keeper bounty — is called each day. An escalating bounty
(≈0.005→0.03 ETH-equiv over ~2h) plus the fact that the advance delivers jackpot payments makes daily
calling economically rational. If skipped for multiple days the next call backfills gap days, **capped
at 120 iterations** for gas safety; gap days beyond 120 are skipped. A coinflip stake placed on a
skipped day never resolves — `_unlockRng` advances `dailyIdx` straight to the current day, so
`processCoinflipPayouts` is never called for that day and the stake stays permanently unclaimable. The
staked FLIP was already burned at deposit (as every coinflip stake is), so the loss is confined to the
affected bettor and never touches stETH solvency. Reaching >120 skipped days requires >120 consecutive
days with nobody calling `mintFlip` at all — a total abandonment under which FLIP is already valueless.

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

**Lido stETH dependency.** Protocol revenue depends on staking yield, not the prize pool: yield surplus
above all pool obligations is split four ways (vault / sDGNRS / charity / buffer). The prize pool itself
is player buy-ins, and game RTP is player-relative — neither is yield-funded. If yield→0 that revenue
disappears but the protocol stays solvent (the solvency invariant `balance >= claimablePool` does not
depend on yield). Negative rebases are absorbed by an 8% buffer.

---

## 2. Accepted issues & scope boundaries

**Presale over-credit is WONTFIX (bounded).** PRESALE-01 can over-credit, but the amount is bounded,
presale-only, and the presale itself is 50-ETH-capped. Accepted.

**Genesis admin self-break is a NON-finding.** An admin (or anyone) breaking their *own* game at
genesis, when `sDGNRS.votingSupply() == 0` (no engaged community yet), is not a vulnerability — there
is no victim. An admin-power finding must exhibit an **engaged-community victim**: a snapshot with
`votingSupply > 0`. Genesis-only griefs are out of scope.

---

## 3. Accepted out-of-scope risk: the > 120-day VRF-death deadman fallback (do NOT submit)

**Mechanism.** When the game has not sealed a day for more than 120 days
(`_vrfDeadmanFired ≡ _simulatedDayIndex() − dailyIdx > 120`, `DegenerusGameStorage.sol:1534-1536`;
`dailyIdx` is uint24 and always `<= _simulatedDayIndex()` so no underflow), the terminal release no
longer waits for Chainlink. `_getHistoricalRngFallback` (`DegenerusGameAdvanceModule.sol:1444-1468`)
commits a fallback word from sealed historical `rngWordByDay` admixed with `block.prevrandao`; the
`reverseFlip` nudge is cancelled-and-consumed (`unchecked fallbackWord -= totalFlipReversals`,
`:1395`, against the `+=` in `_applyDailyRng :2023-2030`).

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

The full machine-readable baseline for the frozen tree is committed in `audit/automated/` — Slither
0.11.5 (2,830 results / 101 detectors; the 130 "High" are dominated by `uninitialized-state` false
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
