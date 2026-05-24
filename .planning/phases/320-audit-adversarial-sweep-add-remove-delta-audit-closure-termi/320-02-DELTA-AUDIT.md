# Phase 320 — Add/Remove + OPEN-E + JGAS Delta-Audit (v46.0)

**Phase:** 320 / Plan 02 · **Authored:** 2026-05-24
**Baseline:** v45.0 closure HEAD `62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` → **subject HEAD** `30b5c89c` (contracts/+test/ byte-frozen since; planning-only commits after).
**Posture:** read-only delta audit; zero `contracts/` + zero `test/` mutation. Every cited file:line re-grep-verified against HEAD on the OPEN-E-bearing main tree (`grep -c fundingSource contracts/AfKing.sol == 21`).

---

## §1 Audit Subject + Baseline

**Subject = every v45→v46 `contracts/` commit** (`git log --oneline 62fb514b..HEAD -- contracts/`), cross-checked against the STATE.md ledger — complete, no surface omitted:

| Commit | Scope |
| --- | --- |
| `df4ef365` | feat(317) — the v46 batched ADD+REMOVE diff: do-work crank + subscription (new `AfKing.sol` keeper) + legacy AFKing/ETH-auto-rebuy removal + the JGAS jackpot-split removal. **The keeper-reconciliation + slot gap-closure (the "317-08 family") landed INSIDE this batch** — NOT as separate `contracts/` commits (verified: only `df4ef365`, `42140ceb`, `e1baa978` touch `AfKing.sol`). |
| `e4014f91` | feat(319-05) — GAS reward-peg calibration (66_528 resolve / box peg). |
| `795e679d` | fix(319-05) — CR-01 box-peg correction 137_944→71_203 (per-box marginal) + WR-01 multi-box round-trip test. |
| `42140ceb` | feat(319.1) — OPEN-E shared funding source: `subscribe()` `fundingSource` param + operator-approval routing across AfKing/Vault/sDGNRS [OPENE-01..04]. |
| `e1baa978` | feat(319.1) — WR-01 indexed `fundingSource` on `SubscriptionUpdated`. |
| `745cd63d` | test(318-01) — deploy AfKing in the fixture + pin AF_KING (test/fixture only; in the delta but not a contract behavior subject). |

Baseline anchor `62fb514b…` confirmed present; `df4ef365` + `42140ceb` confirmed present.

---

## §1.A Delta-Surface Table

Disposition confirms the landed diff matches the locked `316-SPEC.md` add+remove+JGAS design (the "intended" reference), EXCEPT the one flagged SUB-07 cancel divergence (deferred to v47.0 per 320-01).

