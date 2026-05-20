# Phase 310: Implementation — Single Batched USER-APPROVED Contract Diff (IMPL) - Context

**Gathered:** 2026-05-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Apply the LOCKED Phase 309 SPEC (`.planning/phases/309-*/309-SPEC.md`, SPEC-01..04) across the
4 touched contracts as **IMPL-01..05** in a **single batched USER-APPROVED contract diff** —
present ONE diff at the end of the phase, get ONE approval, no partial commits, no pre-approval
(per `feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` +
`feedback_no_contract_commits` + `feedback_manual_review_before_push`).

Touched files: `contracts/storage/DegenerusGameStorage.sol`,
`contracts/modules/DegenerusGameLootboxModule.sol`,
`contracts/modules/DegenerusGameMintModule.sol`,
`contracts/modules/DegenerusGameWhaleModule.sol`.

**This is an execution phase — the design is LOCKED in the 309 SPEC + REQUIREMENTS.md. Do NOT
redesign.** The discussion did not reopen any locked decision; it resolved one cross-module
reachability gap the SPEC did not address (helper + EV-logic placement, below). Storage layout
BREAKS acceptable (pre-launch redeploy-fresh per `feedback_frozen_contracts_no_future_proofing`;
no migration concern). All cited `file:line` re-grep-verified against source pre-patch per
`feedback_verify_call_graph_against_source`.

</domain>

<decisions>
## Implementation Decisions

