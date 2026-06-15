---
phase: 392-entropy-and-econ
plan: 01
subsystem: audit
tags: [council, cross-model, reward-economics, ev-neutrality, money-pump, whale-pass, gemini, codex]

# Dependency graph
requires:
  - phase: 388-foundation-subject-freeze-green-baseline
    provides: "byte-frozen subject a8b702a7 + the FC-392-01..15 reward-economics finding-candidate ledger + the green oracle"
  - phase: 391-rng-spine
    provides: "the proven NET-1 council-net shape (391-01-COUNCIL-PROMPT/NET) + the RNG-freshness slice on record (so the ECON slice can scope to EV/incentive, not freshness)"
provides:
  - "NET 1 (cross-model council) ON RECORD for the full ECON slice (ECON-01..06 + the owned FC-392 reward-economics leads)"
  - "392-01-COUNCIL-PROMPT-ECON.md — the neutral reward game-theory council prompt charged vs frozen a8b702a7"
  - "the raw council output (gemini on record; codex skipped + documented) under the phase council/ dir"
  - "392-01-COUNCIL-NET.md — the capture record + the raw leads routed to 392-03 Wave-2 adjudication"
affects: [392-03 ECON adjudication, 392-04 BURNIE+phase-index, 396 terminal close]

# Tech tracking
tech-stack:
  added: []
  patterns: ["council.sh fan-out → raw capture → COUNCIL-NET record (the established v63 NET-1 shape, matched from 390/391)"]

key-files:
  created:
    - .planning/phases/392-entropy-and-econ/392-01-COUNCIL-PROMPT-ECON.md
    - .planning/phases/392-entropy-and-econ/392-01-COUNCIL-NET.md
    - .planning/phases/392-entropy-and-econ/council/econ.gemini.txt
    - .planning/phases/392-entropy-and-econ/council/econ.council.json
  modified: []

key-decisions:
  - "Single-model-on-record is sufficient with the skip documented: codex hit a HARD usage-limit cap (not transient), so the slice records the codex skip in skipped[]+skip_reasons and proceeds on gemini's real audit per the plan's both-unavailable rule (T-392-02 does not apply — one model IS on record with real content)"
  - "Gemini's first fan-out returned an empty answer (CLI swallows stderr → 1-byte false-green); a direct re-run captured the substantive audit, treated as the real council verdict despite an rc=124 timeout on gemini's trailing (read-only-blocked) report-write step that fired AFTER the full answer was emitted"
  - "The stray gemini repro (test/repro/StreakPumpRepro.test.js, written despite read-only plan mode, OUTSIDE the byte-frozen subject) was removed as an unplanned agent artifact; its content is captured as RAW lead 1/2 for 392-03"
  - "Both gemini HIGH candidates are routed RAW to 392-03 for the skeptic dual-gate vs frozen source — NOT pre-adjudicated here (the council finds; Claude adjudicates at 392-03)"

patterns-established:
  - "Write-capable-agent verification after a council fan-out: git diff a8b702a7 -- contracts/ empty AND scan for stray out-of-out-dir writes ([[feedback_verify_writecapable_agents]])"
  - "Degenerate council output (empty/1-byte answer) is a false-green: re-derive availability from real content, not the -s test, and document the re-run narrative for audit-trail integrity"

metrics:
  duration: "~30 min"
  completed: "2026-06-15"
---

# Phase 392 Plan 01: ENTROPY-AND-ECON — NET 1 (Council) ECON Slice Summary

NET 1 (the cross-model council) is ON RECORD for the full ECON reward-game-theory slice — a neutral
council prompt covering ECON-01..06 + the owned FC-392 reward-economics leads (with the money-pump search,
the whale-half-pass channel, and the redemption ETH-spin value-extraction surface charged hard as dedicated
prime targets, and the design-intent anchor + bounded-accrual doctrine encoded) was authored against the
byte-frozen subject `a8b702a7`, fanned via `council.sh --label econ`, and the raw output captured: gemini
on record with two HIGH candidates + ECON-02/05/01 VERIFIED SOUND, codex skipped (hard usage-limit cap,
documented). The subject is proven byte-frozen throughout; the raw leads are routed to 392-03 for the
skeptic dual-gate.

## What was built

