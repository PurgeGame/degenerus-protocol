# Phase 480 — Cross-Model Council Review (plans, pre-execution)

**Date:** 2026-06-29 · **Baseline:** frozen `4ab900f1` · **Subject:** 480-01 + 480-02 execution plans (rename-sweep, zero-behavior-change)

**Seats:** Codex (gpt-5.5, xhigh, agentic frozen-source) ✅ · GLM-5.2 (z.ai, API, source-inlined) ✅ · Claude-lens workflow (5 dimension reviewers → adversarial-verify → synthesize, 26 raw findings) ✅ · Gemini ❌ (Google deprecated the free-tier CLI: `IneligibleTierError` — permanently out until re-authed via Antigravity).

## Headline verdict (all three seats agree)

**The rename itself is byte-neutral — zero behavior / ABI / storage-layout risk.** Layout methodology is sound (the `git diff` vs the pre-rename golden is the real proof, not the tautological post-capture `--check`; `DecEntry`/`TerminalDecEntry` are pure value-type structs so the type-name rename moves only the `typeLabel` string). The F1 split is correctly grounded (sink param = scaled-ENTRIES → `entriesScaled`; the 4 bug-sites = scaled-WHOLE → `wholeTicketsScaled`). `\bTICKET_SCALE\b` correctly excludes `AFKING_TICKET_SCALE`. The 2 inline-asm `.slot` reads bind by name, slot number unchanged. KEEP-set survives.

**BUT the plans are NOT safe to execute exactly as written** — the defects are concentrated in the **verification gates and doc-sync**, not the contract rename. 1 blocking + 2 high + ~8 medium.

---

## BLOCKING

### B-1 — EV-tripwire collision: the stat tests pin the renamed literals, so `npm run test:stat` goes RED on a *correct* rename, and the plan tells the executor to STOP
*Codex F-01 + Claude-lens AG-01 (independently found) + GLM gate-class — triangulated, high confidence.*

`test/stat/JackpotTicketRollBernoulliEv.test.js` (and the Lootbox EV testers) hold **contract-source-string regex assertions** that match the exact tokens 480 renames — e.g. `/uint32\s+whole\s*=\s*scaledTickets\s*\/\s*uint32\(TICKET_SCALE\)/.test(source) ... .to.equal(true)` — pinning both `scaledTickets` (F1, Jackpot:2133) and `TICKET_SCALE` (RN-04, Storage:157). After the rename the source reads `scaledWholeTickets / uint32(QTY_SCALE)`, the regex fails, `.to.equal(true)` FAILS, `npm run test:stat` (a 480-02 acceptance) goes RED. Yet 480-02 counts these in "the 37 EV assertions pass UNCHANGED" and says *"if any required an edit to pass, STOP: a rename disturbed a Bernoulli expression (behavior change, out of scope)."* → the plan's own tripwire **mis-classifies the required RN-10 literal-sync as a behavior change** and halts a correct execution.

**Fix:** Re-scope the EV tripwire to mean *"no NUMERIC / Monte-Carlo expected-value change"* (samples, expected values, math byte-identical). Explicitly **permit source-string-literal updates** in the `*BernoulliEv` regexes (`TICKET_SCALE`→`QTY_SCALE`; `scaledTickets`→`scaledWholeTickets` in the production-source regexes), and add `scaledTickets`/`scaledWholeTickets`/`QTY_SCALE` to the 480-02 sweep.

---

## HIGH

