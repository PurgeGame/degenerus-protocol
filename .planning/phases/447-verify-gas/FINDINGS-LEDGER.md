# v72.0 Phase 447 — VERIFY+GAS findings ledger (running)

> Live tracker, appended as the 6 isolated review agents return. Reports live alongside this file (`VERIFY-*.md`, `GAS-*.md`). Cross-model (Codex/Gemini) verification of load-bearing items happens after consolidation. Severity: CAT/HIGH/MED/LOW/INFO.
> Green baseline: forge 944/0/108 (BASELINE.md).

## Agent status
| # | agent | scope | status | verdict |
|---|-------|-------|--------|---------|
| 1 | foilpack | FOIL/RARE/MATCH-01..05, SEC-03, foil-queue liveness | ✅ done | CLEAN 11/11 MATCH · 4 INFO (verified vs **445-SPEC §U+§V = authoritative**; liveness crux holds; EIP-170 OK) |
| 2 | match | MATCH-06..10, PILLAR-RNG/SOLV (foil legs) | ✅ done | 0 CAT/HIGH/MED · 1 LOW · 2 INFO |
| 3 | rig | RIG-01/02, PILLAR-RNG/SOLV (rig) | ✅ done | CLEAN 10/10 MATCH · 3 INFO (EV=100 all tables, P(S9) byte-identical, ETH/FLIP byte-identical) |
| 4 | rescore-ev | RIG-03, MATCH-10 EV | ✅ done | CLEAN · 3 INFO |
| 5 | spine-layout | storage layout, mint refactor, advance brick | ✅ done | CLEAN · 1 LOW (F-03) · 3 INFO · layout all-appended (forge-inspect proven), advance NOT brickable, refactor byte-equiv |

> ## ❌ F-04 WITHDRAWN — NOT A FINDING (USER ruling, protocol owner, 2026-06-21). FIX REVERTED.
> USER: `pendingFuture` is structurally tiny — it accrues only from purchases DURING the brief freeze window, vs `futurePrizePool` = a whole cycle's accumulation. So `pendingFuture` is never anywhere near 10% of `futurePrizePool`. ⇒ the frozen-branch ETH payout (bounded by `pendingFuture` balance + revert-on-insufficient) is already ≲ the same magnitude the unfrozen 10% cap enforces; there is NO extra drain to cap. And paying an ETH win in ETH when pending can cover it is the DESIRED behavior — the lootbox-redirect "fix" wrongly denied legitimate ETH payouts for zero real safety gain. Both Codex and the Claude match-agent missed that `pendingFuture` is inherently small (economic-model knowledge the audit agents lacked). **F-04 fix REVERTED via `git checkout` on the 3 files; only the gas Pick 4 (MintModule) remains. Tree byte-identical to the earlier-proven-green Pick-4 state (forge 944/0/108).**
>
> ## ✅ PHASE 447 VERIFY VERDICT: 0 CAT / 0 HIGH / 0 MED / 0 real LOW. As-built is CLEAN. Only contract change = the optional gas Pick 4. (F-01/F-02/F-03/CG-1 by-design or HOLDS per Codex; F-04 withdrawn by USER.)
> All 33 in-scope requirements verified MATCH against the authoritative 445-SPEC §U+§V. Two LOWs: **F-01 resolved BY-DESIGN** (§V.3), **F-03 defense-in-depth** (bounded-safe today). Independent math confirms: rig EV=100 all tables + P(S9) byte-identical; foil rescore EV 2.16/ticket & 2.633/pack <0.01%; gold@×6 4.69%. Storage all-appended (forge-inspect). advanceGame not foil-brickable. Frozen producers byte-untouched. ETH leg ≤10% cap. Pillars (Solvency/RNG/Liveness) all hold subject to the F-03 hardening decision + CG-1 council coverage.
| 6 | gas | GAS-01/02 candidates | ✅ done | 5 TOP PICKS (~600 gas, behavior-inert) + 1 dead-code |

