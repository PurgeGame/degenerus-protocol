# AUDIT-V63 PLAN — Post-v62 Audit (Critical Invariants + Reward Game-Theory)

> The method doc for v63.0. Canonical scope + REQ-IDs: `.planning/REQUIREMENTS.md`. Phase structure: `.planning/ROADMAP.md` (v63.0 section). Surface-map prose: `.planning/v63-surface-map/`.

## 0. Why this milestone

Since the v62.0 close (`MILESTONE_V62_AT_HEAD_77580320…`), ~60 commits (40 contract files, +4322/−3489) landed on `main` **without** a formal audit-milestone close — exactly the surfaces the process normally gates hard: storage layout (a full packing phase), the solvency-adjacent redemption rework, the RNG-freeze-adjacent BURNIE emission rework, and the reward game-theory. v63 is the formal audit of that delta, plus the previously-deferred audit debt the USER chose to fold in.

## 1. Subject & baseline

- **Baseline** = v62.0 closure subject `77580320` (last formally audited frozen point).
- **Subject** = HEAD `a8b702a7`, byte-frozen at FOUNDATION (Phase 388). The audit delta = `git diff 77580320 a8b702a7 -- contracts/`.
- The subject must stay byte-identical through every sweep phase (`git diff <frozen-sha> HEAD -- contracts/` empty); a CONFIRMED finding's fix is a separate, gated, USER-hand-reviewed boundary, after which the subject re-freezes.

## 2. The method — COUNCIL + CLAUDE, BOTH (USER 2026-06-14)

Two independent finding nets run in every sweep phase:

1. **The cross-model council** — the Gemini + Codex CLIs (`gemini`, `codex`, both confirmed at `~/.local/bin`) as primary finders, each pass charged neutrally ("here is what we believe is safe — find where it breaks"), adjudicated against the frozen subject. This honors the v62 cross-model premise ([[cross-model-led-audits-over-claude-only]]): Claude-only audits repeatedly missed what the council caught (v60 LIFECYCLE/RNGRETRY/RNGREUSE/gasceil/WHALE-01; v62 V62-01/02/03).
2. **The Claude Workflow net** — deep multi-agent adversarial Workflows (isolated top-model subagents, neutral prompts per [[mythos-isolated-agent-audit-architecture]]), per sweep dimension, with adversarial-verify / loop-until-dry / completeness-critic patterns.

Claude is the **orchestrator**: builds the foundation, runs both nets, ADJUDICATES every lead against frozen source, runs the skeptic gate before any CATASTROPHE/HIGH ([[feedback_skeptic_pass_before_catastrophe]]), and synthesizes. A no-finding verdict for a sweep area requires **both** nets on record. After any Write-capable fan-out, git-status-verify the subject was not mutated ([[feedback_verify_writecapable_agents]]).

## 3. Ordering — FOUNDATION-FIRST

You cannot adjudicate findings without a green oracle, and the packing phase moved storage slots, so the slot-hardcoded harnesses must be recalibrated FIRST. Phase 388 (FOUNDATION) is Claude-built and runs before the sweeps; 389-395 are the dual-net sweeps; 396 is the terminal close.

## 4. Threat weighting (USER-locked)

DOMINANT = RNG/freeze · HIGH = gas-DoS only in the advanceGame chain (16.7M = gg) · SPINE = solvency · LOW/confirmatory = access-control + reentrancy + MEV ([[threat-model-reentrancy-mev-nonissues]]). Keeper-bounty exploitability uses REAL prevailing gas, not the 0.5-gwei peg ([[feedback_bounty_exploit_uses_real_gas_not_peg_ref]]). RNG audits trace BACKWARD from each consumer and enumerate every in-window SLOAD ([[feedback_rng_backward_trace]], [[feedback_rng_window_storage_read_freshness]]).

## 5. Design-intent anchor (do not re-litigate)

The reward rebalances are documented in `.planning/PAPER-REWARD-CHANGES-BRIEF.md`: most are **EV-neutral redistributions** (spins stake the value they replace; ticket budget ×11/9; far-future 1.5×/0.875×; variance ranges centered on the old EV); only the **EV-multiplier lift** (floor 80→90%, ceiling 135→145%, score-to-ceiling 25,500→40,000) and the **recycle-bonus relaxation** change EV. The ECON sweep's job is to VERIFY these stated invariants hold in code (EV-neutrality, bounded accrual, no money-pump), not to flag the documented changes themselves. Also respect the standing by-design rulings ([[intended-game-mechanics-not-findings]], [[degenerette-wwxrp-rtp-by-design]], [[lootbox-resolution-timing-by-design]]).

## 6. The surface-map foundation (already done — 8-agent read-only Workflow)

Seven dimension maps (`.planning/v63-surface-map/{storage-packing,solvency,rng-freeze,reward-economics,gas-identity,permissionless-access,coinflip-burnie}.md`), all verified against source with contracts clean, found **0 HIGH on inspection** — the change set preserves the `claimablePool` identity, the sDGNRS backing identity, the RNG-freeze spine, and the packing value-identities. The MED design-intent leads they surfaced are the prime sweep targets (intaken at FOUNDATION as finding-candidates):

