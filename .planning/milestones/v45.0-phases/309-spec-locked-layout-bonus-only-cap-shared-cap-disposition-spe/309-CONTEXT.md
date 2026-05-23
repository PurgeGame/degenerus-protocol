# Phase 309: SPEC — Locked Layout + Bonus-Only Cap + Shared-Cap Disposition (SPEC) - Context

**Gathered:** 2026-05-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Produce `.planning/phases/309-*/309-SPEC.md` that LOCKS the v45.0 design BEFORE any
contract change, covering SPEC-01..04 (packed-slot layout, bonus-only cap semantics,
allocation-time tally + open-time application, shared-cap disposition). Every cited
`file:line` across the 4 touched contracts is grep-verified against contract HEAD per
`feedback_verify_call_graph_against_source` — no "by construction" / "single fn reaches
all paths" claims. **Zero `contracts/` mutations and zero `test/` mutations** in this
phase: SPEC produces a planning artifact only.

The underlying v45.0 design is LOCKED in `.planning/REQUIREMENTS.md` (SPEC-01..04) +
`.planning/v45-lootbox-evcap-fix-plan.md`. This discussion did NOT redesign it — it
resolved the genuinely-open sub-decisions inside the locked design and one direct
conflict between the two source docs.

</domain>

<decisions>
## Implementation Decisions

### SPEC-01 — Packed-slot layout

- **D-01 (width — resolves a doc conflict):** `adjustedPortion` is **`uint64`**, NOT
  `uint96`. REQUIREMENTS.md SPEC-01 says `uint64`; the v45 fix-plan said `uint96`; the
  SPEC locks `uint64` and treats the fix-plan's `uint96` as superseded. Rationale:
  `adjustedPortion ≤ LOOTBOX_EV_BENEFIT_CAP = 10 ETH = 1e19 wei`; `ceil(log2(1e19)) = 64`
  so 64 bits is the minimum that holds it, and `uint64` max ≈ 18.44 ETH gives ~84%
  headroom. A single box's accumulated `adjustedPortion` can never exceed the cap (each
  `add = min(deposit, remaining)` advances `used`). Tightest standard width → matches
  `feedback_maximal_variable_packing` + the REQUIREMENTS.md "tightest field widths" gas
  directive.

- **D-02 (co-pack — baseLevel folded in):** The packed word merges the base level too.
  Final `uint256` layout:
  - `[0:16]`    `score + 1`   (`uint16`, 0 = unset)
  - `[16:80]`   `adjustedPortion` (`uint64`, ≤ 10 ETH)
  - `[80:104]`  `baseLevel + 1` (`uint24`, 0 = unset)
  - `[104:256]` free (152 bits)

  This **removes the separate `lootboxBaseLevelPacked` slot entirely** (declared at
  `Storage.sol:1374-1375`), merging it into the new word → **net −1 storage slot per
  (index, player) box** (on top of the score slot already counting as no-new-slot since
  the old `uint16` occupied a full slot). Chosen per the explicit maximal-packing gas
  directive: `baseLevel` shares the exact `(uint48 index => address)` key, has an
  identical lifecycle (written once at first deposit, read + cleared at open), all its
  sites live inside the 4 in-scope files, it is NOT a seed input, and the deposit-time
  `adjustedPortion` accumulation already read-modify-writes the word so folding level in
  adds zero deposit-path cost.

- **D-03 (co-pack — lootboxDay REJECTED, locked):** `lootboxDay` (`uint32`,
  `Storage.sol:1370`) shares the same key shape but is **excluded** from the packed word.
  It is read at `LootboxModule.sol:528/616` and feeds the frozen roll seed
  `keccak256(abi.encode(rngWord, player, day, amount))` at `:545`. Co-packing it would
  perturb a seed-input read path — forbidden by **INV-04 / IMPL-05** (seed/roll
  byte-identical). The SPEC documents this as an evaluated-and-rejected candidate with
  this reason.

