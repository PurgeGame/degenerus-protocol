# 270-01-DELTA-SURFACE.md — Post-v32.0 Deferred-Commit Adversarial Sub-Audit Working File

**Phase:** 270 (post-v32-0-deferred-commit-adversarial-sub-audit)
**Audit baseline:** v36.0 closure HEAD `1c0f0913` → v37.0 source-tree HEAD at Phase 270 entry `8fd5c2e1` (Phase 269 LBX-01 close)
**Phase 270 plan-author entry SHA:** `311feb1e` (STATE.md commit at Phase 270 plan-author time)
**Generated:** 2026-05-11T06:37Z (Phase 270 active; agent-authored)
**Adversarial-skill posture:** pure agent grep-sweep per D-270-ADVERSARIAL-01 (NO `/contract-auditor` / `/zero-day-hunter` / `/economic-analyst` / `/degen-skeptic` dispatch this phase; SEQUENTIAL skill-tool pass over the FULL §4 v37.0 surface table is scheduled in Phase 271 per D-NN-ADVERSARIAL-02 carry; Phase 270 verdicts are recorded with the SAME vocabulary but flagged grep-sweep-only).
**Coherence anchor:** dual evidence per D-270-COHERENCE-01 — every adversarial-surface row carries BOTH (a) landing-SHA hunk view (`git show <sha> -- <path>`, per-declaration classification under {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED}) AND (b) v37.0 HEAD invariant cite (grep recipe against the live `contracts/` and `test/` trees with expected output).
**Methodology anchor:** `feedback_design_intent_before_deletion.md` is PRIMARY governing memory per D-270-DESIGN-INTENT-METHOD-01. Both target commits ARE removal commits, so each removed code path carries a design-intent trace (pickaxe `git log -p -S '...'`) + actor game-theory walk (actor × state × outcome) + forward-looking risk bound.
**Phase 271 §3.A grep-cite anchor:** `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md` (this file) per D-270-FILES-01 + ROADMAP §270 success-criterion-5.

**Verdict vocabulary (per v33-v36 §4 audit precedent):**
- **SAFE** — no exploit path identified; default-safe invariant.
- **SAFE_BY_DESIGN** — explicit invariant in the design eliminates the exploit (e.g., monotonic state machine, immutable constant).
- **SAFE_BY_STRUCTURAL_CLOSURE** — the exploit path is structurally unreachable (e.g., caller-clamp, type-system enforcement, control-flow joins).
- **FINDING_CANDIDATE** — potential exploit path identified; row carries Phase-271-§3.A-block-ready stub per D-270-FCFORMAT-01.

**Taxonomy vocabulary (per v33-v36 §3.A precedent):**
- **NEW** — declaration added at landing-SHA.
- **MODIFIED_LOGIC** — declaration body changed (functional behavior changed).
- **REFACTOR_ONLY** — declaration body restructured but functional behavior unchanged.
- **DELETED** — declaration removed at landing-SHA.

---

## Commit A: 002bde55 — feat(presale): auto-deactivate flag on per-mint cap crossing

**Landing SHA:** `002bde55069202806ba365f748646f7077576e59` (2026-05-02; +14 / −10 LOC across 3 files)
**Subject:** `feat(presale): auto-deactivate flag on per-mint cap crossing`
**Files touched:** `contracts/modules/DegenerusGameAdvanceModule.sol` (−12/+3), `contracts/modules/DegenerusGameMintModule.sol` (+9/−1), `contracts/storage/DegenerusGameStorage.sol` (+3).
**Audit posture:** removal-commit (the AdvanceModule cap-OR arm and the L142 `LOOTBOX_PRESALE_ETH_CAP` constant declaration are deleted) + relocation (`LOOTBOX_PRESALE_ETH_CAP` moves to GameStorage as the shared source of truth) + inlined-logic addition (the MintModule per-mint cap-clear predicate is the new sole writer of the cap-crossing deactivation transition).

### Per-Declaration Classification

| Declaration | File | Lines (landing-SHA) | Taxonomy | Notes |
|---|---|---|---|---|
| `LOOTBOX_PRESALE_ETH_CAP` (AdvanceModule old declaration) | `contracts/modules/DegenerusGameAdvanceModule.sol` | L142 (pre-002bde55) | **DELETED** | Relocated to `contracts/storage/DegenerusGameStorage.sol` (see row below). The AdvanceModule no longer carries its own copy; both modules read from the GameStorage shared source of truth. |
| AdvanceModule cap-OR deactivation arm | `contracts/modules/DegenerusGameAdvanceModule.sol` | L431-435 (pre-002bde55) | **DELETED** | Original predicate `if (_psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0 && (lvl >= 3 || _psRead(PS_MINT_ETH_SHIFT, PS_MINT_ETH_MASK) >= LOOTBOX_PRESALE_ETH_CAP)) _psWrite(...)` replaced by `if (lvl >= 3 && _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0) { _psWrite(...) }`. The OR-with-cap-threshold clause is structurally unreachable post-002bde55 because MintModule's per-mint cap-clear fires synchronously with every cap-crossing mint, BEFORE the next level-transition is reached. |
| MintModule inlined `presaleStatePacked` SLOAD/mask/SSTORE | `contracts/modules/DegenerusGameMintModule.sol` | L1029-1042 (landing-SHA; HEAD L1031-1040) | **MODIFIED_LOGIC** | Replaces the prior helper-based `_psWrite(PS_MINT_ETH_SHIFT, PS_MINT_ETH_MASK, _psRead(PS_MINT_ETH_SHIFT, PS_MINT_ETH_MASK) + lootBoxAmount)` one-liner with an inline SLOAD/mask/SSTORE block that fuses (i) the cumulative-mint-ETH bump and (ii) the new cap-clear predicate into a single SLOAD + single SSTORE. Functional behavior IS modified (the cap-clear is genuinely new — see NEW row below); the inline shape is not a pure refactor, it changes the semantics of the predicate. |
| MintModule per-mint cap-clear predicate | `contracts/modules/DegenerusGameMintModule.sol` | L1036-1038 (HEAD; landing-SHA L1037-1040) | **NEW** | `if (newMintEth >= LOOTBOX_PRESALE_ETH_CAP) psPacked &= ~uint256(PS_ACTIVE_MASK);` — the sole new writer of the cap-crossing PS_ACTIVE_MASK clear-to-zero transition. Same-tx clear means the buyer who triggers the cap still receives presale terms (local `presale` boolean captured at L996 BEFORE the bump). |
| `LOOTBOX_PRESALE_ETH_CAP` (GameStorage new declaration) | `contracts/storage/DegenerusGameStorage.sol` | L863 (landing-SHA; HEAD L864) | **NEW** | `uint256 internal constant LOOTBOX_PRESALE_ETH_CAP = 200 ether;` — `internal constant` visibility makes it accessible from both AdvanceModule and MintModule (they inherit from `DegenerusGameStorage`). Identical 200 ether value to the pre-002bde55 AdvanceModule declaration; relocation is value-byte-identical. |

### Design-Intent Trace

Per D-270-DESIGN-INTENT-METHOD-01 (PRIMARY governing memory per `feedback_design_intent_before_deletion.md`).

**Pickaxe command + key output (AdvanceModule cap-OR arm origin):**

```bash
git log -p -S "LOOTBOX_PRESALE_ETH_CAP" -- contracts/modules/DegenerusGameAdvanceModule.sol | head -200
```

Anchoring lines:
- Originating landing commit: `4c401497` — `"Degenerus Protocol smart contracts"` (Sun Feb 15 10:34:37 2026; "Complete production Solidity source for the Degenerus Protocol on-chain elimination game"). The AdvanceModule cap-OR arm landed as part of the initial production-code drop with both `lvl >= 3` AND the `LOOTBOX_PRESALE_ETH_CAP` cumulative-ETH threshold OR'd together as the level-transition deactivation predicate; the constant was declared `private constant` at the AdvanceModule L142 site (no cross-module sharing at landing).
- Removal landing commit: `002bde55` — `feat(presale): auto-deactivate flag on per-mint cap crossing` (Sat May 2 21:26:28 2026). The commit body explicitly names the unreachability cause: "*The cap arm in AdvanceModule's level-transition deactivation becomes unreachable once the per-mint check is in place and is removed; the lvl >= 3 trigger remains.*"

