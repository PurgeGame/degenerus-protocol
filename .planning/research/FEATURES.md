# Feature Research: Adversarial Audit Scope (v2.0 — Code4rena Preparation)

**Domain:** Code4rena adversarial security audit of a 22-contract on-chain game with delegatecall modules, VRF, and complex economic mechanics
**Researched:** 2026-03-04
**Confidence:** HIGH (Code4rena official docs verified; AI Arena C4 audit report reviewed; Chainlink VRF V2.5 security docs reviewed; severity classification from official docs.code4rena.com)

---

## How Code4rena Auditors Judge This Protocol

Code4rena contestants are adversarial by nature. They race to find the highest-severity unique finding. They do not do checklists — they exploit asymmetries. The severity rubric that drives all submission decisions is:

- **HIGH:** Assets can be stolen, lost, or compromised directly via a realistic attack path. No hand-wavy hypotheticals. Requires a coded, runnable PoC for EVM/Solidity audits.
- **MEDIUM:** Function or availability of the protocol could be impacted, or value leaks via a path with stated assumptions and external requirements. Still needs a PoC.
- **LOW/QA:** Everything else — state handling issues, spec deviations, rounding dust, event gaps, admin trust assumptions. Bundled into a single QA report per warden.
- **Gas:** Gas optimization recommendations. Awarded separately on a curve. NOT mixed with security findings.
- **Admin/Centralization:** Classified as QA/LOW by default at Code4rena. "Reckless admin mistakes are invalid — assume calls are previewed." Only escalates to MEDIUM if there is a realistic, non-hypothetical harm path that doesn't require the admin to act in bad faith.

**Key Code4rena judging dynamics that affect scope planning:**

1. The most contested audit areas produce the most duplicates. Being first with a HIGH finding matters more than finding every LOW.
2. Overstating severity causes score reduction. A LOW submitted as HIGH damages the warden's score.
3. For game contracts specifically: the AI Arena C4 audit (Feb 2024, $60.5K pool) produced 8 HIGH and 9 MEDIUM findings — all game-mechanics-specific, none generic. The pattern was: game state bypasses (transfer without guard, reroll without type check), accounting asymmetries (zero risk on loss, full reward on win), and randomness manipulation (transaction reversion to farm desired attributes).

---

## Feature Landscape

### Table Stakes (Audit Categories — Missing = Report Is Incomplete)

These are the categories every Code4rena warden will investigate on any game contract. If v2.0 does not explicitly cover each, the final report has gaps that contestants will find.

