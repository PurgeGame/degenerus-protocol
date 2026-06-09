# Council Completeness Review — Degenerus v62 Invariant Property Net (FUZZ-01..05)

You are an external auditor on a cross-model council. Another model (Claude) has built a durable
always-on invariant net for the Degenerus Protocol and will consume it as the regression oracle for a
series of upcoming adversarial sweeps. **Your single job: find what property is MISSING.** Do not
re-derive the properties below — assume they hold (each is a green fuzz invariant with a proven
falsifiability seam and a non-vacuity gate). Tell us the reachable action sequence that violates an
**unstated** invariant the net does not yet assert.

## Frozen audit subject

Read the EXACT frozen source tree at git commit `c4d48008` (do NOT read the working tree — it has
test-only additions). Use `git show c4d48008:contracts/<File>.sol` to read any contract. Key contracts:
`contracts/DegenerusGame.sol`, `contracts/GameAfkingModule.sol`, `contracts/JackpotModule.sol`,
`contracts/DegenerusAffiliate.sol`, `contracts/DegenerusVault.sol`, `contracts/StakedDegenerusStonk.sol`,
`contracts/DegenerusDeityPass.sol`, `contracts/BurnieCoin*.sol`, `contracts/interfaces/*`.

## The 5 properties already asserted (the net) — DO NOT re-propose these

1. **FUZZ-01 SOLVENCY** (`V61SolvencyAfpay.inv.t.sol`): the packed-balance Σ identity
   `claimablePool == Σ over all tracked addresses of (claimable low-128 half + afking high-128 half of
   balancesPacked slot 7)` holds, AND `claimablePool <= address(game).balance + stETH`, across a WIDE
   buyer action-space (afking fund/buy/cashout/smite/decurse/advance + whale-bundle + lazy pass + deity
   pass + presale-box + claim cashout). Every ETH balance is created only through real paired entrypoints.

2. **FUZZ-02 RNG-FREEZE** (`RngWindowFreeze.inv.t.sol`): no player-controllable action taken while the
   VRF window is open (rngLocked / request pending) mutates any ENUMERATED in-window-consumed slot —
   `rngWordByDay[day]`, `lootboxRngWordByIndex[index]`, the lootbox-rng packed index/word slot (36/37),
   and the non-VRF reads consumed alongside RNG (`dailyIdx` slot 0:3, lootbox cursor slot 36 low-48).
   `advanceGame` is the exempt heartbeat. Player actions fired in-window: placeDegeneretteBet, purchase,
   openBoxes.

3. **FUZZ-03 GAS-CEILING** (`AdvanceGasCeiling.sol` + `AdvanceGasCeilingFuzz.t.sol`): every single
   `advanceGame()` tx consumes <= 16,777,216 gas (EIP-7825) across fuzzed reachable worst-case pre-states
   (bucket geometry / owed sizes / level 10..4000) AND the v60 game-over→terminal-jackpot composition
   regression. Observed max ~6.6M.

4. **FUZZ-04 BOX-ENQUEUE** (`BoxEnqueue.inv.t.sol`): every persisted box (lootboxEth or presaleBoxEth
   entry with base != 0 for an active index) is present in `boxPlayers[index]` until opened — never held
   un-enqueued — across the full box-creating action-space (mint-with-lootbox, presale-box, afking-cover,
   whale/lazy/deity pass). Opened boxes (base==0) are correctly absent.

5. **FUZZ-05 POOL-CONSERVATION** (`PoolConservation.inv.t.sol`): the four pools
   (current/next/future/claimable) sum to a fully-backed total `sum <= address(game).balance + stETH`,
   AND pool-to-pool transfers (future→next, next→current, consolidation, jackpot, claim debit) conserve
   value — the total only grows by real ETH inflow and shrinks by real ETH outflow/payout; no unbacked
   credit is ever minted.

## Shared action-space the handlers drive

Pass buys (whale bundle / lazy / deity), presale-box buys, mint-with-lootbox, afking fund/cover/cashout,
deity smite + decurse, claimWinnings, claimBingo, advanceGame heartbeat, placeDegeneretteBet, openBoxes,
VRF request→fulfill→unlock. All actors are bounded EOAs in disjoint address bands; the three protocol
balance holders (VAULT, SDGNRS, GNRUS) receive jackpot quarter-shares + presale 80/20 credits.

## The question

Given these 5 properties and that action-space, against the frozen `c4d48008` source:

1. **What invariant is MISSING?** Name a protocol property that SHOULD always hold but none of FUZZ-01..05
   asserts. Be specific about the state variable(s) and the entrypoint(s) involved.
2. **What reachable action sequence violates an unstated invariant?** Give a concrete ordered sequence of
   real entrypoint calls (with actor/timing/level) that would leave the protocol in a state none of the 5
   properties would flag as broken — i.e. a blind spot.
3. Prioritise the DOMINANT threat classes for this protocol: RNG/freeze manipulability, solvency
   (claimablePool / pool backing), and gas-DoS in the advanceGame chain (16.7M = permanent game-over
   brick). Lower priority: access-control, reentrancy, MEV.

For each gap: state the **property**, the **violating sequence**, the **state var / slot**, and the
**severity**. Be concrete and reachable — speculative "could maybe" gaps without a reachable sequence are
not useful. If you believe the net is complete for a threat class, say so explicitly and why.