**Task 1 — the neutral ECON council prompt** (`392-01-COUNCIL-PROMPT-ECON.md`, 344 lines, commit
`74d8f2d5`). Matches the just-approved 390/391 prompt shape: header role + "read the EXACT frozen source at
`a8b702a7` via `git show`" instruction; the USER-locked threat-priority line (a closed positive-EV money
pump is HIGH; a scarce-asset supply over-mint and an unbounded accrual are value-bearing; a desirability
complaint about a documented change is NOT a finding); the trust-boundary framing (delegatecall reward
consumers over the shared base; standalone sDGNRS/coinflip; this slice = EV/accrual/scarce-supply, NOT
freshness [391] or aliasing [389]); the DESIGN-INTENT ANCHOR (Class-A EV-neutral redistributions + the two
Class-B documented EV changes are BY-DESIGN — VERIFY the claims hold in code, do not re-litigate); the
KNOWN-BY-DESIGN exclusion list; the thesis mapped to ECON-01..06; the dedicated numbered break-targets (the
ECON-04 money-pump search demanding per-leg value accounting; FC-392-07 whale-pass acquisition-cost +
supply-cap; FC-392-08 redemption ETH-spin value-extraction with the solvency half cross-ref'd to 390; the
FC-392-01/-02 streak-gaming, FC-392-05/-06/-09 EV-cap-bound, FC-392-03/-04/-10 ramp/comment/sentinel, and
FC-392-14/-15 affiliate leads); the explicit ECON-01 bounded-accrual per-surface sweep table; and the
per-finding output format. No verdict pre-stated.

**Task 2 — the council fan-out + NET capture** (`392-01-COUNCIL-NET.md`, 179 lines + the council/ outputs,
commit `0d647da6`). `council.sh --label econ` was run; gemini is on record with a substantive
21-line traced audit; codex is in `skipped[]` with a recorded reason. The COUNCIL-NET record documents the
manifest, the raw output paths, the fan-out narrative (the gemini empty-first-attempt → re-run, the codex
usage-limit skip, the write-capable-agent verification + stray-artifact removal), a one-line characterization
per model, the raw leads routed to 392-03, the byte-freeze attestation, and the explicit "NET 1 ON RECORD"
line.

## Council outcome (RAW — not adjudicated here)

- **gemini (on record):** two HIGH candidate findings + VERIFIED SOUND on ECON-02 / ECON-05 / ECON-01.
  1. **Money pump (ECON-04 prime target):** 100% neutral-EV lootbox floor STACKED with the 10% recycle
     kicker → a claimed repeatable ≥110%-RTP loop; asserts the 10-ETH benefit cap only bounds the uplift
     ABOVE 100%. → routed to 392-03 as the PRIORITY lead; needs the per-leg value accounting (BURNIE
     flip-credit illiquidity + flip-survival + sub-100% direct-open box EV + claimable-must-be-won-first)
     against the frozen `_applyEvMultiplierWithCap` + recycle kicker before any HIGH elevation.
  2. **Streak pump (ECON-06/ECON-01):** afking↔manual same-day toggling double-counts a streak increment,
     breaching the ≤3/day rate bound. → routed to 392-03; needs the frozen `_questCompleteWithPair` afking
     slot-0-skip + the decay anchors re-read, the magnitude lens (ceilings are FIXED — this is ramp-speed
     gaming, not a ceiling breach), and an empirical oracle to confirm/refute.
  - **VERIFIED SOUND:** ECON-02 (the 40/15/15/15/10/5 split, 19,678-bps ticket budget, far/near
    weighting), ECON-05 (the `wwxrpJackpotWhalePassBracketAwarded` flag enforces one-per-bracket supply
    across all channels), ECON-01 (ROI/decimator/EV consumers hard-saturate → no unbounded accrual).
- **codex (skipped):** hard usage-limit cap (not a refusal/timeout); carried to 392-03/396 for an
  opportunistic post-reset second-source re-run. The non-prime charged targets (whale-pass acquisition-cost
  quantification, redemption ETH-spin value-extraction, EV-cap-bound, ramp/comment/sentinel, affiliate
  composition) received no explicit council verdict and are carried Claude-net-primary to 392-03.

## Verification