### H-1 (AG-02) — the `ticketQuantity` exclusion gate is broken backwards: it FALSE-REDs on a correct keep
There are **two** `ticketQuantity` tokens bound to `TicketsBought`, not one: the decl `MintModule:165` AND its `@notice` at `:162`. The gate `rg '\bticketQuantity\b' contracts/ | grep -v 'event TicketsBought'` only filters line 165; the `:162` `@notice` survives → gate is non-empty → **FAILS even though the event field (481) was correctly kept**. The acceptance text "exactly one survives" is false (it's two). Also `:162` holds `TICKET_SCALE` so it *must* be edited (→`QTY_SCALE`) while keeping `ticketQuantity`.
**Fix:** filter the whole `TicketsBought` block (or assert count = 2, both bound to the event); keep `ticketQuantity` at `:162`, only swap `TICKET_SCALE`→`QTY_SCALE`.

### H-2 (AG-03) — negative-polarity source-string assertions erode to vacuous-green; no gate catches it
`expect(body.includes("% TICKET_SCALE"), …).to.equal(false)` at `RemByte:97`, `CrossSurfaceTicketMixing:700/:268`. After the rename `"% TICKET_SCALE"` can never appear → `includes` returns false → `.to.equal(false)` **passes for the wrong reason** and the invariant it guarded is silently untested. The 480-02 no-stale grep omits `TICKET_SCALE` (can't blanket it — test/ keeps independent JS `const TICKET_SCALE = 100n` value mirrors), so Task 1 passes green with these stale.
**Fix:** rename the pinned literal to `% QTY_SCALE` in those negative assertions; add a triage step over `rg 'TICKET_SCALE' test/` distinguishing JS value-mirrors (keep) from contract-source-string assertions (rename).

---

## MEDIUM (gate / scope / doc — grouped)

- **M-1 (MERGE-PACKBET = Codex F-03):** "`_packFullTicketBet` body UNTOUCHED" contradicts RN-07 + the no-stale gate. Its signature/body use `customTicket`/`ticketCount`/`amountPerTicket` (`:1043-1057`); RN-07 + the compiler + `! rg 'amountPerTicket|customTicket'` force renaming them, and the gate also hits the FT_* bit-layout doc bare-words (`:380/:385`). **Fix:** restate KEEP precisely — what's untouched in 480 is the function NAME, the `FT_*_SHIFT` constants (names+values), `MODE_FULL_TICKET`/`FT_HAS_CUSTOM_SHIFT`, and the packing shift-*structure* — NOT the param identifiers or doc bare-words, which follow RN-07 (bytecode-neutral). Include `ticketCount:1045` explicitly (it has no gate, could be left a mixed signature).
- **M-2 (MERGE-EVENTFIELD):** split 480-local / 481-event-field identifiers (`ticketCount`, `playerTicket`, `resultTicket`, `TicketsQueuedScaled.quantityScaled` at Storage:560) lack explicit "KEEP for 481" pins and have no no-stale gate; `_queueTicketsScaled` lacks the param-only guard its `_queueEntryRange` sibling has. **Fix:** add the 481 KEEP pins + the param-only guard; complete the `ticketCount` 480-rename site list (`IDegenerusGame.sol:289/296`, `IDegenerusGameModules.sol:430`).
- **M-3 (MERGE-AFK-SCALE):** RESEARCH §8 says `:164-167 → QTY_SCALE = 100`, which taken literally turns `GameAfking:164` into the FALSE "QTY_SCALE = 400" (it semantically denotes `AFKING_TICKET_SCALE = 400`). 480-01 RN-04 handles it correctly; RESEARCH §8 is wrong and the `\bTICKET_SCALE\b` gate can't tell right from wrong. **Fix:** correct RESEARCH §8 (separate `:164` → `AFKING_TICKET_SCALE = 400` from the inherited refs); add `rg -q "AFKING_TICKET_SCALE = 400"` AND `! rg -q "QTY_SCALE = 400"`.
- **M-4 (AG-04):** the F1 disambiguation — the phase's central anti-recurrence goal — has **NO automated gate** (compile is green whether F1 is applied or not; only the human by-eye diff catches it). **Fix:** add `! rg '\b(scaledTickets|countScaled)\b' contracts/`, assert the sink param is `entriesScaled`, and `rg -q 'wholeTicketsScaled'` in Jackpot+Lootbox.
- **M-5 (AG-05):** 480-02 no-stale grep not exhaustive (omits `_fullTicketPayout`, `WHALE_PASS_TICKETS_PER_LEVEL`, `TICKET_SCALE`, Decimator locals); a `_fullTicketPayout` comment at `test/gas/Phase268GasRegression.test.js:46` falls through BOTH plans (RESEARCH §7 greps are `--glob '*.sol'` only). **Fix:** extend the 480-02 grep to the full rename set + drop the `.sol`-only restriction (add a `.js/.mjs` pass).
- **M-6 (SCOPE-03):** the NFT-scrub gate `! rg "1 entry = 1 minted NFT"` matches only 2 of the 4 refs (Storage:674/679 use different wording). **Fix:** broaden to `! rg -i '\bNFT\b' contracts/storage/DegenerusGameStorage.sol` (§10.7 asserts exactly 4, all in Storage).
- **M-7 (IC-01 = Codex F-04):** binding ledger §10.7/§3 still says `TICKET_SCALE` is "[PENDING owner] / LOCKED KEEP" while RESEARCH §8 + both plans execute the ~73-ref `QTY_SCALE` rename. The owner pick (2026-06-29) was recorded only in RESEARCH/plans; the binding doc was never synced. **Fix:** sync ledger §10.7 + §3 to record RENAME→`QTY_SCALE`.
- **M-8 (IC-02 = GLM F-05):** `JackpotBernoulliTester.sol` is required by the frontmatter + RN-04 + the Task-3 "17 files" prose, but omitted from the Task-1/Task-3 `<files>` lists (which show 16). **Fix:** add it to all three manifests.

## LOW / NIT
F1 stale comments (Storage:676, tester); imprecise un-gated anchors; `WHALE_PASS_TICKETS_PER_LEVEL` not enumerated in ledger §10.5/§10.7 + omitted from the 480-02 sweep; `--check`-without-`--capture` row in VALIDATION would false-RED; Jackpot:2127/2133 two-live-locals which→which not bound; ledger §2A stale decimator targets (`levelBets` vs `decLevelBets`).

---

## What this means for the in-flight executor (480-01)
The executor's *contract diff* is sound (byte-neutral). Verify against: **M-1** (did it rename `_packFullTicketBet` params + keep `FT_*_SHIFT`? did it catch `ticketCount:1045`?), **M-4** (F1 applied correctly — `entriesScaled` param vs `wholeTicketsScaled` bug-sites), **H-1** (did it wrongly edit the `:162` `@notice` `ticketQuantity` to satisfy the broken gate, or correctly keep it?). All are by-eye diff checks at the Task-3 gate.

## Recommended amendments (all PLAN/DOC/TEST — ungated, no contract change)
1. 480-02: re-scope the EV tripwire (B-1), fix negative-polarity assertions (H-2), extend the no-stale grep to the full set incl. `.js` (M-5, M-2), add the F1 gate (M-4).
2. 480-01 gate text: fix the `ticketQuantity` exclusion (H-1), broaden the NFT-scrub gate (M-6), restate the `_packFullTicketBet` KEEP (M-1), add the 481 event-field KEEP pins (M-2).
3. RESEARCH §8: correct the AFKING `:164` instruction (M-3).
4. ledger §10.7 + §3: sync `TICKET_SCALE`→`QTY_SCALE` decision (M-7).
5. 480-01 `<files>` manifests: add `JackpotBernoulliTester.sol` (M-8).