| Category | Why Every Warden Checks This | Complexity for Degenerus | v1.0 Status |
|----------|------------------------------|--------------------------|-------------|
| ETH accounting invariant | HIGH severity if ETH can be drained or locked; this is "assets directly at risk" | HIGH — stETH rebasing + BPS splits + multi-step game-over + lootbox payouts + claimable balances all interact | INCOMPLETE — 8 of 9 Phase 4 plans unexecuted; carried to v2.0 as the critical gap |
| Cross-function reentrancy | Single-function reentrancy is obvious; cross-function is consistently missed and always HIGH | MEDIUM — claimWinnings + purchase + delegatecall paths share state; stETH.transfer() is the external call of concern | PARTIAL — single-function analyzed; cross-function synthesis explicitly listed as v2.0 gap |
| Admin power abuse | QA-level at C4 by default; escalates to MEDIUM if admin can halt, pause, or redirect funds without player recourse | MEDIUM — DegenerusAdmin has wireVrf, subscriptionId management, emergency stall trigger; question is whether stall is irreversibly admin-triggered | NOT STARTED — listed explicitly in v2.0 active requirements |
| advanceGame() gas ceiling | HIGH/MEDIUM if a realistic state can cause advanceGame() to exceed 16M gas, permanently bricking the game | HIGH — bucket iteration + delegatecall + VRF fulfillment all in call graph; Sybil bloat question tied here | NOT STARTED — complete call graph required |
| VRF griefing vectors | MEDIUM for retry window abuse; HIGH if randomness can be selectively applied or discarded by an attacker | HIGH — 18h retry window, subscription drain potential, coordinator substitution via wireVrf | PARTIAL — VRF lifecycle audited in v1.0; retry window exploitation and subscription control not yet analyzed |
| Token mint/burn authorization | HIGH if unauthorized minting exists; direct asset theft | MEDIUM — COIN.vaultMintAllowance(), DGNRS.claimWhalePass(), BurnieCoin burn/mint paths | NOT STARTED — listed in v2.0 active requirements |
| BurnieCoinflip house edge | MEDIUM if coinflip is exploitable or EV is wrong direction; game integrity | MEDIUM — coinflip range verification, outcome front-running window, AfK transition timing | NOT STARTED — listed in v2.0 active requirements |
| Integer arithmetic (fee splits) | HIGH if BPS splits don't sum correctly; rounding direction can drain protocol at scale | HIGH — 90/10 pool split, daily jackpot percentage, lootbox EV multiplier, deity pass T(n) | PARTIAL — formulas flagged; invariant testing not complete |
| Access control enumeration | LOW/QA for missing guards on non-critical functions; HIGH if critical paths are unguarded | MEDIUM — 22 contracts, 10 delegatecall entry points, VRF coordinator guard | COMPLETE — v1.0 full access control matrix delivered |
| Delegatecall storage collision | HIGH if slot mismatch exists; corrupts all downstream state | HIGH — 10 modules, all inherit DegenerusGameStorage | COMPLETE — v1.0 confirmed zero slot collisions |
| VRF lifecycle (Chainlink 8-point) | MEDIUM-HIGH — standard Chainlink checklist for consumer contracts | MEDIUM — rngLockedFlag, requestId matching, fulfillRandomWords non-reversion | COMPLETE — v1.0 all PASS |
| FSM transition completeness | MEDIUM if illegal FSM transitions are reachable | MEDIUM — three-state FSM (purchase/jackpot/gameOver) | COMPLETE — v1.0 all legal/illegal transitions enumerated |
| Whale/deity pass economic exploits | MEDIUM if pricing formulas can be gamed or EV is attacker-positive | HIGH — T(n) triangular pricing, bundle-level-eligibility guard (F01 found in v1.0) | PARTIAL — F01 (whale bundle level guard) found; deeper EV modeling deferred to v2.0 |
| Sybil bloat (storage DOS) | MEDIUM if player count growth can force advanceGame() over gas limit | HIGH — per-player storage, bucket cursor mechanics, trait burn iteration | NOT STARTED — listed in v2.0 active requirements |

### Differentiators (High-Value Findings — What Wins Code4rena)

These are the categories where well-funded adversarial contestants will spend their time on this protocol. A thorough engagement that produces findings here is what the Code4rena contest prep deliverable requires.

