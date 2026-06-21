# VERIFY — Foil Pack Purchase + Rarity + Ticket Plumbing (447)

> Defensive code-vs-spec verification of the as-built `ffbd7796 (v70 freeze) → HEAD` foil-pack
> surface. Scope: FOIL-01..05, RARE-01..04, SEC-03, PILLAR-LIVE (foil-queue side).
> READ-ONLY review; no `.sol` modified. Cross-checked against `.planning/REQUIREMENTS.md`,
> `.planning/V71-FOILPACK-FINAL-SPEC.md`, and **`445-SPEC.md §U + §V` (authoritative, USER sign-off
> 2026-06-19/20 — §V.7-V.12 supersede the FINAL-SPEC body and §U where they conflict)**.

**Method note.** The authoritative design is the §V resolution chain, not the FINAL-SPEC body. Key
late pivots that this verification holds the code to: pack = **16 boosted entries** (V.7);
**match lines ARE the VRF-rolled tickets** — no deterministic buy-time signature (V.8); foil drain
**relocated to the FoilPackModule via delegatecall** (V.9); foil buy is an **additive leg of
`purchase(...,bool foil)`** orchestrated in the facade, with the standalone `buyFoilPack()` removed
(V.12); per-pack price = `FOIL_PACK_TICKETS(10) × priceForLevel(_activeTicketLevel())`.

---

## Per-requirement verdict table

