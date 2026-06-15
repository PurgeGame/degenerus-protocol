# 392-04 — NET 2 (deep Claude adversarial net) — ENTROPY-AND-ECON / BURNIE-coinflip-rework slice

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`;
`git diff a8b702a7 -- contracts/` EMPTY before and after this task; all source read via
`git show a8b702a7:contracts/<File>.sol`, working tree ignored).
**Baseline (the audit oracle):** `test/REGRESSION-BASELINE-v63.md` — forge **854 / 0 / 110**; the
emission-conservation anchor is the green **BurnieEmissionSeeds** invariant (5/5); the carry-settle anchor
is **CoinflipCarryClaim.t.sol** (partial / cap / loss-zeroing / compounding).
**Net:** NET 2 = the deep Claude adversarial net, run INDEPENDENTLY of NET 1 (the council). Each property
was attacked against the frozen source FIRST; the council outputs (392-02 + `council/burnie.gemini.txt`;
`codex` skipped — hard usage-limit cap) are folded in at §9 ONLY, with a convergent/divergent note per item.
**Posture:** AUDIT-ONLY. Provisional verdicts only; the finalized adjudication + routing is 392-FINDINGS-
BURNIE.md (Task 2). A CONFIRMED finding is DOCUMENTED + ROUTED to a gated USER-hand-review boundary, never
fixed here. Neutral defensive-engineering vocabulary throughout.
**Design-intent anchor (AUDIT-V63-PLAN §5):** survive-before-mint is the DEFINING intent of the rework; the
stochastic backing-variance trade (the old fixed 2M reserve → an 8M-stake/~4M-EV seeded flip position) is
INTENDED variance — this net VERIFIES conservation / completeness / monotonicity / round-trip-losslessness,
it does NOT re-litigate the variance trade or BURNIE's "worthless except the whale pass" rating. BURNIE is
OFF the ETH/`claimablePool` solvency spine (BURNIE-06), so any confirmed gap is an under-credit / strand /
lost-emission class, NOT ETH insolvency. The threat weighting (§4) still rates a backing under-credit or a
lost-emission window as VALUE-BEARING (the spine concern of this phase) — the BURNIE-worthless rating bounds
the magnitude, it does NOT dismiss the class.

---

## §0. Method — the BURNIE backing/emission model attacked

The independent net builds an end-to-end accounting model of BURNIE creation and sDGNRS/VAULT backing, then
tries to break four properties: (a) CONSERVATION — no BURNIE mints without a survived flip, no
over/under-emission vs the seeded principal; (b) BACKING COMPLETENESS — every unit of BURNIE that backs an
sDGNRS redeemer is visible to `burnieOwed`; (c) LATCH MONOTONICITY — the sDGNRS perpetual-rebuy arming fires
once, never double-mints, never re-enters; (d) ROUND-TRIP LOSSLESSNESS — the packed stake/day-result lanes
survive read/write and BURNIE never reaches the ETH path. The two prime backing leads (FC-392-16 carry
strand, FC-392-17 VAULT window-aging) get a dedicated exhaustive trace (§1, §2). Every item records:
PROPERTY · attack/sequence tried · STATE VAR + `file:line` at `a8b702a7` · the settling
identity/bound/trace · a PROVISIONAL verdict.

---

## §1. BURNIE-04 / FC-392-16 — sDGNRS auto-rebuy carry stranded from redemption backing (DEDICATED EXHAUSTIVE BACKING TRACE)

**Property:** every unit of BURNIE that backs an sDGNRS redeemer is visible to `burnieOwed`.
**Attack:** drive the protocol past day 20 (sDGNRS armed onto perpetual 0-take-profit auto-rebuy), let
sDGNRS win flips so its rolling position grows into `autoRebuyCarry`, then submit a redemption and check
whether `burnieOwed` reflects the carry-resident BURNIE.

### 1a. The full backing trace (read-side, end-to-end)

```
StakedDegenerusStonk._burnFor (the submit path):
  burnieBal       = coin.balanceOf(sDGNRS)                              (StakedStonk:1029)
  claimableBurnie = coinflip.previewClaimCoinflips(sDGNRS)              (StakedStonk:1030)
  burnieOwed      = ((burnieBal + claimableBurnie) * amount) / supply   (StakedStonk:1031)
  if (burnieOwed != 0) coinflip.redeemBurnieShare(beneficiary, burnieOwed) (StakedStonk:1072-1073)

BurnieCoinflip.previewClaimCoinflips(player)                            (BurnieCoinflip:971-975):
  = _viewClaimableCoin(player) + playerState[player].claimableStored

BurnieCoinflip._viewClaimableCoin(player)                              (BurnieCoinflip:1013-1064):
  startDay = playerState[player].lastClaim
  if (startDay >= flipsClaimableDay) return 0
  ... sums per-day WIN payouts (stake + stake*reward%/100) over the window ...
  // reads coinflipStakePacked + coinflipDayResultPacked; NEVER reads autoRebuyCarry