| Category | Value Proposition for Auditors | Complexity | Notes |
|----------|-------------------------------|------------|-------|
| claimWinnings() CEI violation — cross-function reentrancy | If ETH/stETH is transferred before clearing the claimable balance, an attacker who triggers an ETH callback can reenter a different function (purchase, lootbox resolution, affiliate payout) that also modifies prize pool state — bypassing a same-function reentrancy guard. This is HIGH severity if exploitable, and consistently missed because wardens check same-function reentrancy only. | HIGH | Critical path: claimWinnings → stETH.transfer() → Lido callback → ? Most impactful if the callback can reenter purchase() before state clear. |
| advanceGame() worst-case gas — complete call graph | advanceGame() dispatches multiple delegatecall modules. At worst-case game state (many active players, all buckets full, lootboxes pending, VRF word consuming jackpot scatter), the cumulative gas may approach or exceed the 16M block limit. If any realistic player count can trigger this, it is a permanent game-brick — HIGH severity. | HIGH | Requires full call graph trace: advanceGame → advance module → jackpot module → lootbox module → bucket iteration. Sybil bloat interacts: n cheap wallets create n more bucket entries. |
| Admin emergency stall — rug vector analysis | The 3-day emergency stall is admin-triggered. Questions for Code4rena: (1) Can admin trigger stall immediately after a large whale deposit, before payout? (2) Does stall give admin any privileged withdrawal capability not available to players? (3) Can admin repeatedly trigger/resolve stall to delay payouts indefinitely? (4) Can wireVrf replace the VRF coordinator with a malicious contract? These are MEDIUM at C4 severity (admin trust is assumed) unless any path allows non-admin actors to trigger or unless the stall creates a direct fund-theft mechanism. | MEDIUM-HIGH | wireVrf is the highest-risk admin function: substituting a malicious VRF coordinator gives the admin full control over all RNG outcomes. Classification depends on whether the coordinator address is multisig-protected. |
| VRF retry window exploitation | The 18h VRF retry timeout means: if VRF fulfillment is delayed (Chainlink outage, subscription drain), a waiting attacker can observe how the game state will evolve and time their retry-trigger to an advantageous moment. This is distinct from the Chainlink subscription-owner reroll attack (patched). At C4, this is MEDIUM if the attacker has no special privileges — they can trigger the retry but cannot choose the random word. | MEDIUM | Key question: does the retry path allow any bet placement or state change between the original VRF request and the retry? If yes, it becomes a selective-input attack — players can choose bets after seeing the pending VRF entropy, which is HIGH. |
| VRF subscription drain (griefing) | A malicious user could drain the LINK subscription balance by triggering repeated VRF requests (one per game advance) via valid game play. This DoS-es the game when LINK runs out. At C4: MEDIUM if it requires genuine game participation (has economic cost); LOW if the cost is prohibitive. | MEDIUM | Depends on the cost-to-drain ratio: how much ETH does an attacker spend in tickets vs. how much LINK is drained? If LINK subscription can be replenished by anyone this is informational. |
| BurnieCoinflip — house edge and front-running | BurnieCoin coinflips must have a provably correct house edge (if there is one), and the coinflip outcome must not be front-runnable. Key questions: (1) Is the coinflip outcome derived from a Chainlink VRF word, or from block-level data? (2) What is the expected value of the coinflip relative to COIN cost? (3) Can the AfK transition timing (enter AfK then immediately exit) create a window to flip without the AfK cost? | MEDIUM | If coinflip uses block-level data (timestamp, blockhash) instead of VRF, it is HIGH — validators can reroll. If it uses VRF but the VRF word is shared with another game outcome, the entropy pool may be predictable before the flip resolves. |
| COIN/DGNRS mint authorization audit | vaultMintAllowance defines how much COIN the vault can mint. If this cap can be bypassed (e.g., by directly calling a mint function without going through the vault), it is HIGH. If the allowance can be set arbitrarily by admin without player recourse, it is MEDIUM (admin trust). If claimWhalePass() in DGNRS can be called for the same player twice, it is HIGH (double mint). | MEDIUM-HIGH | Specific focus: is there any call path to mint COIN or DGNRS that bypasses the authorization check? This is the token supply invariant. |
| Whale bundle + lootbox combined EV | A well-funded whale can buy a bundle at 2.4 ETH (levels 0-3) and immediately redeem lootboxes funded by their purchase. If the lootbox EV multiplier for a high-activity-score whale exceeds 1.0, the whale extracts more ETH than deposited. This is a MEDIUM-HIGH finding because it is a designed mechanic — the question is whether the math is correct. | HIGH | Requires: (a) verify activity score cannot be inflated cheaply before bundle purchase; (b) verify lootbox EV formula cannot exceed 1.0 for any realistic activity score; (c) verify whale bundle level eligibility (F01 fix) prevents level 0 abuse. |
| Sybil wallet storage bloat — game brick | If each Sybil wallet creates O(k) permanent storage entries (bucket slots, player records, affiliate entries), a coordinated group of n wallets creates O(n*k) entries. The next advanceGame() call must iterate over all of them. If this exceeds 16M gas, the game is permanently bricked for all players. This is HIGH at Code4rena because it directly compromises all funds in the game. | HIGH | Requires: calculate per-player storage cost, per-wallet gas contribution to advanceGame() loop, and find the wallet count n where total gas exceeds 16M. |
| Game-over fund distribution — zero-balance proof | After game-over settlement, the contract should hold zero ETH (all funds distributed as claimable). If any path leaves funds locked (unclaimed claimable, rounding dust, stETH balance mismatch), this is MEDIUM. If any path allows funds to be claimed twice, it is HIGH. | HIGH | Multi-step sequence (advanceGame→VRF→fulfill→advanceGame→gameOver) must be traced end-to-end. The stETH balance at the time of settlement may differ from the balance at game start due to rebasing. |
| Cross-function reentrancy synthesis | The existing v1.0 work analyzed per-module reentrancy. The missing piece is cross-function reentrancy: can an ETH callback from claimWinnings reenter purchase()? Can a stETH transfer callback from lootbox resolution reenter an affiliate payout? This synthesis pass connects all ETH-touching call sites and verifies that CEI holds across function boundaries, not just within each function. | HIGH | Specifically look for: any ETH send that is not the last operation in a function; any function called by an ETH callback that also modifies shared state without a reentrancy guard. |