- **D-04 (no other cap-bounded co-pack):** Per SPEC-01's literal scope (cap-bounded
  per-box fields), the only other cap-bounded field is `lootboxEvBenefitUsedByLevel`,
  keyed `(player, level)` — wrong key shape for an `(index, player)` slot — so it cannot
  co-pack. SPEC records the negative finding explicitly. (`baseLevel` in D-02 is an
  opportunistic non-cap-bounded co-pack the user opted into beyond SPEC-01's literal ask.)

- **D-05 (rename — locked):** Rename `lootboxEvScorePacked → `**`lootboxPurchasePacked`**
  (`mapping(uint48 => mapping(address => uint256))`). The word is no longer EV-only
  (it carries the base level too), so a neutral "purchase-time packed state" name is the
  accurate description of what IS, per the `feedback_no_history_in_comments` spirit. This
  single mapping **replaces both** `lootboxEvScorePacked` and `lootboxBaseLevelPacked`.

- **D-06 (helper signatures — locked):**
  `_packLootboxPurchase(uint16 scorePlus1, uint64 adj, uint24 baseLevelPlus1) → uint256`
  and `_unpackLootboxPurchase(uint256) → (uint16 scorePlus1, uint64 adj, uint24
  baseLevelPlus1)`.

- **D-07 (no new slot attestation):** SPEC must explicitly attest no NEW storage slot is
  introduced — mapping values never cross-pack and the old `uint16` already occupied a
  full slot; the change is net −1 slot via the `baseLevel` merge. Zero-at-open clears all
  three fields in a single SSTORE of the whole word.

### SPEC-02 — Bonus-only cap (carried from REQUIREMENTS, no new decision)

- **D-08:** In `_applyEvMultiplierWithCap` (`LootboxModule.sol:475`), replace the
  `== LOOTBOX_EV_NEUTRAL_BPS` early return with `<= LOOTBOX_EV_NEUTRAL_BPS` →
  `return (amount * evMultiplierBps) / 10_000` (penalty or neutral applies in full, never
  consumes the cap). Only `> NEUTRAL` draws the cap. Applies to all three callers
  (`openLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`). Verbatim from
  REQUIREMENTS.md SPEC-02 + fix-plan Change 1.

### SPEC-03 — Allocation tally + open-time application (carried; only width was open)

- **D-09:** Per-deposit tally rule (frozen multiplier from first-deposit score):
  `mult <= NEUTRAL` → store `score+1` only, no cap draw; `mult > NEUTRAL` →
  `add = min(deposit, CAP - lootboxEvBenefitUsedByLevel[player][lvl])`, advance the used
  accumulator, accumulate `adjustedPortion`. First deposit writes `score+1` (and now
  `baseLevel+1` per D-02); later deposits accumulate `adjustedPortion` only via
  read-modify-write of the packed word. `openLootBox` applies
  `scaled = mult <= NEUTRAL ? amount*mult/1e4 : adj*mult/1e4 + (amount - adj)` with **no
  cap SLOAD/SSTORE**; zero-at-open clears the whole packed slot. Verbatim from SPEC-03
  except `adjustedPortion` width now locked to `uint64` (D-01).

### SPEC-04 — Shared-cap disposition

- **D-10 (ACCEPT + document — locked):** `resolveLootboxDirect` (decimator/degenerette)
  and `resolveRedemptionLootbox` (redemption) keep consuming the shared per-(player,
  level) cap at resolution via `_applyEvMultiplierWithCap` (Change 1 only; no purchase
  point). Disposition = **ACCEPT**, backed by a rigorous word-independence backward-trace
  per `feedback_rng_backward_trace` (NOT a "by construction" assertion):
  1. `evMultiplierBps = _lootboxEvMultiplierFromScore(activityScore)` derives from the
     **frozen** `activityScore` parameter (decimator = bucket-at-burn, degenerette =
     bet-time, redemption = burn-submission snapshot), **not** from `rngWord`. Verified at
     `LootboxModule.sol:674` and `:710`.
  2. The seed uses raw `amount` (`:671/:707`), so cap allocation never changes any roll
     (IMPL-05 / INV-04).
  3. Purchased boxes now allocate the cap pre-word at purchase, so they do not compete at
     resolution.
  4. The only residual freedom is resolution-ORDER cap-steering among on-the-fly bonus
     boxes — but since multipliers are frozen, steering the scarce cap to the highest-mult
     box is optimal regardless of the word. Knowing `rngWord` yields no extra gain → not a
     freeze violation; classified as already-accepted self-MEV (REQUIREMENTS.md
     Out-of-Scope "Accepted self-MEV races").
- **D-11 (SLOAD enumeration required):** Per `feedback_rng_window_storage_read_freshness`,
  the SPEC must enumerate ALL SLOADs inside the `[rng request, unlock]` window for all
  three callers and confirm `lootboxEvBenefitUsedByLevel[player][currentLevel]` is the only
  shared mutable consumed alongside the word — not just assert it.

### Claude's Discretion

None — every gray area was decided by the user. (The four AskUserQuestion decisions:
`uint64` width, co-pack baseLevel, rename to `lootboxPurchasePacked`, accept+document
SPEC-04.)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner, SPEC executor) MUST read these before planning or writing the SPEC.**