| Surface (reqs) | Commit | Re-grepped contracts/ anchors (HEAD) | Disposition |
| --- | --- | --- | --- |
| **PROTO-01..05** (keeper gate, deity preservation) | `df4ef365` | kept `hasAnyLazyPass` gate `DegenerusGame.sol:1472`; permanent-deity bits `DegenerusGame` ctor `:222/:223` (preserved byte-unmodified per SUB-09) | NEGATIVE-VERIFIED — matches SPEC |
| **CRANK-01..04** (permissionless do-work crank) | `df4ef365` | `AfKing.sol:569` permissionless `sweep(maxCount)`; `:614` day-stamp idempotency skip; `:728` funding-skip; `DegenerusGame.sol:1687-1697` keeper-gated `batchPurchase` | NEGATIVE-VERIFIED — matches SPEC |
| **REW-01..04** (bounty = creditFlip, gas-pegged) | `df4ef365` + `e4014f91` + `795e679d` | `AfKing.sol:801` `bountyEarned = batchLen * ((BOUNTY_ETH_TARGET·PRICE_COIN_UNIT·mult)/mp)`; `:802` single `creditFlip` per tx; box peg 71_203 (per-box marginal, CR-01) | NEGATIVE-VERIFIED — matches SPEC (CR-01 faucet fix preserved) |
| **SUB-01..06,08,09** (subscribe, funding waterfall, two-tier skip-kill, charge=burnForKeeper) | `df4ef365` | `AfKing.sol:375-382` subscribe; `:438`/`:634` burnForKeeper (subscribe-time/day-31); `:728` two-tier funding-skip; `:729` exemption keys un-spoofable `player`; SUB-09 self-subscribe `DegenerusVault.sol:474` + `StakedDegenerusStonk.sol:380` (both `address(0)`=self) | NEGATIVE-VERIFIED — matches SPEC |
| **SUB-07** (lapsed/cancelled lifecycle) | `df4ef365` | `AfKing.sol:455-468` `setDailyQuantity(0)` → `:459` `_removeFromSet` swap-pop `:825-837`; NO in-sweep `dailyQuantity==0` reclaim branch | **DIVERGES from SPEC lock** — `316-SPEC.md:152` locks "external cancel moves nothing"; IMPL swap-pops immediately → **H-CANCEL-SWAP-MISS** (MEDIUM, 320-01 §8). USER-adjudicated DEFER-to-v47.0 (fix locked). v46.0 SOURCE-TREE FROZEN held. |
| **RM-01..06** (legacy AFKing mode + free ETH auto-rebuy removal) | `df4ef365` | RM kill-set grep ZERO (below); kept `hasAnyLazyPass` (PROTO-01/RM-04) is the only afKing-named survivor; ETH winnings credit to claimable (`DegenerusGameJackpotModule.sol:1275` `_addClaimableEth`) | NEGATIVE-VERIFIED — kill-set clean |
| **JGAS-01/02** (two-call jackpot-ETH split removal) | `df4ef365` | JGAS kill-set grep ZERO (below); single-call `DegenerusGameJackpotModule.sol:286/:457` `_processDailyEth`; `:210` `DAILY_ETH_MAX_WINNERS=305`; `:229` "All 305 winners (159+95+50+1) paid in a single call" | NEGATIVE-VERIFIED — single-call, no resume |
| **OPENE-01..04** (shared funding source) | `42140ceb` + `e1baa978` | `Sub.fundingSource` `:85`; sole set-point `subscribe():426`; gate `:397-403` `isOperatorApproved`+`revert NotApproved`; default-self short-circuit `:439`/`:697`; `_poolOf[src]` draw `:728`; indexed event `:160` | NEGATIVE-VERIFIED — re-attests 319.1 13/13 (320-01 SWP-OPENE) |

### RM kill-set grep (re-run at HEAD)
`grep -rnE "afKing|AFKING_|setAutoRebuy|autoRebuyState|AutoRebuyState|_processAutoRebuy|_calcAutoRebuy|settleFlipModeChange|_afKingRecyclingBonus|deactivateAfKingFromCoin|syncAfKingLazyPassFromCoin" contracts/ --include=*.sol` filtered to exclude `contracts/test`, `mocks`, and the kept `contracts/AfKing.sol`:
- **Dead legacy symbols (setAutoRebuy / autoRebuyState / _processAutoRebuy / _calcAutoRebuy / settleFlipModeChange / _afKingRecyclingBonus / deactivateAfKingFromCoin / syncAfKingLazyPassFromCoin): ZERO matches.**
- Surviving `afKing`-named refs = the NEW SUB-09 keeper wiring only: `DegenerusVault.sol` (`afKing` field + `afKing.subscribe(address(this),true,false,1,0,address(0))`) + `StakedDegenerusStonk.sol` (`afKing` field + `afKing.subscribe(address(this),true,false,1,2,address(0))`) — the ADD surface, not legacy — plus the kept `hasAnyLazyPass` (`DegenerusGame.sol:1472`). RM kill-set CLEAN.

### JGAS kill-set grep (re-run at HEAD)
`grep -rnE "SPLIT_CALL1|SPLIT_CALL2|resumeEthPool|_resumeDailyEth|STAGE_JACKPOT_ETH_RESUME|call1Bucket" contracts/ --include=*.sol` excluding `contracts/test`+`mocks`: **ZERO matches.** The two-call split + the `resumeEthPool` carry are fully removed.

---

## §2 Composition Attestations