### Anti-Features (Categories That Look Productive But Waste Audit Time)

These are activities that seem audit-relevant but either are explicitly out of scope, produce only QA/Gas-level findings at Code4rena, or have been completed in v1.0.

| Anti-Feature | Why It Seems Valuable | Why It Wastes Time | What to Do Instead |
|--------------|----------------------|-------------------|-------------------|
| Admin privilege findings submitted as HIGH | Admin trust abuse is a real concern; feels impactful | Code4rena explicitly categorizes admin/centralization as QA-level. "Reckless admin mistakes are invalid." Submitting admin-only attacks as HIGH gets downgraded and penalizes the warden's score. Only escalates to MEDIUM with non-hypothetical harm that doesn't require admin bad faith. | Document admin power as an enumeration in the QA report. Only escalate wireVrf (coordinator substitution) if it creates an unpermissioned attack vector — that is the one admin function with HIGH potential. |
| Gas optimization recommendations | Finding gas inefficiencies feels thorough | Explicitly out of scope per PROJECT.md. Gas findings are submitted separately as a Gas Report at Code4rena, not mixed into security findings. Mixing dilutes the security report and wastes time on a separate scoring track. | Note gas costs only where they create a security risk (e.g., advanceGame() gas ceiling). Otherwise record as Gas Report material and do not spend security analysis time on it. |
| Static analysis output (Slither/Aderyn) without manual triage | Tools run fast and produce output | Raw scanner output without manual triage is noise. v1.0 already classified 319+ Slither/Aderyn detections as false positives with reasoning. Revisiting them wastes time that should go to untriaged areas. | Use v1.0 triage classifications as the baseline. Only run new scans on code paths not covered in v1.0 (ETH accounting paths, admin functions, coinflip contract). |
| Per-contract access control re-audit | Access control is critical | v1.0 delivered a complete access control matrix for all 22 contracts with delegation safety proofs. Re-auditing this is redundant. | Use v1.0 access control matrix as a reference. The v2.0 access control work is specifically admin power abuse (what privileged functions can do), not whether the function is guarded (already confirmed). |
| Storage layout re-verification | Slot collisions are severe | v1.0 confirmed zero slot collisions across all 10 delegatecall modules with forge inspect. This is a deterministic check that does not need repeating unless a module is modified. | Only re-verify if new module code is added or existing modules are changed. Use v1.0 storage layout map as authoritative. |
| Testnet contract review | Testnet contracts exist and are similar to mainnet | Testnet contracts use TESTNET_ETH_DIVISOR=1000000 and different VRF config. Findings on testnet are not transferable to mainnet security posture. Explicitly out of scope per PROJECT.md. | Focus exclusively on mainnet configurations. |
| Formal verification of all 22 contracts | Exhaustive correctness proofs feel valuable | Full formal verification of 22 contracts is a months-long engagement. Out of scope per PROJECT.md. Using it as an audit phase would crowd out manual analysis time. | Use bounded symbolic execution (Halmos) only for specific numeric formulas: deity pass T(n) overflow, ticket cost formula, BPS split sums. These are bounded checks, not full verification. |
| FSM transition re-audit | FSM has complex multi-step transitions | v1.0 enumerated all legal and illegal FSM transitions with proof of unreachability. This is complete. Re-doing it does not produce new findings. | Use v1.0 FSM transition graph as a reference. The v2.0 FSM work is specifically the advanceGame() gas budget under worst-case FSM state, not the transition logic itself. |
| Mock/test infrastructure review | Tests are code, auditing them is thorough | Mock contracts are not deployed. Findings on test infrastructure have no mainnet security impact. Explicitly out of scope per PROJECT.md. | Use test infrastructure only as behavioral specification — if a test asserts property X, assume X is the intended behavior and verify the implementation enforces it on-chain. |
| VRF lifecycle basic checklist re-run | VRF is complex and high-risk | v1.0 ran the full 8-point Chainlink VRF V2.5 security checklist and confirmed all items PASS. Re-running the same checklist does not produce new findings. | The v2.0 VRF work is specifically: (1) retry window exploitation timing, (2) subscription drain griefing economics, (3) coordinator substitution via wireVrf. These are second-order VRF risks beyond the basic checklist. |