### v45.0 locked design (load-bearing)
- `.planning/REQUIREMENTS.md` — SPEC-01..04 locked decisions, IMPL-01..05, INV-01..06,
  the v45.0 goal, the gas directive, and the Out-of-Scope list (incl. accepted self-MEV).
- `.planning/v45-lootbox-evcap-fix-plan.md` — Change 1 (bonus-only cap) + Change 2
  (purchase-time tally + packing), wrinkles/decisions, files-touched, verification
  checklist. NOTE: its `uint96` width and its EV-only packing layout are SUPERSEDED by
  D-01/D-02/D-05 here (`uint64`; word also carries `baseLevel`; renamed
  `lootboxPurchasePacked`).
- `.planning/STATE.md` — milestone framing, audit baseline
  `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`, commit-policy posture.
- `.planning/ROADMAP.md` §Phase 309 — the 5 success criteria the SPEC must satisfy.

### Contract HEAD sites to grep-verify (baseline `MILESTONE_V44_AT_HEAD_6f0ba296…`)
- `contracts/storage/DegenerusGameStorage.sol:1370` — `lootboxDay` (uint32; co-pack
  REJECTED, D-03).
- `contracts/storage/DegenerusGameStorage.sol:1374-1375` — `lootboxBaseLevelPacked`
  (uint24; REMOVED/merged, D-02).
- `contracts/storage/DegenerusGameStorage.sol:1379` — `lootboxEvScorePacked` (uint16;
  widened to uint256 + renamed `lootboxPurchasePacked`, D-05).
- `contracts/storage/DegenerusGameStorage.sol:1427-1428` — `lootboxEvBenefitUsedByLevel`
  (the shared cap accumulator; keyed `(player, level)`).
- `contracts/modules/DegenerusGameLootboxModule.sol:308-314` — `LOOTBOX_EV_MIN/NEUTRAL/MAX_BPS`
  (8000/10000/13500) + `LOOTBOX_EV_BENEFIT_CAP` (10 ether).
- `contracts/modules/DegenerusGameLootboxModule.sol:475-509` — `_applyEvMultiplierWithCap`
  (Change 1 site, SPEC-02).
- `contracts/modules/DegenerusGameLootboxModule.sol:517` — `openLootBox` (frozen-apply
  site; reads score/level/adj from packed word; zero-at-open).
- `contracts/modules/DegenerusGameLootboxModule.sol:559/675/711` — the three
  `_applyEvMultiplierWithCap` call sites (open / resolveLootboxDirect / resolveRedemptionLootbox).
- `contracts/modules/DegenerusGameLootboxModule.sol:528/541/545/570/616` — `lootboxDay`
  read + seed build + `lootboxBaseLevelPacked` read/clear (freeze-sensitive zone).
