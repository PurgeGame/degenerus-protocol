# v74.0 — C4A Readiness: Synthesis & Milestone-Shaping Brief

> Inputs: 5 grounding reports (repo-doc gap audit · frozen-subject + invariant catalog · deploy/harness surface · C4-contest README mechanics · adversarial-agent architecture) + owner CONSTRAINTS.md.
> Subject: Degenerus Protocol `contracts/` tree byte-frozen at git tree `d6615306` (IMPL `64ec993e`), closed under v73.0 (`MILESTONE_V73_AT_HEAD_15650b6a…`, verdict 0 CAT/0 HIGH/0 MED/0 LOW). HEAD is 1 commit ahead (the gas faucet, owner-deprioritized as third-party).

---

## 1. Executive summary

v74.0 has two goals, and they share one engine. The first goal is a **live adversarial agent**: a program that holds funded wallets, plays the protocol continuously, and actively *attempts* to either brick the game or extract more value than the rules allow — not just theorize about it. The second goal is a **C4A-ready package**: get the contest README, scope list, and known-issues perimeter to the point where every issue a Code4rena warden could legitimately get paid for has already been either fixed by us or precisely documented as a known issue (which makes it ineligible for an award).

The good news is that the repo is already most of the way to both. The contract subject is byte-frozen and carries **zero open findings** across all severities, with a deep, well-codified invariant suite (~18 Foundry invariant files plus statistical oracles) that already encodes the exact conservation, EV-ceiling, and liveness properties an adversarial agent needs to watch. The repo also already ships a **one-command full local deploy** (`npm run deploy:local`) that stands up all 25 contracts plus a mock VRF and seeds player wallets, and a complete invariant-handler harness (`test/fuzz/`) that already sequences purchase → advance-day → VRF → multi-level play. The agent does not need to be invented from scratch; it needs to be assembled from parts the repo already has, then pointed at a live deployment.

The work that remains is therefore: **(A)** wrap the existing harness + deploy tooling into a continuously-running daemon with an off-chain economic ledger and a by-design allowlist, run it hard against a local fork as the fast bug-finder, then point the same agent at the live 15-minute-day testnet for a realistic 24/7 soak; and **(B)** do the *documentation and tightening* work that no audit milestone has done yet, because every prior milestone was a code-correctness audit, not a contest-packaging exercise. The repo's contest-facing docs (`scope.txt`, README, KNOWN-ISSUES) are **stale by several milestones** — they still name deleted contracts (BurnieCoin, Stonk, EndgameModule), omit live ones (FoilPack, ActivityCurveLib, the gas faucet), and carry pre-rename names — and there is no SECURITY.md, no in-scope-only nSLOC table, and no known-issues entries for the by-design quirks (Degenerette/WWXRP rig behavior, the carried LOW defense-in-depth items). Closing that gap is the bulk of goal 2, and almost none of it touches a contract.

The only contract-touching decision is whether to **fix** the small carried defense-in-depth items (the `:1843/:1850` re-roll `==0` guard, the VRF rotation-timer hardening) or **document them as accepted-LOW known issues**. The recommendation below is to document, not fix, for v74 — keep the frozen subject frozen so the audit story stays narrow — which means v74 can run almost entirely autonomously behind a single small approval gate (and possibly no contract gate at all).

---

## 2. WORKSTREAM A — Live adversarial testnet agent

### 2.1 Recommended architecture (one clear recommendation, grounded in the repo)

**Build one off-chain TypeScript daemon (ethers v6) that drives two substrates with the same code: first a forked/local node for speed, then the live 15-minute-day testnet for realism.** This is the architecture report #5 calls the strongest, and report #3 confirms it is the only thing in the repo's toolbox that exercises the *exact deployed bytecode* under real gas/EIP-170/composition limits — which matters specifically for this protocol because of its documented gas-ceiling/brick history (the v60 game-over 17.54M-gas composition brick).

Concretely, reuse what already exists rather than authoring new infrastructure:

