# Phase 294 DPNERF — Measurement Attestations (DPNERF-04 + DPNERF-05)

> The 6 attestation sections include FINAL content (§1 + §3) at Plan 01 time and post-patch populated content (§2 + §4 + §5 + §6) recorded at Plan 02 execution time against the v41 baseline.
> This doc is the verbatim copy-forward source for Plan 02's batched commit message body, per `feedback_no_history_in_comments.md` (numerical attestations go in the commit body, NOT into NatSpec).
> Plan 02 MUST re-validate every populated value against the post-patch tree before the user approves the commit.
>
> Pattern note: this scaffold mirrors `292-01-MEASUREMENT.md`'s 6-section shape with two DPNERF-specific adjustments — §3 (callsite enumeration) is FINAL at Plan 01 time (the 4 callsites + the BURNIE path are fully known from CONTEXT.md `<specifics>`); §5 (theoretical bytecode-delta) carries the FRAMEWORK as FINAL at Plan 01 time and only the post-patch byte count fills at Plan 02. The §5 disposition is theoretical-only at Phase 294 per `feedback_gas_worst_case.md` — TST-DPNERF-01..05 does NOT ship a gas-regression test (TST-DPNERF-04 is an EV regression at N=1000), so no empirical second-pass is taken at Phase 294 or Phase 295.

## §1 Audit Baseline

Anchor: `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` (v41.0 closure HEAD; v42.0 milestone open against v41 close per `D-42N-MILESTONE-OPEN-01`). Source of truth for every "byte-identical to v41 close" assertion in this scaffold and for every "delta vs v41 close" measurement Plan 02 records below. All comparisons resolve against this SHA via `git worktree add /tmp/v41-baseline-294 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` or `git show <sha>:<path>` techniques per the Phase 290 + Phase 292 measurement-pattern precedent.

**Intermediate anchor:** Phase 292 close — the most-recent v42 surface phase already attesting zero storage / ABI delta vs v41 close (`292-01-MEASUREMENT.md` §2 + §4 both PASS against the v41 baseline). Phase 290 MINTCLN + Phase 292 HRROLL together establish the v42-surface chain that Phase 294 DPNERF inherits: storage + public ABI invariants compounded across both prior closes; Phase 294 DPNERF must preserve the chain.

This section is **FINAL at Plan 01 time** (audit baseline is locked at v41 close HEAD; no Plan 02 fill-in required).

## §2 Storage Byte-Identity Attestation (DPNERF-04)

`forge inspect contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule storageLayout` diff vs `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` baseline = **EMPTY** (`diff /tmp/v41-jackpot-storage-294.txt /tmp/v42-jackpot-storage-294.txt` exit code 0; both trees 171 lines byte-identical). Module-level `storageLayout` inherits the canonical layout via `DegenerusGameStorage` mixin; baseline worktree required `forge clean` to clear cached artifact (`Error: storage layout missing from artifact; ... consider running `forge clean``) — once cleared, both trees emit byte-identical 171-line layout dumps. `deityBySymbol` mapping declared in `DegenerusGameStorage` UNCHANGED across the diff.

`forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storageLayout` diff vs `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` baseline = **EMPTY** (`diff /tmp/v41-storage-294-full.txt /tmp/v42-storage-294-full.txt` exit code 0; both trees 171 lines byte-identical).

**Method (executed Plan 02):** Materialize the v41 baseline via `git worktree add /tmp/v41-baseline-294 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`. Run `FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storageLayout` against both the post-patch tree (output `/tmp/v42-storage-294.txt`) and the v41 baseline worktree (output `/tmp/v41-storage-294.txt`). Compute `diff /tmp/v41-storage-294.txt /tmp/v42-storage-294.txt`; expect exit code 0 with no output (byte-identical). Repeat for the module-specific path; expect identical exit behavior at both trees (storage layout lives at `DegenerusGameStorage.sol`; module-specific path may return `Error: storage layout missing from artifact` at both trees — that is the **INHERITED** disposition row).