**Pickaxe command + key output (MintModule presale-state bit-write evolution):**

```bash
git log -p -S "_psWrite" -- contracts/modules/DegenerusGameMintModule.sol | head -80
```

Anchoring lines:
- Pre-002bde55 the MintModule presale bump used the helper-based `_psWrite(PS_MINT_ETH_SHIFT, PS_MINT_ETH_MASK, _psRead(PS_MINT_ETH_SHIFT, PS_MINT_ETH_MASK) + lootBoxAmount);` form (a separate SLOAD + separate SSTORE through the helper). Phase 208-03 commit `396f3d4e` (Apr 9 2026, "propagate type narrowing through MintModule, WhaleModule, PayoutUtils") touched the surrounding `LootBoxBuy` event signature and other type-narrowing concerns but did not change the bump-via-`_psWrite` shape.
- At `002bde55` the bump was inlined into a SLOAD + mask + cap-check + SSTORE block. The fusion was driven by the cap-clear predicate addition: doing both writes through `_psWrite` would have required two SLOADs / two SSTOREs on the same slot, defeating the gas-budget claim of `~10 gas` added cost asserted in the commit message.

**Original purpose of the removed code (AdvanceModule cap-OR arm):**

The AdvanceModule cap-OR deactivation arm was designed as a dual-trigger safety net at the level-transition seam: deactivate the presale flag either (a) once `lvl >= 3` (the level-transition trigger — presale ends at level 3 regardless of cap state) OR (b) once cumulative mint-only ETH crossed 200 ether AT level-transition (the cap trigger — presale ends if too much ETH was committed during this level, even if `lvl < 3`). The cap arm caught the overshoot case where cumulative mint-only ETH had crossed 200 ether mid-level but the level-transition hadn't yet rotated past `lvl = 3`. Pre-002bde55, no per-mint cap check existed, so overshoots could persist for an entire level until the next `advanceGame` deactivation pass.