- **Deploy + ABIs + wallets:** `npm run node` (Hardhat node, 310 pre-funded accounts, chainId 31337) + `npm run deploy:local` (`scripts/deploy-local.js`) already stands up all 25 contracts + 4 mocks + a mock VRF, seeds tickets for 3 signers, and **exports a manifest + per-contract ABI JSON** to `deployments/localhost-abis/`. The agent loads that manifest and those ABIs; it does not hand-roll typing. (ethers v6 via `@nomicfoundation/hardhat-toolbox` is already the integration surface; typechain is present.)
- **Action surface:** every player action is an external function on `DegenerusGame.sol` (`purchase`, `advanceGame`, `redeemFlip`, `claimFoilMatch[Many]`, `purchaseWhaleBundle/LazyPass/DeityPass`, `degeneretteResolve`, `claimBingo`, `claimAfkingFlip`, `claimDecimatorJackpot[Many]`, `claimWinnings[StethFirst]`, `claimAffiliateDgnrs`, `claimWhalePass`). The agent derives strategy-driven + randomized action sequences from this ABI.
- **Canonical driving reference:** `test/fuzz/helpers/DeployProtocol.sol` + the `test/fuzz/handlers/` set (GameHandler, MultiLevelHandler, DegeneretteHandler, SolvencyActionHandler, VRFPathHandler, WhaleHandler, RedemptionHandler, VaultHandler, FSMHandler) already encode the *correct* purchase→advance→VRF→multi-level sequencing and the actor/bound patterns. Mirror these in the daemon; do not reinvent the lifecycle.

**Second substrate, same agent:** run the identical daemon against the live testnet. The owner constraint that the testnet uses **accelerated 15-minute game-days** is the key enabler — it makes a live public 24/7 soak genuinely practical (days/levels progress in near-real-time, no hand fast-forwarding), and it means the agent operates in a **live multi-actor environment** (honest bots playing alongside it), which is exactly the front-run / sandwich / shared-window-grief surface the owner wants probed.

**Run the local fork as the fast bug-finder, the live testnet as the realism soak.** On the fork, compress months of game-days into minutes via `evm_increaseTime`/`evm_setNextBlockTimestamp` + `evm_mine`, fund instantly via `anvil_setBalance`, impersonate whales via `anvil_impersonateAccount`, and `evm_snapshot`/`evm_revert` around each hypothesized exploit to retry cheaply. Re-fork at a fresh block periodically to resync fidelity.

**Free breadth on top of the daemon, zero new code:** run the existing Foundry invariant campaign continuously as a parallel autonomous adversary — `FOUNDRY_PROFILE=deep forge test --match-path 'test/fuzz/invariant/*'` (deep profile = 1000 runs × 256 depth). It already auto-emits a minimal failing sequence. This is the lowest-effort autonomous adversary in the repo and should run alongside the daemon, not instead of it.

### 2.2 The runtime invariant oracle (the properties to monitor — from report #2)

These are the load-bearing runtime properties the agent must assert after every external-call action. All are already codified in the repo's invariant/stat suites — the agent mirrors them off-chain:

1. **SOLVENCY conservation:** `claimablePool == Σ over all tracked addresses of (claimable low-half + afking high-half of balancesPacked[*])`. (`DegenerusGameStorage.sol:358-360`; `V61SolvencyAfpay.inv.t.sol`.) Poll via `claimablePoolView()`.
2. **BACKING bound (no unbacked liability):** `claimablePool <= address(game).balance + stETH.balanceOf(game)`. The backing side must sum *all legs* prior audits enumerated — vault claimable + afking funds + in-flight stETH + stage reserves — and the liability side must include sDGNRS redemption backing **and the auto-rebuy carry** that v63 BURNIE-04 showed can get stranded from backing. Re-check **after every external call** (the V62-03 / yield-surplus CEI reentrancy class is caught exactly here).
3. **sDGNRS redemption segregation:** segregated ETH ≤ game balance + stETH; no double-claim; 50% redemption cap; roll bounds [25,175]; totalSupply non-increasing. (`RedemptionInvariants.inv.t.sol`.)
4. **Degenerette per-(N, heroIsGold) EV ceiling:** every honest sub-case EV ≤ 100 centi-x (house edge ≥ 0, never EV-positive) and exactly EV-equal across hero placement; rigged-lane EV in [99.99857, 99.99955]; +5% ETH bonus is exactly 5.000%. (`DegenerettePerNEvExactness.test.js`.)
5. **Held-fixed pins:** P(S=9) byte-identical to pre-v73; WWXRP RTP curve 70→115→118→120% (floor 70%); activity ROI curve 90→99.9%; S=9 whale-pass bracket unchanged. (`DegeneretteV73Invariants.test.js`.)
6. **Rig m≥7 cap (no rigged S=9):** the WWXRP rig can never route an S=9 jackpot payout (max post-rig fired score = 8, Codex-enumerated 1024-state). The agent asserts: *no observed rigged S=9 payout ever occurs.*
7. **LIVENESS / no-brick:** `advanceGame` must never revert and a single batched tx must never exceed the block gas ceiling (history: 17.54M-gas game-over composition). Plus a **no-permanent-dead-state** check: after any brick-suspect sequence, assert the system can still be advanced/redeemed (the dead-lootbox/dead-state history makes this as important as the revert oracle). (`KeeperResolveBetWorstCaseGas.t.sol`.)