> **The 309 SPEC is load-bearing and fully locks SPEC-01..04.** It lives in phase 309's directory
> (`check_spec` looked only in 310's dir, so `spec_loaded` was false here) — downstream agents
> MUST read it (see Canonical References). The decisions below are ONLY the two cross-module
> placement decisions resolved in this discussion; everything else is the SPEC verbatim.

### Cross-module helper + EV-logic placement (the gap the SPEC missed)

The 309 SPEC §1.7/D-06 locked the pack/unpack helpers into `DegenerusGameLootboxModule.sol`.
That placement is **architecturally infeasible**: the modules are separate delegatecall contracts
sharing only `DegenerusGameStorage` (Lootbox `is DegenerusGameStorage`; Mint/Whale
`is DegenerusGameMintStreakUtils is DegenerusGameStorage`). Mint/Whale do NOT inherit
LootboxModule, so they cannot call a Lootbox-private helper — yet IMPL-03's deposit-time tally
runs in Mint/Whale and must pack/RMW the word AND classify bonus-vs-not.

- **D-01 (pack/unpack helpers → shared base):** Place BOTH `_packLootboxPurchase` and
  `_unpackLootboxPurchase` in `contracts/storage/DegenerusGameStorage.sol` as `internal pure`,
  inherited by Lootbox, Mint, AND Whale. Single source of truth; matches the existing precedent
  (`_packEthToMilliEth`/`_unpackMilliEthToWei`/`_packBurnieToWhole`/`_unpackWholeBurnieToWei`
  already live as `internal pure` at `DegenerusGameStorage.sol:1347-1365`). This **overrides the
  SPEC §1.7/D-06 LootboxModule placement** — the signatures from SPEC §1.7 are unchanged, only
  the home file moves. Avoids the inline-duplicated-business-logic drift bug class
  (`feedback_verify_call_graph_against_source`, Phase 294 BURNIE precedent).

- **D-02 (EV multiplier fn + EV constants → shared base):** The deposit-time tally must evaluate
  `mult = _lootboxEvMultiplierFromScore(score)` to branch `mult > NEUTRAL` (draw cap) vs
  `mult <= NEUTRAL` (no draw), and read `LOOTBOX_EV_NEUTRAL_BPS` + `LOOTBOX_EV_BENEFIT_CAP` for
  `remaining = CAP - used`. All three are currently `private`/`private constant` in LootboxModule
  (`_lootboxEvMultiplierFromScore` at `:444-446`; `LOOTBOX_EV_MIN/NEUTRAL/MAX_BPS` at `:308-312`;
  `LOOTBOX_EV_BENEFIT_CAP` at `:314-315`). Relocate `_lootboxEvMultiplierFromScore` + the EV
  constants it needs (MIN/NEUTRAL/MAX_BPS, BENEFIT_CAP, and any `ACTIVITY_SCORE_*` it references)
  to `DegenerusGameStorage.sol` as `internal`/`internal constant` so all modules share ONE
  score→bps source of truth. Mint/Whale today have ZERO EV references (the cap is drawn entirely
  at resolution); moving it to deposit time is what pulls EV classification into them.
  - **`_applyEvMultiplierWithCap` STAYS in LootboxModule** — only the two resolvers
    (`resolveLootboxDirect`, `resolveRedemptionLootbox`) still call it (SPEC-04 ACCEPT keeps them
    drawing the cap at resolution with the Change-1 `<=` rewrite). `openLootBox` no longer calls
    it (frozen-apply per SPEC-03 §3.4). No cross-module need for it.

### Locked by the 309 SPEC — carried forward verbatim, NOT reopened

- **SPEC-01 (packed word):** `uint256` per `(uint48 index, address player)`:
  `[0:16]` `score+1` (uint16) | `[16:80]` `adjustedPortion` (uint64) | `[80:104]` `baseLevel+1`
  (uint24) | `[104:256]` free (written zero). Replaces BOTH `lootboxEvScorePacked` and
  `lootboxBaseLevelPacked` → net −1 slot. `adjustedPortion` width = **uint64** (NOT the fix-plan's
  uint96 — superseded). Rename `lootboxEvScorePacked → lootboxPurchasePacked` (uint256). No new
  slot (D-07). `lootboxDay` co-pack REJECTED (seed input — freeze hard line). Helper signatures
  per SPEC §1.7 (home file per D-01 above).
- **SPEC-02 (bonus-only cap, IMPL-01):** in `_applyEvMultiplierWithCap`, replace
  `if (evMultiplierBps == NEUTRAL) return amount;` with
  `if (evMultiplierBps <= NEUTRAL) return (amount * evMultiplierBps) / 10_000;`. Penalty + neutral
  apply in full and draw ZERO cap; only `> NEUTRAL` draws.
- **SPEC-03 (allocation tally + open-apply, IMPL-03/IMPL-04):** deposit-time tally with the box's
  frozen first-deposit-score multiplier: `mult <= NEUTRAL` → store `score+1` only, no draw;
  `mult > NEUTRAL` → `add = min(deposit, CAP - lootboxEvBenefitUsedByLevel[player][lvl])`, advance
  the used accumulator, accumulate `adjustedPortion` via RMW of the packed word. First deposit
  writes `score+1` and `baseLevel+1`; later deposits accumulate `adjustedPortion` only.
  `openLootBox` applies `scaled = mult <= NEUTRAL ? amount*mult/1e4 : adj*mult/1e4 + (amount-adj)`
  with NO cap SLOAD/SSTORE; zero-at-open clears the WHOLE packed slot in one SSTORE (replacing the
  two clears at Lootbox:570/571).
- **SPEC-04 (shared cap, ACCEPT):** the two resolvers keep drawing the shared per-`(player, level)`
  cap at resolution (Change-1 only); proven word-independent in SPEC §4. No fix.
- **IMPL-05 (seed/roll byte-identical):** raw `amount` still feeds
  `keccak256(abi.encode(rngWord, player, day, amount))` at all four roll sites
  (`:545/:621(amountEth)/:671/:707`); `lootboxEth` layout untouched. Only reward SCALING uses
  `adjustedPortion`.
- **DIV-1 preserved per-site:** Mint writes `baseLevel` as `uint24(cachedLevel + 1)`
  (Mint:992-994); Whale writes `uint24(level + 2)` (Whale:855). The pack helper takes an
  ALREADY-ENCODED `baseLevelPlus1` and MUST NOT normalize the two offsets.
- **DIV-2 preserved per-site:** Mint's score write is gated behind `if (lbFirstDeposit)`
  (Mint:1154-1155); Whale's is inline in the `existingAmount == 0` branch (Whale:856-858). Wire
  each module's existing structure to the packed word without re-ordering its score read.

### Claude's Discretion

- Exact bit-mask/shift implementation inside the relocated `_pack/_unpackLootboxPurchase` helpers
  (the layout is fixed by SPEC-01; the encoding mechanics are standard).
- Whether subsequent-deposit `adjustedPortion` accumulation in Mint/Whale uses
  `_unpackLootboxPurchase` then `_packLootboxPurchase`, or a narrower masked RMW — both are
  acceptable as long as `score+1`/`baseLevel+1` are preserved and the layout matches SPEC-01.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner, executor) MUST read these before planning or implementing.**