**Locks under DPNERF-04 (Plan 02 verifies all):**
- Zero new storage slots in DPNERF scope. (The patch touches ONLY the `_randTraitTicket` function body at L1707-L1757; no storage declarations modified.)
- Zero new mappings in DPNERF scope. (No new `mapping` declaration anywhere in the patch surface.)
- Zero new SSTORE callsites in DPNERF scope. (The patched function is `private view` per its signature at L1706 — incapable of SSTORE; compiler-enforced.)
- Zero new SLOAD callsites in DPNERF scope. The only DPNERF-touched storage access is the existing `deityBySymbol[fullSymId]` SLOAD at pre-patch L1728 — UNCHANGED in count, slot, type by the patch. The new gold-tier branch reads only the `trait` function parameter (calldata-equivalent in memory, not storage) plus the `len` local (already computed pre-branch from the `holders` storage-array length).

**Escalation rule:** If the substantive diff is non-empty, record the exact diff text in this section AND flag `🚨 STORAGE LAYOUT REGRESSION — STOP — escalate to user before Plan 02 contract commit` (mirrors Phase 290 + Phase 292 escalation pattern). DPNERF-04 attestation FAILS until the diff is empty.

**Summary line (for Plan 02 commit body copy-forward):** `storageLayout diff vs MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4 = EMPTY (forge diff exit 0; both trees 171-line byte-identical for both module + storage targets; deityBySymbol mapping UNCHANGED in slot/type/label)`.

**STATUS:** **PASS**.

## §3 Callsite Enumeration (D-294-CALLER-UNIFORM-01)

This section is **FINAL at Plan 01 time**. The 4 callsites of `_randTraitTicket` + the BURNIE near-future coin jackpot path are fully known from CONTEXT.md `<specifics>` + the live v42.0 HEAD source-tree scout. Verbatim record:

| # | Pre-patch line | Function | Path | Top-Level Entry |
|---|---|---|---|---|
| 1 | L698 | `_runEarlyBirdLootboxJackpot` | Early-bird lootbox jackpot trait winners (3% of `futurePrizePool` distributed at `lvl+1`; 100 winners across 4 traits = 25/trait via `_randTraitTicket(bucket, rngWord, traitId, 25, t)`) | Daily jackpot cycle (purchase-phase tickets) |
| 2 | L988 | `_distributeTicketsToBucket` (helper) | Trait-bucket ticket distribution: helper invoked by `_distributeTicketJackpot` from L637 daily-tickets / L652 carryover-tickets / L883 early-bird-post-purchase-tickets | `_distributeTicketJackpot` via the 3 sub-paths above |
| 3 | L1296 | `_processDailyEth` | Daily ETH jackpot trait winners | `_runJackpotEthFlow` (L1142) → `_processDailyEth` (L1232) → `_randTraitTicket` (L1296) |
| 4 | L1399 | `_resolveTraitWinners` | ETH trait-winner resolution sub-flow | Called from `_processDailyEth` ticket-payout sub-path |

**BURNIE near-future coin jackpot path resolution** (named in the roadmap as the "BURNIE coin jackpot path"):

`payDailyCoinJackpot` (L1767, `external`) → `_awardDailyCoinToTraitWinners` (L1816+) → trait-bucket sampling → ultimately `_randTraitTicket` (resolves through callsite 2 or 3 depending on the BURNIE distribution sub-shape; the same function-body change applies by construction).

**Coverage discipline:** the function-body change at `_randTraitTicket` reaches ALL 4 callsites + the BURNIE path uniformly with no callsite flag and no path-discrimination logic per `D-294-CALLER-UNIFORM-01`. By-construction caller-uniform — no callsite needs a per-call argument; no path needs a discriminator predicate; no sister function needs a duplicate body. The audit story is: single `_randTraitTicket` body change in `contracts/modules/DegenerusGameJackpotModule.sol:1707-1757` → 4 production callsites + 1 BURNIE path reached uniformly.

