---
phase: 480
slug: rename-sweep-gated-contract-diff-2-no-behavior-change
status: ready
nyquist_compliant: true
wave_0_complete: true
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
| **No-stale-literal guard** | `rg "traitBurnTicket\|ticketsOwedPacked\|_queueTickets\b\|_queueTicketsScaled\b\|_queueTicketRange\b\|_budgetToTicketUnits\|_TICKETS_PER_LEVEL\|VAULT_PERPETUAL_TICKETS\|DecEntry\|TerminalDecEntry\|_decClaimableFromEntry\|amountPerTicket\|customTicket\|_fullTicketPayout\|\bTICKET_SCALE\b" contracts/` returns nothing (all four `*_TICKETS_PER_LEVEL` rename in 480; `TICKET_SCALE`→`QTY_SCALE` — `\bTICKET_SCALE\b` excludes the KEPT `AFKING_TICKET_SCALE`). **`ticketQuantity` is handled separately** — exactly one survives (the `TicketsBought` event field at `MintModule:165`, 481 scope); gate `[ -z "$(rg '\bticketQuantity\b' contracts/ \| grep -v 'event TicketsBought')" ]` (480-01-PLAN Task 1). |
| **Full suite command** | `npm test && npm run test:stat && forge test` |
| **Estimated runtime** | quick (compile + layout `--check`) ~1–2 min; full suite several minutes (≥ the 479-close floor) |

---

## Sampling Rate

- **After every rename task commit:** `npx hardhat compile && forge build` + the no-stale-literal guard for the symbol(s) renamed in that task.
- **After the contract hunk lands:** `storage_layout_oracle.sh --capture` then `git diff scripts/layout/golden/` (label-only) then `--check` green; `forge build` green (compile-break `.t.sol`/`.sol` set).
- **After the test-harness sweep:** FULL Hardhat suite (`npm test`) — the ONLY signal for the runtime by-name string-assertion class (forge cannot see it).
- **After every plan wave:** full suite (`npm test && npm run test:stat && forge test`).
- **Before close (484):** full suite green; layout golden `--check` green; Bernoulli/EV testers green UNCHANGED.
- **Max feedback latency:** ~1–2 min (compile + layout `--check`).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 480-rn-storage | contract | 1 | RN-01, RN-02 | — (layout-stability invariant) | `traitBurnTicket`→`lvlTraitEntry` (incl. 2 `.slot`) + `ticketsOwedPacked`→`entriesOwedPacked`; layout byte-stable | source + layout golden | `forge build && scripts/layout/storage_layout_oracle.sh --check` | ✅ | ⬜ pending |
| 480-rn-sinks | contract | 1 | RN-03 | — | `_queueTickets*`→`_queueEntries*` + params; entries semantics in NatSpec | source assertion | `! rg "_queueTickets\b" contracts/ && npx hardhat compile` | ✅ | ⬜ pending |
| 480-rn-consts | contract | 1 | RN-04 | — | the four `*_TICKETS_PER_LEVEL` (incl. `WHALE_PASS`)/`VAULT_PERPETUAL_TICKETS`→`*_ENTRIES_*` (values 40/2/2/4/16 UNCHANGED) + the dual-use scale factor `TICKET_SCALE`→`QTY_SCALE` (incl. the 2 BernoulliTester mirrors, Bernoulli math byte-identical); `AFKING_TICKET_SCALE`=400 KEPT | source assertion | `rg -q "WHALE_BONUS_ENTRIES_PER_LEVEL = 40" contracts/ && rg -q "QTY_SCALE = 100" contracts/storage/DegenerusGameStorage.sol && ! rg "\bTICKET_SCALE\b" contracts/ && rg -q "AFKING_TICKET_SCALE = 400" contracts/modules/GameAfkingModule.sol` | ✅ | ⬜ pending |
| 480-rn-helper-locals | contract | 1 | RN-05 | — | `_budgetToTicketUnits`→`_budgetToEntries`; `*TicketUnits` (entries) renamed; bug-site scaled-whole disambiguated to `wholeTicketsScaled` | source assertion | `! rg "_budgetToTicketUnits\|TicketUnits" contracts/` | ✅ | ⬜ pending |
| 480-rn-decimator | contract | 1 | RN-06 | — | `DecEntry`/`TerminalDecEntry`/`_decClaimableFromEntry`/`terminalDecEntries`/`levelEntries`/`entry*` locals→**BET** (`DecBet`/`dec`-prefixed: `decLevelBets`/`decBetBurn`/`decBetBucket`/`decBetSubBucket`); "External Entry Points" comments + `decBurn` KEPT | source assertion | `! rg "DecEntry\|_decClaimableFromEntry" contracts/ && rg "struct DecBet" contracts/storage/DegenerusGameStorage.sol && rg "External Entry Points" contracts/modules/DegenerusGameDecimatorModule.sol` | ✅ | ⬜ pending |
| 480-rn-degenerette | contract | 1 | RN-07 | — | `amountPerTicket`→`amountPerSpin`, `ticketCount`→`spinCount`, `customTicket`→`customTraits`, `_fullTicketPayout`→`_degenerettePayout` + `*Traits` locals + Vault/interface lockstep; the EVENTS + `FT_*_SHIFT` + `_packFullTicketBet` body UNTOUCHED (481/482) | source assertion | `! rg "amountPerTicket\|customTicket\|_fullTicketPayout" contracts/ && rg "_packFullTicketBet" contracts/modules/DegenerusGameDegeneretteModule.sol` | ✅ | ⬜ pending |
| 480-rn-ticketquantity | contract | 1 | RN-08 | — | `ticketQuantity`→`entryQuantityScaled` (67 param/local refs Mint/Game/Vault/interfaces); EXACTLY ONE survives — the `TicketsBought` event FIELD at `MintModule:165` (481) | source assertion | `[ -z "$(rg '\bticketQuantity\b' contracts/ \| grep -v 'event TicketsBought')" ] && rg -q "entryQuantityScaled" contracts/DegenerusGame.sol` | ✅ | ⬜ pending |
| 480-doc-fixes | contract | 1 | RN-09 | — | Comment-only F2 (JackpotTicketWin NatSpec)/F3 (ticketsOwedView/getPlayerPurchases/getTickets @return)/F5 (whalePassClaims) + NFT scrub (4 Storage CONV-02 refs); no behavior | by-eye diff | `! rg "1 entry = 1 minted NFT" contracts/` | ✅ | ⬜ pending |
| 480-layout-golden | test | 1 | RN-10 (criterion 4) | — (layout-stability invariant) | All ~25 goldens recaptured; diff is label/typeLabel-only (no slot/offset/bytes/encoding move); standalone goldens byte-identical | golden diff | `scripts/layout/storage_layout_oracle.sh --capture && git diff --stat scripts/layout/golden/ && scripts/layout/storage_layout_oracle.sh --check` | ✅ | ⬜ pending |
| 480-harness-compile | test | 1 | RN-10 | — | The compile-break Solidity set renamed in lockstep — re-derived by grep (LARGER than the pre-§10 7 files: RN-07/RN-08 add ~20 `.sol` test files); `forge build` is the oracle | forge build | `forge build` | ✅ | ⬜ pending |
| 480-harness-byname | test | 2 | RN-10 | — | Runtime JS by-name string assertions updated (`DeityPassGoldNerf` deriveStorageSlot, `LootboxAutoResolveRegression`/`MintCleanupRegression` `.includes`/`===`, the 479-reconciled `_queueTickets(...)` source-string suites); event-field assertions (481) UNTOUCHED; no stale internal literal in `test/` | full Hardhat | `npm test` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- None — existing forge + Hardhat + layout-oracle infrastructure covers every RN requirement. No new test file is required (this is a behavior-preserving rename; the proof is "the existing suite stays green after the rename + golden recapture"). The only authored artifacts are the recaptured layout goldens and the in-place harness updates.