**The economic oracle is off-chain and owner-held, not read from the contract.** Per report #5 (A1's "Revenue Normalizer" pattern): maintain a per-actor ledger in ONE numeraire (normalize sDGNRS/DGNRS/claimable/afking/vault legs to ETH at a consistent rate), accumulate net P&L per wallet, and alarm only when realized profit exceeds the modeled EV bound **by k·σ over a counted sample** — never on per-spin equality. This is critical because (a) the payouts are RNG-defined so legitimate variance is large, and (b) the live testnet has honest background flow, so the "win more than you should" test must be *per-actor* net-P&L-vs-EV while solvency/backing invariants hold *globally across all actors*. The project has already seen "flaky" invariant trips that were stale harness slots, not real solvency breaks — statistical gating plus a by-design allowlist (deity-boon, salvage windows, owner knobs, known WONTFIX) suppresses those.

### 2.3 Continuous operation + reproducible violations

- **VRF:** local/fork uses `MockVRFCoordinator.fulfillRandomWords(lastRequestId(), word)` — the agent picks the word *adversarially*. Live testnet wires real Chainlink VRF V2.5 (async, needs a funded LINK sub, no manual fulfill) — the agent waits and observes. Loop `advanceGame` until `rngLocked()==false` to fully settle a day; decode the `Advance` event with the **AdvanceModule ABI** (delegatecall context), not the Game ABI.
- **Funding/refill:** fork = `anvil_setBalance` instant; live = a treasury wallet drip-refills each actor below a low-water mark. **Serialize every send through a NonceManager with replace-by-fee bumping** — report #5 names stuck-nonce as the #1 operational hazard (one stuck tx freezes all later txs from that account).
- **Checkpoint/resume:** persist the actor ledger + last-processed block to disk and reconcile against chain on boot; persist the Foundry/Echidna corpus. Run in small checkpointed pausable units so a 5h cap-stop never lands mid-attempt (repo process rule).
- **Reproducible repro:** log every action as a structured replayable record (from, to, calldata, value, block, pre/post ledger snapshot) + the `evm_snapshot` id. A flagged violation is then already a runnable tx sequence. The Foundry invariant runner shrinks its failing sequence for free.
- **False-positive discipline:** report only exploits that *concretely executed* net-positive after gas + revenue-normalization; reconcile economically so "profit" isn't an artifact of depleting a token's own pool; gate EV games statistically; allowlist by-design behaviors; differential ledger-vs-chain to localize a real leak vs an oracle bug.
- **On a live shared chain:** a successful brick affects honest actors too — acceptable on testnet (that IS the finding), but the agent should **log + repro rather than silently wedge** the shared chain.

### 2.4 Repo gotchas to fix first (from report #3)

- `package.json` references `test/adversarial/` and `test/simulation/` dirs that **do not exist** — these scripts (`test:adversarial`, `test:adversarial:sepolia-actors`, `test:sim`) are stale and will fail. Fix or delete before relying on them.
- No `deployments/` artifacts are committed — the agent must run `deploy:local` first to obtain addresses/ABIs.
- `.env.example` WXRP defaults to `0x0`, so WWXRP-currency paths may be inert without a real WWXRP address on a public testnet.
- The `_deployProtocol` real-clock setUp flake (no `block_timestamp` pin) is harness-wide and intermittent — pinning it is the lowest-effort de-flake (see Workstream B).

---

## 3. WORKSTREAM B — C4A package

### 3.1 What a C4-style README must contain (from report #4)

