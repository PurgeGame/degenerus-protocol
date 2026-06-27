# Phase 475 — CROSS-MODEL-REAUDIT (the conditional contract gate)

**Milestone:** v74.0 — As-Built Milestone Audit + C4A Package
**Executed:** 2026-06-27
**Gate:** ⚑ FIRED — one real defect surfaced and was owner-approved + fixed (`93d17288`).

## Cross-model setup (CMRA-01)
- **Codex** (codex-cli 0.142.2, `codex exec --sandbox read-only`) = primary finder. Authenticated + verified live.
- **Gemini** (gemini-cli 0.47.0) = **unavailable**: `IneligibleTierError` ("This client is no longer
  supported for Gemini Code Assist for individuals"). Not a transient outage — the account tier is
  ineligible. Council ran Codex-only, as the milestone plan assumed.
- Six isolated read-only adversarial passes over the ranked top attack surfaces, neutral prompts, with
  the locked by-design exclusions + the skeptic filter (structural-protection + real-mainnet-gas EV lens)
  embedded. Contracts git-verified unmodified after the read-only runs.

## Dispositions (CMRA-02) — every candidate written up
| # | Surface | Codex verdict | Disposition |
|---|---------|---------------|-------------|
| 01 | Purchase hot-path solvency fold | NONE | clean (corroborates 468 SOLV) |
| 02 | VRF-death deadman + mid-day RNG | CATASTROPHE (prevrandao grind) | **REFUTED / by-design** — the >120d VRF-death super-fallback's grindable terminal distribution is the accepted price of fund-recovery vs permanent brick; owner-ruled, v68 precedent. See KNOWN-ISSUES. |
| 03 | Queue-gate / swap / composition | CATASTROPHE (post-reveal ticket insertion) | **REFUTED** — lootboxes can't be opened after game-over; tickets only ever enter the present level via the freeze-isolated queue (write slot frozen at rng-request). Corroborates 469 RNG-03. |
| 04 | sDGNRS level-start box | MEDIUM (skipped box fires vs known word) | **REFUTED** — `_runSubscriberStage` (box sizing) can only run pre-rng-REQUEST for that day's word, so the resolution word isn't even requested when `amount` is fixed; StaleAdvance/sealed-word guards block stale-word reuse. Corroborates 469 RNG-04. |
| 05 | payAffiliateCombined EV/distribution | NONE | clean (corroborates 471 EV-03; only the immaterial ≤3-FLIP quest rounding) |
| 06 | Access / admin governance timing | MEDIUM (recovery-spanning stale proposal) | **REAL → FIXED `93d17288`** (the one gate). |

## The one real finding — 06 (MEDIUM → fixed)
**`DegenerusAdmin.vote()` / `canExecute()` recovery-spanning stale proposal.** The kill-on-recovery was
*lazy* — it only killed a VRF-coordinator-swap proposal when `vote()` was poked while currently recovered
(`stall < 44h`). A proposal created in stall-1 could survive an un-poked recovery and then, on a later
≥44h re-stall within its 168h lifetime, execute against its **age-decayed** threshold (down to 5%) with
stale votes — installing an arbitrary VRF coordinator below the intended governance bar. The function's
own comment already declared this must not happen; the code didn't enforce it. (My 470 ACCESS-06 audit had
ruled this HOLDS/"terminal" — the cross-model pass caught the lazy-kill gap; recorded as the value of the
council over Claude-only.)

**Fix (owner-approved, `93d17288`):** `vote()` + `canExecute()` additionally invalidate the proposal when
`lastVrfProcessed > createdAt` — any VRF word fulfilled after creation means a recovery occurred, so the
proposal is dead. Recovery-proof without a poke (compares persistent `lastVrfProcessed`). **Logic-only, no
storage/struct change** (Game layout + the 466 storage golden untouched; DegenerusAdmin layout unchanged).
A regression test (stall→recover-un-poked→re-stall ⇒ proposal killed / `canExecute`=false) is added in the
467 harness-green pass. Build clean; the VRFGovernance + GovernanceGating suites stay green (74/74).

## Subject update (cascades to 478)
The byte-frozen subject moves from `3986926c` (tree `280bdb19`) to the fix:
- **impl `93d17288` · `contracts/` tree `f06b1ef6`** — the ONLY contract delta vs `3986926c` is
  `DegenerusAdmin.sol` (+16/−6). The manifest subject pin (MAN-01), the 466 freeze record, and the closure
  baseline are re-pointed to `93d17288`/`f06b1ef6` at Phase 478.

**Verdict:** cross-model adversarial pass complete; 5 surfaces clean/by-design/refuted, 1 real MEDIUM
found → owner-approved fix shipped. The gate is resolved.