**Original purpose of the removed code (AdvanceModule's L142 constant declaration):**

`private constant LOOTBOX_PRESALE_ETH_CAP = 200 ether;` at AdvanceModule L142 was the sole declaration of the cap value before relocation. With the AdvanceModule cap-OR arm deleted at `002bde55`, AdvanceModule no longer needs the constant; with the MintModule per-mint cap-clear added at the same commit, MintModule DOES need it. The relocation to GameStorage as `internal constant` lets both modules read the same value through the shared GameStorage parent contract — the storage layout / runtime cost of an internal constant in a parent contract is identical to the prior module-local private constant.

**Unreachability cause (AdvanceModule cap-OR arm post-002bde55):**

The MintModule per-mint cap-clear predicate at L1036-1038 (HEAD) fires synchronously with every cap-crossing mint: as soon as `newMintEth >= LOOTBOX_PRESALE_ETH_CAP`, the same SSTORE that bumps the cumulative-ETH counter also bit-clears `PS_ACTIVE_MASK`. Once `PS_ACTIVE_MASK` is bit-cleared, the AdvanceModule's hypothetical cap-OR arm's `_psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0` precondition is structurally false; the OR clause cannot fire because the active-flag is already zero. The remaining `lvl >= 3` clause covers the case where presale ends because the level transitioned without ever crossing the cap.

**Forward-looking risk bound (re-introduction prevention):**

- The `LOOTBOX_PRESALE_ETH_CAP` constant is `internal constant` in GameStorage at L864 — accessible from both modules via inheritance; the relocation is byte-identical to the prior AdvanceModule-local declaration in value (`200 ether`).
- The per-mint cap-clear is a single-site `if (newMintEth >= LOOTBOX_PRESALE_ETH_CAP) psPacked &= ~uint256(PS_ACTIVE_MASK);` predicate in MintModule. Forward grep recipe `grep -rn "PS_ACTIVE_MASK" contracts/modules/` returns exactly TWO writers at HEAD (MintModule cap-clear L1037 + AdvanceModule lvl-3 trigger L432) — no third writer.
- Re-introducing the AdvanceModule cap-OR arm in a future commit would NOT change observable behavior (the precondition is unreachable post-cap-crossing), but the maintainer would be re-introducing a dead code path that the v37.0 audit explicitly removed — a `feedback_no_dead_guards.md` violation. The trace anchor is THIS section; the grep recipe is `grep -nE "lvl >= 3.*_psRead.*PS_MINT_ETH" contracts/modules/DegenerusGameAdvanceModule.sol` which MUST return EMPTY at any future audit HEAD.
- Re-introducing the MintModule's prior helper-based `_psWrite(PS_MINT_ETH_SHIFT, PS_MINT_ETH_MASK, ...)` form would re-break the gas-budget claim (the inline shape is what keeps the bump+cap-check at +1 SLOAD + +1 SSTORE rather than +2 SLOAD + +2 SSTORE). Cosmetic regression, no security impact, but trace anchor lives here.

### Adversarial-Surface Sweep

Per D-270-DEPTH-01 (4 ROADMAP-enumerated surfaces (i)-(iv); ZERO scope expansion).

| Surface | Landing-SHA Evidence | v37.0 HEAD Invariant Cite | Verdict | Verdict Rationale |
|---|---|---|---|---|
| **(i) state-machine ordering implications** | `git show 002bde55 -- contracts/modules/DegenerusGameAdvanceModule.sol`: L142 `LOOTBOX_PRESALE_ETH_CAP` DELETED; L431-435 cap-OR deactivation arm DELETED (replaced by `if (lvl >= 3 && _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0)` lvl-only trigger). `git show 002bde55 -- contracts/storage/DegenerusGameStorage.sol`: L863 `LOOTBOX_PRESALE_ETH_CAP = 200 ether` NEW with `internal constant` visibility. | `grep -n "LOOTBOX_PRESALE_ETH_CAP" contracts/storage/DegenerusGameStorage.sol` → L864 `uint256 internal constant LOOTBOX_PRESALE_ETH_CAP = 200 ether;` (single internal-constant declaration at HEAD). `grep -n "LOOTBOX_PRESALE_ETH_CAP" contracts/modules/DegenerusGameAdvanceModule.sol` → EMPTY (zero matches — declaration AND callsite both absent at HEAD; AdvanceModule never references the constant post-relocation). `grep -n "lvl >= 3" contracts/modules/DegenerusGameAdvanceModule.sol` → L431 `if (lvl >= 3 && _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0) {` (sole AdvanceModule-side deactivation predicate). | **SAFE_BY_STRUCTURAL_CLOSURE** | The constant relocation is value-byte-identical (200 ether at both sites; `internal constant` in GameStorage has the same runtime semantics as the prior `private constant` in AdvanceModule because GameStorage is the parent class both modules inherit from). The AdvanceModule level-transition seam still carries the `lvl >= 3` lower-bound guard as the sole AdvanceModule-side deactivation condition; no state-machine ordering hazard is introduced because the deactivation transition has moved from "potentially-twice-per-level (cap-OR clause OR lvl-3-trigger)" to "at-most-once-per-cap-crossing-mint (MintModule predicate) OR at-most-once-at-level-3-transition (AdvanceModule predicate)", and the two writers are temporally disjoint (a cap-crossing mint that fires the MintModule clear sets `PS_ACTIVE_MASK = 0`, making the subsequent AdvanceModule `_psRead != 0` precondition false). |
| **(ii) presale-flag timing across the auto-deactivate threshold** | `git show 002bde55 -- contracts/modules/DegenerusGameMintModule.sol`: L1029-1042 inlined SLOAD/mask/SSTORE block (MODIFIED_LOGIC); L1037-1040 per-mint cap-clear predicate `if (newMintEth >= LOOTBOX_PRESALE_ETH_CAP) psPacked &= ~uint256(PS_ACTIVE_MASK);` (NEW). | `grep -nB2 -A20 "if (presale)" contracts/modules/DegenerusGameMintModule.sol` confirms the live block: local `bool presale = _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0;` is captured at L996 — 35 lines BEFORE the `if (presale) { ... newMintEth ... cap-clear }` block at L1031-1040, AND the local `presale` value is RE-USED at the post-bump split-selection switch at L1053 (`else if (presale) { futureBps = LOOTBOX_PRESALE_SPLIT_FUTURE_BPS; ... }`) so the buyer that triggers the cap-clear gets the presale split (5050-style) instead of the post-presale split — buyer-receives-presale-terms-before-deactivation invariant holds at HEAD. | **SAFE_BY_DESIGN** | The local `presale` boolean captured BEFORE the bump-and-clear is the load-bearing invariant. Every downstream branch in MintModule (the split-selection at L1053, the BURNIE-bonus path at L1054 implicit through `LOOTBOX_PRESALE_SPLIT_*` constants, and the `emit LootBoxBuy(buyer, lbDay, ..., presale, ...)` event at the function's tail) reads the LOCAL captured `presale`, not the post-bit-clear storage value. The buyer who triggers the cap-crossing mint receives all presale benefits (split, event flag, BURNIE bonus) as the commit message explicitly documents and as the storage-vs-local read pattern enforces. |
| **(iii) downstream consumer assumptions in MintModule interaction** | `git show 002bde55 -- contracts/modules/DegenerusGameMintModule.sol`: the inlined SLOAD/mask/SSTORE block (MODIFIED_LOGIC) preserves the same bit-layout contract as the prior helper-based `_psWrite` (PS_MINT_ETH at bits [8, 136) — uint128 sub-field — and PS_ACTIVE at bits [0, 8) — uint8 sub-field). The mask/shift constant references (`PS_MINT_ETH_SHIFT = 8`, `PS_MINT_ETH_MASK = 0xFF...FF` 128 bits, `PS_ACTIVE_MASK = 0xFF` 8 bits) inherit from GameStorage UNCHANGED. | `grep -nE "(PS_MINT_ETH_(SHIFT\|MASK)\|PS_ACTIVE_(SHIFT\|MASK))" contracts/storage/DegenerusGameStorage.sol` → L858 `PS_ACTIVE_SHIFT = 0`, L859 `PS_ACTIVE_MASK = 0xFF`, L860 `PS_MINT_ETH_SHIFT = 8`, L861 `PS_MINT_ETH_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF` (4 constants present, byte-identical to landing-SHA; 8-bit ACTIVE sub-field at bits [0,8), 128-bit MINT_ETH sub-field at bits [8, 136)). `grep -rn "PS_MINT_ETH" contracts/` returns ONLY MintModule L1033-1035 as the inline writer + the two GameStorage constants — no other reader/writer of PS_MINT_ETH at HEAD; LootboxModule + WhaleModule only read PS_ACTIVE. | **SAFE_BY_STRUCTURAL_CLOSURE** | The inlined SLOAD/mask/SSTORE preserves the byte-layout contract: the same 128-bit `newMintEth` sub-field at bits [8, 136), the same 8-bit `PS_ACTIVE` sub-field at bits [0, 8). Downstream consumers that read PS_MINT_ETH or PS_ACTIVE via `_psRead(SHIFT, MASK)` see byte-identical values to the prior helper-based shape. The `newMintEth & PS_MINT_ETH_MASK` mask at L1035 enforces the 128-bit width before the field is written back — a `lootBoxAmount` large enough to overflow uint128 would silently wrap the cumulative-ETH counter, BUT (a) `lootBoxAmount` is constrained by ETH supply on the L1 chain (no realistic value approaches 2^128 / 10^18 ≈ 3.4 × 10^20 ether), AND (b) the cap-clear predicate `newMintEth >= LOOTBOX_PRESALE_ETH_CAP` uses the un-masked `newMintEth` so the cap-clear cannot be bypassed by an overflow-wrap. |
| **(iv) presale → post-presale transition coherence** | `git show 002bde55 -- contracts/modules/DegenerusGameMintModule.sol`: per-mint cap-clear predicate is the sole NEW writer of the `PS_ACTIVE_MASK` clear-to-zero transition. `git show 002bde55 -- contracts/modules/DegenerusGameAdvanceModule.sol`: cap-OR clause DELETED removes a stale writer at the level-transition seam; remaining `lvl >= 3 && _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0` trigger is the only AdvanceModule-side writer. | `grep -rn "PS_ACTIVE_MASK\|PS_ACTIVE_SHIFT" contracts/modules/` returns 8 hits across MintModule (1 read at L996, 1 write at L1037 via `&= ~uint256(PS_ACTIVE_MASK)`), AdvanceModule (1 read at L431, 1 write at L432 via `_psWrite`), LootboxModule (1 read at L542), and WhaleModule (3 reads at L360 / L506 / L660). NO write outside MintModule.L1037 + AdvanceModule.L432. **Exactly two writers; both clear-to-zero (no writer sets `PS_ACTIVE_MASK` to non-zero at any HEAD path — that initialization happens via constructor / admin path outside the runtime per-mint hot-loop).** | **SAFE_BY_STRUCTURAL_CLOSURE** | Presale → post-presale transitions are monotonic-one-way at HEAD: `PS_ACTIVE_MASK` goes 1→0 exactly once per game lifecycle, and only two writers exist (MintModule cap-clear or AdvanceModule lvl-3 trigger; whichever fires first wins, the other becomes a no-op because the `_psRead != 0` precondition is false). Neither writer can race because both run in player-tx context with no reentrancy entry into either function during the bit-write (the player-tx flow holds the EVM single-threaded execution context until completion; the only reentrancy hazard would be a callback during the bit-write, which neither code path triggers — no `.call{value: ...}` between the SLOAD and SSTORE in MintModule's inlined block, no external call in AdvanceModule's `_psWrite` helper). |

### Actor Game-Theory Walk

Per D-270-DESIGN-INTENT-METHOD-01 (flowing prose per CONTEXT.md "Claude's Discretion" — the actor model is a small finite set).

**Actor 1 — Presale buyer triggering exactly the cap-crossing mint.**

- **State at tx entry:** `psPacked & PS_ACTIVE_MASK != 0` (presale active) AND `(psPacked >> PS_MINT_ETH_SHIFT) + msg.value's lootBoxAmount portion ≥ LOOTBOX_PRESALE_ETH_CAP` (this tx will cross the cap).
- **Captured-before-bump:** `bool presale = _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0;` at L996 reads `presale = true`.
- **Mid-block flow:** L1031 enters `if (presale)`; L1033 computes `newMintEth = (current PS_MINT_ETH field) + lootBoxAmount`; L1034-1035 builds `psPacked` with the new mint-ETH; L1036-1038 cap-check fires, bit-clears `PS_ACTIVE_MASK` in the same `psPacked`; L1039 commits the SSTORE.
- **Post-clear:** L1042+ split selection at L1053 reads LOCAL `presale = true` (captured at L996, unchanged), so the buyer gets `LOOTBOX_PRESALE_SPLIT_FUTURE_BPS / NEXT_BPS / VAULT_BPS` (the presale split). The `emit LootBoxBuy(..., presale, ...)` event records `presale = true` so downstream indexers + BURNIE bonus accounting flag this tx as a presale purchase.
- **Outcome:** the cap-triggering buyer gets the SAME presale terms (split, event, BURNIE bonus) as every earlier presale buyer in the cycle. NO advantage gained (cannot game by under-betting or over-betting; the cap-crossing is determined by the cumulative-ETH sum). NO value lost (would have gotten the same terms regardless of being the trigger). NO state-machine ordering hazard (the same-tx clear means subsequent buyers see `presale = false` immediately).

**Actor 2 — Presale buyer mid-cycle (well before cap-crossing).**

- **State at tx entry:** `psPacked & PS_ACTIVE_MASK != 0` AND `post-bump newMintEth < LOOTBOX_PRESALE_ETH_CAP`.
- **Flow:** standard presale mint path. L1036-1038 cap-check evaluates `newMintEth < LOOTBOX_PRESALE_ETH_CAP` → predicate false, no bit-clear; L1039 writes back the bumped `psPacked` with `PS_ACTIVE_MASK` unchanged.
- **Outcome:** behavior UNCHANGED from pre-002bde55. The buyer pays presale split, gets presale event, gets BURNIE bonus. NO observable difference (the only added cost is the L1036-1038 predicate evaluation, ~10 gas as the commit message documents).

**Actor 3 — Late mint after cap-crossing.**

- **State at tx entry:** `psPacked & PS_ACTIVE_MASK == 0` (presale already deactivated — either by a prior cap-crossing mint via MintModule's per-mint clear, OR by `lvl >= 3` triggering AdvanceModule's level-3 clear).
- **Flow:** L996 captures `bool presale = false`; L1031 `if (presale)` is false → the cap-clear block at L1031-1040 is skipped entirely (no SLOAD / SSTORE on `presaleStatePacked` at all); L1053 selects `else if (presale)` → false → falls through to the post-presale split at L1058-1061 (`LOOTBOX_SPLIT_FUTURE_BPS / NEXT_BPS`, no vault bps); `emit LootBoxBuy(..., presale=false, ...)`.
- **Outcome:** behavior UNCHANGED from pre-002bde55. Note: pre-002bde55 the AdvanceModule cap-OR arm could also have caused this actor to see `presale = false` if cumulative-ETH had crossed 200 ether but the AdvanceModule hadn't fired yet — that race-window is closed at 002bde55 because the cap-clear now fires synchronously with the cap-crossing mint, not deferred to the next level-transition.

**Actor 4 — AdvanceModule cap-OR arm hypothetical re-introduction.**

- **State at proposal:** future commit re-adds the OR-with-cap-threshold clause to the level-transition deactivation predicate.
- **Outcome:** **BLOCKED** at the audit-trail layer. The re-introduction would be observable behavior-equivalent to the no-op at HEAD (the `_psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0` precondition is false post-MintModule-cap-clear), but would re-introduce a dead code path that this Phase 270 audit explicitly catalogued as DELETED. The trace anchor is this Commit A section; the forward-looking grep recipe is `grep -nE "lvl >= 3.*_psRead.*PS_MINT_ETH" contracts/modules/DegenerusGameAdvanceModule.sol` which MUST return EMPTY at any future audit HEAD. Re-introduction is a `feedback_no_dead_guards.md` violation.

---

## Commit B: 2713ce61 — chore(vault): remove dead setDecimatorAutoRebuy wrapper

**Landing SHA:** `2713ce61e0d4e5953ee5ad00b49e67bf8df2eaf6` (2026-05-05; +3 / −20 LOC across 2 files)
**Subject:** `chore(vault): remove dead setDecimatorAutoRebuy wrapper`
**Files touched:** `contracts/DegenerusVault.sol` (−9 LOC: interface member + external wrapper), `test/fuzz/CoverageGap222.t.sol` (+3 / −11 LOC: fuzz coverage entry removed, renumbered).
**Audit posture:** removal-commit (the orphan vault wrapper `gameSetDecimatorAutoRebuy(bool)` + its `IDegenerusGamePlayerActions.setDecimatorAutoRebuy(address,bool)` interface declaration are deleted; the matching fuzz coverage entry in `CoverageGap222.t.sol` is companion-deleted; the surviving entries are mechanically renumbered `o7 → o6`, `o8 → o7`). The underlying GAME-side `setDecimatorAutoRebuy` was already removed in Phase 146 ABI cleanup (commit `31ec2780`); `2713ce61` closes the orphan wrapper.

### Per-Declaration Classification

| Declaration | File | Lines (landing-SHA) | Taxonomy | Notes |
|---|---|---|---|---|
| `setDecimatorAutoRebuy(address player, bool enabled)` (IDegenerusGamePlayerActions interface member) | `contracts/DegenerusVault.sol` | L31-32 (pre-2713ce61; NatSpec `/// @notice Toggle decimator auto-rebuy for a player.` + function signature line) | **DELETED** | Interface-level selector removal. The underlying GAME-side `setDecimatorAutoRebuy` was removed in Phase 146 ABI cleanup (commit `31ec2780` — `refactor(decimator): remove auto-rebuy, inline whale pass tickets`); `2713ce61` closes the orphan wrapper. |
| `gameSetDecimatorAutoRebuy(bool enabled)` (external vault wrapper) | `contracts/DegenerusVault.sol` | L640-645 (pre-2713ce61; 5-line block: NatSpec L640-642 + signature L643 + body L644 + close L645) | **DELETED** | External wrapper that proxied an admin GAME function. Body `gamePlayer.setDecimatorAutoRebuy(address(this), enabled);` would have reverted at runtime post-Phase-146 because the GAME-side selector was already gone; orphan no-op from Phase 146 close through 2713ce61 landing. |
| Fuzz coverage entry `o6` (`gameSetDecimatorAutoRebuy(bool)` low-level call + matching `assertFalse(o6, ...)` rejection assertion) | `test/fuzz/CoverageGap222.t.sol` | pre-landing entry at L1079-1083 (low-level `.call` block) + L1107 (assertion) | **DELETED** | Coverage-list entry for the removed selector. Companion-deletion of the dead surface: the assertion `vault.gameSetDecimatorAutoRebuy rejected non-vaultOwner caller` can no longer be exercised because the selector is absent from the vault ABI. |
| Fuzz coverage renumber `o7 → o6` + `o8 → o7` | `test/fuzz/CoverageGap222.t.sol` | post-landing entries at L1079-1097 (renumbered low-level call blocks + matching renumbered assertions at L1100-1101) | **REFACTOR_ONLY** | Mechanical renumber: `(bool o7, ) = address(vault).call(... "gameSetAfKingMode(...)")` becomes `(bool o6, ...)`; `(bool o8, ...) "gameSetOperatorApproval(...)"` becomes `(bool o7, ...)`. Matching `assertFalse(...)` strings re-numbered identically. No behavioral change — the surviving rejection assertions still exercise the same vault entry points; only the local-variable identifiers are renamed. |

### Design-Intent Trace

Per D-270-DESIGN-INTENT-METHOD-01.

**Pickaxe command + key output (vault wrapper introduction):**

```bash
git log -p -S "setDecimatorAutoRebuy" -- contracts/DegenerusVault.sol | head -100
```

Anchoring lines:
- Originating landing commit: `4c401497` — `"Degenerus Protocol smart contracts"` (Sun Feb 15 10:34:37 2026; the same initial production-code drop that introduced the AdvanceModule cap-OR arm in Commit A's trace). The vault wrapper `gameSetDecimatorAutoRebuy(bool)` and the matching `IDegenerusGamePlayerActions.setDecimatorAutoRebuy(address,bool)` interface member landed together as part of the initial decimator-auto-rebuy admin surface.
- Removal landing commit: `2713ce61` — `chore(vault): remove dead setDecimatorAutoRebuy wrapper` (Tue May 5 04:39:28 2026). The commit body explicitly names the unreachability cause: "*The underlying setDecimatorAutoRebuy on the GAME contract was removed in the Phase 146 ABI cleanup, leaving the vault's interface stub and gameSetDecimatorAutoRebuy passthrough as unreachable code. Drops the fuzz coverage entry that exercised the dead wrapper.*"

**Pickaxe command + key output (GAME-side function lifetime):**

```bash
git log --all --oneline -S "setDecimatorAutoRebuy" -- 'contracts/**' | head -10
```

Anchoring commits (most-recent first):
- `2713ce61` — vault-side removal (this commit).
- `31ec2780` — Phase 146 ABI cleanup (Apr 9 2026): `refactor(decimator): remove auto-rebuy, inline whale pass tickets`. Commit body: "*Remove auto-rebuy from decimator claims — ETH credited directly. Delete `_processAutoRebuy`, `_addClaimableEth` (no callers remain). Delete `decimatorAutoRebuyDisabled` mapping, setter, and event. Delete `AUTO_REBUY_BONUS_BPS`, `AFKING_AUTO_REBUY_BONUS_BPS` constants. Inline whale pass ticket award in `_awardDecimatorLootbox` — no more two-step claim. Tickets queued directly via `_queueTicketRange`.*" 192 LOC removed from `contracts/modules/DegenerusGameDecimatorModule.sol`; 17 LOC removed from `contracts/DegenerusGame.sol`; 3 LOC removed from `contracts/storage/DegenerusGameStorage.sol`. This is the canonical Phase 146 ABI cleanup that orphaned the vault wrapper.
- `4c401497` — original Degenerus Protocol smart contracts drop (Feb 15 2026); GAME-side `setDecimatorAutoRebuy` landed.

**Original purpose of the removed code (vault wrapper + interface member):**

The vault wrapper `gameSetDecimatorAutoRebuy(bool enabled)` (gated by `onlyVaultOwner` per its NatSpec) was designed as the proxy admin GAME function that allowed the vault-owner (the >50.1%-DGVE holder) to toggle the vault-as-player's decimator-auto-rebuy state on the GAME contract. The matching `IDegenerusGamePlayerActions.setDecimatorAutoRebuy(address player, bool enabled)` interface member was the typed-call ABI declaration the vault used to dispatch the call. The wrapper was part of a larger admin-passthrough family (BURNIE auto-rebuy via `gameSetAutoRebuy`, BURNIE take-profit via `gameSetAutoRebuyTakeProfit`, AFK king mode via `gameSetAfKingMode`, operator approval via `gameSetOperatorApproval`) that lets the vault-owner administer the vault's player-side state across each subsystem.

**Original purpose of the removed code (fuzz coverage entry):**

The `o6` coverage entry in `CoverageGap222.t.sol` was part of the vault-as-non-vault-owner rejection sweep — it sent a `gameSetDecimatorAutoRebuy(bool)` low-level `.call()` from a non-vault-owner address and asserted the call returned `false` (because the vault's `onlyVaultOwner` modifier would revert). The entry exercised the `NotVaultOwner` revert path for that specific admin selector.

**Unreachability cause (vault wrapper post-Phase-146 + fuzz coverage entry post-2713ce61):**

The Phase 146 ABI cleanup at `31ec2780` (Apr 9 2026) removed the underlying GAME-side `setDecimatorAutoRebuy` function from `contracts/modules/DegenerusGameDecimatorModule.sol` together with the entire `decimatorAutoRebuyDisabled` mapping + `_processAutoRebuy` helper + `AUTO_REBUY_BONUS_BPS` constants — the decimator subsystem moved to a direct-ETH-credit model that does not need an auto-rebuy toggle. After Phase 146 close, any call from the vault wrapper at `gamePlayer.setDecimatorAutoRebuy(address(this), enabled);` would have reverted at runtime because the selector no longer existed on the GAME contract. The vault wrapper was therefore orphan-code from Phase 146 close (Apr 9 2026) through 2713ce61 landing (May 5 2026) — a ~26-day window where the wrapper would unconditionally revert if called. The fuzz coverage entry inherited the same dead status because the rejection path it tested (revert before reaching the GAME contract via `onlyVaultOwner` modifier) was still observable, BUT exercising a known-dead selector adds no coverage value over exercising any other rejection-path selector; deleting the coverage entry tightens the test surface to the actual ABI.

**Forward-looking risk bound (re-introduction prevention):**

- The removed vault selector `gameSetDecimatorAutoRebuy(bool)` was `external onlyVaultOwner` — a 4-byte selector at the vault's public ABI boundary. The removed interface member `setDecimatorAutoRebuy(address,bool)` was a typed-call entry in `IDegenerusGamePlayerActions`. Re-introducing the selector at the vault would require THREE coordinated edits: (a) re-add the interface declaration in `IDegenerusGamePlayerActions`, (b) re-add the external wrapper in `DegenerusVault`, AND (c) re-add the underlying GAME-side function in `DegenerusGameDecimatorModule` (or some replacement module). Without (c), the wrapper would revert at runtime — i.e., (a)+(b) alone reproduce the exact dead state that this commit cleaned up.
- The forward grep recipe is `grep -rn "setDecimatorAutoRebuy\|gameSetDecimatorAutoRebuy" contracts/ test/` which MUST return EMPTY at any future audit HEAD (or, in a hypothetical re-introduction, MUST return a coordinated set across `IDegenerusGamePlayerActions` + `DegenerusVault` + `DegenerusGameDecimatorModule` — a three-site re-add is the deliberate signal). This recipe is the canonical Phase-271-§4 + future-audit anchor preventing accidental re-introduction.
- The fuzz coverage entry surface is bounded by the surviving rejection-sweep entries in `CoverageGap222.t.sol` (`o0`-`o7` for the vault block at HEAD). Adding a new selector to the vault rejection sweep would require a follow-on `o8` entry; the absence of `o8` in the vault block at HEAD is the structural signal that the rejection-sweep coverage matches the live vault ABI.

### Adversarial-Surface Sweep

Per D-270-DEPTH-01 (4 ROADMAP-enumerated surfaces (v)-(viii); ZERO scope expansion).

| Surface | Landing-SHA Evidence | v37.0 HEAD Invariant Cite | Verdict | Verdict Rationale |
|---|---|---|---|---|
| **(v) admin-entry-point-removal blast radius** | `git show 2713ce61 -- contracts/DegenerusVault.sol`: vault `gameSetDecimatorAutoRebuy(bool)` external wrapper at L640-645 DELETED (5-line block including NatSpec + signature + body + brace); interface member `setDecimatorAutoRebuy(address,bool)` at L31-32 DELETED (2-line block: NatSpec + signature). | `grep -rn "setDecimatorAutoRebuy\|gameSetDecimatorAutoRebuy" contracts/ test/` → EMPTY (zero matches anywhere under `contracts/` or `test/` at HEAD). The selector is structurally absent from the vault ABI. | **SAFE_BY_STRUCTURAL_CLOSURE** | The removed admin entry point had no live callers at landing because Phase 146 ABI cleanup (`31ec2780`) had already removed the underlying GAME-side function ~26 days earlier (Apr 9 → May 5 2026). Blast radius from removal is zero: no live contract or test references the selector at v37.0 HEAD; any off-chain ABI consumer using a stale `setDecimatorAutoRebuy` selector would silently no-op via `.call()` (returns false) or fail at compile time via typed-interface call. No state change, no fund movement. |
| **(vi) downstream gating assumptions in BURNIE auto-rebuy code path** | `git show 2713ce61 -- contracts/DegenerusVault.sol`: the diff touches ONLY the two `setDecimatorAutoRebuy`-related declarations; `setAutoRebuy(address,bool)`, `gameSetAutoRebuy(bool)`, `setAutoRebuyTakeProfit(address,uint256)`, `gameSetAutoRebuyTakeProfit(uint256)` are UNTOUCHED in the diff (no hunk lines reference them). | `grep -n "setAutoRebuy\|gameSetAutoRebuy\|setAutoRebuyTakeProfit" contracts/DegenerusVault.sol` → 6 hits at HEAD: L47 `setAutoRebuy(address,bool)` interface decl + L49 `setAutoRebuyTakeProfit(address,uint256)` interface decl + L627 `gameSetAutoRebuy(bool)` external wrapper + L628 wrapper body `gamePlayer.setAutoRebuy(address(this), enabled);` + L634 `gameSetAutoRebuyTakeProfit(uint256)` external wrapper + L635 wrapper body. All present at HEAD; the 3 BURNIE-auto-rebuy survivor selectors (`setAutoRebuy`, `gameSetAutoRebuy`, `setAutoRebuyTakeProfit` family) are byte-identical to landing-SHA. | **SAFE_BY_DESIGN** | Orthogonality: Decimator-auto-rebuy (decimator-jackpot-side admin state) and BURNIE-auto-rebuy (token-rebalance-side admin state) are distinct subsystem state machines. The two share only the linguistic root "auto-rebuy" — there is no shared mapping, shared modifier, shared event, or shared callsite. Removing one orphan admin selector on the Decimator side has zero effect on the BURNIE side's gating predicates: `setAutoRebuy` (BURNIE per-player toggle) + `gameSetAutoRebuy` (BURNIE vault-side wrapper) + `setAutoRebuyTakeProfit` (BURNIE take-profit configuration) all continue to dispatch to the BURNIE-rebalance subsystem in `DegenerusGameMintModule` / `DegenerusGameBoonModule` without modification. |
| **(vii) Decimator state-machine implications** | `git show 2713ce61 -- contracts/DegenerusVault.sol`: 2713ce61 touches no Decimator state-machine declaration or modifier — the diff is confined to the vault's interface stub and external wrapper. The removed wrapper was a control-plane admin call (toggle a flag for a player address), not a state-machine transition. | `grep -rn "decimator.*[Aa]uto[Rr]ebuy\|[Aa]uto[Rr]ebuy.*[Dd]ecimator" contracts/` → EMPTY at HEAD (no callsite combines `decimator` and `auto-rebuy` substrings; the Decimator state machine has zero residual auto-rebuy state). `grep -n "[Aa]uto[Rr]ebuy" contracts/modules/DegenerusGameDecimatorModule.sol` → EMPTY (DecimatorModule has zero auto-rebuy references at HEAD; Phase 146's full cleanup is preserved). | **SAFE_BY_STRUCTURAL_CLOSURE** | The removed wrapper was the LAST callsite at the vault boundary that combined `decimator` + `auto-rebuy` semantics. Phase 146 had already cleaned the interior of the Decimator subsystem (`decimatorAutoRebuyDisabled` mapping deleted; `_processAutoRebuy` helper deleted; `AUTO_REBUY_BONUS_BPS` + `AFKING_AUTO_REBUY_BONUS_BPS` constants deleted; setter + event deleted). With 2713ce61's vault-side cleanup the last user-facing surface that mentioned `decimator-auto-rebuy` is also gone; the Decimator state-machine perimeter at HEAD is byte-clean — zero auto-rebuy state to track, zero auto-rebuy admin surface, zero residual constants. |
| **(viii) residual `setDecimatorAutoRebuy` callsite proof-of-zero** | `git show 2713ce61 -- contracts/DegenerusVault.sol` + `git show 2713ce61 -- test/fuzz/CoverageGap222.t.sol`: 2713ce61's combined diff removed the selector from the interface (L31-32 vault) + the wrapper from the vault (L640-645) + the `o6` coverage entry (L1079-1083 fuzz) + the matching `assertFalse(o6, "vault.gameSetDecimatorAutoRebuy rejected non-vaultOwner caller")` assertion (L1107 fuzz). | **CANONICAL FORWARD-LOOKING RECIPE:** `grep -rn "setDecimatorAutoRebuy\|gameSetDecimatorAutoRebuy" contracts/ test/` → EMPTY at HEAD (zero matches across all `.sol` files under `contracts/` and `test/`). Verified at Phase 270 working-file authoring time (this row); this is the residual-callsite-of-zero proof per DELTA-02. | **SAFE_BY_STRUCTURAL_CLOSURE** | The grep recipe IS the canonical forward-looking anchor preventing re-introduction. Any future commit that re-introduces the selector — partial (interface only, or wrapper only) or full (interface + wrapper + GAME-side impl) — would surface in this grep at Phase 271+ HEAD, gating delta-surface re-audits. At Phase 270 close the recipe returns EMPTY; the proof-of-zero is structurally complete. |

### Actor Game-Theory Walk

Per D-270-DESIGN-INTENT-METHOD-01.

**Actor 1 — Vault owner attempting to call `gameSetDecimatorAutoRebuy(bool)` post-2713ce61.**

- **State at tx entry:** post-landing-SHA vault contract; selector `gameSetDecimatorAutoRebuy(bool)` absent from the vault's external ABI.
- **Low-level dispatch:** `address(vault).call(abi.encodeWithSignature("gameSetDecimatorAutoRebuy(bool)", true))` returns `(success=false, returnData=empty)` because the function selector does not exist in the vault's dispatch table; the fallback function is also absent (the vault has no `fallback()` or `receive()` handler for unmatched selectors at this surface). No state change at the vault. No state change at the GAME contract (the dispatch never reaches the GAME-side call because the vault dispatch fails first).
- **Typed-call dispatch:** `IDegenerusGameVault(vaultAddr).gameSetDecimatorAutoRebuy(true)` fails at compile time (the interface member is absent from the live `DegenerusVault.sol`); any consumer trying this with a stale ABI will fail to compile.
- **Outcome:** NO state change; NO fund movement; NO value transferred; NO observable side-effects beyond the failed `.call()` return value. The vault owner who tries the stale selector simply observes a no-op.

**Actor 2 — Fuzz coverage exercising the removed `o6` selector.**

- **State at tx entry:** post-landing `CoverageGap222.t.sol`; the `o6` entry has been removed (the low-level call + assertion both deleted); the surviving entries (`gameSetAfKingMode`, `gameSetOperatorApproval`) have been renumbered `o7 → o6`, `o8 → o7`.
- **Coverage delta:** the fuzz harness no longer sends the `gameSetDecimatorAutoRebuy(bool)` low-level call; the assertion `vault.gameSetDecimatorAutoRebuy rejected non-vaultOwner caller` no longer fires.
- **Outcome:** fuzz coverage of the SURVIVING vault rejection-sweep entries (`gameClaimWhalePass` at `o3`, `gameSetAutoRebuy` at `o4`, `gameSetAutoRebuyTakeProfit` at `o5`, `gameSetAfKingMode` at the new `o6`, `gameSetOperatorApproval` at the new `o7`) is preserved (the renumber is mechanical; only the local-variable identifiers change). No coverage gap is introduced because the deleted entry exercised a dead selector — removing the assertion `assertFalse(o6, "vault.gameSetDecimatorAutoRebuy rejected non-vaultOwner caller")` removes a known-tautology (any non-vault-owner call to any vault `onlyVaultOwner` function returns false; the assertion was structurally redundant with the surviving `o3`/`o4`/`o5`/`o6`/`o7` assertions).

**Actor 3 — ABI consumer (off-chain script or other contract) using stale `setDecimatorAutoRebuy(address,bool)` selector.**

- **State at tx entry:** consumer holds an ABI compiled against a pre-2713ce61 vault interface; vault at v37.0 HEAD.
- **Low-level `.call()` dispatch:** silent no-op (selector not in vault dispatch table; `call` returns `(success=false, returnData=empty)`). Consumer must inspect the return value to discover the failure.
- **High-level typed-interface call:** consumer that imports `IDegenerusGamePlayerActions` from the v37.0 source tree will fail at compile time (the interface no longer carries `setDecimatorAutoRebuy`); consumer that has a stale local copy of the interface and dispatches via that copy will hit the same low-level `.call()` failure described above.
- **Outcome:** the off-chain consumer must update its ABI to discover the removal; the risk is pure off-chain bookkeeping, NOT on-chain value loss. The vault holds no decimator-auto-rebuy state to lose (the underlying GAME-side state was removed at Phase 146); there is nothing the consumer "should" have toggled that they now cannot.

**Actor 4 — Maintainer hypothetically re-introducing the selector.**

- **State at proposal:** future commit re-adds `setDecimatorAutoRebuy` somewhere under `contracts/`.
- **Three-coordinated-edits requirement:** to be observably functional, the re-introduction needs (a) `IDegenerusGamePlayerActions.setDecimatorAutoRebuy(address,bool)` interface declaration, (b) `DegenerusVault.gameSetDecimatorAutoRebuy(bool)` external wrapper, AND (c) the underlying GAME-side implementation (e.g., a new `setDecimatorAutoRebuy(address,bool)` in `DegenerusGameDecimatorModule` plus matching storage state). Without (c) the wrapper reverts at runtime; without (a) the wrapper fails to compile; without (b) there is no admin entry point.
- **Outcome:** **BLOCKED** at the audit-trail layer. The forward-looking grep recipe `grep -rn "setDecimatorAutoRebuy\|gameSetDecimatorAutoRebuy" contracts/ test/` is the canonical Phase-271+ anchor; any non-EMPTY result at a future audit HEAD MUST be investigated as a deliberate three-site re-add (with matching design-intent trace + actor game-theory walk per `feedback_design_intent_before_deletion.md`). Re-introduction without that audit trail is a `feedback_no_dead_guards.md` + `feedback_design_intent_before_deletion.md` violation.

---

## KI Envelope Walk (DELTA-04)

Per D-270-KI-01. Each row records: the KI envelope's canonical scope language quoted from `KNOWN-ISSUES.md` at v36.0 close; the Phase 270 disposition; and the grep recipe + evidence verifying neither target commit modifies the surface the envelope ranges over. All 4 rows are **RE_VERIFIED-NEGATIVE-scope at Phase 270** — feeds Phase 271 §6b directly.

The target-commit file set against which the KI walk is grep-bounded: `contracts/modules/DegenerusGameMintModule.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol` + `contracts/storage/DegenerusGameStorage.sol` + `contracts/DegenerusVault.sol` + `test/fuzz/CoverageGap222.t.sol` (the 5 distinct files touched by 002bde55 ∪ 2713ce61).

| KI | Scope at v36.0 close (quoted from KNOWN-ISSUES.md) | Phase 270 disposition | Evidence |
|---|---|---|---|
| **EXC-01 (affiliate roll)** | "**Non-VRF entropy for affiliate winner roll.** Deterministic seed (gas optimization). Worst case: player times purchases to direct affiliate credit to a different affiliate. No protocol value extraction." | **RE_VERIFIED-NEGATIVE-scope at Phase 270** | Per-commit hunk inspection: `git show 002bde55 --unified=0 \| grep -iE 'affiliate'` returns 0 added/removed lines; `git show 2713ce61 --unified=0 \| grep -iE 'affiliate'` returns 0 added/removed lines. Neither target commit touches the affiliate-roll code path. (Note: ambient affiliate-pool references exist in the target-commit file set — `AFFILIATE_POOL_REWARD_BPS` constant in AdvanceModule, affiliate-credit accounting in MintModule — but those lines are NOT in either commit's diff.) The EXC-01 deterministic-seed scope is unchanged by Phase 270. Forward-cite Phase 271 §6b. |
| **EXC-02 (prevrandao fallback)** | "**Gameover prevrandao fallback.** `_getHistoricalRngFallback` (`DegenerusGameAdvanceModule.sol:1301`) hashes `block.prevrandao` together with up to 5 historical VRF words as supplementary entropy when VRF is unavailable at game over. A block proposer can bias prevrandao (1-bit manipulation on binary outcomes). Trigger gating: only reachable inside `_gameOverEntropy` (`AdvanceModule:1252`) and only when an in-flight VRF request has been outstanding for at least `GAMEOVER_RNG_FALLBACK_DELAY = 14 days`." | **RE_VERIFIED-NEGATIVE-scope at Phase 270** | Per-commit hunk inspection: `git show 002bde55 --unified=0 \| grep -iE 'prevrandao\|block.difficulty'` returns 0 added/removed lines; `git show 2713ce61 --unified=0 \| grep -iE 'prevrandao\|block.difficulty'` returns 0 added/removed lines. Neither commit touches `_getHistoricalRngFallback` or `_gameOverEntropy`. The 14-day fallback-delay constant + the 5-historical-VRF-words admixture pattern are UNCHANGED at HEAD vs v36.0 baseline (AdvanceModule diff at 002bde55 confines to L139-142 constant block + L431-435 deactivation predicate; AdvanceModule's RNG-fallback code at L1252+ is in a separate region untouched by 002bde55). Forward-cite Phase 271 §6b. |
| **EXC-03 (F-29-04 mid-cycle substitution)** | "**Gameover RNG substitution for mid-cycle write-buffer tickets.** ... if a mid-cycle ticket-buffer swap has occurred (daily RNG request via `_swapAndFreeze(purchaseLevel)` at `DegenerusGameAdvanceModule.sol:292`, OR mid-day lootbox RNG request via `_swapTicketSlot(purchaseLevel_)` at `DegenerusGameAdvanceModule.sol:1082`) and the new write buffer is populated with tickets queued at the current level awaiting the expected-next VRF fulfillment, a game-over event intervening before that fulfillment causes those tickets to drain under the final gameover entropy (`_gameOverEntropy` at `DegenerusGameAdvanceModule.sol:1222-1246`) rather than the originally-anticipated mid-day VRF word." | **RE_VERIFIED-NEGATIVE-scope at Phase 270** | Per-commit hunk inspection: `git show 002bde55 --unified=0 \| grep -iE '_processGameOver\|_gameOverRng\|mid-cycle'` returns 0 added/removed lines; `git show 2713ce61 --unified=0 \| grep -iE '_processGameOver\|_gameOverRng\|mid-cycle'` returns 0 added/removed lines. Neither commit touches `_swapAndFreeze`, `_swapTicketSlot`, or `_gameOverEntropy`. The mid-cycle write-buffer substitution path is UNCHANGED. Forward-cite Phase 271 §6b. |
| **EXC-04 (EntropyLib XOR-shift, NARROWED to BAF-only at v36)** | "**EntropyLib XOR-shift PRNG for BAF jackpot ticket rolls.** `EntropyLib.entropyStep()` (256-bit XOR-shift, shifts 7/9/8) is consumed by `_jackpotTicketRoll` (`DegenerusGameJackpotModule.sol:2186-2229`) for the BAF jackpot ticket-distribution path (target level + offset selection per ticket). ... Lootbox-path consumption was removed at v36.0 per Phase 266 refactor (now uses bit-sliced `EntropyLib.hash2` keccak draws); remaining xorshift consumer is BAF jackpot only — candidate for future-phase refactor following the same bit-sliced keccak pattern." | **RE_VERIFIED-NEGATIVE-scope at Phase 270** | Per-commit hunk inspection: `git show 002bde55 --unified=0 \| grep -iE 'EntropyLib\|jackpotTicketRoll\|xorshift'` returns 0 added/removed lines; `git show 2713ce61 --unified=0 \| grep -iE 'EntropyLib\|jackpotTicketRoll\|xorshift'` returns 0 added/removed lines. Neither commit touches `EntropyLib`, `_jackpotTicketRoll`, or any BAF-jackpot xorshift path. The v36 narrowed-to-BAF-only scope is UNCHANGED by Phase 270 (the BAF-jackpot xorshift consumer lives in `DegenerusGameJackpotModule.sol`, which is NOT in either target commit's file set). Forward-cite Phase 271 §6b. |

**Summary:** Zero KI promotions; zero `KNOWN-ISSUES.md` modifications attributable to Phase 270. All 4 EXC envelopes (EXC-01..04) feed Phase 271 §6b as RE_VERIFIED-NEGATIVE-scope inputs. The target-commit file set is grep-bounded by the 5 distinct files touched (MintModule + AdvanceModule + GameStorage + Vault + CoverageGap222.t.sol); per-commit hunk inspection (`git show <sha> --unified=0`) returns zero added/removed lines matching any of the four KI surface predicates. Phase 270 trivially satisfies D-270-KI-01.

---

## Phase 271 Handoff

Per D-270-FILES-01 + D-270-FCFORMAT-01. Phase 271 inputs cleanly captured at Phase 270 close.

### §3.A row inputs (Phase 271 delta-surface table)

Phase 270's working-file appendix at the canonical path `.planning/phases/270-post-v32-0-deferred-commit-adversarial-sub-audit/270-01-DELTA-SURFACE.md` IS the grep-cite anchor (per D-270-FILES-01 + ROADMAP §270 success-criterion-5). Phase 271 §3.A author consumes:

- **Commit A row** (`002bde55` — feat(presale): auto-deactivate flag on per-mint cap crossing). Source: Commit A section above. Per-declaration classifications: 5 rows (DELETED × 2 + MODIFIED_LOGIC × 1 + NEW × 2). Per-surface verdicts: 4 surfaces (i)-(iv); all SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; ZERO FINDING_CANDIDATE.
- **Commit B row** (`2713ce61` — chore(vault): remove dead setDecimatorAutoRebuy wrapper). Source: Commit B section above. Per-declaration classifications: 4 rows (DELETED × 3 + REFACTOR_ONLY × 1). Per-surface verdicts: 4 surfaces (v)-(viii); all SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE; ZERO FINDING_CANDIDATE.

Phase 271 §3.A author may choose prose disclosure or table format per planner discretion; row shape inherits from `audit/FINDINGS-v33.0..v36.0.md` §3.A precedent.

### §4 surface table inputs (Phase 271 adversarial sweep)

**NONE NEW** — Phase 270's 8 surfaces (i)-(viii) are absorbed into Phase 271 §4's full v37.0 surface table at rows (a)-(h)-adjacent. ROADMAP §271 D-NN-ADVERSARIAL-02 carry schedules `/contract-auditor` + `/zero-day-hunter` SEQUENTIAL pass over the FULL §4 v37 surface table; that pass re-audits Phase 270's two-commit declarations as part of the full v37 surface walk. Phase 270's pure-grep-sweep verdicts (SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE) are recorded with the same vocabulary; if the Phase 271 skill-tool pass agrees, the verdict locks; if it disagrees, Phase 271 §4 takes precedence and the Phase 270 verdict gets revised in the SUMMARY-time disposition row.

### §6 KI walk inputs (Phase 271 §6b KI gating walk)

**4 RE_VERIFIED-NEGATIVE-scope rows** (EXC-01 affiliate roll / EXC-02 prevrandao fallback / EXC-03 F-29-04 mid-cycle substitution / EXC-04 EntropyLib XOR-shift NARROWED-to-BAF-only) per the KI Envelope Walk table above. Phase 271 §6b consumes; zero KI promotions; zero `KNOWN-ISSUES.md` modifications attributable to Phase 270.

### §5 REG-04 prior-finding spot-check inputs

Phase 271 §5 REG-04 sweeps `audit/FINDINGS-v25..v36.0.md` for findings referencing the v37-touched function set including `setDecimatorAutoRebuy` (2713ce61's removed selector) + presale-flag handling (002bde55's modified surface). At v33 close, REG-01 already audited the GameStorage `_livenessTriggered` body byte-identity at 002bde55's slot-move side-effect — Phase 271 REG-04 walk likely encounters that row and marks PASS. Phase 270 forwards the audit-trail context: 002bde55 relocates `LOOTBOX_PRESALE_ETH_CAP` from AdvanceModule L142 to GameStorage L863 (HEAD L864), causing constant-insertion line-shifts in GameStorage; the `_livenessTriggered` body byte-identity holds with line-shift offset = +3 lines from L1246-1256 (pre-002bde55) to L1249-1259 (post-002bde55, per v33 REG-01 row).

### FINDING_CANDIDATE escalations

**ZERO at Phase 270 close** (default expectation per D-270-FCFORMAT-01). All 8 surfaces (i)-(viii) verdict SAFE_BY_DESIGN or SAFE_BY_STRUCTURAL_CLOSURE based on the dual-evidence + design-intent + actor-game-theory walks. No surface flagged FINDING_CANDIDATE; no Phase-271-§3.A-block-ready stub content was authored. If a Phase 271 adversarial-skill pass surfaces a hypothesis that Phase 270 missed, Phase 271 §4 owns the upgrade path.

---

## Self-Check

Per D-270-PLAN-01 Task 3 acceptance criteria. All checks asserted against the working file as it stands at Task 3 close (pre-commit).

| Check | Expected | Status |
|---|---|---|
| H2 section heading "Commit A: 002bde55" present (anchored count) | `grep -cE '^[#][#] Commit A: 002bde55' file` returns 1 | ✓ |
| H2 section heading "Commit B: 2713ce61" present (anchored count) | `grep -cE '^[#][#] Commit B: 2713ce61' file` returns 1 | ✓ |
| H2 section heading "KI Envelope Walk" present (anchored count) | `grep -cE '^[#][#] KI Envelope Walk' file` returns 1 | ✓ |
| H2 section heading "Phase 271 Handoff" present (anchored count) | `grep -cE '^[#][#] Phase 271 Handoff' file` returns 1 | ✓ |
| H2 section heading "Self-Check" present (anchored count) | `grep -cE '^[#][#] Self-Check' file` returns 1 | ✓ (this section) |
| 8 surface verdicts present (4 per commit per D-270-DEPTH-01) | `grep -cE '\(i\) state-machine ordering\|\(ii\) presale-flag timing\|\(iii\) downstream consumer\|\(iv\) presale.*post-presale\|\(v\) admin-entry-point\|\(vi\) downstream gating\|\(vii\) Decimator state-machine\|\(viii\) residual.*setDecimatorAutoRebuy'` returns >= 8 | ✓ |
| 4 KI envelope rows present (EXC-01..04 per D-270-KI-01) | `grep -cE 'EXC-0[1-4]'` returns >= 4 | ✓ |
| 4 RE_VERIFIED-NEGATIVE-scope verdicts in KI walk | `grep -c 'RE_VERIFIED-NEGATIVE-scope'` returns >= 4 | ✓ |
| 2 design-intent trace H3 headings present (one per commit per D-270-DESIGN-INTENT-METHOD-01) | `grep -cE '^[#][#][#] Design-Intent Trace' file` returns 2 | ✓ |
| 2 actor-game-theory walk H3 headings present (one per commit) | `grep -cE '^[#][#][#] Actor Game-Theory Walk' file` returns 2 | ✓ |
| Zero FINDING_CANDIDATE verdict cells (default per D-270-FCFORMAT-01) | no surface row's Verdict column carries the literal string FINDING_CANDIDATE as the cell value; only vocabulary-reference uses in header + handoff sections | ✓ (vocabulary refs only; zero verdict cells) |
| File-level taxonomy classifications present (NEW/MODIFIED_LOGIC/REFACTOR_ONLY/DELETED) | `grep -cE 'NEW\|MODIFIED_LOGIC\|REFACTOR_ONLY\|DELETED'` returns >= 5 | ✓ |
| Zero source-tree mutations at Task 3 commit boundary | `git diff --stat contracts/ test/` returns EMPTY | ✓ (verified pre-commit) |
| Phase 146 ABI cleanup anchored as Commit B unreachability cause | `grep -c 'Phase 146' file` returns >= 1 | ✓ |
| Surface (viii) residual-callsite proof-of-zero at HEAD | `grep -rn 'setDecimatorAutoRebuy\|gameSetDecimatorAutoRebuy' contracts/ test/` returns EMPTY | ✓ |
| BURNIE-auto-rebuy survivors UNCHANGED (surface vi) | `grep -n 'setAutoRebuy\|gameSetAutoRebuy\|setAutoRebuyTakeProfit' contracts/DegenerusVault.sol` returns 6 hits (3 selectors × 2 — interface + wrapper-or-body each) at HEAD | ✓ |
| PS_ACTIVE_MASK writers limited to 2 (surface iv) | `grep -rn 'PS_ACTIVE_MASK\|PS_ACTIVE_SHIFT' contracts/modules/` returns exactly 2 write sites (MintModule.L1037 + AdvanceModule.L432); reads-only in LootboxModule + WhaleModule | ✓ |
| `LOOTBOX_PRESALE_ETH_CAP` GameStorage internal constant (surface i) | `grep -n 'LOOTBOX_PRESALE_ETH_CAP' contracts/storage/DegenerusGameStorage.sol` returns L864 internal constant; `grep -n 'LOOTBOX_PRESALE_ETH_CAP' contracts/modules/DegenerusGameAdvanceModule.sol` returns EMPTY | ✓ |

All Task 3 self-check assertions PASS.

---