| REQ | Code ref | Verdict | Note |
|---|---|---|---|
| **FOIL-01** one pack / account / raw level (auto-reset) | `FoilPackModule.sol:156-165`; cap `_foilBoughtThisLevel` `Storage.sol` (`foilRecord[lvl][buyer] != 0`); record write `:303-306` | **MATCH** | Keyed on `_activeTicketLevel()` (V.1 override of "raw level"), with the final-jackpot-day reroute to `level+1` (`:157-164`) so the cap, record, queue, and the claim's `dailyFoilDraw[day].level` all share one cycle key. Presence (slot≠0) IS the cap; distinct cycles = distinct outer keys ⇒ auto-reset per cycle. The §V.1 align-buy-to-draw fix is correctly applied. |
| **FOIL-02** price = 10×priceForLevel, 4 tickets / 16 quadrant entries | facade `_purchaseWithFoil` `DegenerusGame.sol:636-637`; foil leg `FoilPackModule.sol:184-185`; `FOIL_PACK_TICKETS=10`, `FOIL_PACK_ENTRIES=16` `Storage.sol` | **MATCH** | `cost = FOIL_PACK_TICKETS * priceForLevel(_activeTicketLevel())` = exactly 10×. The drain resolves a fixed `FOIL_PACK_ENTRIES = 16` boosted entries per buyer = 4 tickets × 4 quadrants (`_processFoilDrain:715`, `_resolveFoilBuyer:762-772`). Match record carries 4 lines; `ticketIndex ∈ 0..3`. Per V.7 (16, not the legacy "400"/"4"). |
| **FOIL-03** payable fresh ETH or claimable; afking leg rejected | facade `:632-642`; foil leg `:186-197`; `balancesPacked` low-128 = claimable / high-128 = afking (`Storage.sol:921-941`) | **MATCH** | Facade caps `fresh` at total `cost`, routes overpay to afking (`_creditAfkingValue`), carves `fresh − mintFresh` for the foil leg. Foil leg: `DirectEth` reverts when claimable is needed (`:189`); the claimable debit guard `remaining + 1 > uint128(bal)` (`:194`) keeps `remaining ≤ claimable−1`, so the low-half subtraction can never borrow into the **afking principal** (high 128). Afking principal is never spent. |
| **FOIL-04** spend routes 75% next / 25% future | `FoilPackModule.sol:199-216`; `FOIL_TO_FUTURE_BPS = 2500` `Storage.sol` | **MATCH** | `futureShare = cost*2500/10000` (25%), `nextShare = cost − futureShare` (75%). Applied to the foil cost only (ticket/lootbox legs keep their own 90/10). Frozen/unfrozen routing branch reused verbatim (`_getPendingPools`/`_getPrizePools`). Inverse of the 90/10 ticket split, as specified. |
| **FOIL-05** foil tickets are normal jackpot entries; boosted traits write real color tiers incl color==7 gold | `_resolveFoilBuyer` files into `traitBurnTicket[lvl][traitId]` `:774-805`; jackpot samples the same bucket (`JackpotModule.sol:641,955,1650`); gold channel keys on `color==7` (`JackpotModule.sol:1006-1031`) | **MATCH** | The drain writes 16 boosted 6-bit traits (`[QQ][CCC][SSS]`) into the shared `traitBurnTicket[lvl]` the jackpot draws from — zero new wiring. Boosted `color==7` (gold) lands in the same bucket, so foil gold auto-inherits the gold channel. The both-queues readiness gate (below) guarantees the entries are filed before the draw. |
| **RARE-01** NEW sibling producer `traitFromWordFoil`/`packedTraitsFoil`; frozen shared producers unmodified | `TraitUtils.sol:225-341` (added); diff has a **single** `@@ -222,4 +222,122 @@` hunk (tail-only) | **MATCH** | `foilCuts`/`foilTrait`/`traitFromWordFoil`/`packedTraitsFoil` added at the file tail. The frozen `weightedColorBucket`/`traitFromWord`/`packedTraitsFromSeed` (lines 115-178) are **byte-untouched** (no hunk touches that region — verified via `git diff`). `RngFreezeAndRemovalProofs` invariant intact by construction. Symbol stays uniform `& 7`, byte-identical to `traitFromWord`. |
| **RARE-02** multiplier ×2@0 → ~×5@350 → ×6@max via `foilBoostBps` | `ActivityCurveLib.sol:96-127` | **MATCH** | 4-segment curve reusing the 500/30000 knees: `FOIL_MIN_BPS=20000` (×2 @0), `FOIL_VA_BPS=50000` (×5 @ K=300), `FOIL_VB_BPS=55000` (×5.5 @500), `FOIL_MAX_BPS=60000` (×6 @30000). Computed: score 0→2.0×, 300→5.0×, 350→5.125×, 30000→6.0× — matches "~×5@350". Endpoint guards make 0 and the cap exact. |
| **RARE-03** multiplier frozen at BUY, applied at RESOLVE (never live-read) | freeze `:288,303-306`; drain reads `_foilMultFor` `:758`; claim reads `_foilRecordFor` `:459-460`; spin uses passed `activityScore` `:581,599-602` | **MATCH** | `multBps` AND the raw `activityScore` are frozen into `foilRecord[lvl][buyer]` at buy. The drain re-derives lines with the frozen `multBps`; the claim re-derives with the frozen `multBps` from the same record; the payout spin's RTP uses the **passed-in** frozen `activityScore`, explicitly "not a live read" (`:599-601`). No `_playerActivityScore` / live read at resolve. Fully determined at buy. |
| **RARE-04** all rarer tiers lifted; ×6 ⇒ gold ≈4.7%/quadrant | `foilCuts` `TraitUtils.sol:248-272`; verified numerically + `FoilLadderParity.t.sol` PASS | **MATCH** | `/15360` tapered ladder, rare-rank weights `w5={4:2,5:3,6:4,7:5}`, color 3 held flat (`w3=32*60`, V.6). Numerically: ×6 → gold = **4.688%/quadrant** (≈4.7%, exact), ×2 → 1.562%, ×5 → 3.906%; color 3 = 12.5% at every M; ladder sums to exactly 15360 (rem split across the 3 commons, color 0 absorbs `rem mod 3`). |
| **SEC-03** body in GAME_FOILPACK_MODULE, thin facade, storage appended | module `DegenerusGameFoilPackModule.sol` (new); facade stubs `DegenerusGame.sol:562-588,724-734`; storage append `Storage.sol:2394-2574`; `ContractAddresses.sol:67-69` | **MATCH** | Full foil body (buy/claim/drain/payout) lives in the new delegatecall-only module (`address(this)==GAME` guard on every external entry). Facade `purchase(...,bool foil)` + `claimFoilMatch` 4-arg stub forward only. Storage appended after `boxPlayers` (no slot move/retype). `GAME_FOILPACK_MODULE` appended last in `ContractAddresses` (shifts no other address). **EIP-170 (GAS-02): all modules `< 24,576`** — Mint 23,822 (754 free), FoilPack 10,308, Jackpot 18,396, Advance 19,203, Game 21,221, `TicketBatchStageHarness` 24,457 (119 free). |
| **PILLAR-LIVE** (foil-queue side) — no brick / no strand / no corruption; bounded gas | `_processFoilDrain` `:692-739`; `_drainFoil` `MintModule.sol:747-769`; readiness gate `AdvanceModule.sol:237-254,286-311`; `_foilDrainPending` `Storage.sol` | **MATCH** | Verified against four liveness questions (strand, brick/underflow, permanent-block, level round-trip) — all hold. Load-bearing invariant: `resolveDay ≥ dailyIdx+1 ≥ foilDrainDay` (monotone `dailyIdx`) ⇒ a buy can never land below the forward-only low-water mark (no strand, no gate bypass). Deferral guard `room < 35` is byte-identical to the `unchecked` charge `35` (no underflow). `foilCursor` makes any bucket resumable (≥15 buyers/tx at WRITES_BUDGET_SAFE=550). Drain body has no revert path; `_drainFoil` checks empty returndata before decode. The both-queues gate (`ticketQueue.length > 0 || _foilDrainPending()`) blocks the draw until foil entries are filed, and pending⇒sealed⇒drainable ⇒ never stuck true. |

**Tally: 11 / 11 MATCH · 0 DELTA · 0 UNSURE.**