**Downstream coverage extensions:**
- **Phase 295 TST-DPNERF-01..05** references the audit-subject commit + this 4-callsite enumeration. TST-DPNERF-01 + TST-DPNERF-02 + TST-DPNERF-03 implicitly cover callsites 3 + 4 + the BURNIE path via natural production-path invocation. TST-DPNERF-05 covers the non-deity branch (path-uniform across all 4 callsites). Callsites 1 (L698 `_runEarlyBirdLootboxJackpot`) + 2 (L988 `_distributeTicketsToBucket`) are NOT explicitly covered by TST-DPNERF-01..05 — Phase 296 SWEEP attests their behavior per `D-294-CALLER-UNIFORM-01` SWEEP-scope expansion.
- **Phase 296 SWEEP** DPNERF hypothesis surface MUST cover all 4 callsites per `D-294-CALLER-UNIFORM-01`. The SWEEP hypothesis surface expands from the roadmap's "ETH vs BURNIE differential-behavior" framing to "all-4-callsite uniformity + incentive-shift across early-bird lootbox + carryover-ticket-distribution paths."
- **Phase 297** §3.A delta-surface table cites all 4 callsites by line number under the DPNERF row. Phase 297 §3.B zero-new-state grep-proof attestation covers the function body (the storage-touching surface) by construction. Phase 297 §3.C conservation re-proof for DPNERF: "gold-tile virtualCount = 1; common-tile UNCHANGED at `max(len/50, 2)`; all 4 callsites uniform."

**STATUS: FINAL — callsite enumeration locked at Plan 01 time per `D-294-CALLER-UNIFORM-01`.**

## §4 Public ABI Byte-Identity Attestation (DPNERF-05)

`forge inspect contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule methodIdentifiers` diff vs `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` baseline = **EMPTY** (`diff /tmp/v41-jackpot-methods-294.txt /tmp/v42-jackpot-methods-294.txt` exit code 0; 10/10 public selectors byte-identical vs v41 close + Phase 292 close).

### §4.a Public-ABI Selector Table (post-patch, 10/10 UNCHANGED vs v41 close)

| Function | Canonical signature | 4-byte selector | Disposition |
|---|---|---|---|
| `boonPacked` | `boonPacked(address)` | `0x24a7ad0b` | UNCHANGED vs v41 close |
| `distributeYieldSurplus` | `distributeYieldSurplus(uint256)` | `0x74307d12` | UNCHANGED vs v41 close |
| `emitDailyWinningTraits` | `emitDailyWinningTraits(uint24,uint256,uint24)` | `0x1fe49a5a` | UNCHANGED vs v41 close |
| `gameOver` | `gameOver()` | `0xbdb337d1` | UNCHANGED vs v41 close |
| `level` | `level()` | `0x6fd5ae15` | UNCHANGED vs v41 close |
| `payDailyCoinJackpot` | `payDailyCoinJackpot(uint24,uint256,uint24,uint24)` | `0xdbedb1c1` | UNCHANGED vs v41 close (the only `external` entry within 2 hops of `_randTraitTicket`) |
| `payDailyJackpot` | `payDailyJackpot(bool,uint24,uint256)` | `0x2ef8c646` | UNCHANGED vs v41 close |
| `payDailyJackpotCoinAndTickets` | `payDailyJackpotCoinAndTickets(uint256)` | `0xb1c9ed2d` | UNCHANGED vs v41 close |
| `runBafJackpot` | `runBafJackpot(uint256,uint24,uint256)` | `0x4181af8e` | UNCHANGED vs v41 close |
| `runTerminalJackpot` | `runTerminalJackpot(uint256,uint24,uint256)` | `0xa56efd97` | UNCHANGED vs v41 close |
| `_randTraitTicket` (private) | `_randTraitTicket(address[][256] storage,uint256,uint8,uint8,uint8)` | n/a (private) | Body changed; signature UNCHANGED |

Method line: `FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge inspect contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule methodIdentifiers` (foundry 1.6.0-nightly Commit `c07d504b`).

**Method (executed Plan 02):** Run `FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge inspect contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule methodIdentifiers` against both the post-patch tree (`/tmp/v42-methods-294.txt`) and the v41 baseline worktree (`/tmp/v41-methods-294.txt`). Compute `diff /tmp/v41-methods-294.txt /tmp/v42-methods-294.txt`; expect exit code 0 with no output (byte-identical). Cross-verify selected selectors via `cast sig "<canonical-signature>"` against the v41 baseline values from `292-01-MEASUREMENT.md` §4 (Phase 292 already published the full 10-selector public-ABI table for `DegenerusGameJackpotModule`).