The contest README is the *contract for what is payable*. Ship it in the current C4 section order (confirmed against the live 2026-04-k2 and 2025-11-merkl repos): audit-details header · "Important notes for wardens" (mandatory coded PoC for High/Medium; downgrade-to-Low = ineligible) · automated/V12 findings (out of scope) · **Publicly known issues** · Overview · Links · **Scope + in-scope file table with nSLOC + machine-readable `scope.txt`** · **Files out of scope + `out_of_scope.txt`** · Additional context · **Areas of concern (where to focus)** · **Main invariants** · **trusted/restricted roles table (security/trust model)** · prior audits · build/test/PoC instructions.

### 3.2 Current gap vs C4A-ready (from reports #1 and #2)

The contest-facing docs have never been packaged for a contest and are stale by several milestones:

- **`scope.txt` is attested at v55** — it lists *deleted* contracts (BurnieCoin, BurnieCoinflip, Stonk, EndgameModule) and *omits live* ones (FoilPackModule, ActivityCurveLib, GasFaucet).
- **`report.md`'s per-file nSLOC includes out-of-scope mocks and tests** — there is no in-scope-only nSLOC table.
- **README contract count/module list is wrong** — claims 25 contracts, names a nonexistent EndgameModule, omits FoilPack/Bingo/Afking/ActivityCurveLib. Actual: ~14 modules + 6 libs (see report #2's full file census).
- **v65 rename never propagated to contest docs** — README/KNOWN-ISSUES still use BurnieCoin/BurnieCoinflip/Stonk instead of FLIP/Coinflip/DGNRS/sDGNRS.
- **No SECURITY.md, no Prior-Audits summary, no trust-model in one place.**
- **KNOWN-ISSUES has zero entries** for FoilPack, Bingo, Afking, Degenerette Variant-2, or the WWXRP rig — none of the by-design quirks are documented, so any warden surfacing them is currently *awardable*.
- **`report.md` + `ADERYN-TRIAGE.md` predate the gas-faucet commit** — their triage status vs HEAD is stale.

### 3.3 What to FIX vs DOCUMENT (mapping the carried open items)

Every carried item in report #2 is pre-existing, USER-deferred LOW or stale-anchor — none was introduced by v73. Recommended disposition:

| Carried item | Disposition | Rationale |
|---|---|---|
| `:1843/:1850` `==0` re-roll guard | **DOCUMENT** (accepted-LOW known issue) | VRF-fair, no EV/double-pay, recoverable under honest-admin; fixing widens the equivalence/re-audit story and unfreezes the subject. |
| 423 VRF rotation-timer hardening | **DOCUMENT** (accepted-LOW known issue) | Recoverable under honest governance, bounded by the non-resettable 120/365-day backstop; unrelated surface. |
| 6 stale `test:stat` SurfaceRegression anchors | **FIX** (test-only, no contract) | Re-anchor to the frozen tree so the stat suite stops carrying known-red anchors; runs autonomously, no approval gate. |
| `_deployProtocol` real-clock setUp flake | **FIX** (test-only: pin `block_timestamp` in `foundry.toml`) | Lowest-effort carried item; de-flakes the whole suite and the agent's reuse of `DeployProtocol.sol`. |
| DegenerusGasFaucet (unwired/unaudited-vs-deployment) | **DOCUMENT as out-of-scope** | Owner-deprioritized ("essentially third party, not a big deal"); not wired into ContractAddresses/deploy. Mark explicitly out-of-scope rather than auditing it for v74. |
| Stale `report.md` / `ADERYN-TRIAGE.md` | **FIX** (regenerate at HEAD) | Triage must be current for the package. |

Net: **the contract subject stays byte-frozen.** All Workstream-B fixes are test/docs only.

### 3.4 The exact known-issue specificity needed to exclude a finding (from report #4)

C4's standard clause — *"Anything included in this section is considered a publicly known issue and is therefore ineligible for awards"* — only excludes a submission **if the entry genuinely covers the demonstrated mechanism AND the conceded impact.** There is no numeric specificity threshold; judges adjudicate case-by-case, and the escape hatch is that a known issue does *not* exclude a "substantively distinct or higher-severity attack path" the loose wording didn't actually cover. **Vague disclaimers ("centralization risks exist") fail to exclude concrete higher-severity exploits.**

Practical rule for our known-issues entries: each must name (a) the **specific function/mechanism**, (b) the **precise behavior conceded**, and (c) the **worst-case impact accepted** — e.g. not "the rig may behave unexpectedly" but "`_rigWwxrpResult` deterministically steers up to the m≥7 cap; the rig can raise displayed score by up to +2 but can never route an S=9 jackpot payout (max fired score = 8); this is by-design and the resulting EV stays in [99.99857, 99.99955] centi-x." Tighten in-scope nSLOC by moving tests/mocks/interfaces/scripts to `out_of_scope.txt`; list prior audits (v62/v63/v66/v67/v70/v73 FINDINGS) so those become pre-classified known issues; and run the bot/static tooling yourself pre-freeze so low-hanging items are already-known.

### 3.5 Concrete deliverables

1. Regenerated `scope.txt` from tree `d6615306` (drop deleted, add FoilPack/ActivityCurveLib, decide GasFaucet) + `out_of_scope.txt`.
2. In-scope-only file + nSLOC table (built from `report.md` minus mocks/tests), embedded in the contest README.
3. Rename pass across all four contest docs (BURNIE→FLIP, BurnieCoinflip→Coinflip, Stonk→DGNRS/sDGNRS).
4. KNOWN-ISSUES sections — FoilPack, Degenerette Variant-2, WWXRP rig (the m≥7-cap/+2-steer behaviors), Bingo, Afking, and the two accepted-LOW carried items — each mechanism-+-impact specific per §3.4.
5. SECURITY.md + trusted/restricted roles table + Prior-Audits subsection (with the frozen-subject hash and the v73 floor forge 943/0/108) + Areas-of-Concern + Main-Invariants sections (the latter is just §2.2 in prose).
6. A single machine-readable **invariant manifest** (id, identity, on-chain read, comparator, source `file:line`) so the agent and the README's Main-Invariants section share one canonical oracle.

---

## 4. OPEN DESIGN DECISIONS the owner must make

**D1 — Agent stack.**
*Recommendation:* **One off-chain ethers-v6 TypeScript daemon as the primary agent, with the existing Foundry invariant campaign (`deep` profile) running in parallel as a free breadth-adversary.** Reuse `deploy-local.js` manifest/ABIs + `test/fuzz/handlers` sequencing.
*Tradeoff:* The daemon is the only thing that hits the *exact deployed bytecode* and the live multi-actor testnet (essential given the gas-brick history), but it's slow (~1 action/block) and you own nonce/retry/funding orchestration. Foundry is faster/deeper and auto-shrinks repros but runs against a fork snapshot, not live. Running both gets breadth + bytecode-fidelity; adding a third tool (Echidna/ItyFuzz optimization-mode profit search) is *optional bonus breadth* — recommend deferring it to a stretch phase, not the critical path.

**D2 — Live public testnet vs forked-anvil.**
*Recommendation:* **Both, in sequence — build/iterate on a local fork (speed), then point the same agent at the live 15-minute-day testnet (realism).** This is exactly the owner's stated working model and the 15-min days make the live soak practical.
*Tradeoff:* Fork = instant time-travel + free funding + cheap snapshot/retry, but it's a snapshot with no honest background flow or MEV surface. Live testnet = real bytecode + honest multi-actor traffic + real Chainlink VRF (the front-run/sandwich/shared-window-grief surface), but needs a funded LINK sub and you can't fast-forward. Doing fork-first then live captures both; the only cost is wiring the same agent to two RPC modes (which the design already accounts for).

**D3 — One combined milestone vs split.**
*Recommendation:* **One combined v74.0 milestone** — the two workstreams share the invariant catalog (§2.2 = §3.5 item 6) and the agent's findings feed directly into the squash/known-issues list.
*Tradeoff:* Combined keeps the invariant manifest single-sourced and lets agent findings flow into the README in one pass; the risk is a larger milestone. Mitigated because Workstream B is almost entirely autonomous docs/test work and Workstream A is additive (new files, no contract edits) — so the milestone is wide but shallow, with at most one tiny approval gate.

**D4 — Scope of the squash (how hard to fix vs document).**
*Recommendation:* **Document, don't fix — keep the contract subject byte-frozen.** Map the carried items per §3.3: the two LOW defense-in-depth items become precisely-worded accepted-LOW known issues; only test/docs items (stale anchors, `foundry.toml` timestamp pin, `report.md`/`ADERYN` refresh) get fixed.
*Tradeoff:* Documenting keeps the v73 audit story narrow and lets v74 run with **no contract approval gate at all** (lowest risk, fastest). Fixing the two LOW items would remove them from the known-issues list entirely but unfreezes the subject and forces a re-audit/equivalence pass. Given they're recoverable-under-honest-assumptions LOWs and the owner wants C4A-readiness fast, documenting wins. *(Owner can override per-item if they'd rather ship a fix — that converts the milestone's single optional gate into a real one.)*

**D5 — How aggressive the known-issues list should be.**
*Recommendation:* **Aggressive on the by-design quirks (FoilPack/Degenerette/WWXRP rig/Bingo/Afking) and the two carried LOWs, each with mechanism-+-impact specificity per §3.4 — but NOT vague blanket disclaimers.** List all prior-audit FINDINGS so they're pre-classified known.
*Tradeoff:* A precise, well-populated list maximally shrinks the payable pool (its single biggest lever), but each entry must concede the worst-case impact honestly — over-broad wording ("centralization risks exist") fails to exclude a concrete higher-severity path and can read as burying a real bug. The discipline is *specific-and-honest*, not *broad-and-defensive*; that's the line between a legitimate known-issues perimeter and a buried bug.

---

## 5. Proposed phase breakdown (continuing from 456 → 457+)

Sized so all contract-touching work (if any) is one batched diff behind a single approval gate, and everything else runs autonomously. Under the recommended D4 (document-not-fix), **457–463 have no contract gate at all**; the only gate is the *optional* 464.

| Phase | Goal (one line) |
|---|---|
| **457 SCOPE** | Regenerate `scope.txt` / `out_of_scope.txt` from tree `d6615306`; build the in-scope-only nSLOC table; refresh `report.md` + `ADERYN-TRIAGE.md` to HEAD. *(docs only)* |
| **458 RENAME+SECURITY** | Rename pass across all contest docs (BURNIE→FLIP / Coinflip / DGNRS); author SECURITY.md + trusted-roles/trust-model table + Prior-Audits subsection. *(docs only)* |
| **459 KNOWN-ISSUES** | Author the KNOWN-ISSUES perimeter (FoilPack/Degenerette-V2/WWXRP-rig/Bingo/Afking + the 2 carried LOWs + gas-faucet out-of-scope), each mechanism-+-impact specific; assemble the C4-order contest README. *(docs only)* |
| **460 MANIFEST** | Emit the single machine-readable invariant manifest (id/identity/read/comparator/source) shared by the README Main-Invariants section and the agent oracle; fix/delete the stale `test:adversarial`/`test:sim` package.json scripts. *(docs + test-config only)* |
| **461 HARNESS-FIX** | Pin `block_timestamp` in `foundry.toml` (de-flake setUp); re-anchor the 6 stale `test:stat` SurfaceRegression / PerPullEmptyBucketSkip baselines to the frozen tree. *(test-only, autonomous)* |
| **462 AGENT-FORK** | Build the ethers-v6 daemon (loads deploy-local manifest/ABIs, NonceManager + drip-refill, ledger + by-design allowlist, the §2.2 oracle); drive it against a local fork with time-compression; run the parallel `deep` Foundry invariant campaign; capture any repros. *(new files, autonomous)* |
| **463 AGENT-SOAK** | Point the same agent at the live 15-min-day testnet for a 24/7 multi-actor soak (real VRF, honest background flow, MEV/shared-window probes); triage findings into FIX vs DOCUMENT; log + repro any brick rather than wedging the chain. *(new files + ops, autonomous)* |
| **464 SQUASH-GATE** *(optional, single approval gate)* | IF any agent finding (or owner override on a carried LOW) warrants a contract change, batch ALL contract edits into ONE diff for owner review; otherwise this phase is a no-op and v74 ships gate-free. *(SOLE contract approval gate)* |
| **465 TERMINAL** | Re-verify suite at the frozen/updated floor; produce `audit/FINDINGS-v74.0.md` (chmod 444) + the final C4A package bundle (README + scope/out_of_scope + KNOWN-ISSUES + SECURITY + manifest); stamp the v74 closure signal. *(docs only)* |
