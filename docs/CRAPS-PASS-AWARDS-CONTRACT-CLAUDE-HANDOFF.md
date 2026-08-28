# Craps pass awards: whale buyers, deity buyers, and the presale box: Contract Claude handoff

> Status: product brief approved in discussion on 2026-08-27.
>
> Three award lanes, one door. Whale-pass buyers earn ordinary Craps day passes and deity-pass
> buyers earn HIGH-ROLLER passes — both **only while the game is below level 10** — and the
> presale box's FLIP branch converts roughly **half its FLIP budget into Craps passes**. Every
> award is a direct pass-credit registration exactly like the lootbox lane: no token, no claim
> step, no new asset.

<agent_identity>

You are Contract Claude, the senior Solidity engineer implementing these awards in the Degenerus
Protocol. Work from the live repository; the contracts are authoritative for current behavior and
this brief for the product delta. Do not reset, discard, or broadly rewrite unrelated work.

</agent_identity>

<domain_knowledge>

## The one door

`CrapsBattle.creditPasses(address player, uint32 normal, uint32 high)` — `OnlyGame`, credit-only,
no external calls, saturating at the lane cap with `CrapsPassesDropped` announced. It exists and
is tested (built as the lootbox delivery fallback). The richer
`deliverPasses(player, normal, high)` additionally auto-reserves tomorrow; it is `OnlyGame` too.

Both purchase sites run as DELEGATECALLS inside the Game, so an external call from them reaches
the table with `msg.sender == GAME` and passes the gate — the LootboxModule already calls
`deliverPasses` this way in production.

Credits never expire, are non-transferable, and are spent by their owner through
`applyCrapsPasses`/`buyFutureCrapsDays`. A normal pass is one future ordinary day seat
(~22,800 FLIP expected cost, 25,000 retail); a high pass is one high-roller day seat
(~433,240 expected, 450,000 retail).

## The three sites

1. **Whale pass** — `DegenerusGameWhaleModule.purchaseWhalePass(buyer, quantity, affiliateCode)`
   (module margin 7,617 B). Quantity 1..100.
2. **Deity pass** — `DegenerusGameWhaleModule.purchaseDeityPass(buyer, symbolId, affiliateCode)`,
   one per address, ever.
3. **Presale box** — `DegenerusGameLootboxModule._resolvePresaleBox` (module margin 3,850 B).
   The 50%-probability FLIP branch computes `flipBudget = amount * flipBps / 10_000` in ETH
   terms, converts to FLIP at `priceForLevel(currentLevel)`, rounds, and pays as coinflip
   credit. The other branches (40% DGNRS, 10% WWXRP) are untouched by this brief.

## Margins and constraints

CrapsBattle 24,457 B (margin 119 — DO NOT add code there; the door exists). DegenerusGame proper
24,487 B (margin 89 — add nothing there). WhaleModule and LootboxModule have room. The RNG-window
gate (`scripts/rng-window-manifest.tsv`) must be updated if any new code reads a VRF word — the
presale change happens inside an existing consumer and should need no new registration, but run
`make check-rng-window` and classify anything it flags.

</domain_knowledge>

<task_definition>

## 1. Whale-pass buyers (pre-level-10 only)

On a successful `purchaseWhalePass`, credit the buyer **one normal Craps pass per pass
purchased** (`quantity` passes for a quantity buy), via `creditPasses(buyer, quantity, 0)`,
**only when the game is below level 10** at purchase time. Use the same level variable the
function already reads (`level`); recommended comparator: `level < 10` — state the chosen rule in
the event docs and hold it with a boundary test at levels 9 and 10.

- The award rides the purchase transaction; a purchase that reverts awards nothing.
- `creditPasses`, not `deliverPasses`: a purchase should not silently commit the buyer's
  tomorrow. The buyer spends credits on days of their choosing.
- Decide and document whether a whale-boon-discounted purchase still earns (recommended: yes —
  the award keys on passes bought, not on price paid).

## 2. Deity-pass buyers (pre-level-10 only)