### (a) ADD × REMOVE compose cleanly
- **ETH winnings always credit to `claimable`** — no ticket-conversion interception left by the removed auto-rebuy. `DegenerusGameJackpotModule.sol:1275` (`_addClaimableEth` per ETH winner) + `:723` (`claimablePool += claimableDelta`). The `claimablePool == Σ claimableWinnings` aggregate liability (`:39`) stays balanced. Cross-ref 318-05 RngFreezeAndRemovalProofs (deterministic-no-VRF-word-credit). NEGATIVE-VERIFIED.
- **BURNIE flip-autorebuy = flat 75bps unconditional** (KEPT @75bps; no deity/activity scaling, no under/over-credit). Cross-ref 320-01 SWP-REMOVE.B + economic-analyst SWP-REMOVE.B (`BurnieCoinflip.sol` `RECYCLE_BONUS_BPS=75`, floor-rounded). NEGATIVE-VERIFIED.
- **`_hasAnyLazyPass` is the ONLY retained afKing-named symbol** (PROTO-01/RM-04 keeper gate, `DegenerusGame.sol:1472`); all legacy auto-rebuy machinery removed (RM grep ZERO). NEGATIVE-VERIFIED.
- No orphaned/double-credited winnings: the do-work crank reward path (`creditFlip` bounty) + the subscription claimable-read path do NOT collide with the removed ETH-auto-rebuy interception (cross-ref 320-01 SWP-COMPOSE — CEI debit `AfKing.sol:750` before `batchPurchase`, day-stamp after). NEGATIVE-VERIFIED.

### (b) JGAS daily-ETH single-call composition
The daily ETH jackpot completes in ONE `advanceGame` stage at the 305-winner ceiling (buckets 159/95/50/1, `DegenerusGameJackpotModule.sol:209-210/:229`) with **NO resume stage entered** and **NOTHING stranded by the dropped `resumeEthPool` carry** (JGAS kill-set ZERO). Conservation `sum(claimable) + whale-pass == paidWei ≤ pool` re-attested from 318-06 JackpotSingleCallCorrectness (305 emissions, per-bucket exact share, single-call fully resolves with no resume carry). The split-removal delta composes cleanly with the RM-02 ETH-auto-rebuy removal — both touch the daily-ETH payout; together they leave a single-call, claimable-crediting path with no orphan. NEGATIVE-VERIFIED.

### (c) OPEN-E default-self equivalence (`fundingSource == 0`)
`fundingSource == 0` (self) short-circuits the approval read and resolves `src = subscriber/player` at `AfKing.sol:439` (subscribe-time) / `:697` (ETH draw), SLOADing the **same single `_poolOf` slot** at `:728` as pre-OPEN-E (per-draw gas unchanged, behavior-identical). The two SUB-09 protocol callers both pass `address(0)` = self (`DegenerusVault.sol:474`, `StakedDegenerusStonk.sol:380`). **No cross-account spend is possible without `isOperatorApproved(S,M)` consent checked AT `subscribe()` ONLY** — the `:397-403` gate (`fundingSource != 0 && fundingSource != subscriber && !isOperatorApproved(...) → revert NotApproved`) is the sole, subscribe-only authorization (never per-draw, never at day-31 renewal). Re-attests 319.1 VERIFICATION 13/13 + 320-01 SWP-OPENE.1/.2. NEGATIVE-VERIFIED (default-self byte-identical).

---

## §3 Forward-cite for FINDINGS-v46.0.md §3 (Plan 04)
`<FINDINGS-v46.0-§3-DELTA-CROSS-CITE-PLACEHOLDER>` — Plan 04 consolidates this delta-surface table + the three composition attestations into `audit/FINDINGS-v46.0.md` §3. The SUB-07 divergence row carries forward as the FINDINGS record of H-CANCEL-SWAP-MISS (deferred-to-v47.0).

---

*Delta-audit authored 2026-05-24 on the OPEN-E-bearing main tree. RM + JGAS kill sets grep-clean (ZERO); OPEN-E default-self behavior-identical; daily ETH jackpot single-call at the 305 ceiling. Every surface matches the 316-SPEC lock except SUB-07 (H-CANCEL-SWAP-MISS, deferred v47.0). Zero contracts/+test/ mutation.*
