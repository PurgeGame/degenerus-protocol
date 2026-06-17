# Phase 420 CORRUPT — Verification

**Subject:** frozen `contracts/` tree `4a67209a` @ HEAD `0bb7deca` (clean, re-verified post-fan-out). No contract change.
**Method:** NET-1 council (Gemini 3 Pro + Codex) + NET-2 (Claude, 2 rounds: 10 + 4 verifiers + completeness critic) + orchestrator crux. Adversarial verification — any non-clean candidate re-traced by an independent refuter.

## Requirement attestation

| Req | Statement | Verdict | Evidence |
|-----|-----------|---------|----------|
| **CORRUPT-01** | Packed-slot integrity (DEC-ALIAS class) — no aliasing/overflow into a neighbour field under any reachable (level, day, offset, player) | ✅ **HOLDS** | 13 flagged slots + 8 critic-surfaced slots all verified; every write is a masked field RMW (compiler-managed or correct manual mask); DEC-ALIAS `lvl+1` isolation crux-confirmed (`Decimator:1017-1024`); EvCap two-window eviction always drops the dead key; slot 5/34 masked RMW preserve co-resident fields |
| **CORRUPT-02** | Write-after-write ordering leaves no exploitable intermediate at any external-call boundary | ✅ **HOLDS** | Mint 4-helper sequence is field-isolated atomic RMW; advance counters mutate under `rngLockedFlag` (reentrant advance reverts `RngNotReady`/purchases revert `RngLocked`); degenerette recirc runs `allowEthSpin=false` so the deferred pool flush is never observed |
| **CORRUPT-03** | Partial-failure atomicity — all-or-nothing where required | ✅ **HOLDS** | Every dispatch stub bubbles via `_revertDelegate`/`revert E()`; the one deliberate swallow (`_handleGameOverPath`) makes no external call (atomic rollback) and falls through to a fresh-read idempotent drain; money paths debit-before-send in one frame |
| **CORRUPT-04** | Reentrancy mid-advance cannot observe a half-updated invariant or double-count | ✅ **HOLDS** | claimWinnings debits both halves + `claimablePool` before payout (1-wei sentinel blocks re-claim); `maybeCurse` writes disjoint storage; subscribe→AFFILIATE.claim is FLIP-only with atomic read-and-zero; `_payoutWithStethFallback` stETH-first/ETH-last fix holds; the only player ETH `call{value:}` runs last |
| **CORRUPT-05** | Solvency / pool identities (`claimablePool == Σ(claimable+afking)` + sDGNRS backing) preserved across every column path | ✅ **HOLDS** (+INFO-01) | Every `balancesPacked` credit/debit pairs an equal `claimablePool` move; sDGNRS INV-10/13/02 keep backing ≥ claims; the two temporary breaks (decimator reserve, terminal sweep) resolve over-reserved and are documented (`Storage:361`). INFO-01: the literal sum statement must include outstanding decimator claim rounds (by-design) |

## Findings
- **Real findings: 0** (0 CAT / 0 HIGH / 0 MED / 0 LOW).
- **INFO-01** (CORRUPT-05): identity statement incomplete during decimator reserve windows — documented, solvency-positive, by-design → 424 MECH (test asserts reserve-inclusive identity).
- **INFO-02** (slot 46 `yieldAccumulator`): cache-overwrite-across-external-call is callee-protected (creditFlip callback-free), not CEI-protected — not reachable on the frozen tree; future-edit fragility → 424 MECH (no-callback regression / comment).

## Routed forward (424 MECH, test-only)
Full-packed-slot layout oracle (not just the 13 flagged); reserve-inclusive solvency invariant test; `creditFlip` no-callback regression; (carryover) worst-case gas harness + P10 regression.

## Success criteria (ROADMAP phase 420) — all met
1. Packed-slot integrity proven across the column ✅ 2. Write-ordering consistent at every external-call boundary ✅ 3. Partial-failure atomicity ✅ 4. Reentrancy cannot corrupt / double-count ✅ 5. Solvency identities preserved (with documented reserve exception) ✅