BurnieCoinflip.redeemBurnieShare(redeemer, base)                       (BurnieCoinflip:940-967):
  held       = burnie.balanceOf(sDGNRS)
  burnFromHeld = min(base, held);  burnForCoinflip(sDGNRS, burnFromHeld)
  remainder  = base - burnFromHeld
  if (remainder != 0) consumed = _claimCoinflipsAmount(sDGNRS, remainder, false)  // consumes claimableStored only
  _addDailyFlip(redeemer, base, ...)                                   // deferred mint, offset by burn+consume
  // NEVER reads autoRebuyCarry
```

### 1b. The three settling determinations (the prompt's exhaustive trace)

**(i) NEITHER read path touches `autoRebuyCarry`, and there is NO liquidation path called by sDGNRS.**
- `previewClaimCoinflips` = `_viewClaimableCoin` + `claimableStored` (BurnieCoinflip:971-975). `_viewClaimableCoin`
  (BurnieCoinflip:1013-1064) reads only `lastClaim`, `coinflipStakePacked`, `coinflipDayResultPacked` — it
  never references `state.autoRebuyCarry`. `claimableStored` is a distinct field (BurnieCoinflip:147).
- `redeemBurnieShare`'s consume waterfall (BurnieCoinflip:940-967) covers `base` from (held balance via
  `burnForCoinflip`) then (`_claimCoinflipsAmount(sDGNRS, remainder, false)` @956). `_claimCoinflipsAmount`
  (BurnieCoinflip:367-391) draws from `claimableStored` + the `mintable` returned by `_claimCoinflipsInternal`
  — and on an ARMED player `_claimCoinflipsInternal` rolls wins into `carry` and returns `mintable == 0` for
  the rolled portion (the `rebuyActive` branch banks only the take-profit `reserved`, which is 0 under
  0-take-profit; BurnieCoinflip:496-507). So the waterfall never reaches the carry.
- LIQUIDATION PATH: the carry could be liquidated by `claimCoinflipCarry(sDGNRS,…)` (BurnieCoinflip:754) OR by
  disabling rebuy via `setCoinflipAutoRebuy(sDGNRS,false,…)` (which mints `carry`, BurnieCoinflip:709-714).
  **Grep is clean — nothing calls either for sDGNRS:** `git grep claimCoinflipCarry` finds only the definition
  + the interface decl (no caller); `setCoinflipAutoRebuy` is reachable only via `msg.sender==GAME`
  (BurnieCoinflip:662) or `DegenerusVault.coinSetAutoRebuy` (`onlyVaultOwner`, DegenerusVault:645) — neither
  targets sDGNRS, and sDGNRS holds NO code that calls either (StakedStonk has no `setCoinflipAutoRebuy` /
  `claimCoinflipCarry` reference — grep on StakedStonk = 0). So carry-resident BURNIE is invisible to the only
  consumer of sDGNRS's BURNIE backing AND has no realizable liquidation path under the deployed code.

**(ii) CONSERVATIVE — under-credit/strand only, never over-credit or insolvency.**
- `burnieOwed = ((burnieBal + claimableBurnie) * amount)/supply`. Excluding the carry makes `claimableBurnie`
  SMALLER, so `burnieOwed` is SMALLER. The waterfall (BurnieCoinflip:940-967) only ever destroys ≤ `base` of
  sDGNRS's OWN backing (held first, then `claimableStored`), and `base = burnieOwed <= burnieBal + claimableBurnie`
  by construction, so the waterfall never reverts and never over-consumes. There is no over-credit and no path
  by which the redeemer receives more than sDGNRS's accounted backing. The defect class is strictly
  UNDER-CREDIT / STRAND of value that DOES belong to redeemers proportionally — value-bearing, but bounded off
  the ETH spine (BURNIE-06).

**(iii) STEADY STATE — `_viewClaimableCoin(sDGNRS)` returns 0 between resolutions.**
- After arming (epoch≥20), `processCoinflipPayouts` calls `_claimCoinflipsInternal(sDGNRS,false)` EVERY
  resolved day (BurnieCoinflip:877-878), which advances `state.lastClaim` to the latest processed day
  (BurnieCoinflip:566-568 `if (processed != start) state.lastClaim = processed`). So immediately after each
  daily resolution `lastClaim == flipsClaimableDay`, and `_viewClaimableCoin(sDGNRS)` short-circuits at
  `startDay >= latestDay ⇒ return 0` (BurnieCoinflip:1020). Therefore `previewClaimCoinflips(sDGNRS)` ==
  `claimableStored` in steady state, and `claimableStored` for sDGNRS is structurally 0 under 0-take-profit
  rebuy (no take-profit ever banks into it post-arming). Net: `burnieOwed` reflects ONLY sDGNRS's HELD wallet
  balance — and post-seed, sDGNRS's ongoing winnings roll into carry rather than the wallet, so the ongoing
  BURNIE share delivered to redeemers post-seed is essentially ZERO (the seed-window wins that DID mint to the
  wallet during days 1-20 remain as held balance and are correctly counted).

### 1c. Design-intent determination

The old design held a fixed 2M BURNIE as sDGNRS held balance (always visible to `burnieOwed`) + a 2M virtual
VAULT reserve. The rework replaces this with a seeded flip position: days 1-20 wins mint to sDGNRS's wallet
(visible backing), then sDGNRS goes on perpetual 0-take-profit rebuy where ongoing wins roll into a carry
that backing CANNOT see and that has NO liquidation path. So the post-seed BURNIE-share economics the 2M
reserve provided are NOT reproduced for redeemers — the carry is a value sink relative to redemption backing.
Whether this is INTENDED (a deliberate "the seed window is the BURNIE backing; post-seed redeemers get only
the held seed-window winnings, BURNIE being worthless-except-the-whale-pass") or ACCIDENTAL (the carry
genuinely SHOULD count) is a design-intent call the comment at BurnieCoinflip:872-879 partially answers — it
explicitly states post-arming "BURNIE leaves sDGNRS's flip position solely through a redemption's burn+consume
leg" and "the return is structurally zero under 0-take-profit rebuy," i.e. the design KNOWS the carry does not
flow to redeemers. That is a documented, deliberate structural choice — but it leaves the carry as accounted-
nowhere value relative to the proportional-backing promise.

**PROVISIONAL VERDICT — CONFIRMED (under-credit/strand), severity MED, bounded off the ETH spine.** The carry
is invisible to `burnieOwed` and has no sDGNRS-reachable liquidation path; redeemers are progressively
under-credited for carry-resident BURNIE post-seed. Conservative (no over-credit, no insolvency, no
ETH-spine effect). The documented "structurally zero return" comment indicates the design ACCEPTS the carry
not flowing to redeemers, which pushes toward BY-DESIGN, but the value IS proportionally owed under the
`burnieOwed` formula's own premise, which keeps it a real backing-completeness gap. **Routed-fix shape (NOT
applied):** either (a) have `burnieOwed` count `autoRebuyCarry` in sDGNRS's backing (add a
`previewCoinflipCarry(sDGNRS)` read to the `claimableBurnie` term), or (b) add an sDGNRS-reachable carry
liquidation on the redemption path so the carry materializes into held/claimable backing before
`burnieOwed` is computed, or (c) formally rule it BY-DESIGN and record a KNOWN-ISSUES note that post-seed
BURNIE redemption backing is the held seed-window balance only. Task 2 finalizes the verdict + routing with
the skeptic gate. **Codex second-source flagged (post-reset) — this is the top prime lead.**

---

## §2. BURNIE-05 / FC-392-17 — VAULT seed-stake 30-day window-aging forfeiture (DEDICATED DETERMINATION)

**Property:** the VAULT's day-1-20 seed (~half the seeded principal) is recoverable.
**Attack:** never claim the VAULT for the first 51+ days and check whether the seed days age out of the
30-day first-claim window.

### 2a. The window math (frozen)

For a player with `lastClaim == 0` and `autoRebuyEnabled == false`, the claim window is
`windowDays = COIN_CLAIM_FIRST_DAYS = 30` (BurnieCoinflip:421, constant @137), and
`minClaimableDay = latest > windowDays ? latest - windowDays : 0` (BurnieCoinflip:445-447). The claim then
sets `if (start < minClaimableDay) start = minClaimableDay` (BurnieCoinflip:433), SILENTLY skipping every day
below `minClaimableDay` (the loop begins at `cursor = start+1`, BurnieCoinflip:451). The view twin
`_viewClaimableCoin` (BurnieCoinflip:1022-1031) applies the identical clamp. So if the VAULT first claims when
`flipsClaimableDay >= 51`, then `minClaimableDay = 51 - 30 = 21 > 20`, and ALL VAULT seed days (1..20) are
below `minClaimableDay` ⇒ skipped ⇒ never minted. The VAULT's entire ~half-of-4M expected seed emission is
silently and unrecoverably forfeited.

### 2b. The three determinations (the prompt's required treatment)

**(i) Is the VAULT guaranteed to claim within 30 days, or on auto-rebuy at deploy?** NO guarantee in code.
The VAULT seed is written identically to sDGNRS in the constructor (BurnieCoinflip:189-197), but ONLY sDGNRS
is auto-claimed by `processCoinflipPayouts` (BurnieCoinflip:877-893). The VAULT must act through
`DegenerusVault.coinClaimCoinflips` → `claimCoinflips(VAULT,…)` (DegenerusVault:630-631) — an `onlyVaultOwner`
manual call. The VAULT is NOT auto-claimed and NOT armed onto auto-rebuy at deploy: the sDGNRS arming is
hard-coded in `processCoinflipPayouts` (BurnieCoinflip:884-892) and applies to `ContractAddresses.SDGNRS`
ONLY; the VAULT's own auto-rebuy can only be enabled by an `onlyVaultOwner` call to `coinSetAutoRebuy`
(DegenerusVault:645-646), which is NOT invoked at construction (the DegenerusVault constructor has no such
call — grep clean; the only VAULT auto-rebuy reachability is the owner-operated `coinSetAutoRebuy`).

**(ii) Is there ANY auto-claim / auto-rebuy safety net for the VAULT seed?** NO. sDGNRS has the hard-coded
daily auto-claim + the day-20 arming safety net (BurnieCoinflip:877-892). The VAULT has NEITHER — its only
paths are the manual `coinClaimCoinflips` and the manual `coinSetAutoRebuy`, both `onlyVaultOwner`. There is
no keeper, no advanceGame-chain hook, no constructor arming for the VAULT.

**(iii) Under the realistic deploy/operations timeline, is the seed at silent forfeiture risk?** YES, IF the
VAULT owner does not act within the first 30 resolved days. NOTE the escape hatches that BOUND the risk: if
the VAULT owner calls `coinSetAutoRebuy(true,…)` BEFORE day 51, the armed-player branch changes
`minClaimableDay = autoRebuyStartDay` (BurnieCoinflip:441-444) rather than `latest - 30`, so an armed VAULT
settles back to its enable day and the window-aging clamp no longer applies — arming within 30 days fully
escapes the forfeiture. Likewise a single `coinClaimCoinflips` within the first 30 days claims the early seed
days before they age out (a claim at day≤30 has `minClaimableDay=0`, capturing all of days 1..20). So the
seed is recoverable IFF the VAULT owner performs ONE operational action (claim or arm) within ~30 days of
deploy; absent that action, the seed silently ages out with no on-chain warning and no recovery.

### 2c. Design-intent determination

This is the surface map's flagged "most likely to need a contract change." The VAULT is a protocol-controlled
address (the deployer/operator holds >50.1% DGVE), so the realistic timeline is "the operator who just
deployed claims the seed promptly." Against that timeline the forfeiture risk is low — a deliberate
"use-it-or-lose-it" window is a plausible by-design posture for a protocol-owned address. BUT: (a) the
asymmetry is unguarded and silent — unlike sDGNRS, the VAULT has no safety net, and the forfeiture is
irreversible with zero on-chain signal; (b) the value at risk is ~half the seeded principal (~2M expected
BURNIE), which the threat weighting rates as a value-bearing lost-emission window; (c) the 30-day window is
NARROW relative to a deploy-then-bootstrap operational reality where the operator may not touch the VAULT's
coinflip claim for weeks. The defect is NOT a player-exploitable extraction (no third party gains) — it is a
self-inflicted operational forfeiture risk on a protocol address, which softens it toward an operational-
note / BY-DESIGN class rather than a hard contract finding, PROVIDED the deploy runbook guarantees the
within-30-day action.

**PROVISIONAL VERDICT — CONFIRMED-as-risk (lost-emission window), severity MED, contingent on the deploy
runbook.** The VAULT seed is at silent unrecoverable forfeiture risk if the owner does not claim OR arm
within the first 30 resolved days; there is no auto-claim safety net and no on-chain warning. If the deploy
runbook GUARANTEES a within-30-day VAULT claim/arm, this is BY-DESIGN (use-it-or-lose-it on a protocol
address) — but that guarantee is OPERATIONAL, not enforced in code. **Routed-fix shape (NOT applied):**
either (a) auto-claim the VAULT alongside sDGNRS in `processCoinflipPayouts` during the seed window, or (b)
arm the VAULT onto auto-rebuy at deploy (mirroring the sDGNRS day-20 arming), or (c) widen
`COIN_CLAIM_FIRST_DAYS` enough to cover the seed window, or (d) accept BY-DESIGN + add a deploy-runbook MUST
("claim or arm the VAULT coinflip within 30 days of deploy"). This is the lead most likely to warrant a
contract change. Task 2 finalizes with the skeptic gate. **Codex second-source flagged (post-reset).**

---

## §3. BURNIE-02 — emission conservation (re-verified, anchored on BurnieEmissionSeeds 5/5)

**Property:** no over/under-emission vs the seeded principal; the seed→arm handoff has no off-by-one.
**Attack:** sum the seeded principal, trace the per-day resolution + the seed→arm handoff for an off-by-one.

- **Seed sum:** the constructor writes `_setFlipStake(d, VAULT, 200_000e18)` and `_setFlipStake(d, SDGNRS,
  200_000e18)` for `d = 1..20` inclusive (`d <= SEED_FLIP_DAYS`, BurnieCoinflip:178-186). Total seeded STAKE
  = 200k × 20 × 2 = **8M BURNIE**, ~half expected to win (≈4M EV pre-reward%, more with the win bonus),
  replacing the removed 2M direct grant + 2M virtual reserve. `BurnieCoin._supply` starts fully ZERO (no
  constructor mint; BurnieCoin:170-178 + comment) — nothing mints up front.
- **One epoch per call:** `processCoinflipPayouts` resolves exactly one `epoch` per call (driven by
  advanceGame), `_storeDayResult(epoch,…)` (BurnieCoinflip:826) then `flipsClaimableDay = epoch`
  (BurnieCoinflip:849). sDGNRS is auto-claimed every resolved day (BurnieCoinflip:877-880), so its cursor
  tracks `flipsClaimableDay` 1:1 through the seed window (no missed day → no window-aging for sDGNRS).
- **Seed→arm handoff (off-by-one check):** the arming `if (epoch >= SEED_FLIP_DAYS)` (BurnieCoinflip:884)
  fires when day 20 settles, AFTER `_claimCoinflipsAmount(SDGNRS, max, true)` (BurnieCoinflip:880) has already
  minted day-20's win to sDGNRS's wallet. `autoRebuyStartDay = sdgnrsState.lastClaim` (BurnieCoinflip:890) ==
  20 at that point. Days 21+ then take the armed branch (`_claimCoinflipsInternal(SDGNRS,false)`,
  BurnieCoinflip:877-878) and roll into carry. The `>=` (not `==`) is monotone-safe: epoch increases
  monotonically and the latch (§5) blocks re-arming, so the boundary fires exactly once at epoch 20. NO
  off-by-one: day 20 is minted-to-wallet (seed-window semantics) AND triggers arming for day 21+.
- **Conservation identity:** `BurnieCoin._supply.totalSupply` + `vaultAllowance` both start at 0; BURNIE
  enters only via `mintForGame` (each gated on a survived flip, §4) and leaves via `burnForCoinflip`/`burnCoin`.
  No path mints the seed principal directly — it materializes only through the resolution walk on surviving
  days. The green **BurnieEmissionSeeds invariant (5/5)** is the standing conservation oracle for the
  seed-window emission (854/0/110 baseline).

**PROVISIONAL VERDICT — REFUTED (conservation holds).** No over/under-emission found; the seed→arm handoff is
off-by-one-clean; anchored on BurnieEmissionSeeds 5/5.

---

## §4. BURNIE-01 — survive-before-mint completeness (per-source enumeration; FC-392-19 folded)

**Property:** EVERY BURNIE mint source gates on a survived coinflip.
**Attack:** enumerate every `mintForGame`/`creditFlip` BURNIE source and confirm each requires a survived
flip (directly, or via a flip stake that itself must survive a later day).

| BURNIE source | Survive-gate | Cite |
|---|---|---|
| Seed stakes (days 1-20) | mint ONLY if the day's flip wins (`if (win) payout` in the claim loop; loss forfeits principal) | BurnieCoinflip:481-509, 188-197 |
| Per-bet Degenerette survival flip | `acc.burnieMint += totalPayout; totalPayout *= 2` on a won fair flip, `-= totalPayout; = 0` on a loss; netted once per bet, flushed via `coin.mintForGame(player, acc.burnieMint)` | DegeneretteModule:771-780, flush :447 |
| Box-origin BURNIE spins (×3 under one survival flip) | `survived = total != 0 && (hash2(seed, BOX_SURVIVAL_TAG)&1==1); total = survived ? total*2 : 0; if (total!=0) coin.mintForGame(...)` — mint-only, no pool/ETH | DegeneretteModule:1384-1389 |
| Normal coinflip win (player flips) | same win-gated claim loop as the seeds | BurnieCoinflip:481-509 |
| Keeper box bounty | `coinflip.creditFlip(msg.sender, …)` — a flip STAKE, not a direct mint; it must survive a later day's flip before minting | StakedStonk:810-813 |
| Afking BURNIE settlement | `coinflip.creditFlip(player, owed*1e18)` — a flip credit (stake), not a direct mint; survives a later flip | GameAfkingModule:1096 |
| sDGNRS redemption BURNIE leg | `_addDailyFlip(redeemer, base, …)` deferred mint offset 1:1 by `burnForCoinflip`+consume ⇒ net new BURNIE = 0 (conserved, not a new emission) | BurnieCoinflip:940-966 |

Every direct mint (`mintForGame`) is win-gated; every credit (`creditFlip`/`_addDailyFlip`) lands a flip
STAKE that must itself survive a later day before it can mint. No BURNIE mints without a survived flip.

**FC-392-19 (survival-flip seed reuse) folded:** the per-bet survival flip uses `hash2(rngWord, betId)`
(DegeneretteModule:773), and a per-bet lootbox box would use the SAME `hash2(rngWord, betId)` as its seed.
For BURNIE bets `betLootboxShare == 0` (lootbox-share is ETH-only), so NO box opens on a BURNIE bet — there
is no observable correlation and no path that mixes a BURNIE survival outcome with a box draw. `betId` is
`++nonce` (not free) and `rngWord` is VRF-committed AFTER placement, so a player cannot steer the shared
derivation. Defence-in-depth only.

**PROVISIONAL VERDICT — REFUTED (survive-before-mint complete); FC-392-19 REFUTED (no box on a BURNIE bet).**

---

## §5. BURNIE-03 — latch monotonicity (FC-392-18 folded)

**Property:** `sdgnrsAutoRebuyArmed` arms exactly once, never double-mints, never re-enters.
**Attack:** find a path that disarms, re-runs the arming block, double-mints, or toggles the enabled flag off
to extract carry.

- **Set once, never cleared:** `sdgnrsAutoRebuyArmed` is the storage bool (BurnieCoinflip:175); it is set to
  `true` once at `epoch >= SEED_FLIP_DAYS` (BurnieCoinflip:884-889) and there is NO code path that sets it
  false. The arming block is gated behind the `else` of `if (sdgnrsAutoRebuyArmed)` (BurnieCoinflip:877/881),
  so once armed only `_claimCoinflipsInternal(SDGNRS,false)` runs (carry roll, 0 take-profit → mints nothing).
- **No double-mint:** the seed-window branch mints via `_claimCoinflipsAmount(...,true)` (BurnieCoinflip:880);
  the armed branch (`_claimCoinflipsInternal(SDGNRS,false)`) banks only the take-profit `reserved`, which is 0
  under 0-take-profit, into `claimableStored` — it never mints. The two branches are mutually exclusive on the
  latch. epoch is monotone (advanceGame), so the boundary fires once.
- **No carry extraction toggle:** `setCoinflipAutoRebuy(SDGNRS,false,…)` would mint the carry — but it is
  NEVER called for sDGNRS (grep clean; reachable only via `msg.sender==GAME` or `DegenerusVault.coinSetAutoRebuy`
  on the VAULT, neither targeting sDGNRS; sDGNRS holds no such call). The enabled flag cannot be toggled off
  to extract carry.

**FC-392-18 (fromGame permissive branch) folded:** `setCoinflipAutoRebuy` has a `fromGame = msg.sender == GAME`
branch (BurnieCoinflip:662-668) that uses the `player` verbatim and SKIPS the operator-approval `_resolvePlayer`
arm. NO in-protocol GAME module calls `setCoinflipAutoRebuy` (grep across `contracts/*.sol` = only the
definition + the VAULT/interface decls; no module invocation), so the branch is presently UNREACHABLE and
matches baseline (not a regression). Per [[open-e-operator-approval-trust-boundary]] operator-approval IS the
trust boundary; a latent permissive branch reachable only by GAME is consistent with that boundary. Confirm
it stays unreachable.

**PROVISIONAL VERDICT — REFUTED (latch monotone, no double-mint, no carry-extraction toggle); FC-392-18
REFUTED (unreachable, matches baseline).**

---

## §6. BURNIE-06 — packed-lane round-trip + off-spine

**Property:** the stake lane and the day-result lane round-trip losslessly; BURNIE never reaches the ETH path.

- **Stake lane (2 days/slot, 128-bit wei lanes):** `_flipStake(day,p) = uint128(coinflipStakePacked[day>>1][p]
  >> ((day&1)*128))`; `_setFlipStake` masks `~(uint128.max << shift)` and ORs `weiAmount << shift`
  (BurnieCoinflip:1072-1085). The sibling day's 128 bits are preserved by the mask. `weiAmount` is provably
  ≤ uint128 (BurnieCoin caps total supply at uint128, and a stake never exceeds supply), so no lane overflow
  into the sibling. Round-trip lossless; sub-1-BURNIE wei granularity preserved (flip credits can be sub-token).
- **Day-result lane (32 days/slot, 8-bit 3-state):** `_storeDayResult` writes `win ? rewardPercent : 1`
  (BurnieCoinflip:1101-1106); `_dayResult` reads `b`, `win = b >= 50` (BurnieCoinflip:1092-1098). Wins store
  `rewardPercent ∈ [50,156]` (unlucky=50, lucky=150, normal 78+[0..37], +bonus ≤+6 → max 156 ≤ 255;
  BurnieCoinflip:799-815, 829-831), losses store the nonzero sentinel `1`, unresolved reads `0`. `b >= 50`
  cleanly separates wins; NO win can land in `[2,49]` (the only sub-50 fixed branch is unlucky=50). The
  resolution-detection `rewardPercent == 0 && !win` skips only the unresolved (`b==0`) state. Lossless 3-state
  round-trip; no win mis-reads as a loss.
- **Off the ETH spine:** BURNIE is minted (`mintForGame`) / burned (`burnForCoinflip`/`burnCoin`) only; no
  BURNIE flow credits `claimableWinnings` or the prize pools. Degenerette BURNIE payouts mint directly; box
  BURNIE spins are mint-only (no pool/ETH/recirc, DegeneretteModule:1347-1394); the afking BURNIE settlement
  is a flip credit (GameAfkingModule:1096); the sDGNRS redemption BURNIE leg burns+consumes to offset the
  deferred mint (net new BURNIE = 0). No new BURNIE→ETH path.

**PROVISIONAL VERDICT — REFUTED (lanes lossless, no sibling corruption, BURNIE off the ETH spine).**

---

## §7. FC-392-11 — loss-sequence backing dynamics (the backing half; RNG-lock half attested at 391)

**Property:** a loss sequence (or a single large-carry loss) cannot drop sDGNRS backing below outstanding
redemption obligations in a way a redeemer can exploit; `claimCoinflipCarry` cannot interact with the sDGNRS
settle to let a redeemer extract mid-roll.
**Attack:** model a loss sequence against outstanding obligations; check the carry-claim/settle interaction.

- **391 cross-ref (RNG-lock half):** 391-FINDINGS §2c proves the RNG-lock over the carry roll is AIRTIGHT —
  `claimCoinflipCarry` reverts on `rngLocked()` at the TOP (BurnieCoinflip:759) BEFORE settling/reading the
  carry; `processCoinflipPayouts` applies the roll inside the locked window; no window exists where a carry
  claim/settle reads the roll before the lock blocks it. This net builds the BACKING half on that finding.
- **Loss-sequence backing model:** post-arming, sDGNRS's ongoing wins roll into carry and a loss ZEROES the
  carry (`if (rebuyActive) carry = 0` on a losing day, BurnieCoinflip:512-514). CRUCIALLY (per §1), the carry
  is ALREADY invisible to `burnieOwed` — so a loss that zeroes the carry does NOT reduce any backing that
  `burnieOwed` was counting (it was counting only held + claimableStored, which the carry roll never fed). The
  loss-sequence cannot drop ACCOUNTED backing below obligations because the volatile carry was never accounted
  in the first place. `burnieOwed` reflects only the held seed-window balance, which is a settled wallet
  balance not subject to the loss-sequence. So the path-dependent backing variance does NOT couple to the
  accounted obligations — it couples only to the (already-stranded, §1) carry.
- **No mid-roll redeemer extraction:** `redeemBurnieShare` (BurnieCoinflip:940-967) consumes only held +
  `claimableStored`, never the carry/pending stake; the RNG-lock blocks `claimCoinflipCarry` during the roll
  window. A redeemer submitting during a roll receives `burnieOwed` based on the frozen held balance, not the
  in-flight carry. No extraction window.

**PROVISIONAL VERDICT — REFUTED (no accounted-backing-below-obligations break; no mid-roll extraction). The
backing variance couples only to the stranded carry (§1), not to the obligations `burnieOwed` tracks. The
RNG-lock half is attested at 391.**

**FC-392-13 (carry settle-ordering double-count) folded:** `claimCoinflipCarry` calls
`_claimCoinflipsInternal(player,false)` FIRST (BurnieCoinflip:763), which banks the take-profit `reserved`
chunks into `mintable` → `claimableStored` (BurnieCoinflip:765-768) and writes the final rolled `carry` into
`state.autoRebuyCarry` (BurnieCoinflip:571-574), THEN reads `state.autoRebuyCarry` and withdraws ≤ `amount`
from it (BurnieCoinflip:770-777). The take-profit `reserved` and the rolled `carry` are DISJOINT partitions of
each day's payout (`reserved = (payout/takeProfit)*takeProfit; carry = payout - reserved`, BurnieCoinflip:496-507)
— a single win is split, never counted in both channels. The settle banks into `claimableStored` (claimed via
the normal `claimCoinflips`), the carry-withdraw touches `autoRebuyCarry` only. NO double-count. Anchored on
the green CoinflipCarryClaim.t.sol coverage. **FC-392-13 REFUTED.**

---

## §8. FC-392-12 / FC-392-20 (LOW-INFO leads)

- **FC-392-12 (seed-stake leaderboard/bounty exclusion):** the constructor writes the seeds via the direct
  `_setFlipStake` storage helper (BurnieCoinflip:181-182), NOT via `_addDailyFlip` — and `_updateTopDayBettor`
  (the leaderboard write) is called ONLY from `_addDailyFlip` (BurnieCoinflip:617). The bounty/biggest-flip
  records (`currentBounty`, `biggestFlipEver`, `bountyOwedTo`) are touched only by the bounty resolution in
  `processCoinflipPayouts` and the `_addDailyFlip` bounty-arm path, never by `_setFlipStake`. So no path reads
  the days-1..20 seed stake into a leaderboard/bounty/BAF/biggestFlipEver computation that mis-credits the
  VAULT/sDGNRS protocol addresses. **PROVISIONAL VERDICT — REFUTED (seeds excluded from leaderboard/bounty).**
- **FC-392-20 (claim-window widening gas, cross-ref FC-393-04 → 393):** `COIN_CLAIM_DAYS 90→365`,
  `AUTO_REBUY_OFF_CLAIM_DAYS_MAX 1095→1460`, day counters `uint8→uint16` (BurnieCoinflip:136-138). The deep
  auto-rebuy walk uses `uint32 remaining` (BurnieCoinflip:448, safe for 1460); the shallow path uses the
  `uint16 windowDays` (safe for 365). The per-claim resolution-walk ceiling rises with the wider windows, but
  the walk is PER-CALL and CALLER-PAID, NOT in the advanceGame chain (sDGNRS's auto-settle walks ~1 new day
  per resolution). A claim that has accrued the full window does a bounded SLOAD walk the CALLER pays for; no
  realistic actor can force a many-hundred-day cold-SLOAD walk into a GAS-SENSITIVE caller (the advanceGame
  chain auto-settles sDGNRS at 1 day/advance; the wide windows are only on the user-paid manual claim path).
  The fresh-gas worst-case confirmation under the new packed masked sub-word reads is owned by 393
  (FC-393-04). **PROVISIONAL VERDICT — INFO (bounded, caller-paid, off the advanceGame chain); gas worst-case
  cross-ref → 393.**

---

## §9. Council fold-in (NET 1 leads, read AFTER the independent net above)

Read AFTER §1-§8 per the dual-net discipline. `council/burnie.gemini.txt` is on record; `codex` is in
`skipped[]` (hard usage-limit cap, identical banner to 392-01, reset ~late evening — NOT a refusal/timeout).
**Codex second-source re-run flagged (post-reset, carry to 396)** for any CONFIRMED finding — especially the
two prime backing leads.

| Item | Council (gemini) | NET 2 (this doc) | Convergent? |
|---|---|---|---|
| BURNIE-04 / FC-392-16 | **FINDING (PRIME-01)** — carry invisible to `previewClaimCoinflips`; redeemers progressively under-credited; carry a "black hole," no liquidation path | **CONFIRMED (under-credit/strand, MED)** §1 — exhaustive backing trace: carry unread by both paths, no sDGNRS liquidation, conservative, steady-state burnieOwed = held only | ✓ CONVERGENT (both land the prime target; NET 2 adds the conservative bound + the routed-fix shape) |
| BURNIE-05 / FC-392-17 | **FINDING (PRIME-02)** — VAULT day-1-20 seed silently forfeited if not claimed within the 30-day window; no auto-claim safety net (unlike sDGNRS) | **CONFIRMED-as-risk (lost-emission window, MED), contingent on the deploy runbook** §2 — confirms the window math + the no-safety-net asymmetry; ADDS the arm/claim-within-30-days escape hatches that bound it | ✓ CONVERGENT (NET 2 adds the escape-hatch bound + the runbook contingency) |
| BURNIE-01 | VERIFIED SOUND (every source gates on a survived flip) | REFUTED (§4 per-source enumeration; FC-392-19 folded) | ✓ CONVERGENT |
| BURNIE-02 | VERIFIED SOUND (8M-stake/~4M-EV replaces 2M+2M) | REFUTED (§3 conservation + off-by-one-clean handoff; BurnieEmissionSeeds 5/5) | ✓ CONVERGENT |
| BURNIE-03 | VERIFIED SOUND (latch monotone, correct wallet→carry transition) | REFUTED (§5 set-once, no double-mint, no toggle; FC-392-18 folded) | ✓ CONVERGENT |
| BURNIE-06 | VERIFIED SOUND (128-bit/8-bit lanes lossless, BURNIE off the ETH spine) | REFUTED (§6 lane round-trip + off-spine) | ✓ CONVERGENT |
| FC-392-11 / -12 / -13 / -19 / -20 | NO explicit gemini verdict (selective on non-prime targets) | §7/§8/§4 — all adjudicated provisional (REFUTED / INFO), Claude-net-primary | — (council coverage gemini-only + selective; carried Claude-net-primary; codex second-source recommended) |

**No council-only divergent lead** that NET 2 did not independently reach. gemini's two FINDINGS land on the
exact two prime targets NET 2 also CONFIRMED; gemini's four SOUND verdicts converge with NET 2's four
REFUTEDs; the five non-prime leads received no explicit gemini verdict and are carried Claude-net-primary.

---

## §10. NET 2 provisional verdict summary

| Item | PROVISIONAL VERDICT (NET 2) | Settling cite |
|---|---|---|
| **BURNIE-01** | REFUTED | per-source survive-gate enum §4 (DegeneretteModule:771-780/1384-1389, BurnieCoinflip:481-509, GameAfkingModule:1096) |
| **BURNIE-02** | REFUTED | conservation + handoff §3 (BurnieCoinflip:178-186/880/884-892; BurnieEmissionSeeds 5/5) |
| **BURNIE-03** | REFUTED | monotone latch §5 (BurnieCoinflip:175/877/884-889) |
| **BURNIE-04 / FC-392-16** | **CONFIRMED (under-credit/strand, MED)** | exhaustive backing trace §1 (StakedStonk:1029-1031; BurnieCoinflip:971-975/940-967; carry unread, no liquidation) |
| **BURNIE-05 / FC-392-17** | **CONFIRMED-as-risk (lost-emission window, MED), runbook-contingent** | VAULT-window determination §2 (BurnieCoinflip:421/433/445-447; DegenerusVault:630-646; no safety net) |
| **BURNIE-06** | REFUTED | lane round-trip + off-spine §6 (BurnieCoinflip:1072-1106) |
| **FC-392-11** | REFUTED (backing half); RNG-lock half attested 391 | loss-sequence model §7 (couples only to stranded carry; BurnieCoinflip:512-514/940-967) |
| **FC-392-12** | REFUTED | leaderboard exclusion §8 (`_setFlipStake` bypasses `_updateTopDayBettor`) |
| **FC-392-13** | REFUTED | settle-ordering disjoint partition §7 (BurnieCoinflip:496-507/571-574/763-777) |
| **FC-392-18** | REFUTED (unreachable, matches baseline) | §5 (BurnieCoinflip:662-668; grep-clean GAME caller) |
| **FC-392-19** | REFUTED (no box on a BURNIE bet) | §4 (DegeneretteModule:773; `betLootboxShare==0` for BURNIE) |
| **FC-392-20** | INFO (bounded, caller-paid); gas → 393 | §8 (BurnieCoinflip:136-138/448; cross-ref FC-393-04) |

**NET 2 ON RECORD** for the full BURNIE/coinflip-rework slice, independent of the council, with a per-item
attack + provisional verdict. The two prime backing leads received dedicated rigorous treatment (§1 carry
backing trace, §2 VAULT-window determination) and BOTH land as CONFIRMED (MED, off the ETH spine). Emission
conservation re-verified (§3), survive-before-mint enumerated per source (§4), the latch proven monotone
(§5), the packed-lane round-trip confirmed (§6), the loss-sequence backing modeled (§7), the council leads
folded (§9). `git diff a8b702a7 -- contracts/` EMPTY (read-only over the frozen subject).