## Open findings (need decision / cross-model)
- **F-01 · RESOLVED → BY-DESIGN (no fix).** MATCH agent flagged the T=8/4-of-4 moonshot scoring the **hero-overridden** (LIVE) set vs the older §E.3 "hero-free pure-VRF" gate. **Adjudicated against the AUTHORITATIVE spec: `445-SPEC.md §V.3 (D3)` REMOVES the HERO-FREE crux + `heroFreeCount==4` gate** (USER sign-off 2026-06-19) → 4-of-4 is plain `liveCount==4`, hero applied to all tiers, and **"SEC-01 disposition changes from mitigated to accepted by-design."** Safety basis (§V.3 + §V.4 D4): foil lines frozen at buy (no live RNG) + hero wagers committed pre-reveal; steerer controls one quadrant's SYMBOL only, never its COLOR (1/8 VRF) → a 4-of-4 needs the hero quadrant's color to also land by luck (the measured ~8× edge), EV-negative to attempt for a pool-neutral ½ whale pass; two-distinct-heroes (D4) tightens further. **As-built code matches §V.3.** → Codex sanity-check the "EV-negative/pool-neutral" reasoning at 450 REAUDIT (load-bearing, "3 pillars"), but NOT a contract change. The match agent's flag = stale-spec comparison; REQUIREMENTS.md MATCH-09 wording is itself superseded by §V.3 (reconcile in doc, 449/451).
- **F-02 · RESOLVED → BY-DESIGN (optional gas cleanup).** `packedTraitsFoil`/`traitFromWordFoil` uncalled is intended per §V.8 (match lines ARE the VRF roll; no buy-time signature producer). Foilpack agent confirms live path = `_deriveFoilLines`/`foilTrait`, correct. Not a bug. Optional: drop the uncalled funcs from DegenerusTraitUtils as behavior-inert source-surface cleanup in the freeze diff (low value; §U.1/RARE-01 named them, so reconcile doc rather than over-trim). DEFER decision to consolidation.

- **F-03 · LOW (defense-in-depth, PILLAR-LIVE) · SPINE agent.** `_processFoilDrain` outer day-walk decrements the per-call budget per *buyer*, not per empty *day*; the worst-case bound currently leans on the external one-pack-per-level buy guard (`buyFoilPack:177`). Bounded/safe today (no active brick). Hardening = per-empty-day budget decrement. → Codex cross-model: confirm "no active brick today" + whether the hardening is worth landing in the freeze diff. Composes with INFO-2 (named `FOIL_DRAIN_CHARGE` constant).