---

## Feature Dependencies

```
[ETH Accounting Invariant — v2.0 CRITICAL GAP]
    └──requires──> [claimWinnings CEI cross-function reentrancy] (reentrancy breaks the invariant)
    └──requires──> [BPS split rounding direction proof] (precision errors cause invariant drift)
    └──requires──> [game-over zero-balance proof] (terminal state must clear all funds)
    └──requires──> [stETH rebasing desync check — v1.0 PARTIAL] (external balance changes break invariant)

[advanceGame() gas analysis — v2.0 CRITICAL GAP]
    └──requires──> [complete call graph from advanceGame] (must know all code paths)
    └──requires──> [Sybil bloat per-player storage calculation] (bloat is the worst-case trigger)
    └──enhances──> [VRF griefing — subscription drain] (same gas budget that's strained by bloat)

[Admin power abuse analysis — v2.0 GAP]
    └──requires──> [wireVrf coordinator substitution risk] (highest-severity admin vector)
    └──requires──> [emergency stall trigger conditions] (who can trigger, when, what it enables)
    └──conflicts with──> [admin findings submitted as HIGH] (Code4rena caps admin trust at QA/MEDIUM)

[VRF griefing — v2.0 GAP]
    └──requires──> [VRF lifecycle — v1.0 COMPLETE] (prerequisite: understand the happy path)
    └──requires──> [retry window timing analysis] (18h window vs. state changes between request and retry)
    └──conflicts with──> [VRF lifecycle re-audit] (v1.0 is complete; v2.0 is second-order risks only)

[Token mint/burn authorization — v2.0 GAP]
    └──requires──> [access control matrix — v1.0 COMPLETE] (prerequisite: know who can call what)
    └──focuses on──> [vaultMintAllowance bypass] (specific exploit path within the authorization model)
    └──focuses on──> [claimWhalePass double-mint check] (specific invariant within the authorization model)

[BurnieCoinflip house edge — v2.0 GAP]
    └──requires──> [VRF lifecycle — v1.0 COMPLETE] (prerequisite: know how VRF entropy flows)
    └──requires──> [COIN economic model — v1.0 PARTIAL] (prerequisite: understand COIN value vs. coinflip cost)

[Whale/deity EV analysis — v2.0 GAP]
    └──requires──> [whale bundle level eligibility — F01 fix confirmed] (prerequisite: F01 already found)
    └──requires──> [activity score manipulation analysis] (EV depends on whether activity score is cheap to farm)
    └──enhances──> [Sybil bloat analysis] (Sybil wallets may also manipulate activity score metrics)

[Cross-function reentrancy synthesis — v2.0 GAP]
    └──requires──> [per-module reentrancy — v1.0 COMPLETE] (prerequisite: per-function analysis done)
    └──requires──> [ETH accounting invariant paths] (must know all ETH-touching call sites)
    └──enables──> [claimWinnings CEI classification] (determines if the gap is exploitable cross-function)
```