### v45.0 LOCKED design (load-bearing — read first)
- `.planning/phases/309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe/309-SPEC.md`
  — THE locked design. §0 grep-verified call-graph (every `file:line` IMPL touches), §1 packed
  layout (SPEC-01), §2 bonus-only cap (SPEC-02), §3 tally + open-apply (SPEC-03), §4
  word-independence proof + in-window SLOAD enumeration (SPEC-04). MUST read before any patch.
- `.planning/REQUIREMENTS.md` — IMPL-01..05 (the 5 requirements this phase delivers), INV-01..06
  (acceptance criteria proven at Phase 311 TST), the gas directive, Out-of-Scope (incl. accepted
  self-MEV), and the commit posture.
- `.planning/phases/309-*/309-CONTEXT.md` — decisions D-01..D-11 the SPEC transcribes
  (uint64 width, baseLevel co-pack, rename, ACCEPT verdict).
- `.planning/ROADMAP.md` §Phase 310 — the IMPL-01..05 scope statement + wave shape (1 batched
  USER-APPROVED contract commit).
- `.planning/v45-lootbox-evcap-fix-plan.md` — Change 1 + Change 2 narrative. NOTE its `uint96`
  width and EV-only packing layout are SUPERSEDED by SPEC-01 (uint64; word carries baseLevel;
  renamed `lootboxPurchasePacked`).
- `.planning/STATE.md` — baseline `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`.

### Contract HEAD sites IMPL touches (re-grep-verify pre-patch)
- `contracts/storage/DegenerusGameStorage.sol:1347-1365` — existing `internal pure` pack/unpack
  precedent; the new helpers (D-01) + relocated EV fn/constants (D-02) land here.
- `contracts/storage/DegenerusGameStorage.sol:1370` — `lootboxDay` (uint32; co-pack REJECTED).
- `contracts/storage/DegenerusGameStorage.sol:1374-1375` — `lootboxBaseLevelPacked` (REMOVED/merged).
- `contracts/storage/DegenerusGameStorage.sol:1379` — `lootboxEvScorePacked` (→ uint256
  `lootboxPurchasePacked`).
- `contracts/storage/DegenerusGameStorage.sol:1427-1428` — `lootboxEvBenefitUsedByLevel` (shared
  cap accumulator, keyed `(player, level)`).
- `contracts/modules/DegenerusGameLootboxModule.sol:308-315` — `LOOTBOX_EV_MIN/NEUTRAL/MAX_BPS` +
  `LOOTBOX_EV_BENEFIT_CAP` (relocate per D-02).
- `contracts/modules/DegenerusGameLootboxModule.sol:444-446` — `_lootboxEvMultiplierFromScore`
  (`private pure`; relocate per D-02).
- `contracts/modules/DegenerusGameLootboxModule.sol:475-509` — `_applyEvMultiplierWithCap`
  (Change-1 site, IMPL-01; STAYS in Lootbox).
- `contracts/modules/DegenerusGameLootboxModule.sol:517-591` — `openLootBox` (frozen-apply,
  IMPL-04; reads packed word, no cap SLOAD/SSTORE, whole-word zero-at-open at 570/571).
- `contracts/modules/DegenerusGameLootboxModule.sol:528/541/545/557/570/571/616/621` — `lootboxDay`
  read + seed builds + baseLevel/score read+clear.
- `contracts/modules/DegenerusGameLootboxModule.sol:559/675/711` — the three
  `_applyEvMultiplierWithCap` call sites (open / resolveLootboxDirect / resolveRedemptionLootbox).
- `contracts/modules/DegenerusGameLootboxModule.sol:666/702` — resolver signatures (frozen
  `activityScore` param multiplier source, SPEC-04).
- `contracts/modules/DegenerusGameMintModule.sol:987-994/1013-1015/1154-1155/1396-1397` — purchased-box
  deposit tally sites (first-deposit + subsequent + BURNIE path) + score write (DIV-2 gated).