- `contracts/modules/DegenerusGameLootboxModule.sol:666/702` — `resolveLootboxDirect` +
  `resolveRedemptionLootbox` (frozen-`activityScore` multiplier source, SPEC-04).
- `contracts/modules/DegenerusGameMintModule.sol:987-992/1013/1155` — purchased-box deposit
  tally sites (first-deposit + subsequent) + `lootboxDay`/`lootboxBaseLevelPacked` writes.
- `contracts/modules/DegenerusGameWhaleModule.sol:851/854/855/856/876` — whale deposit
  tally sites + `lootboxDay`/`lootboxBaseLevelPacked` writes.

### Memory / methodology (must apply)
- `feedback_rng_backward_trace`, `feedback_rng_commitment_window`,
  `feedback_rng_window_storage_read_freshness` — SPEC-04 trace method (D-10/D-11).
- `feedback_verify_call_graph_against_source` — grep-verify every cited line; no
  "by construction".
- `feedback_maximal_variable_packing` — drove D-01 (uint64) + D-02 (baseLevel co-pack).
- `feedback_security_over_gas`, `feedback_frozen_contracts_no_future_proofing` — packing
  never trades a freeze invariant; no future-proofing redundancy.
- `feedback_no_history_in_comments` — drove the rename (D-05); SPEC/comments describe
  what IS.
- `v45-vrf-freeze-invariant` — the north-star freeze invariant the SPEC defends.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_lootboxEvMultiplierFromScore(uint256 score)` — already maps activity score → bps;
  reused unchanged at all three callers (`:674/:710` and the open path). The frozen
  multiplier source for SPEC-04's word-independence argument.
- Existing `(score + 1)` / `(level + 1)` sentinel convention (0 = unset) — the new packed
  word reuses it for both `score+1` and `baseLevel+1`.

### Established Patterns
- Mapping values never cross-pack — widening a single `mapping(... => uintN)` value to
  `uint256` introduces no new slot (the basis for the "no new slot" attestation).
- Read-modify-write packed words on incremental deposits — `adjustedPortion` accumulation
  already loads the word, so co-packing `baseLevel` adds no deposit-path SLOAD.
- Seed = `keccak256(abi.encode(rngWord, player, day, amount))` on the RAW amount across
  all four lootbox roll sites (`:545/:621/:671/:707`) — the freeze-sensitive invariant
  (INV-04) the packing must not perturb.

### Integration Points
- Storage decl `Storage.sol:1374-1379` is where `lootboxBaseLevelPacked` is removed and
  `lootboxEvScorePacked` becomes `lootboxPurchasePacked` (uint256).
- All `lootboxBaseLevelPacked` read/write sites (`Mint:992`, `Whale:855`, `Lootbox:541/570`)
  must rewire to the packed word — all within the 4 in-scope files (no scope escape).
- The new helpers live in `DegenerusGameLootboxModule.sol` (with the EV constants /
  `_applyEvMultiplierWithCap`).

</code_context>

<specifics>
## Specific Ideas

- The user explicitly chose to ride the opportunistic `baseLevel` co-pack along with the
  V-081 fix (maximal packing over surgical minimalism) — but only because it is in-scope
  (all sites in the 4 files), not a seed input, and zero added deposit cost. `lootboxDay`
  was the hard line: seed input → never co-packed.
- The SPEC verdict for the shared cap is ACCEPT — but the user wants the rigorous
  word-independence trace + full in-window SLOAD enumeration written out, not an
  assertion. Treat "accept" as a claim requiring proof in the SPEC artifact.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (The Future Requirements list in
`.planning/REQUIREMENTS.md` §Future Requirements remains the home for VRF-freeze
housekeeping, v44 bookkeeping cleanup, and the v43 backlog — out of scope for v45.0.)

</deferred>

---

*Phase: 309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe*
*Context gathered: 2026-05-20*
