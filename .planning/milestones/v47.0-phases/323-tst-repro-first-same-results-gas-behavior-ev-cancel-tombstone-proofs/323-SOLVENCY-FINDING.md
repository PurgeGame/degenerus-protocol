# 323-SOLVENCY-FINDING — Post-game-over Degenerette resolution over-credits `claimablePool`

**Verdict: REAL INSOLVENCY (small, post-game-over only). Contract subject FROZEN at `fb29ed51`.**

This note records the outcome of the CATASTROPHE-OR-STALE determination on the ~8 foundry
solvency/economic invariants that fail at v47 HEAD. The investigation found **two distinct
causes** behind the failures:

1. **STALE HARNESS (the dominant cause, 4 of 5 suites + most DegeneretteBet counterexamples)** —
   the invariants' obligation set omits the freeze-window pending buffer while live and
   double-counts the dead `futurePrizePool` after game-over. Fully solvent; details in §3.
2. **REAL INSOLVENCY (DegeneretteBet only)** — `resolveDegeneretteBets` has **no game-over /
   liveness guard**, so a Degenerette ETH bet placed before game-over can be resolved AFTER
   game-over and credit `claimableWinnings` from the post-drain `futurePrizePool` residual,
   pushing `claimablePool` strictly **above** the contract ETH balance. `claimablePool` is the
   sum of directly-withdrawable `claimableWinnings`, so this is a genuine unbacked obligation.

Because (2) is a real unbacked-obligation path, per the task's hard rule **no test was fixed and
no contract was touched** — all five invariants are left failing so the finding is not masked.

---

## 1. The unbacked path (exact call sequence + the wei that becomes unbacked)

Reachable with ordinary, un-privileged user calls (no `vm.store`/`vm.deal` fabrication):

1. `purchase{value:…}` — buy tickets so the player has a valid lootbox RNG index.
2. `placeDegeneretteBet{value: B}(player, 0 /*ETH*/, …)` — places an ETH Degenerette bet. The
   `B` wei is added to `futurePrizePool` (`_collectBetFunds`,
   `DegenerusGameDegeneretteModule.sol:582-589`).
3. `advanceGame()` + VRF fulfill — commits the bet's `lootboxRngWordByIndex[index]` so the bet
   becomes resolvable.
4. Game-over fires (liveness timeout — a normal terminal path). `handleGameOverDrain`
   (`DegenerusGameGameOverModule.sol:78`) computes `available = totalFunds − claimablePool`,
   **zeroes the live prize pools** (`:145-147`), and distributes `available` to claimants via
   the terminal jackpot (`runTerminalJackpot`, `:180`). The terminal jackpot re-parks a residual
   back into `futurePrizePool` (solo-bucket whale-pass conversion,
   `DegenerusGameJackpotModule.sol:1411` `_setFuturePrizePool(_getFuturePrizePool()+whalePassCost)`),
   so after the drain `futurePrizePool` holds a small non-zero residual while
   `balance == claimablePool` (the drain put 100 % of `available` into claimable).
5. `resolveDegeneretteBets(player, [betId])` — **POST-game-over.** No `gameOver` /
   `_livenessTriggered()` guard exists on this entry (`DegenerusGame.sol:778` →
   `DegenerusGameDegeneretteModule.resolveBets` `:415`); the only gate is the
   per-index RNG-readiness check (`_resolveFullTicketBet` `:633-634`), which passes because the
   word was committed in step 3. The ETH win is capped to a fraction of `futurePrizePool`
   (`_distributePayout`, unfrozen branch, `:819-833`) and credited to `claimableWinnings` via
   the cross-bet flush `_addClaimableEth` (`resolveBets` `:430`, `_addClaimableEth` `:1182-1185`,
   which does `claimablePool += weiAmount`).

**Result:** `claimableWinnings`/`claimablePool` grows by the resolved ETH share (drawn from the
post-drain `futurePrizePool` residual, which is **not** backed by spare balance — the drain had
already committed the full balance to other claimants). `claimablePool` ends strictly greater
than `address(game).balance`.

### Reproduced numbers (fresh fuzz campaign, default seed, contracts @ `fb29ed51`)

```
GameOverDrained(available = 9.056816381454187156 ETH, claimablePool = 0)   // drain → all to claimable
post-drain:   balance = 9.056816381454187156   claimablePool = 9.0568…   futurePool = ~1% residual
resolveDegeneretteBets credits claimable by  0.016398510012289614 ETH  (== the residual paid out)
final:        balance = 9.056816381454187156   claimablePool = 9.073214891466476770
unbacked    = claimablePool − balance = 0.016398510012289614 ETH   (EXACTLY the resolve credit)
```

`balance < claimablePool` by **16 398 510 012 289 614 wei (~0.0164 ETH)** — confirmed at the
`DegeneretteBetInvariant.invariant_solvencyUnderDegenerette` assertion (game `gameOver()==true`,
so the live pools are dead and the only obligation is `claimablePool`).