Supporting empirical evidence: `forge test` — `FoilPackEV.t.sol` 4/4 PASS (EV calibration N1/N5/N15/N30),
`FoilLadderParity.t.sol` 4/4 PASS (foilCuts well-formed, hoist parity, packedTraitsFoil parity,
traitFromWordFoil parity). `forge build --sizes` clean, EIP-170 satisfied.

---

## Ranked DELTAs / risks

No correctness DELTAs were found in scope. The items below are **INFO-level observations**
(by-design choices or non-blocking notes), recorded for completeness — none is a code/design deviation.

### INFO-1 — `TicketBatchStageHarness` EIP-170 margin is thin (119 B)
- **Severity: INFO** (test harness, not a mainnet contract).
- The test harness `TicketBatchStageHarness` (which `is DegenerusGameMintModule`) sits at 24,457 / 24,576
  (119 B free). Production `DegenerusGameMintModule` is 23,822 (754 B free). This is the documented
  V.12 tradeoff (orchestrating the foil split in the facade keeps MintModule's buy path byte-identical
  to pre-foil HEAD; the harness inherits the module + adds 54 B). Both fit, but the harness has the least
  headroom of any artifact. **Suggested (do NOT apply): track this margin in the GAS-02 / 449 size oracle
  so a future MintModule edit that grows the harness past 24,576 is caught at build, not deploy.**

### INFO-2 — Spin entropy uses the claim-day word, line derivation uses the resolveDay word (by design)
- **Severity: INFO** (intended; not a deviation).
- `_payFoilTier` seeds the currency split + spin from `rngWordByDay[uint24(day)]` (the **claim/draw**
  day, `:590-597`), while `_deriveFoilLines` derives the match line from `rngWordByDay[resolveDay]`
  (the **freeze** day, `:481`). These differ across the whole-level eligibility window (`day ≥ resolveDay`).
  This is correct per design: the line is frozen at resolveDay; the payout magnitude/currency derive from
  the matched draw's own word (disjoint `FOIL_CCY_TAG`/`FOIL_SPIN_TAG` lanes). The `day > type(uint24).max`
  guard (`:449`) and the `day` truncation note (`:445-448`) correctly prevent marker aliasing. No issue.

### INFO-3 — `packedTraitsFoil` is defined but not called on the buy path (by design, V.8)
- **Severity: INFO**.
- Per V.8 the buy no longer rolls a deterministic signature, so `packedTraitsFoil` (the 4-lane buy-side
  packer) is no longer invoked by `buyFoilPack`; the drain/claim use `_deriveFoilLines` → `foilTrait`
  directly. `packedTraitsFoil` survives as a tested/documented producer (covered by `FoilLadderParity.t.sol`).
  This is the explicit V.8 edit-surface note ("`packedTraitsFoil` survives … but is no longer called by the
  buy"). Not dead-code-in-error; intentional. A gas pass (GAS-01) may flag it for removal if the test no
  longer needs the wrapper, but that is a separate axis.

### INFO-4 — Permissionless claim + keeper bounty is correctly griefing-resistant (positive note)
- **Severity: INFO** (confirmation, not a risk).
- `claimFoilMatchMany` wraps each claim in `try/catch` external self-call so one unpayable/stale tuple
  cannot poison the batch (`:391-414`); the bounty pays only per **settled** claim (`:422-430`), so a
  padded batch farms nothing. The CEI marker (`foilMatchClaimed[mk] = true` before any payout, `:504`)
  plus the `day`-truncation marker guard close the double-pay surface. Confirmed sound.

---

## Cross-cutting confirmations (in-scope, holding)

- **Frozen-producer integrity (RARE-01):** `git diff ffbd7796 HEAD -- DegenerusTraitUtils.sol` yields a
  single tail hunk; the v70-frozen `weightedColorBucket`/`traitFromWord`/`packedTraitsFromSeed` are
  byte-identical. RNG-freeze proof unaffected.
- **mint == claim invariant (FOIL-05 + RARE-03):** the drain's `_deriveFoilLines(buyer, lvl,
  rngWordByDay[resolveDay], multBps)` and the claim's identical call produce the SAME 4 lines, so the
  jackpot samples exactly what is claimable. Level round-trip holds across purchase phase, jackpot phase,
  the final-jackpot-day reroute, and the level-1 special seal (`dailyFoilDraw` lvl=1 ⇔ `_activeTicketLevel()=1`).
- **Pool conservation (FOIL-04):** `nextShare + futureShare == cost` exactly (`nextShare = cost −
  futureShare`); no rounding leak. The foil ETH spend is split into the existing pools only — no unbacked credit.
- **Storage layout (SEC-03):** all foil state appended after the v70 tail; no existing slot moved or retyped
  (to be re-attested by the 449 layout golden).

---
*VERIFY authored 2026-06-21 (447). Read-only; no contract edits. Foil-queue PILLAR-LIVE crux verified
via an isolated liveness stress pass; the remaining PILLARs (SOLV/RNG full) + RIG/MATCH are 450 scope.*
