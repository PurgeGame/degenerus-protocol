# Codex council backfill — phases that ran without codex (usage cap until ~2026-06-16 02:33 AM)

Codex hit a ChatGPT usage limit mid-v64. Each phase below ran its NET-1 council with **gemini only**
(+ NET-2 Claude + deterministic scripts). After the reset, run `ask-codex.sh` against each phase's
council prompt, then reconcile any codex-surfaced lead into that phase's `NNN-FINDINGS.md` (and the
terminal `FINDINGS-v64.0.md`). A codex CLEAN/convergent result just adds the second council net on record.

Backfill command per phase:
```bash
bash .planning/audit-v52/cross-model/bin/ask-codex.sh \
  --out .planning/phases/<DIR>/council/<label>.codex.txt \
  .planning/phases/<DIR>/<NNN>-01-COUNCIL-PROMPT-<LABEL>.md
```

## Deferred phases (update as the run proceeds)
- [ ] **401 PACKING-GAS-IDENTITY** — `pack` — dir `401-packing-gas-identity` (gemini CLEAN all 4 + scripts; NET-2 0 surviving leads)
- [ ] **402 PERMISSIONLESS-COMPOSITION** — `perm` — dir `402-permissionless-composition` (gemini + NET-2; codex deferred). ⭐ PRIORITY for codex 2nd opinion: PERM-04 (MintStreakRecorded front-load — USER ruled by-design/event-derivable) + PERM-CRIT-01 (freeze-window ETH-spin deep-revert — USER ruled by-design) + PERM-03-L1 (zero-word defense-in-depth INFO).
- [ ] **403 RNG-FREEZE SPINE** — `rng` — dir `403-rng-freeze-spine` (gemini + NET-2; codex deferred)
<!-- add 404/etc here if they also land before the reset -->

## After backfill
- Reconcile each codex output into the phase findings + flip the "codex deferred" note to "codex on record".
- Re-attest the affected requirements with both council models on record.