### Dependency Notes

- **ETH accounting invariant is the master dependency.** It depends on reentrancy, BPS math, game-over settlement, and stETH behavior. It cannot be verified before these are complete. This is why Phase 4 in v1.0 was intentionally deferred — it requires all of Phase 3 (module audit) to be done first. In v2.0, Phase 3 is complete, so Phase 4 can proceed.
- **advanceGame() gas analysis is independent of accounting.** It can run in parallel with the ETH accounting work. The only dependency is having the full call graph, which requires reading the code directly.
- **Admin abuse and VRF griefing are partially independent.** wireVrf connects them — coordinator substitution is both an admin power and a VRF griefing vector. Analyze wireVrf once, classify in both.
- **Cross-function reentrancy synthesis must be last.** It integrates findings from all other categories. Running it before the accounting invariant and module audits are complete produces incomplete analysis.

---

## MVP Definition (Phases of v2.0 Audit Work)

### Phase 1: Unfinished Business from v1.0 (Do First — Blocks Report)

These are explicitly the gaps carried over. Without them, the audit is 74% complete, not 100%.

- [ ] ETH accounting invariant — trace all inbound/outbound ETH paths; assert `address(this).balance + stETH.balanceOf(this) >= claimablePool` holds across all paths
- [ ] BPS split correctness — verify all splits sum to input amount; fuzz with values 1 wei to 1000 ETH to confirm rounding does not accumulate
- [ ] claimWinnings() CEI — does ETH/stETH transfer happen before or after clearing the claimable balance? Is there a reentrancy guard? Does it cover delegatecall paths?
- [ ] game-over zero-balance proof — trace the full game-over sequence and confirm contract holds zero ETH after all claimable balances are set
- [ ] Cross-contract synthesis report (07-03, 07-05 from v1.0 plan) — integrate all findings into prioritized final report

### Phase 2: New v2.0 Attack Surface (Add After Phase 1)

These are the attack surfaces not covered in v1.0.

- [ ] advanceGame() complete call graph — every delegatecall invocation mapped, worst-case gas path identified per code branch
- [ ] Sybil bloat calculation — per-player storage cost, O(n) growth factor, critical player count n at which advanceGame() exceeds 16M gas
- [ ] Admin power abuse — wireVrf coordinator substitution risk, emergency stall trigger conditions, stall-as-payout-delay analysis
- [ ] VRF retry window exploitation — 18h window vs. state changes; any bet placement or purchase between VRF request and retry creates selective-input attack
- [ ] VRF subscription drain economics — cost-to-drain ratio vs. game economics; determine if this is MEDIUM or informational
- [ ] COIN/DGNRS mint authorization — vaultMintAllowance bypass paths; claimWhalePass double-mint check; burnCoin return value on insufficient balance
- [ ] BurnieCoinflip house edge — entropy source verification (VRF vs block data), expected value calculation, AfK window timing
- [ ] Whale/deity combined EV model — can a high-activity-score whale extract positive EV from bundle + lootbox combination?

### Phase 3: Final Synthesis (Do Last — Report Gate)

- [ ] Cross-function reentrancy synthesis — map all ETH-touching call sites; verify CEI holds across function boundaries, not just within each function
- [ ] Final prioritized findings report — CRITICAL / HIGH / MEDIUM / LOW / Gas / QA sections; Code4rena severity methodology applied to all findings

---

## Feature Prioritization Matrix

All items below are for the v2.0 audit scope. v1.0 items are marked COMPLETE and included only as context.