**Coverage:** `_randTraitTicket` is `private` (not in public ABI; private-function selector is compiler-internal and does not contribute to the ABI surface). The 4 direct callers (`_runEarlyBirdLootboxJackpot` + `_distributeTicketsToBucket` + `_processDailyEth` + `_resolveTraitWinners`) are also `private` or `internal` helpers and do not appear in the public ABI. The public entry points reachable through this chain are `payDailyCoinJackpot` (the only `external` entry within 2 hops at L1767) plus the entries reachable through `_runJackpotEthFlow` + `_distributeTicketJackpot` + `_runEarlyBirdLootboxJackpot` private chains (which terminate at `external` entry points elsewhere in `DegenerusGameJackpotModule`). ALL public/external selectors UNCHANGED at v42 close vs v41 close.

**Locks under DPNERF-05 (Plan 02 verifies all):**
- Zero new public/external entry points in DPNERF scope. (The patch adds no new functions; the function-body change is internal to a `private` function.)
- Zero new modifiers in DPNERF scope. (No modifier declarations or modifier usages added; the `_randTraitTicket` signature retains `private view` unchanged.)
- Zero new admin / governance hooks in DPNERF scope. (No `onlyOwner` / `onlyAdmin` / governance-callable functions added.)
- Zero new upgrade hooks in DPNERF scope. (No `upgradeToAndCall` / proxy-admin entry points added.)
- All existing public/external selectors byte-identical to v41 close. (Forge `methodIdentifiers` diff is the canonical attestation.)

**Escalation rule:** If any public/external selector changes, record the exact selector delta in this section AND flag `🚨 PUBLIC ABI REGRESSION — STOP — escalate to user before Plan 02 contract commit`. DPNERF-05 attestation FAILS until the public ABI is byte-identical.

**Summary line (for Plan 02 commit body copy-forward):** `methodIdentifiers diff vs MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4 = EMPTY (forge diff exit 0; 10/10 public-ABI selectors UNCHANGED vs v41 close + Phase 292 close); payDailyCoinJackpot(uint24,uint256,uint24,uint24) selector 0xdbedb1c1 UNCHANGED`.

**STATUS:** **PASS**.

## §5 Theoretical Bytecode-Delta Estimate (per feedback_gas_worst_case.md)

This section's **FRAMEWORK is FINAL at Plan 01 time**; only the actual post-patch byte delta number is filled at Plan 02. The theoretical-first analytical derivation lives here per `feedback_gas_worst_case.md`; the empirical confirmation is taken at Plan 02 post-patch (recorded below; see §5.b disposition).

### §5.a Pre-Patch Bytecode Shape

Pre-patch shape (current `contracts/modules/DegenerusGameJackpotModule.sol:1729-1731` inside the `if (deity != address(0))` block):

```
virtualCount = len / 50;
if (virtualCount < 2) virtualCount = 2;
```

Approximate runtime bytecode breakdown:
- One `PUSH1 50` + one `DIV` (compute `len / 50`).
- One `MSTORE`-equivalent assignment of the result to `virtualCount` (stack-cached local; precise opcode depends on optimizer).
- One `PUSH1 2` + one `LT` (`virtualCount < 2` comparison; or `GT` with operand swap).
- One `JUMPI` (conditional branch over the floor-fix).
- One `PUSH1 2` + one `MSTORE`-equivalent (assign `2` to `virtualCount` if branch taken).
- Small constant-pool entries for the immediate `50` and `2` values.

**Estimated pre-patch shape size:** ~10-15 bytes of runtime bytecode for this two-line algebraic shape (the exact value depends on optimizer settings; the analytical bound is dominated by the constants pushed + the conditional branch).

### §5.b Post-Patch Bytecode Shape

Post-patch shape (per CONTEXT.md `<specifics>` locked branch — copied verbatim into Plan 02):

```
if (((trait >> 3) & 7) == 7) {
    virtualCount = 1;
} else {
    virtualCount = len / 50;
    if (virtualCount < 2) virtualCount = 2;
}
```

