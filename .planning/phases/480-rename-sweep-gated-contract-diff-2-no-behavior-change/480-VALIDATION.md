---
phase: 480
slug: rename-sweep-gated-contract-diff-2-no-behavior-change
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-29
---

# Phase 480 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> **No behavior change.** This phase renames identifiers; the validation proves byte-stable storage layout (label-only golden diff), green compile across the compile-break test set, a green FULL Hardhat suite (the runtime by-name string-assertion class), and no stale literal left in `test/` or `contracts/`.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Foundry (`forge`, Solidity) + Hardhat (Mocha/Chai, JS) |
| **Config file** | `foundry.toml`, `hardhat.config.js` |
| **Layout oracle** | `scripts/layout/storage_layout_oracle.sh` (`--capture` / `--check`); goldens in `scripts/layout/golden/` |
| **Quick run command** | `npx hardhat compile && forge build` (compile-break set) + `scripts/layout/storage_layout_oracle.sh --check` |
| **No-stale-literal guard** | `rg "traitBurnTicket\|ticketsOwedPacked\|_queueTickets\b\|_queueTicketsScaled\b\|_queueTicketRange\b\|_budgetToTicketUnits\|_TICKETS_PER_LEVEL\|VAULT_PERPETUAL_TICKETS" contracts/` returns nothing |
| **Full suite command** | `npm test && npm run test:stat && forge test` |
| **Estimated runtime** | quick (compile + layout `--check`) ~1–2 min; full suite several minutes (≥ the 479-close floor) |

---

## Sampling Rate

- **After every rename task commit:** `npx hardhat compile && forge build` + the no-stale-literal guard for the symbol(s) renamed in that task.
- **After the contract hunk lands:** `storage_layout_oracle.sh --capture` then `git diff scripts/layout/golden/` (label-only) then `--check` green; `forge build` green (compile-break `.t.sol`/`.sol` set).
- **After the test-harness sweep:** FULL Hardhat suite (`npm test`) — the ONLY signal for the runtime by-name string-assertion class (forge cannot see it).
- **After every plan wave:** full suite (`npm test && npm run test:stat && forge test`).
- **Before close (482):** full suite green; layout golden `--check` green; Bernoulli/EV testers green UNCHANGED.
- **Max feedback latency:** ~1–2 min (compile + layout `--check`).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 480-rn-storage | contract | 1 | RN-01, RN-02 | — (layout-stability invariant) | `traitBurnTicket`→`lvlTraitEntry` (incl. 2 `.slot`) + `ticketsOwedPacked`→`entriesOwedPacked`; layout byte-stable | source + layout golden | `forge build && scripts/layout/storage_layout_oracle.sh --check` | ✅ | ⬜ pending |
| 480-rn-sinks | contract | 1 | RN-03 | — | `_queueTickets*`→`_queueEntries*` + params; entries semantics in NatSpec | source assertion | `! rg "_queueTickets\b" contracts/ && npx hardhat compile` | ✅ | ⬜ pending |
| 480-rn-consts | contract | 1 | RN-04 | — | `*_TICKETS_PER_LEVEL`/`VAULT_PERPETUAL_TICKETS`→`*_ENTRIES_*`; values (40/2/4/16) UNCHANGED | source assertion | `rg "WHALE_BONUS_ENTRIES_PER_LEVEL = 40" contracts/` | ✅ | ⬜ pending |
| 480-rn-helper-locals | contract | 1 | RN-05 | — | `_budgetToTicketUnits`→`_budgetToEntries`; `*TicketUnits` (entries) renamed; bug-site scaled-whole disambiguated to `wholeTicketsScaled` | source assertion | `! rg "_budgetToTicketUnits\|TicketUnits" contracts/` | ✅ | ⬜ pending |
| 480-rn-decimator | contract | 1 | RN-06 | — | `DecEntry`/`TerminalDecEntry`/`_decClaimableFromEntry`/`entry*` locals→record; "entry point" comments KEPT | source assertion | `! rg "DecEntry\|_decClaimableFromEntry" contracts/ && rg "Entry Points" contracts/modules/DegenerusGameDecimatorModule.sol` | ✅ | ⬜ pending |
| 480-layout-golden | test | 1 | RN-01, RN-03 (criterion 3) | — (layout-stability invariant) | All ~13 goldens recaptured; diff is label-only (no slot/offset/type move) | golden diff | `scripts/layout/storage_layout_oracle.sh --capture && git diff --stat scripts/layout/golden/ && scripts/layout/storage_layout_oracle.sh --check` | ✅ | ⬜ pending |
| 480-harness-compile | test | 2 | RN-07 | — | Compile-break `.t.sol`/`.sol` renamed (incl. the 2 the map missed) | forge build | `forge build` | ✅ | ⬜ pending |
| 480-harness-byname | test | 2 | RN-07 | — | Runtime by-name string assertions updated (`DeityPassGoldNerf`, `LootboxAutoResolveRegression`, `MintCleanupRegression`); no stale literal in `test/` | full Hardhat | `npm test` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- None — existing forge + Hardhat + layout-oracle infrastructure covers every RN requirement. No new test file is required (this is a behavior-preserving rename; the proof is "the existing suite stays green after the rename + golden recapture"). The only authored artifacts are the recaptured layout goldens and the in-place harness updates.

*Existing infrastructure covers everything; the Bernoulli/EV testers require NO edit (tripwire if they do).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Layout golden diff is label-only | RN-01, RN-03 (criterion 3) | A human/executor must eyeball `git diff scripts/layout/golden/` to confirm only `"label"` strings changed (no `"slot"`/`"offset"`/`"type"`); `--check` proves equality after recapture but the label-only nature is the by-eye gate | After `--capture`: `git diff scripts/layout/golden/` — confirm every hunk is a `label` change; if any `slot`/`offset`/`type` field moved, STOP (a rename hit logic) |
| Batched `.sol` rename diff is rename-only | success criterion 5 | Contract-commit gate — USER reviews `git diff contracts/` to confirm no logic/value/event/selector change before commit | `git diff contracts/`: every hunk is an identifier or comment change; no value, no `event`/`emit` field, no selector, no Bernoulli expression touched |

*The compile-break and runtime by-name classes are fully automated; the two label-only / rename-only confirmations are by-eye gates on the diffs.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or a by-eye diff gate (layout label-only / rename-only)
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (none — existing infra)
- [ ] Runtime by-name string-assertion sweep is a distinct task (forge-invisible; the 479-FIX-05 trap)
- [ ] No watch-mode flags
- [ ] Feedback latency < ~2 min (compile + layout `--check`)
- [ ] `nyquist_compliant: true` set in frontmatter (planner/checker confirms)

**Approval:** pending
