# Phase 265 Plan 01 — Adversarial Validation Log

**Phase:** 265-delta-audit-findings-consolidation
**Plan:** 265-01
**Target:** `audit/FINDINGS-v35.0.md` §4 6-surface draft (a-f) + STAT-03 reframe row
**Methodology:** D-265-ADVERSARIAL-01..03 (parallel `/contract-auditor` + `/zero-day-hunter` spawn AFTER finished §4 draft; NOT `/economic-analyst`, NOT `/degen-skeptic`)
**Spawned:** 2026-05-09

## /contract-auditor

Adversarial review of the v35.0 per-pull-level resample helper `_awardDailyCoinToTraitWinners` in `contracts/modules/DegenerusGameJackpotModule.sol` (live at L1758-1844 in HEAD `5db8682b`) against the §4 6-surface sweep and STAT-03 reframe row in `audit/FINDINGS-v35.0.md`. Methodology: read the helper body line-by-line; trace each surface to its concrete code-path; attempt to construct a counterexample for each verdict.

### Per-row verdicts

- **Surface (a) — Predictability / trait-stacking pre-call attempts: AGREE — SAFE_BY_DESIGN.**
  The per-pull level keccak at L1794-1796 reads `keccak256(abi.encode(randomWord, COIN_LEVEL_TAG, i))` where `randomWord` is the VRF-fulfillment word delivered into `payDailyCoinJackpot`/`payDailyJackpotCoinAndTickets`. The VRF request is committed at the prior `advanceGame` step before holder snapshots can shift; mid-request purchases land in the next day's bucket per the standard Degenerus daily-cycle invariant carried from v25 onward. STAT-01 chi² over 10K aggregated samples (range=4 chi²=5.114 < 7.815 critical at α=0.05 df=3; range=8 chi²=3.019 < 14.067 df=7) confirms uniform `lvlPrime` distribution empirically. No frontrunnable mempool window: the helper executes inside the VRF callback which is dispatched by Chainlink's coordinator — players cannot interpose between fulfillment and `_awardDailyCoinToTraitWinners` invocation.

- **Surface (b) — Level-salt collision between the two near-future BURNIE callers: AGREE — SAFE_BY_DESIGN, with explicit-acknowledgment note.**
  `COIN_LEVEL_TAG = keccak256("coin-level")` (L171) is shared between the two callers. The §4 prose's primary discriminator argument cites "cross-call distinct `randomWord` per VRF day-cycle" — this holds for cross-day calls. **Same-call observation (worth being explicit about):** if the lifecycle ever fires both stage 6 (`payDailyCoinJackpot`, L1710) and stage 9 (`payDailyJackpotCoinAndTickets`, L595) inside a single `advanceGame` invocation, both consume the same `randomWord`. The keccak `keccak256(randomWord, COIN_LEVEL_TAG, i)` would produce identical hash sequences for matching `i`. However, the `(minLevel, range)` bounds passed by each caller differ: stage 6 uses player-determined bounds, stage 9 uses `(lvl+1, lvl+4)` with `range = 4`. Distinct `(minLevel, range)` ⇒ distinct `lvlPrime` sequences. Even where `lvlPrime` happens to coincide for a given `i`, the holder-index keccak at L1816-1818 is `keccak256(randomWord, trait_i, lvlPrime, i)` — same inputs ⇒ same `holderIdx` ⇒ same winner gets paid out from each prize stream, which is a benign duplicate-eligibility property (not a salt collision in the security sense; both streams are funded from independent `coinBudget` allocations). No exploitable collision; **AGREE with §4 verdict** — but note this is worth surfacing in any future reviewer's mental model so the verdict isn't mistaken for "callers are fully decorrelated", which they aren't within a same-VRF-cycle call.

- **Surface (c) — Deity-cache staleness across pulls: AGREE — SAFE_BY_STRUCTURAL_CLOSURE.**
  Loop entry at L1775-1783 caches `deityBySymbol[fullSymId]` into `address[4] memory deityCache` with 4 SLOADs (one per trait). Subsequent reads at L1800 are pure memory loads. Cannot stale: (i) deity slots only mutate via separate admin paths NOT reachable inside `advanceGame`'s call stack; (ii) the 50-pull loop is atomic — no re-entry hooks (helper has no external `call`s except `coinflip.creditFlip` which is a trusted internal-protocol `creditFlip` to `BurnieCoinflip` gated by `onlyGame`; that contract does not call back into the JackpotModule's deity-write paths). Concrete attack test: I considered "what if `coinflip.creditFlip` triggers a callback that writes to `deityBySymbol`?" — the `BurnieCoinflip.creditFlip` function is a pure ledger-write to coinflip state (no external calls back to JackpotModule); even if it did, the deity-write paths are gated by separate admin-only modifiers. No path constructed.