| Lead | Dimension → Phase | Why it's a lead |
|------|-------------------|-----------------|
| Auto-rebuy carry excluded from sDGNRS redemption backing (`previewClaimCoinflips`/`redeemBurnieShare` never read `autoRebuyCarry`) | BURNIE → 392 | redeemers progressively under-credited |
| VAULT seed-stakes (days 1-20) age out of the 30-day first-claim window (only sDGNRS is auto-claimed) | BURNIE → 392 | ~half the seeded initial emission at risk; **most likely to need a contract change** |
| Redemption CLAIM path has no liveness-window gate (only submit does) | SOLV → 390 | strand/double-credit across the gameOver-drain latch |
| Dust-forfeit self-credit via `creditRedemptionDirect` | SOLV → 390 | needs proof the credit is always backed by value leaving sDGNRS |
| Stochastic sDGNRS auto-rebuy backing (a loss zeroes the pending stake) vs old fixed 2M | ECON/RNG → 392/391 | model whether a loss sequence drops backing below obligations |
| Two-window `lootboxEvCapPacked` eviction under resolve-cursor lag >1 level | STORAGE → 389 | the 10 ETH EV cap could be re-earned |
| `DecClaimRound.rngWord` uint32 narrowing | RNG → 391 | freeze-safe but a genuine entropy reduction — check per-bucket distribution bias |
| Box WWXRP-spin (15% of opens) = new whale-half-pass acquisition channel | ECON → 392 | quantify P(S=9) × boxes-per-pass stays near-unfarmable |
| Box ETH-spin reaches a live ETH-pool RMW + recirc inside the solvency-sensitive claim path | SOLV/ACCESS → 390/393 | the V62-03/council CEI surface |

## 7. Phase plan (388-396; numbering continues from v62's 387)

- **388 FOUNDATION** (Claude-built) — freeze subject @ `a8b702a7`; re-derive `forge inspect storageLayout`; recalibrate slot-hardcoded harnesses; green forge+JS baseline; close verifier oracle holes; intake the 7 maps. FND-01..04.
- **389 PACKING-IDENTITY** (dual-net sweep) — storage-layout correctness + gas/refactor behavior-identity (shared refactor surface). STORAGE-01..07, GASID-01..05.
- **390 SOLVENCY-SPINE** (dual-net sweep) — claimablePool / ETH-stETH / sDGNRS backing under the redemption rework + dust-forfeit + CEI + JackpotModule fold. SOLV-01..07.
- **391 RNG-SPINE** (dual-net sweep) — VRF freshness/freeze backward-trace across all new/changed consumers + decimator uint32 entropy + box-spin replay + in-window SLOADs. RNG-01..06.
- **392 ENTROPY-AND-ECON** (dual-net sweep) — reward game-theory + the BURNIE/coinflip rework (coupled via emission/spins/carry): EV-neutrality, money-pump search, scarce-asset invariants, emission conservation, VAULT seed window-aging, auto-rebuy/carry accounting. ECON-01..06, BURNIE-01..06.
- **393 PERMISSIONLESS-COMPOSITION** (dual-net sweep) — new permissionless/keeper entrypoints + adversarial composition across the boundaries the other sweeps touch. ACCESS-01..05.
- **394 LEGACY-DEBT** (dual-net sweep — folded) — the cumulative v50/v51/v52 surface + author `FINDINGS-v50.0.md` + `FINDINGS-v51.0.md`. LEGACY-01..06.
- **395 MUTATION** (Claude-built harness — folded) — the long-pole full mutation campaign over the frozen subject (fix-site + comprehensive oracle; via_ir; CI/overnight). MUT-01..03.
- **396 TERMINAL** — consolidate both nets, council-on-refuted, skeptic gate, adjudicate vs frozen subject, `audit/FINDINGS-v63.0.md` (chmod 444) + `AUDIT-V63-REPORT.html`, re-freeze + `MILESTONE_V63_AT_HEAD_<sha>` + re-attest 58 reqs. TERM-01..03.

## 8. Process rules

- Only committing `contracts/*.sol` needs approval ([[only-contract-commits-need-approval]]); planning/test/docs are hands-off. The commit-guard hook blocks commits while `contracts/*.sol` is dirty (and trips on the literal path token in a commit message) — keep contracts clean during sweeps.
- Pace long/autonomous runs (low concurrency, small batches, checkpoint+commit per unit) to survive a 5h cap mid-run ([[pace-runs-to-survive-5h-cap]]).
- Storage-layout work: `forge inspect <C> storageLayout` for authoritative slots → NON-WIDENING BY-NAME baseline diff (raw red count ≠ regression) ([[storage-packing-breaks-slot-hardcoded-tests]]).
- ⚠ `hardhat compile --force` regenerates `ContractAddresses.sol` → breaks the forge fixture; restore it ([[gas-measure-worstcase-branch-not-typical-seed]]).