*Existing infrastructure covers everything; the Bernoulli/EV testers require NO edit (tripwire if they do).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Layout golden diff is label/typeLabel-only | RN-10 (criterion 4) | A human/executor must eyeball `git diff scripts/layout/golden/` to confirm only `"label"`/`"typeLabel"` name strings changed (no `"slot"`/`"offset"`/`"bytes"`/`"encoding"`); `--check` proves equality after recapture but the name-only nature is the by-eye gate | After `--capture`: `git diff scripts/layout/golden/` — confirm every hunk is a `label`/`typeLabel` name-string change; if any `slot`/`offset`/`bytes`/`encoding` field moved or a standalone golden changed, STOP (a rename hit layout) |
| Batched `.sol` rename diff is rename-only | success criterion 6 | Contract-commit gate — USER reviews `git diff contracts/` to confirm no logic/value/event/selector/FT_*-packing change before commit | `git diff contracts/`: every hunk is an identifier or comment change; no value, no `event`/`emit` field, no selector, no `FT_*_SHIFT`/`_packFullTicketBet`-body change, no Bernoulli expression touched |

*The compile-break and runtime by-name classes are fully automated; the two label-only / rename-only confirmations are by-eye gates on the diffs.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or a by-eye diff gate (layout label-only / rename-only)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (none — existing infra)
- [x] Runtime by-name string-assertion sweep is a distinct task (forge-invisible; the 479-FIX-05 trap)
- [x] No watch-mode flags
- [x] Feedback latency < ~2 min (compile + layout `--check`)
- [x] `nyquist_compliant: true` set in frontmatter (planner/checker confirms)

**Approval:** approved 2026-06-29; **re-scoped 2026-06-29** to the disambiguation ledger §10 binding scope (added RN-06 Decimator-as-BET, RN-07 Degenerette identifier renames, RN-08 `ticketQuantity`→`entryQuantityScaled`, RN-09 doc/NFT fixes; the compile-break Solidity set is now re-derived by grep, not a fixed list — `forge build` is the oracle).