- **Surface (d) — Cross-caller `_randTraitTicket` salt collision: AGREE — SAFE_BY_STRUCTURAL_CLOSURE.**
  Phase 264 SURF-01 grep-proof confirms `_randTraitTicket` body L1653-1703 + 4 other callers L700/L989/L1296/L1399 byte-identical. The coin-jackpot caller no longer uses `_randTraitTicket` — it uses inline `keccak256(abi.encode(randomWord, trait_i, lvlPrime, i))` at L1816-1818. The four preserved `_randTraitTicket` callers each pass caller-distinct `salt` values; the inline coin-jackpot keccak uses `(trait_i, lvlPrime, i)` as discriminators. No collision possible because the function-domain is fully partitioned: `_randTraitTicket(randomWord, salt)` vs inline `keccak256(randomWord, trait_i, lvlPrime, i)` have different argument types AND different byte-encodings under `abi.encode`. Verified by reading `_randTraitTicket` body — it uses `keccak256(abi.encode(randomWord, salt))` with `uint256 salt` as the second arg; the inline coin-jackpot keccak passes `(trait_i, lvlPrime, i)` as a 3-tuple — encodings cannot coincide.

- **Surface (e) — Off-chain indexer semantic-shift attack surface: AGREE — SAFE_BY_DESIGN.**
  Event signature byte-identical at L96 (`event JackpotBurnieWin(address winner, uint24 lvl, uint8 traitId, uint256 amount, uint256 ticketIdx)`). Only the runtime semantics of `lvl` shift from call-constant to per-pull-sampled. The shift is observability-only — no on-chain state machine consults aggregated `lvl` summaries; no oracle, no governance vote, no reward calculation depends on the post-emit `lvl` interpretation. AUDIT-06 §3c disclosure prose + §6b D-09 PASS row + KNOWN-ISSUES.md +1 entry are the appropriate disclosure venue for this observability shift. No exploitable surface.

- **Surface (f) — Gas-griefing via repeated cold SLOAD: AGREE — SAFE_BY_DESIGN.**
  Per-pull body at L1798-1842 reads `traitBurnTicket[lvlPrime][trait_i]` at L1798 — this is the cold-SLOAD candidate. With 50 pulls across up to 16 distinct `(lvl', trait_i)` cells, EIP-2929 cold-SLOAD warming after the first ~16 distinct slots gives realistic worst case 16×2100 + 34×100 = ~37K, plus per-pull body work 1.5-2.2K × 50 = 75-110K. Phase 264 SURF-05 pinned `PAY_DAILY_COIN_JACKPOT_GAS_REF = 2,860,535` with `PER_CALL_GAS_DELTA_BOUND = 120K`. AdvanceGame measured 9.42× margin above 1.99× ceiling at HEAD `cf564816`. No griefing surface: a player cannot influence `lvlPrime` selection (VRF-derived) to force pessimal slot diversity; `i % 4` trait rotation is deterministic. The 50-pull cap is hard-bounded by `DAILY_COIN_MAX_WINNERS` constant (L228 / L1766). Helper is `private` — no external invocation path exists.

- **STAT-03 reframe row — Empty-bucket skip behavior on sparse holder-density fixtures: AGREE — SAFE_BY_STRUCTURAL_CLOSURE per D-265-STAT03-01.**
  Empty-bucket silent-skip at L1807-1814 (`if (effectiveLen == 0) { ++i; ++cursor; if (cursor == cap) cursor = 0; continue; }`) is structural-by-design per Phase 263 PPL-05. The cursor still advances on skip — preserving share-math determinism across skips (the `extra` remainder distribution at L1830-1832 still allocates the +1 wei correctly to the next non-skipped pull whose `cursor < extra`). Phase 264 D-IMPL-01 deity-fixture empirically proves 50/50 emit count under deity-backed dense conditions across 3 fixed seeds — the helper distributes the full `coinBudget` when holder density is non-empty across all `(lvl', trait_i)` cells. The natural-lifecycle 88.24% skip rate measured by `test/stat/PerPullEmptyBucketSkip.test.js` reflects the test fixture's holder density (~64 vault tickets distributed across 16 cells = ~75% empty cells expected, observed ~88% post-PRNG variance) — NOT a protocol behavior under production-real conditions. Reframe is technically sound; STAT-03 is fixture-calibration, not a finding.