- Task 1 automated verify: `392-01-COUNCIL-PROMPT-ECON.md` non-empty, references `a8b702a7`, names all of
  ECON-01..06 + FC-392-01..10 + FC-392-14/-15, and matches the money-pump / EV-neutral / whale-half-pass /
  bounded-accrual greps. PASS (344 lines).
- Task 2 automated verify: `econ.council.json` exists; `392-01-COUNCIL-NET.md` non-empty with the explicit
  "NET 1 ON RECORD" line; `git diff a8b702a7 -- contracts/` empty. PASS (179 lines; gemini.txt non-empty).
- Byte-freeze attested immediately after the fan-out (and after removing the stray gemini artifact):
  `git diff a8b702a7 -- contracts/` EMPTY and `git status --porcelain contracts/` EMPTY.

## Deviations from Plan

### Auto-fixed / handled inline (no contract source touched)

**1. [Rule 3 - Blocking] codex hit a hard usage-limit cap — recorded as a documented skip, not retried.**
- **Found during:** Task 2 fan-out.
- **Issue:** `codex exec` failed; `/tmp/ask-codex.err` = "You've hit your usage limit ... try again at
  11:56 PM" — a hard account cap, not transient. Per the package-install exclusion's spirit and the plan's
  detect-and-skip contract, a usage-limit skip is recorded faithfully in `skipped[]`, never fatal.
- **Resolution:** recorded in `econ.council.json` `skipped[]` + a `skip_reasons` field + the COUNCIL-NET
  narrative; carried to 392-03/396 for a post-reset second-source re-run. NOT retried (would fail
  identically until the limit resets).

**2. [Rule 1 - Degenerate output] gemini's first fan-out returned an empty (1-byte) answer — re-run to get
real content.**
- **Found during:** Task 2 fan-out.
- **Issue:** the first `council.sh` run wrote a 1-byte (`\n`) gemini answer that passes the `-s` non-empty
  test → a false-green the manifest would record as "available" with no real audit. The ask-gemini wrapper
  swallows gemini stderr (`2>/dev/null`), hiding the cause.
- **Resolution:** a liveness probe confirmed gemini is live; a direct re-run of the same prompt produced
  the substantive audit captured in `econ.gemini.txt`. The re-run exited rc=124 (timeout) ONLY on gemini's
  trailing read-only-blocked report-write step, AFTER the full answer was already on stdout — so the
  captured output is the complete verdict. The manifest was regenerated to reflect the real state.

**3. [Rule 1 - Write-capable agent escape] gemini wrote a stray repro file despite read-only plan mode —
removed.**
- **Found during:** Task 2 post-fan-out git-status-verify.
- **Issue:** `--approval-mode plan` should be read-only, but gemini wrote `test/repro/StreakPumpRepro.test.js`
  (a hardhat repro for its streak-pump claim) OUTSIDE the council out-dir. The byte-frozen subject
  `contracts/` was NOT touched (T-392-01 holds).
- **Resolution:** removed the single specific stray file (not a blanket clean, per the destructive-git
  prohibition); its content is captured as RAW lead 2 in the COUNCIL-NET record for 392-03. gemini did NOT
  create the `plans/reward-economics-audit.md` it claimed (read-only held for that path).

## Threat surface scan

No NEW security-relevant surface introduced — this plan writes only `.planning/` audit artifacts; the
subject `contracts/` is byte-frozen and verified clean. The STRIDE register (T-392-01 tampering, T-392-02
false-green, T-392-03 scope-drift) mitigations are all satisfied and documented in the COUNCIL-NET record.

## Known Stubs

None. The deliverables (the council prompt + the NET capture record) are complete; the two gemini HIGH
candidates and the non-prime charged targets are RAW leads explicitly routed to 392-03, not stubbed work.

## Self-Check: PASSED

- Created files verified present: `392-01-COUNCIL-PROMPT-ECON.md`, `392-01-COUNCIL-NET.md`,
  `392-01-SUMMARY.md`, `council/econ.gemini.txt`, `council/econ.council.json`.
- Commits verified present: `74d8f2d5` (Task 1 prompt), `0d647da6` (Task 2 fan-out + NET capture).
- Byte-freeze verified: `git diff a8b702a7 -- contracts/` empty; `git status --porcelain contracts/` empty.