`claimWinnings` (`DegenerusGame.sol:1434`) pays `claimableWinnings[player]` directly out of
balance; once `Σ claimableWinnings > balance`, the last claimant(s) cannot all withdraw — a
permanent (if small) loss.

---

## 2. Severity

**MEDIUM.** The leak is bounded per occurrence to the post-drain `futurePrizePool` residual
(empirically ≈ the 1 %-pre-seed / whale-pass-conversion remainder, ~0.016 ETH at a ~9 ETH pool,
i.e. low single-digit per-mille of the pool) and only manifests in the **terminal game-over
window** (game already ended). It is not a pre-game-over drain and cannot be farmed across many
levels. It is, however, a true `balance < claimablePool` state reachable by a normal user, so it
is not purely cosmetic.

Skeptic filter applied:
- Reachable by ordinary calls (place bet, advance, game-over, resolve) — **not** handler
  fabrication; the foundry handler used real `placeDegeneretteBet{value:}` /
  `resolveDegeneretteBets`.
- `invariant_ghostAccountingNetPositive` / `invariant_noEthCreation` (deposits ≥ claims) keep
  passing, so this is **not** unbounded ETH minting — it is a bounded terminal-window
  over-credit, hence MEDIUM not CATASTROPHIC.
- The 4-component obligation sum the invariant uses ALSO over-counts the dead post-game-over
  `futurePrizePool`; that part is a false positive (see §3). The real signal is isolated as
  `balance < claimablePool`.

---

## 3. The STALE-HARNESS part (for completeness — these are NOT findings)

The invariants compute `obligations = current + next + claimable + future (+ yield)` from the
per-component external views, and assert `balance >= obligations`. Two modelling gaps inflate
`obligations` above the contract's own canonical reservation:

- **Freeze-window pending buffer omitted.** `_swapAndFreeze`
  (`DegenerusGameStorage.sol:755-768`) moves 1 % of `futurePrizePool` into
  `prizePoolPendingPacked` (storage slot 11, `[future<<128 | next]`), which has **no external
  view**. `futurePrizePoolView()` drops by that 1 % → the harness reads a phantom "surplus" while
  frozen. The contract's own obligation calc in
  `DegenerusGameJackpotModule.distributeYieldSurplus` (`:699-711`) explicitly adds
  `pNext + pFuture`, confirming the pending buffer is a real (balance-backed) obligation the
  harness should count.
- **Dead post-game-over `futurePrizePool` double-counted.** After `handleGameOverDrain`, the live
  prize pools are no longer player liabilities (all distributable funds went to claimable; any
  `futurePrizePool` residual is whale-pass-conversion bookkeeping whose `whalePassClaims` award
  only worthless post-game tickets and whose `claimWhalePass` reverts under
  `_livenessTriggered()`, `DegenerusGameWhaleModule.sol:1019`). The only real obligation once
  `gameOver` is `claimablePool` (and the contract guarantees `balance >= claimablePool` by
  computing `available = balance − claimablePool` in the drain).

Empirically, the strict condition `balance >= claimablePool` held across 7+ fuzz seeds for the
no-resolve sequences (all of which only tripped the stale `+future` sum); it is **only** the
post-game-over `resolveDegeneretteBets` path of §1 that pushes `claimablePool` itself above
balance. The correct harness obligation set is:

```
obligations = gameOver
  ? claimablePool
  : current + next + future + claimable + yield + (pendingNext + pendingFuture)   // slot 11
```

With that set, EthSolvency / MultiLevel / WhaleSybil / VaultShareMath all pass, and DegeneretteBet
passes for every sequence EXCEPT the §1 post-game-over resolve, which correctly stays RED because
`balance < claimablePool` there is real. (These harness corrections were verified locally and then
reverted — no test changes are committed, so the §1 finding remains visible.)

---

## 4. Suggested remediation (contract-side, for a future milestone — NOT applied here)

Gate the Degenerette resolution against the terminal state, mirroring `claimWhalePass`:

- Add `if (_livenessTriggered()) revert E();` (or a `gameOver` check) at the top of
  `DegenerusGameDegeneretteModule.resolveBets` (`:415`), so pending bets cannot be resolved into
  `claimableWinnings` after the game-over drain has already committed the pool. Pending Degenerette
  ETH (held in `futurePrizePool` at bet placement) is then swept by the normal game-over drain /
  final sweep like every other pool, with no post-drain re-credit.
- Alternatively, have `handleGameOverDrain` settle/void outstanding Degenerette bets as part of the
  terminal sweep so no resolvable bet survives the drain.

Either change is a frozen-contract edit and must go through the normal v-next SPEC/approval gate.

---

## 5. Status of the failing invariants

Left **RED** at `fb29ed51` (no test or contract changes committed):
`EthSolvencyInvariant`, `DegeneretteBetInvariant`, `MultiLevelInvariant`, `WhaleSybilInvariant`,
`VaultShareMathInvariant`. Four are RED purely from the §3 stale obligation set (solvent); the
fifth (DegeneretteBet) is RED for both §3 and the genuine §1 `balance < claimablePool` path.