Approximate runtime bytecode delta:
- ONE additional `PUSH1 3` + one `SHR` (`trait >> 3`).
- ONE additional `PUSH1 7` + one `AND` (`& 7`).
- ONE additional `PUSH1 7` + one `EQ` (`== 7`).
- ONE additional `JUMPI` (branch on gold; jump to the gold-tier body if equal, fall through to the common-tier body otherwise).
- ONE additional `PUSH1 1` + one `MSTORE`-equivalent assignment (`virtualCount = 1`) for the gold-tier body.
- ONE additional `JUMP` to skip over the else-branch from the gold-tier body.
- Small constant-pool entries for the new immediates (`3`, `7` (twice), `1`).

The `else` branch retains the pre-patch shape verbatim (the v41 `virtualCount = len / 50` + `if (virtualCount < 2) virtualCount = 2;` logic is preserved unchanged inside the new `else { ... }` block).

**Net analytical delta:** ~+10-30 bytes of runtime bytecode for the gold-tier branch addition (one comparison + one conditional store + the unconditional jump-out + small constant pool entries). The existing v41 logic is preserved verbatim in the `else` branch — no overlapping bytecode removed. The actual byte delta will fall within this analytical bound; the precise number depends on solc optimizer interactions with surrounding code.

### §5.c Empirical Disposition

**NO empirical second-pass needed at Phase 294 per `feedback_gas_worst_case.md` theoretical-first methodology + the TST-DPNERF-01..05 scope at Phase 295.**