- **F-04 · MED (candidate) · PILLAR-SOLV / SEC-02 · Codex-found, CODE-CONFIRMED (the milestone's headline finding).** The foil ETH match leg (`FoilPackModule._payFoilTier:604-613` → `resolveEthSpinFromBox` → `DegeneretteModule._distributePayout`) reuses the Degenerette ETH path whose **FROZEN-pool branch (`DegeneretteModule.sol:929-937`) applies NO `ETH_WIN_CAP_BPS` (10%) cap** — only `revert-on-insufficient` vs `pendingFuture`. (Unfrozen branch :938-953 DOES cap + lootbox-spill.) So a foil ETH match claimed while `prizePoolFrozen` pays the full `ethShare` (= `payout/4` for large wins) **uncapped** from `pendingFuture`, bypassing the 10% cap the 445-SPEC §E.5(C)/T-445-E2 PROMISED for the foil ETH lane. **Amplified by foil's large stakes** (`faces × priceForLevel`, up to 10000× @ T=8 / 400× @ T=7 vs normal Degenerette bets). NOT strict insolvency (revert ⇒ pool never negative), BUT: (a) violates the promised 10%-cap invariant; (b) claim-timing boost (freeze claim = uncapped ETH; unfrozen = 10%-capped w/ lootbox spill); (c) drains `pendingFuture` (next-cycle backing), no spill valve. The frozen-no-cap is pre-existing Degenerette behavior (documented :869-873), but FOIL amplifies the exposure massively. Match agent's "frozen→revert" was incomplete (missed the no-cap).
  - **Reachability to confirm:** is `claimFoilMatch` callable while `prizePoolFrozen`? (claims are pull/claim, persist per-level → likely yes). If a foil ETH claim during freeze with small `pendingFuture` reverts, that's also a claim-liveness wrinkle (player must wait for unfreeze).
  - **Fix options (USER picks at freeze gate):** (1) cap the FROZEN branch at 10% of `pendingFuture` + lootbox spill [uniform, but changes SHARED Degenerette frozen behavior — needs its own regression]; (2) foil-specific pre-cap on the ETH stake/share so only the foil lane is capped [contained]; (3) block/defer the foil ETH leg while `prizePoolFrozen` [simplest; claims wait for unfreeze]. → gemini second opinion on severity + preferred fix; then draft into the freeze diff.

### F-04 FIX — DECIDED (Codex option 3, foil-specific resolver) — to implement on green
**Approach:** new foil-specific ETH resolver; during `prizePoolFrozen` the foil ETH leg pays **0 ETH + recircs full payout to lootbox** (stricter than 10% cap, no `pendingFuture` drain, no liveness dependency). Shared `_distributePayout` + regular box-spin/Degenerette path stay BYTE-IDENTICAL (bool-gated additive branch; suite green proves non-foil preserved).
**Files/edits (verified vs real code):**
1. `IDegenerusGameModules.sol` — add `resolveFoilEthSpinFromBox(address,uint256,uint16,uint256,uint32) external payable;` (mirror `resolveEthSpinFromBox`).
2. `DegenerusGameFoilPackModule.sol:607` — selector `resolveEthSpinFromBox` → `resolveFoilEthSpinFromBox`.
3. `DegenerusGameDegeneretteModule.sol` — refactor `resolveEthSpinFromBox` body (`:1584-1649`) into `private _resolveEthSpinFromBox(...,bool foilFrozenLootboxOnly)`; keep `external resolveEthSpinFromBox` → `_resolve(...,false)`; add `external resolveFoilEthSpinFromBox` (require `customTicket!=0`) → `_resolve(...,true)`. Insert AFTER `payout==0` (`:1618`), BEFORE `_distributePayout` (`:1621`):
   `if (foilFrozenLootboxOnly && prizePoolFrozen) { if (s>=7) _awardDegeneretteDgnrs(player,betAmount,s); emit PayoutCapped(player,0,payout); emit BoxSpin(player,betId,packed,payout,0); _resolveLootboxDirect(player,payout,EntropyLib.hash2(seed,BOX_RECIRC_TAG),activityScore,true); return; }`
   (the address-guard `:1591` moves into the private helper so both externals keep it.) Helpers `_resolveLootboxDirect:969`, `_awardDegeneretteDgnrs:1375`, `BOX_RECIRC_TAG:1416`, `PayoutCapped`/`BoxSpin` events all CONFIRMED present.
**Verify:** full forge suite stays ≥944/0 (proves non-foil unchanged) + ADD a test: foil ETH match claimed under `prizePoolFrozen` pays 0 ETH, recircs payout to lootbox, `pendingFuture` untouched; unfrozen still 10%-capped. → into the freeze diff, presented for USER approve/adjust.
**Revert path if cut off:** `git checkout contracts/modules/DegenerusGameDegeneretteModule.sol contracts/interfaces/IDegenerusGameModules.sol contracts/modules/DegenerusGameFoilPackModule.sol` (keeps only Pick 4 in MintModule); leave F-04 for USER.

## Coverage gaps to close at 450 REAUDIT
- **CG-1 · §V.4 D4 two-distinct-heroes (JackpotModule +77).** The bonus draw rolls its OWN hero forced to a DIFFERENT (quadrant,symbol) than the main (main slot zeroed from bonus wager pool); degenerate empty-pool fallback → no bonus hero (pure-VRF bonus set); MAIN draw must stay BYTE-IDENTICAL (`_rollHeroSymbol` untouched; new `_rollHeroSymbolExcluding` view). Not deeply hit by any single 447 agent → explicit council target: byte-identical-main proof + exclusion correctness + empty-pool fallback + bonus entropy independence.
- Doc reconciliation (449/451, not code): REQUIREMENTS.md MATCH-01 ("signatures frozen at buy") + MATCH-09 ("hero-free pure-VRF") + `buyFoilPack` references are pre-§V; as-built follows §V.3/§V.8/§V.12 (no buy-time signature; foil = additive leg of `purchase(...,bool foil)`; single LIVE set). Code correct; update the milestone docs.

## GAS — decisions (skeptic pass applied)
- ✅ **APPLIED · Pick 4** (MintModule `processTicketBatch` :654 + :712): `queue.length != 0` → `total != 0` (total = queue.length cached @ :635; queue not mutated; HOT advance path). ~200 gas. Build+test pending (batched with F-03 decision).
- ❌ **REJECTED · Picks 2 & 3** (cache `rngLockedFlag` / `dailyIdx` in `buyFoilPack`): the two reads straddle the external calls @ :232-281 (`quests.handlePurchase` / `affiliate.payAffiliate` / `coinflip.creditFlip`); the :297 re-read is post-call. Caching across them is NOT provably behavior-inert (a reentrant/advancing call would diverge; forge suite wouldn't catch it). Not freeze-diff material.
- ⏸ **DEFERRED · Picks 1 & 5** (cache `level` in buyFoilPack / `_purchaseWithFoil` ternary): marginal (~100-200 gas, non-hot once-per-level path) + incomplete read-site visibility. Low value; skip unless a deeper 449 pass wants them.
- NOTE: new foil surface is already gas-lean (foilCursor/foilDrainDay/foilLastResolveDay share one slot; RNG/EV math off-limits). The scavenger's safe yield was small → applied the one hot-path win.

## CROSS-MODEL Codex (ChatGPT) — ✅ DONE (`CODEX-xverify.txt`)
- **CLAIM 1 (F-01 steer):** steer edge BOUNDED & by-design safe (agrees) — buy blocks multi-day word grinding, lines from future `rngWordByDay[resolveDay]`, hero = one symbol, color stays 1/8 VRF. ⇒ F-01 stays by-design.
- **CLAIM 1 (solvency subclaim): VIOLATED → became F-04** (frozen ETH branch uncapped — confirmed in code, see F-04).
- **CLAIM 2 (F-03 liveness): HOLDS.** Per-buyer work fixed + budget-gated at 35; short budget stores foilDrainDay/foilCursor & resumes; future/unsealed buckets don't gate; sparse empty-day walk NOT unbounded (buys blocked `day>dailyIdx+1`, caught-up buys reset foilDrainDay). ⇒ **F-03 is NOT a real brick** — defense-in-depth only, NO code change needed (leave documented LOW). Drop the F-03 hardening from the freeze diff.
- **CLAIM 3 (CG-1 two-distinct-heroes): HOLDS.** Main passes `_NO_HERO_EXCLUDE` (byte-equiv to old `_rollHeroSymbol`); bonus uses salted `rBonus=hash2(randWord,BONUS_TRAITS_TAG)`, excludes `(mainQ<<3)|mainSym`, recomputes weights, returns no hero if total→0; no underflow. ⇒ **CG-1 CLOSED clean.**
- Note: Codex flagged my prompt's "liveCount==4/1000-faces" was a stale §V.3 description — as-built is the later Variant-2 rescore (T=8/10000 faces), which the rescore agent already confirmed correct. Not a finding.

## CROSS-MODEL Gemini — ❌ UNAVAILABLE. CLI auth dead: "client no longer supported for Gemini Code Assist for individuals → migrate to Antigravity" (`GEMINI-f04.txt`). Cross-model = Codex (ChatGPT) only this round (matches USER's "cross-model with chatgpt"). F-04 still triangulated: Codex + my own code-read + reachability confirmed.

## F-04 reachability — CONFIRMED REAL
`claimFoilMatch:352` → `_tryClaimFoilMatch:441` → `_payFoilTier:522` has **NO `prizePoolFrozen` / `gameOver` guard** (the only frozen check, :204, is in the BUY path). So a foil ETH match IS claimable while `prizePoolFrozen==true` → hits the uncapped frozen branch. Reachability ✓ → F-04 stands at MED. (Claims also work post-gameOver per MATCH-05 persist; a permanently-frozen terminal state is the liveness edge to weigh in the fix.)

## GAS scavenger raw candidates (reference)
1. FoilPackModule.sol:156-163/229 — cache `level` (read ×3) — ~200 gas/buy
2. FoilPackModule.sol:157/297 — cache `rngLockedFlag` (×2) — ~100 gas/buy
3. FoilPackModule.sol:177/297 — cache `dailyIdx` (×2) — ~100 gas/buy
4. MintModule.sol:654/712 — `queue.length != 0` → `total != 0` (HOT, finished-batch advance) — ~100 gas
5. DegenerusGame.sol:632 — cache `level` in `_purchaseWithFoil` ternary — ~100 gas/buy
- biggest = buyFoilPack SLOAD-cluster hoist (~500 gas). All RNG/EV math (foilCuts/foilTrait/foilBoostBps/WWXRP tables) confirmed OFF-LIMITS; foilCursor/foilDrainDay/foilLastResolveDay already share one slot (no packing win).

## INFO / carry items
- INFO · indexer `FoilMatchClaimed.tier` domain {2,3,4}→{4..8} re-vendor (off-chain; 449 carry). [rescore + match both noted]
- INFO · add a pure-math forge test pinning `Σ P(T)·face(T)` EV-byte-identity (449 TST). [rescore agent]
- INFO · `FOIL-EV-ANALYSIS.md` faces `{2→7,3→65,4→1000}` stale vs as-built `{4→2,5→6,6→35,7→400,8→10000}` (byte-EV-identical) — reconcile doc before 449 EV proof. [match agent]
- INFO · doc-wording MATCH-10 "≈2" vs RIG-03 2.633 — code implements 2.633. [rescore agent]

## 449 TST prep — npm-harness gap (TST-INFRA-01) diagnosis
- `GAME_FOILPACK_MODULE` IS present in `ContractAddresses.sol:68`; forge deploy helper `test/fuzz/helpers/DeployProtocol.sol` includes it → forge 944/0 green. The lag is the **JS deterministic-deploy path**: `scripts/lib/predictAddresses.js` (+ the Hardhat deploy sequence) must slot the new module into the CREATE-nonce order so the predicted address matches the baked constant (symptom = setup mismatch, 0 assertion fails). FIX @ 449: add foilpack to the JS deploy/predict order (JS edits; `ContractAddresses.sol` regen if needed — it is the one approval-free `.sol`). Also wire it into `scripts/layout/storage_layout_oracle.sh` if the JS layout oracle enumerates modules. Then run full `npm test`.
- 449 EV tests to add: pure-math `ΣP(T)·face(T)` EV-byte-identity pin (rescore INFO-2); RIG-01/02 stat oracle (P(S9) invariance, variant-B flip-one ≤M6, own-table EV=100, RTP {70,115,118,120}).

## Positive confirmations banked (reduce reaudit surface)
- No double-claim: CEI marker set before payout + day-truncation guard. [match]
- No zero-seed grind: `dailyFoilDraw` written only post-seal + `rngWordByDay[day]!=0` recheck. [match]
- ETH leg ≤10% `futurePrizePool` (unfrozen) / `pendingFuture` revert (frozen). [match] → PILLAR-SOLV (foil ETH leg) OK
- Disjoint entropy lanes (FOIL_SEED / CCY / SPIN tags). [match] → PILLAR-RNG
- mint==claim invariant: single `_deriveFoilLines`. [match]
- v70-frozen shared trait producers untouched (foil uses new sibling). [match + rescore]
- WWXRP rig apex P(S9) invariant via M≤7 cap. [match — CROSS-CHECK vs rig agent's "M≤6 flip" boundary]
- Foil match face table exact + EV reproduces 2.16/ticket & 2.633/pack <0.01%; no double-pay; ½-whale-pass relocated to T=8 correctly. [rescore]