| Category | Finding Value (C4 Severity) | Investigation Cost | Priority |
|----------|----------------------------|--------------------|----------|
| ETH accounting invariant | HIGH potential | HIGH — requires full path trace | P1 |
| claimWinnings() CEI cross-function reentrancy | HIGH potential | HIGH — requires call graph | P1 |
| BPS split rounding — game-over zero balance | MEDIUM-HIGH | MEDIUM — math + fuzz | P1 |
| advanceGame() gas ceiling analysis | HIGH potential (if breach found) | HIGH — full call graph required | P1 |
| Sybil bloat — permanent game brick | HIGH potential | MEDIUM — calculate per-wallet cost | P1 |
| Admin wireVrf coordinator substitution | MEDIUM (admin trust) | LOW — single function analysis | P1 |
| VRF retry window exploitation | MEDIUM-HIGH if state changes allowed | MEDIUM | P1 |
| COIN/DGNRS mint authorization | HIGH if bypass exists | MEDIUM | P1 |
| Cross-function reentrancy synthesis | HIGH potential | HIGH — integrating pass | P2 |
| BurnieCoinflip house edge + entropy source | MEDIUM (HIGH if block data) | MEDIUM | P2 |
| Whale/deity combined EV model | MEDIUM | HIGH — analytical modeling | P2 |
| Admin emergency stall — payout delay | MEDIUM (admin trust) | LOW | P2 |
| VRF subscription drain economics | MEDIUM-LOW | LOW — ratio calculation | P2 |
| Activity score manipulation | MEDIUM | MEDIUM | P2 |
| Final prioritized findings report (07-05) | Required deliverable | MEDIUM — synthesis only | P1 |
| Access control matrix (v1.0) | COMPLETE | — | — |
| Delegatecall storage collision (v1.0) | COMPLETE | — | — |
| VRF lifecycle 8-point checklist (v1.0) | COMPLETE | — | — |
| FSM transition graph (v1.0) | COMPLETE | — | — |
| ETH module flow per-module audit (v1.0) | COMPLETE | — | — |
| Input validation (v1.0) | COMPLETE | — | — |
| Economic attack surface modeling (v1.0) | COMPLETE (partial) | — | — |

**Priority key:**
- P1: Must complete for v2.0 audit to be credible as Code4rena contest preparation
- P2: Should complete for thorough adversarial coverage; likely produces MEDIUM findings
- P3: Nice to have; Gas/QA-level findings

---

## Code4rena Severity Mapping — Degenerus v2.0

This maps each v2.0 attack surface to the expected Code4rena severity classification if a finding is confirmed. Severity is per-C4-rubric: HIGH = assets directly at risk, MEDIUM = function/availability impact with stated assumptions, LOW/QA = everything else.

| Attack Surface | Expected C4 Severity If Found | Key Condition for Severity |
|----------------|------------------------------|---------------------------|
| claimWinnings CEI violation (reentrancy) | HIGH — assets directly stolen | Must have exploitable reentry path; ETH/stETH transfer before state clear with no guard |
| BPS split rounding that accumulates | HIGH — assets permanently lost in rounding | Must demonstrate net loss > dust at realistic scale; Balancer pattern |
| advanceGame() gas ceiling breach | HIGH — all funds permanently locked | Must show realistic player count that exceeds 16M; Sybil cost required |
| game-over with locked/uncollectable funds | HIGH — assets lost | Must show funds remain unclaimable after terminal state |
| COIN/DGNRS unauthorized minting | HIGH — supply inflation steals from all players | Must show bypass path to mint without authorization |
| VRF retry + state change = selective input | HIGH — RNG manipulation gives attacker control | Must show that a bet/purchase accepted between request and retry affects outcome |
| wireVrf → malicious coordinator | MEDIUM (not HIGH) | Admin trust assumed at C4; only HIGH if unpermissioned actor can call wireVrf |
| Emergency stall as fund-delay mechanism | MEDIUM | Must show stall can delay claimable funds by >N days; admin intent not required |
| Sybil bloat (near-gas-ceiling, not breach) | MEDIUM — protocol availability impacted | If breach not found but approaching limit, still worth filing as MEDIUM |
| VRF subscription drain (griefing) | MEDIUM if economically feasible | Must calculate cost-to-drain; if prohibitive, this is LOW/informational |
| BurnieCoinflip with block-level entropy | HIGH if confirmed | Any block-level RNG (timestamp, blockhash) is validator-manipulable — direct asset risk |
| BurnieCoinflip negative house edge | MEDIUM | If expected value is player-positive, protocol leaks value; EV proof required |
| Whale + lootbox positive EV extraction | MEDIUM | Must show EV > 1.0 for realistic activity score; requires analytical model |
| Activity score cheap inflation | MEDIUM | Must show cost-to-inflate vs. lootbox EV gain is positive |
| AfK/coinflip timing window | MEDIUM | If AfK transition state allows coinflip without AfK cost |
| Admin functions without timelock | LOW/QA | Standard admin trust; not HIGH unless combined with a specific theft path |
| Event emission gaps | LOW/QA | Does not affect on-chain state |
| Dead code / unreachable branches | LOW/QA | Not exploitable, informational |