### 7th-surface novel composition candidates investigated

- **Helper composition with daily-advance bounty (`AdvanceModule._payAdvanceBounty`):** Hunted for any path where the helper's per-pull payouts could affect or be affected by the advance bounty. The bounty is a fixed escalating ETH transfer to the `advanceGame` caller; the per-pull-level helper distributes BURNIE only. No state-shared dependency. **No surface found.**

- **Helper composition with game-over fallback (`_gameOverEntropy` / 14-day prevrandao admixture):** Hunted for any path where game-over could fire WHILE the helper is mid-execution. Helper runs atomically inside `advanceGame`; `_gameOverEntropy` is invoked by a separate advanceGame branch. The two are not nested. Game-over substitutes the daily VRF word with a prevrandao-admixed entropy on a separate code path — the per-pull-level helper would consume that substituted word like any other randomWord; the keccak chain still produces uniform per-pull bits. KI EXC-02/EXC-04 carry-forward holds. **No surface found.**

- **Helper composition with cross-day RNG-word reuse via VRF stall + backfill:** During the `_backfillGapDays` cap-of-120 path, gap-day RNG words are derived as `keccak256(vrfWord, gapDay)`. If multiple gap days each invoke the helper, each gets a distinct backfilled `randomWord` — no reuse. Even in the worst case where backfill exhausts the 120-day cap and leaves residual gap days unresolved, the unresolved days simply skip BURNIE distribution (the standard `skip-unresolved` BurnieCoinflip handling) — no helper invocation, no exploit. **No surface found.**

- **Stage 6 vs stage 9 same-call randomWord reuse (covered under Surface (b) explicit-acknowledgment):** The two callers can share the same `randomWord` within a single `advanceGame` execution. Distinct `(minLevel, range)` bounds + benign duplicate-eligibility property (same winner getting paid from two separate budgets is by design). **No new finding; explicit acknowledgment added to Surface (b) verdict above.**

### Concrete code-path counterexample audit

- Re-derived the helper from L1758 to L1844; mapped every `if`/`continue`/`unchecked` branch. The empty-bucket cursor-advance at L1808-1812 correctly preserves the `extra` remainder distribution across skips. The deity-cache `address(0)` check at L1802 + `winner != address(0)` check at L1834 correctly handle the no-deity case (no virtualCount allocation, no synthetic winner). The `idx < len` branch at L1821-1827 correctly assigns `ticketIdx = type(uint256).max` for deity wins (sentinel value off-chain indexers can detect). No silent miscount, no off-by-one in the cursor wraparound at L1810-1811 (cursor wraps to 0 on `cap`, preserving the share-math). **No counterexample found.**

### Final verdict