On a successful `purchaseDeityPass`, credit the buyer **one HIGH-ROLLER pass**:
`creditPasses(buyer, 0, 1)`, same level-10 gate, same rules. One per address by construction
(deity passes are one per address).

## 3. Presale box: passes in place of about half the FLIP

In `_resolvePresaleBox`'s FLIP branch only:

```text
flipOut      = <existing computation, unchanged through the rounding>
passBudget   = flipOut / 2
passes       = passBudget / 25_000e18          // the RETAIL figure, floored
flipRemains  = flipOut - passes * 25_000e18
```

- Credit `passes` normal Craps passes through `creditPasses` and pay `flipRemains` as the
  existing coinflip credit. A box whose half-budget is under one pass (most small boxes) pays
  pure FLIP exactly as today — no minimum is broken, no dust is created.
- Cap `passes` at a sane per-box ceiling (recommend 40, uint32-safe by construction) and pay the
  excess as FLIP; a closing-box sweep is DGNRS and is untouched.
- The conversion divides the ALREADY-ROUNDED flipOut, so EV within the branch is conserved by
  construction: `passes * 25_000e18 + flipRemains == flipOut` exactly. Assert it in tests.
- Value note for the docs: at the 25,000 retail rate the buyer receives slightly less than a
  self-bought day (expected cost ~22,800), which is the protocol's ordinary retail margin —
  document it, do not correct for it.
- NO level gate here: a presale box is presale-era by definition, and its resolution level is an
  accident of when it was opened. If you disagree after inspection, surface the tradeoff rather
  than choosing silently.
- Extend `PresaleBoxOpened` (or add one compact event) so an indexer can reconcile
  FLIP-vs-passes; do not lose the existing fields.

## Required verification

1. Whale: quantity N below level 10 credits exactly N normal passes; at/above the boundary
   credits zero; the purchase itself is identical either way.
2. Deity: one high pass below level 10, zero at/above; `CrapsPassesCredited(player, true, 1)`.
3. Boundary tests at levels 9 and 10 for both.
4. Presale FLIP branch: conservation (`passes * 25k + flipRemains == flipOut`), the under-one-pass
   box unchanged, the cap path, and the 40%/10% branches byte-identical.
5. Saturation: a buyer at the pass-lane cap drops the excess with `CrapsPassesDropped`, and the
   purchase still succeeds.
6. The credits are spendable: an awarded pass reserves a future day through `applyCrapsPasses`
   end to end.
7. No new mint or liquid-FLIP path anywhere; passes are credits in CrapsBattle storage only.
8. Sizes: WhaleModule, LootboxModule, CrapsBattle, Game all under EIP-170 (CrapsBattle and Game
   must not grow at all).
9. Run the craps set (`test/craps/*.t.sol` + the four craps fuzz suites), the whale/deity suites,
   the presale/lootbox suites, `make check-rng-window check-craps-progressive`, the storage-layout
   oracle, and `git diff --check`.
10. Update `docs/CRAPS-BATTLE-SYSTEM-OVERVIEW.md` (pass sources) and the day-pass spec's award
    table; the economic docs gain the three new emission lines with expected daily magnitudes.

## Open decisions to surface before building

- Whether the whale award is per PASS (recommended, specced above) or per PURCHASE.
- Exact level comparator (`level < 10` recommended).
- The presale pass rate: retail 25,000 (specced) vs expected 22,800.

</task_definition>

<guardrails>

- Do not add code to CrapsBattle or DegenerusGame proper; the door exists.
- Do not mint tokens or liquid FLIP; a pass is a credit.
- Do not auto-reserve a day from a purchase; credits only.
- Do not touch the presale box's DGNRS/WWXRP branches, the closing sweep, or the RNG derivation.
- Do not let an award failure revert a purchase — creditPasses cannot revert short of OOG, and
  the call is internal-to-delegatecall; if you wrap it, justify the wrap.
- Do not double-award on retried or multi-step purchases; one award per successful purchase path.

</guardrails>
