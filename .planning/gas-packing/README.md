# Gas storage-packing phase

The final APPROVED gas bucket: the deferred storage-packing family. Started 2026-06-12 on top of round 7 (HEAD `1bac49f6`, 27 ahead of origin, UNPUSHED).

Baseline before this phase: forge **845/0/110** by name; Game bytecode **19,001 / 24,576** (headroom 5,575); JS ~138 pre-existing reds by name.

## Scope (every open packing item — APPROVED + NHR/PARTIAL adjudicated in-packet)

User decision 2026-06-12: **do everything** — including StakedStonk, which I had recommended deferring. Rationale: behavior-preserving packing changes no function; the only concern was risk on the solvency spine, and the human gate (user) chose to proceed with the extra-rigor net below.

| Stage | Contract | Items | Harness recalibration |
|---|---|---|---|
| A.1 | DegenerusAdmin | ADMIN-09 (APPROVED) | none — zero slot-hardcoded harness |
| A.2 | BurnieCoinflip | RT-PACKING-08 (APPROVED) + RT-PACKING-09 (PARTIAL→safe leg) | none on these mappings; day-lane boundary tests |
| A.3 | StakedDegenerusStonk | RT-PACKING-12 (NHR→human-gated) + RT-PACKING-13 (PARTIAL) — one re-layout | 3 redemption harnesses (SLOT 7–11) |
| B | Game storage | RT-PACKING-01/02/03/04/05/06 + STORAGE-11/12/13 + DECIMATOR-05 + RT-ADVANCE-12 + AdvanceModule hash2 1-liner | ~30 slot-hardcoded harnesses, recalibrated once |

## Recipe (per contract)
1. Packetize → `packet-<contract>.md`; adjudicate NHR/PARTIAL (skeptic split → safe leg only). Maximal packing within the security floor; reject anything that weakens an invariant.
2. Capture `forge inspect <C> storageLayout` PRE → apply → POST; derive per-region slot shifts (REGION-DEPENDENT — never assume uniform −1).
3. Recalibrate every slot-hardcoded harness from the POST layout (authoritative). Wrong-slot writes fail at RUNTIME (NoPass/panic), compile stays green.
4. Every write site of a merged slot becomes a masked RMW preserving the co-resident field — **never cache the packed word across an external call**.
5. Independent reviewer per packet; git-status-verify Write-capable agents.

## Validation gates (per stage, before commit approval)
- `forge clean && forge build` then `forge test` → expect **845/0/110 by name** (raw red count ≠ regression; NON-WIDENING BY-NAME is the gate).
- `npm test` name-set diff vs clean-HEAD worktree baseline. Only acceptable new reds = the `LootboxAutoResolveMintBoostRegression` byte-pins (self-resolve on commit).
- A.3 + B additionally re-run the SOLVENCY-01 / redemption-reentrancy regression set + reinjection-campaign gates.
- Track Game headroom (19,001; packing should be ~bytecode-neutral — flag growth).
- advanceGame chain bound: <10M target, never >16.7M.

## Commit discipline
- One diff per stage, explicit user approval before each contract commit. Tests/.planning/docs commit freely, but planning commits BEFORE touching .sol (commit-guard blocks all commits while contracts dirty).
- Hook: `mv .git/hooks/pre-commit{,.bak}` → commit with `CONTRACTS_COMMIT_APPROVED=1` → restore. Co-Authored-By trailer.
- Reconcile `audit/GAS-AUDIT-DISPOSITION.md` open count per stage (54 → …). Write memory topic at phase close.

## Ledger at phase start (open 54)
- 7 APPROVED, all this family: RT-PACKING-08, ADMIN-09, RT-PACKING-02/03/04/05/06.
- NHR packing: RT-PACKING-12, STORAGE-11/12/13, DECIMATOR-05, RT-ADVANCE-12.
- PARTIAL packing: RT-PACKING-09, RT-PACKING-13, RT-PACKING-01.
- (Remaining open after this phase = the non-packing NHR/PARTIAL backlog.)