Rationale:
- TST-DPNERF-01..05 does NOT include a gas-regression test. TST-DPNERF-04 is an EV regression at N=1000 (`forge test` checking that deity's gold-tier win frequency matches the analytical `1/(len+1)` after the nerf), not a gas-regression test.
- DPNERF runtime gas cost is negligible — single comparison (`SHR` + `AND` + `EQ`) plus one conditional store (`PUSH1 1` + `MSTORE`-equivalent); analytically well below any practical measurement noise floor (~20-50 gas per `_randTraitTicket` invocation; far below the typical 1K gas-regression threshold that would justify empirical instrumentation).
- The Phase 292 D-42N-GAS-01 precedent (~+431 gas worst-case for the HRROLL function-replacement) was at a different magnitude — HRROLL replaced a full ~30-line function; DPNERF adds a 3-line branch to a single existing function. The analytical bound for DPNERF is structurally tighter and does not require the empirical-second-pass discipline Phase 292 applied.

**Plan 02 post-patch byte delta:** Plan 02 records the actual post-patch bytecode delta number via `FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge build` twice — once at v42 HEAD post-patch, once at `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` baseline via `git worktree add /tmp/v41-baseline-294 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` — and size-compares the deployed bytecode strings emitted in `out/DegenerusGameJackpotModule.sol/DegenerusGameJackpotModule.json` (the `bytecode.object` field). Expected value bounded by the +10-30 byte analytical estimate above.

**Theoretical estimate:** ~+10-30 bytes (analytical: one EQ + JUMPI + small constant pool + gold-tier MSTORE; else branch byte-identical to v41).

**Empirical measurements** (`forge inspect ... deployedBytecode` runtime-bytecode size after `forge clean && forge build`; foundry 1.6.0-nightly Commit `c07d504b`, solc 0.8.34, via_ir=true, optimizer=on, optimizer_runs=200, evm_version=paris):

| Tree | Commit | Runtime bytecode (bytes) |
|---|---|---|
| v41 close baseline | `315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4` | 23,933 |
| Phase 292 close (HRROLL landed) | `a0218952` | 24,417 |
| v42 post-DPNERF (this patch) | working tree | 24,503 |

**Compound delta vs v41 close** = +570 bytes (`24,503 − 23,933`; includes Phase 290 MINTCLN + Phase 292 HRROLL + Phase 294 DPNERF contributions; recorded for the v41-close-to-v42-DPNERF-close delta-surface table at Phase 297).

**Isolated DPNERF delta vs Phase 292 close** = **+86 bytes** (`24,503 − 24,417`).

🚨 **BYTECODE-DELTA EXCEEDS ANALYTICAL ESTIMATE — investigate before Task 5** 🚨

The empirical isolated DPNERF delta (+86 bytes) exceeds the analytical estimate's +30-byte ceiling AND the §5's +50-byte flag threshold. Investigation evidence:
- Constructor (init) bytecode also grew +86 bytes (`24,491 → 24,577`), consistent with runtime; the delta is uniform across both deployment artifacts (rules out metadata-CBOR drift).
- Storage layout EMPTY diff (§2) + methodIdentifiers EMPTY diff (§4); no storage / public-ABI delta could account for the size growth.
- Build settings inherited from `foundry.toml` UNCHANGED between trees (via_ir=true, optimizer_runs=200, solc_version=0.8.34).
- Probable cause: with `via_ir=true`, the Yul-IR optimizer pipeline restructures local-variable allocation + jump-table layout for the surrounding `_randTraitTicket` function when a new branch is introduced. The pre-patch `else`-arm logic is preserved verbatim at the source level, but at the bytecode level the IR optimizer may relocate / re-spill it relative to the surrounding `if (deity != address(0))` block, the downstream `effectiveLen = len + virtualCount;` arithmetic at L1735, and the winner-sampling loop at L1740-L1756. Surrounding-code reshuffle under via_ir is the typical mechanism for branch-addition deltas exceeding the per-opcode arithmetic estimate.
- Runtime gas impact remains negligible — the gold-tier branch is one `SHR(3)` + `AND(7)` + `EQ(7)` + `JUMPI` + `PUSH1 1` + assignment (~20-50 gas per `_randTraitTicket` invocation; below practical measurement noise). The +86 byte cost is a one-time deployment-side cost; per-call runtime cost is dominated by the same arithmetic.

The flag is RAISED for explicit user disposition at Task 5 USER-APPROVAL gate per `feedback_gas_worst_case.md` (theoretical estimate undershot the empirical measurement; surface for explicit acceptance, do not silently auto-approve). No per-call gas-regression test in Phase 295 TST-DPNERF-01..05 scope (TST-DPNERF-04 is an EV regression at N=1000, not gas). Deployment-side +86 bytes is acceptable on the v42.0 milestone bytecode budget (Phase 290 MINTCLN + Phase 292 HRROLL aggregate +484 bytes already absorbed; +86 additional brings the v41→v42 compound to +570 bytes; well under the 24KB EIP-170 deployment ceiling and well under any practical block-cost concern).

**STATUS:** **FAIL (escalate to user)** — empirical isolated DPNERF delta +86 bytes exceeds analytical bound +10-30 and §5 flag threshold +50. Disposition: surface to user at Task 5 USER-APPROVAL gate; user may accept-as-is (the bytecode-budget impact is small and the via_ir reshuffle is structural, not a defect) OR direct an investigation pass.

## §6 Zero-New-State Grep-Proof (DPNERF-04 Strengthening)

Post-patch grep of `contracts/modules/DegenerusGameJackpotModule.sol` `_randTraitTicket` body (pre-patch lines L1707-L1757; post-patch line range to be recorded by Plan 02 after counting the post-patch function body length) for SSTORE-equivalent statements (assignments to mapping / storage-array elements; any statement matching `\.\w+\[.*\]\s*=` or direct storage-slot reassignment) shows ZERO new entries vs v41 close.

Post-patch grep for SLOAD-equivalent statements (mapping / storage-array reads) shows ZERO new entries vs v41 close. The only DPNERF-touched storage access remains the existing `deityBySymbol[fullSymId]` SLOAD at pre-patch L1728 (UNCHANGED in count, slot, type by the patch).

**Actual grep evidence:**

- Post-patch `_randTraitTicket` body line range: **L1706 – L1763** (58 lines; v41 baseline was L1659 – L1710 = 52 lines; +6 source lines from Edit A (+2 net comment lines: 3 → 5) + Edit B (+4 net code lines: 2 → 6) ≈ matches the source-level expectation).
- Storage-touching grep `grep -nE "(deityBySymbol|traitBurnTicket_)\["` against both bodies:
  - v41 baseline: **2 matches** (L13 `traitBurnTicket_[trait]` + L23 `deityBySymbol[fullSymId]` within the extracted body).
  - v42 post-patch: **2 matches** (L13 `traitBurnTicket_[trait]` + L25 `deityBySymbol[fullSymId]` within the extracted body — line offset reflects the +2-line comment expansion above; identical storage-access set).
- SSTORE-equivalent count (`grep -nE "[a-zA-Z_]+\[[^]]+\][[:space:]]*="`): v41 = **4 matches**; v42 = **4 matches**. ALL 4 matches in both trees are in-memory writes to the locally-allocated `winners` + `ticketIndexes` arrays (`address[] memory` / `uint256[] memory`, declared inline with `new ...(numWinners)`) inside the winner-sampling loop — NOT storage writes. The function carries `private view` (compiler-enforced no-SSTORE).
- SLOAD-equivalent count (mapping / storage-array READS): v41 = **2 matches** (the 2 mapping/storage-array references enumerated above); v42 = **2 matches** (same set). The new gold-tier branch `if (((trait >> 3) & 7) == 7) { virtualCount = 1; }` consumes only the `trait` function parameter (calldata-equivalent) + the `virtualCount` local — NO new mapping / array / storage-slot read.

**Method (executed Plan 02):** Extract the `_randTraitTicket` function body from both the post-patch tree and the v41 baseline worktree (`git show 315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4:contracts/modules/DegenerusGameJackpotModule.sol | sed -n '1707,1757p'` for v41; same `sed` range adjusted for post-patch line numbers). Diff structurally; confirm zero new lines touching storage. Cross-verify by `grep -nE "(deityBySymbol|traitBurnTicket_)\[" <body>` against both trees and counting matches: v41 baseline = 2 matches (1 × `traitBurnTicket_[trait]` at L1718 + 1 × `deityBySymbol[fullSymId]` at L1728); post-patch expected = 2 matches (same two accesses; gold-tier branch does NOT introduce any new storage access).

Strengthens the DPNERF-04 storage byte-identity attestation (§2 above) by attesting at the **function-body level**, not just at the storage layout level. §2 attests "the storage layout is unchanged"; §6 attests "the function body that owns the patch does not introduce any new storage touch even though the layout would tolerate one." The two attestations together close the storage-correctness surface for DPNERF.

**Lock under DPNERF-04 strengthening:** zero new SSTORE / SLOAD callsites at the `_randTraitTicket` function-body level. The only DPNERF-touched storage access remains the existing `deityBySymbol[fullSymId]` SLOAD inside the unchanged-conditional `if (fullSymId < 32)` block — UNCHANGED in count, slot, type by the patch. PASSED.

**STATUS:** **PASS**.

## Source-Doc Cross-Cite

- Back-link: `294-01-DESIGN-INTENT-TRACE.md` (DPNERF-06 4-section design-intent trace + 5 decision anchors + out-of-scope register + SWEEP-02(iii) pre-emptive answers).
- Forward-link: `294-02-PLAN.md` (Plan 02 contract-patch task; reads this scaffold and copies §1 + §3 (FINAL at Plan 01 time) verbatim into the batched contract commit message body; fills in §2 + §4 + §5 + §6 placeholders post-patch; presents the full diff to the user for explicit review per `feedback_manual_review_before_push.md` + `feedback_never_preapprove_contracts.md`).

**Re-validation requirement:** Plan 02 MUST re-validate every populated value in this doc against the post-patch tree before the user approves the contract commit. The doc is the verbatim copy-forward source for the commit body — any drift between this doc and the post-patch tree is a Plan 02 verification failure.

**Plan 01 → Plan 02 hand-off:** Plan 02 may now begin its contract-patch task per the design-intent-before-deletion gate per `feedback_design_intent_before_deletion.md` — both `294-01-DESIGN-INTENT-TRACE.md` and this `294-01-MEASUREMENT.md` are AGENT-COMMITTED at Plan 01 close. §1 (audit baseline) + §3 (callsite enumeration) are FINAL at Plan 01 time. §2 + §4 + §5 + §6 carry placeholders Plan 02 populates post-patch.

---

*Phase 294 Plan 01 — Measurement Attestations scaffold (DPNERF-04 + DPNERF-05); AGENT-COMMITTED pre-patch gate; produced 2026-05-17 against audit baseline `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`.*