7 of 7 row verdicts AGREE. Zero F-35-NN finding-candidates. One non-finding observation worth surfacing (Surface (b) same-VRF-cycle randomWord reuse between stages 6 and 9 — benign but explicit acknowledgment recommended in any future reviewer's mental model; already noted inline above). Default §4 verdict roll-up holds: `7 of 7 SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE`.

## /zero-day-hunter

Adversarial novel-surface hunt against the v35.0 per-pull-level resample helper. Per skill mandate: ignore previously-audited vectors (gas, RNG, reentrancy, MEV, admin, economic basics). Hunt for creative composition-based attack surfaces the §4 6-surface sweep may have missed.

### Investigated novel attack hypotheses

- **Hypothesis 1: Deity-pass purchase timing window.** Could a player buy a deity pass for a specific symbol BETWEEN the VRF request and VRF fulfillment, thereby inserting themselves into `deityCache[traitIds[i%4]]` for the upcoming helper call?
  - **Investigation:** Read `deityBySymbol` write paths. Deity assignment writes are gated by separate `purchaseDeityPass` / admin functions, all of which run during the PURCHASE phase (`jackpotPhaseFlag == false`). The helper runs during the JACKPOT phase (`jackpotPhaseFlag == true`) inside the VRF callback. The state-machine transition to JACKPOT phase happens via `advanceGame` AT VRF REQUEST TIME — meaning by the time the helper's deity cache reads `deityBySymbol`, the day's deity assignments are already locked because no PURCHASE-phase writes can land between request and fulfillment. Even if a deity-pass purchase landed in the same block as VRF request, the state-machine ordering ensures it lands BEFORE the request, becoming part of the snapshot.
  - **Why this fails:** Phase ordering invariant — deity assignment is locked at the VRF-request boundary, not the VRF-fulfillment boundary. The cache read at L1780 reflects the locked state.
  - **Mechanism strength:** Robust — depends on the protocol-wide invariant that no PURCHASE-phase mutations land during the JACKPOT phase. This invariant is enforced at every external entry point via `whenPurchase`/`whenJackpot` modifiers. Would only break if a future change introduced a mid-jackpot deity-write path — flag for any future code review touching `deityBySymbol` writes.

- **Hypothesis 2: `traitBurnTicket[lvlPrime][trait_i]` mid-call mutation via cross-module callback.** The helper reads holder arrays at L1798. Could `coinflip.creditFlip(winner, amount)` at L1842 trigger a callback path that writes to `traitBurnTicket`?
  - **Investigation:** Read `BurnieCoinflip.creditFlip` and `creditFlipBatch`. Both are pure ledger-write functions (`onlyGame` modifier; updates `_balances` mapping; no external calls back to JackpotModule). Even hypothetically: `traitBurnTicket` writes are gated by `onlyMintModule` / `onlyGame` modifiers in MintModule, not reachable from BurnieCoinflip's call frame.
  - **Why this fails:** No callback path exists. The only external call inside the helper loop is `coinflip.creditFlip` which is a leaf write.
  - **Mechanism strength:** Robust — depends on `BurnieCoinflip` not adding hooks. Defensive note: any future addition of post-creditFlip hooks (e.g., for analytics, governance, or referral systems) would need to verify no path back to `traitBurnTicket` writes.

- **Hypothesis 3: `effectiveLen` integer-overflow via huge `len`.** Could `traitBurnTicket[lvlPrime][trait_i].length` grow large enough that `len + virtualCount` overflows? Or `virtualCount = len / 50` produce an exploitable value?
  - **Investigation:** `holders.length` is a `uint256` (Solidity default array length type). Practical bound: every entry is a `address` (20 bytes); even at 2^160 ticket-purchase events, the array would consume 2^165 bytes of storage — physically impossible. `virtualCount = len / 50` clamped to `>= 2` when deity present — bounded above by `len`. `effectiveLen = len + virtualCount` — bounded by `len + len/50 < 2*len`, no overflow possible at any practical state size.
  - **Why this fails:** Overflow physically impossible at storage scale; the modulo at L1818 (`% effectiveLen`) gives uniform `idx` even at large `effectiveLen`; the deity-payout branch at L1825 simply pays the cached deity address (no per-ticket lookup).
  - **Mechanism strength:** Robust — Solidity 0.8.x checked arithmetic + physical storage bounds. No exploit.

- **Hypothesis 4: `cap` arithmetic edge case.** L1766-1767: `uint16 cap = DAILY_COIN_MAX_WINNERS; if (cap > coinBudget) cap = uint16(coinBudget);`. What if `coinBudget == 0` (early return at L1765 — no helper execution, no harm). What if `coinBudget == 1`? Then `cap = 1`, `baseAmount = 1`, `extra = 0`, `cursor = randomWord % 1 = 0`. Loop iterates once. Deterministic single-pull payout of 1 unit. Boring.
  - **What about `coinBudget = 50`?** `cap = 50`, `baseAmount = 1`, `extra = 0`, every pull gets exactly 1 unit. Boring.
  - **What about `coinBudget = 49`?** `cap = 49` (since `cap > coinBudget`), `baseAmount = 1`, `extra = 0`, every pull gets 1 unit. Boring.
  - **What about `coinBudget = 51`?** `cap = 50`, `baseAmount = 1`, `extra = 1`, cursor = `randomWord % 50` selects which pull gets the +1. Boring.
  - **No exploit found.** Cap arithmetic is correct across boundary values.

- **Hypothesis 5: Lifecycle stage 6 vs stage 9 ordering exploit.** If both stages 6 and 9 fire inside a single `advanceGame` call, both consume the same `randomWord`. Could a player exploit the deterministic `randomWord` reuse to predict the second call's outcomes once the first call's events emit?
  - **Investigation:** Even if the player can OBSERVE stage 6 outputs and predict stage 9 outputs deterministically (which they can — same `randomWord`, computable outputs given known holder arrays), they cannot ACT on that prediction because both stages execute atomically within the same transaction. There is no inter-stage window in which the player can buy a ticket, alter holder arrays, or interpose any state mutation. The helper completes both invocations before returning control to any external party.
  - **Why this fails:** Atomic execution forecloses the action window. Same-call randomWord-reuse is benign because the player has zero opportunity to act on it.
  - **Mechanism strength:** Robust — depends on `advanceGame` running the lifecycle stages atomically, which it does by construction (single function call, no external mutation points between stage transitions).

- **Hypothesis 6: `_pickSoloQuadrant` interaction.** The §4 sweep doesn't directly address whether the per-pull-level helper interacts with the v34 gold-solo-priority injection. Could a same-call invocation of `_pickSoloQuadrant` (used by ETH jackpot path) influence the BURNIE coin-jackpot helper's outcomes?
  - **Investigation:** Read both code paths. `_pickSoloQuadrant` is invoked by the ETH-jackpot distribution path (`_distributeTicketJackpot`, `_pickSoloQuadrant` at L287/L454/L531/L1181). The BURNIE coin-jackpot helper `_awardDailyCoinToTraitWinners` is a separate code path with no cross-data-flow into `_pickSoloQuadrant`. The two share `randomWord` at the call-tree root but consume it via independent keccak chains (`COIN_LEVEL_TAG` for the BURNIE side; `_pickSoloQuadrant` uses a different effectiveEntropy derivation). No state crosstalk.
  - **Why this fails:** Independent keccak chains; no shared mutable state; both consume `randomWord` as a read-only input.

- **Hypothesis 7: `JackpotBurnieWin.lvl` field re-use as off-chain attack vector.** Could an indexer or analytics tool that legacy-aggregates by `lvl` produce misleading data that influences a downstream on-chain action (e.g., a governance vote, a price oracle, a quest-completion check)?
  - **Investigation:** Searched the protocol for any on-chain consumer of `JackpotBurnieWin.lvl` aggregations. None exist on-chain — `JackpotBurnieWin` is an emit-only event with no on-chain consumer (no governance vote, oracle, or contract reads `lvl`-aggregated data back into state). All consumers are off-chain.
  - **Why this fails:** No on-chain path consumes the indexer's interpretation. AUDIT-06 §3c disclosure correctly scopes this as observability-only.

### Final verdict

**No new surfaces found — §4 6-surface enumeration appears exhaustive for the v35 delta scope.**

7 hypotheses investigated against the helper's composition surface; all fail by structural or invariant-protected mechanisms. Zero novel candidates surfaced. Two defensive notes for any future-code-review reviewer:

1. **Defensive note (Hypothesis 1):** If a future change adds a mid-jackpot deity-write path, the deity-cache freshness invariant Surface (c) relies on would weaken. Flag any `deityBySymbol` writer change in future audits.
2. **Defensive note (Hypothesis 2):** If `BurnieCoinflip.creditFlip` ever gains post-write hooks (e.g., for analytics or referral routing), audit those hooks for any path back to `traitBurnTicket` writes — Surface (c) deity-cache + helper-internal `traitBurnTicket` reads at L1798 depend on no such callback existing.

Both defensive notes are FORWARD-LOOKING — they don't constitute findings against v35.0 HEAD; they're flag-for-future-audits guards. Default §4 verdict roll-up holds: `7 of 7 SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE`.

Concrete attack-narrative: NOT FOUND. Zero exploitable composition surfaces against the v35 per-pull-level resample helper at HEAD `5db8682b`.

## Disposition

Both `/contract-auditor` and `/zero-day-hunter` validated all 7 §4 rows AGREE; **zero disagreements**.

- `/contract-auditor` produced one non-finding observation (Surface (b) same-VRF-cycle randomWord reuse between stages 6 and 9 — benign by atomic-execution argument; explicit acknowledgment in the auditor's verdict prose; does NOT alter the SAFE_BY_DESIGN verdict).
- `/zero-day-hunter` investigated 7 novel hypotheses; all fail by structural/invariant mechanisms; "no new surfaces found" is the honest verdict. Two forward-looking defensive notes captured for future-audit-reviewer awareness (NOT findings against v35.0 HEAD).

Default §4 verdict roll-up holds: **7 of 7 rows SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE**. Zero F-35-NN finding blocks emit. Per `feedback_wait_for_approval.md`: zero disagreements means no user-disposition gate trips; proceeding to Task 8 (§3e AUDIT-03 conservation re-proof) without §4 modifications.

KNOWN-ISSUES.md still receives 1 entry under Design Decisions for the AUDIT-06 indexer semantic-shift (PRE-DECIDED in §3c + §6b D-09 PASS row, NOT triggered by adversarial-pass disposition). Closure verdict string at §6c remains `1 of 1 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_MODIFIED (1 entry added under Design Decisions)`.