- `contracts/modules/DegenerusGameWhaleModule.sol:851/854-858/876` — whale deposit tally sites
  (first-deposit + subsequent) + score write (DIV-2 inline).

### Memory / methodology (must apply)
- `feedback_batch_contract_approval`, `feedback_never_preapprove_contracts`,
  `feedback_no_contract_commits`, `feedback_manual_review_before_push` — single batched
  USER-APPROVED diff; one approval at end; never tell agents contracts are pre-approved; user
  reviews the diff before any push.
- `feedback_verify_call_graph_against_source` — re-grep every cited line pre-patch; no "by
  construction"; inline-duplicated logic is the recurring bug class (drove D-01/D-02).
- `feedback_maximal_variable_packing` — uint64 width + baseLevel co-pack + relocation to one home.
- `feedback_security_over_gas`, `v45-vrf-freeze-invariant` — packing never trades a freeze
  invariant; `lootboxDay` stays un-co-packed (seed input).
- `feedback_no_history_in_comments` — comments describe what IS; drove the rename.
- `feedback_frozen_contracts_no_future_proofing` — storage-layout break acceptable; no migration.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DegenerusGameStorage.sol:1347-1365` — existing `internal pure` pack/unpack helpers
  (`_packEthToMilliEth` etc.) are the exact placement precedent for D-01/D-02; the new helpers +
  relocated EV fn/constants follow the same shape and home.
- `_lootboxEvMultiplierFromScore` — reused unchanged at all callers (open frozen-apply + both
  resolvers + the new Mint/Whale deposit classification); just moves to the shared base.
- `(score+1)`/`(level+1)` sentinel convention (0 = unset) — reused for both packed fields.

### Established Patterns
- Delegatecall-module architecture: all modules inherit `DegenerusGameStorage` and operate on one
  shared storage layout. `internal` members in Storage are reachable by every module — the basis
  for D-01/D-02. Lootbox-`private` members are NOT reachable from Mint/Whale (the gap resolved).
- Mappings allocate a full slot per value regardless of declared width → widening
  `lootboxEvScorePacked` from uint16 to uint256 adds zero slots (no-new-slot attestation).
- Deposit-time RMW of a packed word already loads it, so co-packing `baseLevel` adds no extra
  deposit SLOAD.
- Roll seed = `keccak256(abi.encode(rngWord, player, day, amount))` on the RAW amount at all four
  sites — the INV-04 freeze-sensitive line the packing must not perturb.

### Integration Points
- `DegenerusGameStorage.sol` is the single home for the new helpers + relocated EV fn/constants
  (D-01/D-02), the renamed/widened `lootboxPurchasePacked` mapping, and the removed
  `lootboxBaseLevelPacked` declaration.
- All `lootboxBaseLevelPacked`/`lootboxEvScorePacked` read/write/clear sites (Mint:992/1154,
  Whale:855/856, Lootbox:541/557/570/571) rewire to the packed word — all within the 4 in-scope
  files (no scope escape).

</code_context>

<specifics>
## Specific Ideas

- The user chose maximal single-source-of-truth over SPEC-literal placement on BOTH the helpers
  (D-01) and the EV multiplier fn + constants (D-02): consolidate everything Mint/Whale need into
  `DegenerusGameStorage.sol` rather than duplicate pack/classify logic inline across 3 modules.
  This is an explicit override of SPEC §1.7's LootboxModule placement, justified because the SPEC
  placement is architecturally unreachable from the deposit sites and inline duplication is the
  exact drift bug class flagged by `feedback_verify_call_graph_against_source`.
- The override is scoped narrowly: signatures/semantics from the SPEC are unchanged — only the
  home file moves, and only for the members Mint/Whale must reach. `_applyEvMultiplierWithCap`
  stays in LootboxModule (only the resolvers call it).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (VRF-freeze housekeeping, v44 bookkeeping cleanup,
and the v43 backlog remain in `.planning/REQUIREMENTS.md` §Future Requirements — out of scope for
v45.0.)

</deferred>

---

*Phase: 310-implementation-single-batched-user-approved-contract-diff-im*
*Context gathered: 2026-05-20*