---

## What Code4rena Wardens Will Look For First

Based on the AI Arena audit pattern (8 HIGH, 9 MEDIUM from game mechanics — all protocol-specific, none generic), experienced wardens on this protocol will start here in priority order:

1. **ETH flow from purchase() to claimWinnings()** — the money in/money out path is where HIGH findings concentrate. They will trace every wei from deposit to withdrawal looking for CEI violations and accounting gaps.

2. **advanceGame() with extreme state** — wardens write PoC scripts that stuff the game state (many players, max lootboxes, full buckets) and call advanceGame() to measure gas. If they hit the limit, it's an instant HIGH submission.

3. **Token mint functions** — every ERC20/ERC721 mint function gets checked for authorization bypass. This is muscle memory for experienced wardens.

4. **Coinflip entropy source** — the first thing any warden asks about a coinflip is "what is the randomness source?" If the answer is anything other than a Chainlink VRF word, it's a HIGH.

5. **Admin functions with fund effects** — wardens build a list of every admin function that can move funds or halt game progression. wireVrf and emergency stall will both be reviewed.

6. **cross-function reentrancy via ETH callbacks** — experienced wardens know that same-function reentrancy guards are usually present; they look specifically for cross-function reentry at every ETH send site.

7. **Game mechanic bypasses** (analogous to AI Arena H-01 through H-04) — wardens look for functions that have a guard in one entry point but not another, or type mismatches that allow stat manipulation. The F01 finding (whale bundle level guard) is exactly this pattern. They will look for more.

---

## Sources

- [Code4rena Severity Categorization](https://docs.code4rena.com/competitions/severity-categorization) — HIGH confidence; official C4 severity rubric; defines HIGH/MEDIUM/LOW/QA/Gas criteria
- [Code4rena Submission Guidelines](https://docs.code4rena.com/competitions/submission-guidelines) — HIGH confidence; PoC requirements, overstating severity penalties, QA bundling rules
- [Code4rena AI Arena Audit Report (Feb 2024)](https://code4rena.com/reports/2024-02-ai-arena) — HIGH confidence; 8H/9M findings from game contract audit; direct analogue to Degenerus
- [Chainlink VRF V2.5 Security Considerations](https://docs.chain.link/vrf/v2-5/security) — HIGH confidence; official 8-point checklist; no-re-request rule, fulfillment-must-not-revert rule
- [Chainlink VRF Subscription Owner Attack ($300K bounty)](https://cryptoslate.com/chainlink-vrf-vulnerability-thwarted-by-white-hat-hackers-with-300k-reward/) — MEDIUM confidence; documents the reroll attack vector now patched in V2.5
- [Hacken: Top 10 Smart Contract Vulnerabilities 2025](https://hacken.io/discover/smart-contract-vulnerabilities/) — MEDIUM confidence; access control as #1 exploit vector ($953M in 2025)
- [Immunefi: The Ultimate Guide to Reentrancy](https://medium.com/immunefi/the-ultimate-guide-to-reentrancy-19526f105ac) — MEDIUM confidence; cross-function reentrancy documentation
- PROJECT.md — PRIMARY SOURCE; v2.0 milestone definition, active requirements, known gaps from v1.0, out-of-scope list
- SUMMARY.md (v1.0 research) — HIGH confidence; v1.0 completed items confirmed, gaps identified

---
*Feature research for: Code4rena adversarial audit scope — Degenerus Protocol v2.0*
*Researched: 2026-03-04*
*Supersedes: .planning/research/FEATURES.md (2026-02-28 v1.0 version)*
