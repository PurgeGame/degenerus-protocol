# v62.0 Audit — Running Findings Ledger

> Mutable working ledger; consolidated into `audit/FINDINGS-v62.0.md` (chmod 444) at Phase 387 TERMINAL.
> Subject = frozen `c4d48008`. Method = CROSS-MODEL-LED (gemini + codex primary; Claude adjudicates vs
> frozen source + reproduces convergent findings on the 380/381 harness). v62 is **document-only** — every
> CONFIRMED finding routes to a USER-gated, batched contract fix; NOTHING is fixed/committed autonomously.

## Severity legend
CRIT (fund-loss / permanent brick) · HIGH (exploitable edge or broken core guarantee) · MED (degraded
guarantee, bounded impact) · LOW/INFO (hardening / observation) · REFUTED · BY-DESIGN.

---

## CONFIRMED FINDINGS

### V62-01 — Permissionless lootbox auto-open is structurally dead for human + presale boxes — **MED–HIGH**
- **Source:** 381-06 council (codex C1), adjudicated vs `c4d48008`, **empirically reproduced**
  (`test/repro/C1BoxAutoOpen.t.sol`, 2/2 pass, zero contract mutation; independently re-run by orchestrator).
- **Defect:** boxes enqueue at `boxPlayers[LR_INDEX]`, but VRF words land at `LR_INDEX − 1` (the request
  pre-increments the index). `_openHumanBoxes`/`boxesPending` read the **active** `LR_INDEX`
  (DegenerusGame.sol:1889/1899), so the just-finalized box at `LR_INDEX − 1` is never auto-opened. Presale
  boxes are additionally skipped by the `lootboxEthBase==0` guard (:1912). Afking-cover leg is immune
  (keys off `rngWordByDay`), the differential tell.
- **Reproduced behavior:** word lands at N=2, LR_INDEX=3 → `openBoxes(50)` opens 0, base unchanged across
  repeated calls + further LR_INDEX advance; manual `openLootBox(actor,2)` opens it. Same on daily path.
- **Impact:** re-opens the WHALE-01 anti-timing vector (v60) for the mainline human/presale box classes —
  with the permissionless valve dead, the box owner solely controls open timing (open-time `currentLevel`
  steer; seed itself frozen). No fund-loss / no solvency or RNG-freeze break.
- **Candidate fix (USER-gated, NOT applied):** point the `openBoxes`/`boxesPending` index reads at
  `LR_INDEX − 1` (where words land) + include the presale-box leg; ship the after-fix regression (assert
  `openBoxes` drains a ready box).
- **Status:** OPEN — routed to USER-gated batched fix. Re-examined under 383 ASYM-02 + 384 COMPO.

---

## NET-GAPS (property the fuzz net should add; not themselves findings)
- **NETGAP-02 — advanceGame liveness (non-revert).** No invariant forbids `advanceGame()` reverting in a
  due/unlocked state (tests only `try/catch`). Green-foldable. Owner: 384 COMPO / 385 LOOP (advanceGame
  harness lives there). From 381-06 gemini G2 net-gap.

---

## REFUTED / BY-DESIGN (recorded so they are not re-flagged)
- **G2 (381-06)** unbounded `_backfillOrphanedLootboxIndices` revert → **REFUTED**: scan breaks on first
  filled index; `LR_INDEX` structurally ≤1 ahead; already net-asserted by `VRFPathInvariants.inv.t.sol`.
- **G1 (381-06)** free-mint `dailyHeroWagers` → **REFUTED**: ETH-only credit, every unit backed by a
  debited `msg.value`/`claimablePool`; afking funding moves `claimablePool` in tandem (SOLVENCY-01).

---

## CARRIED CANDIDATES — to adjudicate in the sweeps (from Phase 380 hand-off)
- **affiliate-score magnitude (~2500× ETH→score)** — a 1.01-ETH affiliate buy yields ~25,250-ether
  `affiliateScore` (mint-qty-weighted, not ETH-capped). Intended unit vs over-allocation/asymmetry? → 383 ASYM.
- **FC1** mid-day-blocks-next-advance (VRFCore) → 385 LOOP/VRF.
- **FC2** Degenerette award match-key vs frozen score-key (DegeneretteFreezeResolution) → 383 ASYM.
- **FC3** WWXRP +0.0004% `_wwxrpBonusBucket` uplift (DegeneretteResolveRepeg) → 383/386 (note WWXRP by-design).
- **FC4** frozen cancel auto-claims + drains `affiliateBase` (V56SecUnmanipulable) → 382 PRIME / 386 affiliate.
- **FC5** entropy-binding no longer observable in slimmed TraitsGenerated event (RngIndexDrainBinding) → 385 VRF.
- **FC6** mid-day-pending stall+swap backfills zero gap days (VRFPathCoverage) → 385 LOOP/VRF.

---

## SWEEP PROGRESS
- [x] 381-06 FUZZ-06 council completeness — 1 finding (V62-01), 2 refuted, 1 net-gap.
- [ ] 382 PRIME (PRIME-01..04) — v61 new code (afking-as-payment + pack · cashout-curse · deity-smite).
- [ ] 383 ASYM (ASYM-01..06) — parallel-path families + affiliate-score + FC2/FC3.
- [ ] 384 COMPO (COMPO-01..03) — advanceGame composition + e2e gas + NETGAP-02 liveness.
- [ ] 385 LOOP (LOOP-01..03) — VRF / gas-bounded loops + FC1/FC5/FC6.
- [ ] 386 PERIPH (PERIPH-01..06) — peripheral contracts + FC4 affiliate.
- [ ] 387 TERMINAL — consolidate → audit/FINDINGS-v62.0.md + closure.
