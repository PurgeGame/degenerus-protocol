# Architecture Research: Smart Contract Security Audit Structure

**Domain:** Multi-contract Solidity security audit (delegatecall-heavy on-chain game)
**Researched:** 2026-02-28
**Confidence:** HIGH (direct codebase analysis) / MEDIUM (audit methodology — sourced from Hacken, Cyfrin, Chainlink docs)

---

## System Overview: The Degenerus Protocol

The protocol is 22 deployable contracts organized into five distinct layers. Understanding these layers
and their dependency directions is the primary input to audit phase ordering.

```
+=====================================================================================+
|                           EXTERNAL ACTORS / CALLERS                                 |
|  Players, Whales, Affiliates, Validator/MEV bots, Sybil groups                      |
+=====================================================================================+
            |                    |                    |                    |
            v                    v                    v                    v
+====================+ +===================+ +==================+ +=================+
|   ENTRY FACADE     | |  TOKEN LAYER      | |  PERIPHERAL      | |  ADMIN          |
|   DegenerusVault   | |  BurnieCoin       | |  DegenerusAffil  | |  DegenerusAdmin |
|   DegenerusStonk   | |  BurnieCoinflip   | |  DegenerusQuests | |  (VRF sub mgmt) |
+=========|==========+ |  DegenerusDeity   | |  DegenerusJackpots|+=================+
          |            |  Pass             | |  DegenerusTraits |         |
          |            |  WrappedWrappedXRP| |  Icons32Data     |         |
          v            +===================+ +==================+         |
+=====================================================================================+
|                         GAME CORE: DegenerusGame                                    |
|                                                                                      |
|  FSM: PURCHASE (false) <---> JACKPOT (true)  [terminal: gameOver]                   |
|  ETH prize pool flow: futurePrizePool -> nextPrizePool -> currentPrizePool           |
|  VRF lock state: rngRequestTime!=0 means in-flight, blocks state transitions        |
|                                                                                      |
|  delegatecall dispatches to modules via compile-time constant addresses:             |
|  +---------------+ +---------------+ +---------------+ +---------------+            |
|  | MintModule    | | AdvanceModule | | JackpotModule | | EndgameModule |            |
|  +---------------+ +---------------+ +---------------+ +---------------+            |
|  +---------------+ +---------------+ +---------------+ +---------------+            |
|  | WhaleModule   | | LootboxModule | | BoonModule    | | DecimatorMod  |            |
|  +---------------+ +---------------+ +---------------+ +---------------+            |
|  +---------------+ +---------------+                                                |
|  | DegeneretteM  | | GameOverMod   |                                                |
|  +---------------+ +---------------+                                                |
+=====================================================================================+
            |                    |                    |
            v                    v                    v
+====================+ +===================+ +==================+
|  SHARED STORAGE    | |  PURE LIBRARIES   | |  EXTERNAL DEPS   |
| DegenerusGameStor  | |  EntropyLib       | |  Chainlink VRF   |
| (slots 0-N, packed)| |  JackpotBucketLib | |  Lido stETH      |
| inherited by all   | |  BitPackingLib    | |  LINK token      |
| delegatecall mods  | |  GameTimeLib      | |  VRF Coordinator |
+====================+ |  PriceLookupLib   | +==================+
                       +===================+
```

---

## Component Responsibilities

| Component | Layer | Responsibility | Audit Dependency |
|-----------|-------|----------------|-----------------|
| `DegenerusGameStorage` | Foundation | Defines canonical slot layout for all delegatecall contexts | Must verify FIRST — all module audits depend on this |
| `ContractAddresses` | Foundation | Compile-time constants for all cross-contract addresses | Verify at deploy-time; check zero-address guards |
| `DegenerusGame` | Core | FSM, VRF callback, prize pool accounting, delegatecall dispatch | Central audit target — most complex invariants live here |
| `DegenerusGameAdvanceModule` | Game Module | advanceGame() logic, VRF request/fulfill lifecycle, state transitions | Critical — controls the entire state machine progression |
| `DegenerusGameMintModule` | Game Module | purchase(), ticket pricing, lootbox minting, activity score | High value — direct ETH inflow, pricing math |
| `DegenerusGameJackpotModule` | Game Module | Daily jackpot bucket distribution, ETH/COIN split | High value — ETH outflow accounting |
| `DegenerusGameEndgameModule` | Game Module | Level-to-level transition, next prize pool seeding | Sequential dependency on JackpotModule |
| `DegenerusGameWhaleModule` | Game Module | Whale bundle/lazy pass/deity pass purchases | Pricing formulas, privileged mechanics |
| `DegenerusGameLootboxModule` | Game Module | Lootbox opening, EV multiplier application, claim thresholds | VRF-dependent, activity score interaction |
| `DegenerusGameBoonModule` | Game Module | Deity boon issuance, boon consumption | Access control, one-shot mechanics |
| `DegenerusGameDecimatorModule` | Game Module | Decimator window, auto-rebuy | Phase-gated mechanics |
| `DegenerusGameDegeneretteModule` | Game Module | Degenerette bet placement and resolution | In-game betting, fund flows |
| `DegenerusGameGameOverModule` | Game Module | Terminal state settlement, final distributions | Final-settlement math |
| `BurnieCoin` | Token | ERC20 with coinflip burn/mint gating | Token supply invariants |
| `BurnieCoinflip` | Token | Daily coinflip wagering, auto-rebuy, bounty | Interacts with COIN mint/burn |
| `DegenerusVault` | Entry Facade | Multi-asset vault (ETH + stETH), independent share classes | ETH/stETH accounting, share math |
| `DegenerusStonk` | Entry Facade | DGNRS token, earlybird rewards, affiliate-king mode | Constructor calls GAME, ordering-sensitive |
| `DegenerusAffiliate` | Peripheral | Referral code tracking, affiliate bonus points | Access control on bonus credit |
| `DegenerusJackpots` | Peripheral | Historical jackpot records | Read-only mostly |
| `DegenerusQuests` | Peripheral | Quest streak tracking, activity score contribution | Quest state affects lootbox EV |
| `DegenerusDeityPass` | Peripheral | ERC721 deity pass, triangular pricing | T(n) formula, burn mechanics |
| `DegenerusAdmin` | Admin | VRF subscription ownership, emergency recovery, LINK management | Privileged — single owner, no transfer |
| `Icons32Data` | Data | On-chain SVG trait data | Low security surface |
| `WrappedWrappedXRP` | Token | Joke/prize token, vault-mintable | vaultMintAllowance gate |

---

## Audit Phase Architecture

### Phase Dependencies (What Must Be Reviewed Before What)

The audit has a strict dependency graph. Reviewing in wrong order means findings in later phases
may be invalidated or missed because their prerequisites weren't understood.

```
Phase 1: Storage Foundation
    ↓  (everything inheriting DegenerusGameStorage is invalid without this)
Phase 2: Core State Machine + VRF Lifecycle
    ↓  (all module logic executes in DegenerusGame's storage context)
Phase 3: Module Logic (parallelizable within phase, not across phases)
    ↓  (module outputs feed ETH accounting invariants)
Phase 4: ETH/Token Accounting Integrity
    ↓  (accounting correctness is prerequisite for economic attack analysis)
Phase 5: Economic Attack Surface
    ↓  (understanding what's possible informs access control gaps)
Phase 6: Access Control + Privilege Model
    ↓  (full cross-cutting synthesis)
Phase 7: Cross-Contract Interaction + Integration
```

---

## Recommended Review Order (Detailed)

### Phase 1 — Storage Foundation (review first, gates everything)

**What gets reviewed together:**
- `DegenerusGameStorage.sol` — complete slot-by-slot layout, packed struct integrity
- `ContractAddresses.sol` — compile-time constant correctness, zero-address guards in consumers

**Why this is first:**
Every delegatecall module executes in `DegenerusGame`'s storage context. A slot collision
or incorrect layout understanding invalidates all subsequent module analysis. This is a
30-minute review that saves hours of incorrect assumptions downstream.

**Key questions:**
- Do all 10 modules inherit `DegenerusGameStorage` and ONLY `DegenerusGameStorage`?
- Has any module declared instance-level storage variables outside the shared layout?
- Are packed slots (slots 0 and 1) correctly interpreted in all modules?
- Does the `unchecked` arithmetic in modules preserve packed slot semantics?

**Build order implication:** This phase has no dependencies. Start here.

---

### Phase 2 — Core State Machine and VRF Lifecycle (gates module review)

**What gets reviewed together:**
- `DegenerusGame.sol` — FSM logic, delegatecall dispatch, VRF callback handler
- `DegenerusGameAdvanceModule.sol` — advanceGame() multi-step state machine, all STAGE_* constants
- `GameTimeLib.sol` — day boundary calculations, timeout math

**Why together:**
`advanceGame()` is a delegatecall into `AdvanceModule` which in turn calls other modules
(`JackpotModule`, `EndgameModule`, `GameOverModule`). The full state machine only makes sense
when read as a single coherent unit across `DegenerusGame` dispatch and `AdvanceModule` execution.
VRF lock state (`rngRequestTime`) is set in `DegenerusGame` and read in `AdvanceModule`.

**Key questions:**
- Can `fulfillRandomWords` reenter or be called multiple times for one request ID?
- Is `rngRequestTime != 0` a reliable RNG lock? What clears it, and when?
- Can the 18-hour timeout be exploited to force early retry with fresh entropy?
- Is the multi-step advance (VRF request → fulfill → advanceGame) atomic from an attacker's perspective?
- Can a validator withhold VRF fulfillment to stall the game, then selectively reveal?
- Does `phaseTransitionActive` guard prevent partial-transition reentrancy?
- Are all STAGE_* constants reachable without skipping via crafted state?

**Build order implication:** Phase 1 (storage layout) must be complete first.

---

### Phase 3 — Game Module Logic (parallelizable within this phase)

These modules all execute via delegatecall in `DegenerusGame`'s storage. Review them in this
suggested sub-order based on ETH value at risk:

**3a — MintModule** (highest direct ETH inflow)
- `DegenerusGameMintModule.sol`, `DegenerusGameMintStreakUtils.sol`
- Ticket pricing math (costWei = priceWei * qty / 400), price escalation
- Lootbox grant logic, activity score crediting
- ETH routing into currentPrizePool, futurePrizePool, affiliate splits

**3b — JackpotModule** (highest direct ETH outflow)
- `DegenerusGameJackpotModule.sol`, `JackpotBucketLib.sol`, `EntropyLib.sol`
- `traitBucketCounts()` rotation, `scaleTraitBucketCountsWithCap()` math
- Share distribution (10k basis points sum to exactly 10000?)
- Rounding error accumulation across multi-day jackpots

**3c — LootboxModule** (VRF-dependent, activity score multiplier)
- `DegenerusGameLootboxModule.sol`
- Activity score EV multiplier application
- 5 ETH claim threshold for whale pass eligibility
- RNG word derivation from global VRF words

**3d — EndgameModule** (level transition accounting)
- `DegenerusGameEndgameModule.sol`
- nextPrizePool → currentPrizePool seeding
- futurePrizePool split (90%/10%) correctness

**3e — WhaleModule** (complex pricing formulas)
- `DegenerusGameWhaleModule.sol`
- Whale bundle: 2.4 ETH / 4 ETH pricing guard
- Lazy pass pricing at level 3+ (sum-of-10-level-prices)
- Deity pass triangular pricing T(n) = n*(n+1)/2 overflow

**3f — Supporting modules** (lower independent risk)
- `DegenerusGameBoonModule.sol` — boon issuance access control, one-shot guard
- `DegenerusGameDecimatorModule.sol` — decimator window, auto-rebuy edge cases
- `DegenerusGameDegeneretteModule.sol` — bet placement and resolution fund flows
- `DegenerusGameGameOverModule.sol` — terminal settlement completeness

**Build order implication:** All 3a-3f depend on Phase 1 (storage) and Phase 2 (state machine).
Sub-phases 3a-3f can be reviewed in parallel by different reviewers.

---

### Phase 4 — ETH/Token Accounting Integrity (requires Phase 3 complete)

**What gets reviewed together:**
- `DegenerusVault.sol` — ETH + stETH share accounting, independent share classes
- `DegenerusGame.sol` — `claimWinnings()`, `claimableWinnings` mapping, pull-pattern correctness
- Invariant: `address(this).balance + steth.balanceOf(this) >= claimablePool`
- `BurnieCoin.sol` — ERC20 supply invariants, `burnForCoinflip` / `mintForCoinflip` gate
- Fee split correctness across all code paths (all percentages sum correctly)

**Why together:**
ETH accounting spans multiple contracts. The critical invariant (total assets >= total claimable)
can only be verified by tracing all inflow and outflow paths across `DegenerusGame`, `DegenerusVault`,
and the token contracts. This is a holistic pass, not per-contract.

**Key questions:**
- Does every ETH wei that enters the system get correctly routed into exactly one bucket?
- Can `claimablePool` exceed on-chain ETH balance through any code path?
- Are there paths where ETH gets stuck (sent to contracts with no withdrawal)?
- Do fee splits sum to exactly 100% in basis-points across all branches?
- Does stETH rebasing (Lido yield accrual) affect any accounting?
- Can the vault shares be manipulated via first-depositor attack?

**Build order implication:** Requires all Phase 3 modules to be understood (inflows/outflows mapped).

---

### Phase 5 — Economic Attack Surface (requires Phase 4)

**What gets reviewed together:**
- Sybil/multi-wallet analysis: can coordinated wallets extract excess value from jackpot buckets?
- Whale bundle economics: is 2.4 ETH for a whale pass provably EV-negative for the attacker?
- MEV/validator surface: tx reordering, censorship, sandwich attacks on advanceGame
- Lootbox timing: can players observe VRF result then decide whether to open?
- Degenerette bets: can bet placement be timed around known VRF outcomes?
- Affiliate abuse: can circular affiliate structures extract excess bonus?
- Trait selection bias: do `getRandomTraits()` quadrant boundaries create exploitable clustering?

**Why this is its own phase:**
Economic attacks require a complete picture of all mechanics to evaluate. A finding here often
points back to a Phase 3 implementation detail. Economic analysis validates that the game's
incentive structure is robust, not just that individual functions are correct.

**Build order implication:** Requires Phase 4 (ETH accounting) to be correct — can't assess
economic risk without knowing where funds actually go.

---

### Phase 6 — Access Control and Privilege Model

**What gets reviewed together:**
- `DegenerusAdmin.sol` — single-owner model, no transfer, VRF subscription authority
- All `msg.sender` checks across all contracts
- Operator approval system (`setOperatorApproval`) — escalation vectors
- `isOperatorApproved` gate in Vault/Stonk — can operators exceed their authorized scope?
- Emergency recovery functions — what damage can CREATOR do if compromised?
- LINK donation and bounty multiplier — can this be exploited?

**Why this is late:**
Access control issues are often context-dependent. A function that looks properly gated may still
be abusable if its effects on accounting (Phase 4) or economics (Phase 5) allow secondary extraction.
Reviewing access control after understanding those phases produces higher-quality findings.

**Build order implication:** Builds on Phase 5 context.

---

### Phase 7 — Cross-Contract Integration and Synthesis

**What gets reviewed together:**
- Full call-chain tracing: `DegenerusStonk` → `DegenerusGame` → `AdvanceModule` → `JackpotModule`
- Constructor-time cross-calls: VAULT→COIN, DGNRS→GAME, ADMIN→VRF+GAME
- Reentrancy across contract boundaries (ETH callbacks, stETH rebasing hooks)
- `ContractAddresses` zero-address risk at deploy time
- VRF coordinator replacement path (`wireVrf` in Admin) — who controls it post-deploy?
- `fulfillRandomWords` callback from external coordinator — is the caller validated?

**Why this is last:**
Cross-contract interaction bugs are almost always composite: they require understanding both
sides of the boundary. Phases 1-6 build the per-contract understanding; Phase 7 synthesizes
it across boundaries. Reentrancy findings in Phase 7 often have accounting implications (Phase 4)
that must be cross-referenced.

**Build order implication:** All prior phases must be complete.

---

## Cross-Contract Analysis: How It Differs From Single-Contract Review

Single-contract review follows one control flow. Multi-contract review requires:

### 1. Trust Boundary Mapping

Every external call site must be categorized:
- **Trusted** — same deployer, known address, compile-time constant (`ContractAddresses`)
- **Semi-trusted** — external oracle (Chainlink VRF coordinator) — correct caller, but VRF response content is untrusted input
- **Untrusted** — user-supplied addresses, operator-approved third parties

In this protocol, `ContractAddresses` uses compile-time constants — all cross-contract addresses
are baked in at compile time. This eliminates address-injection vectors but creates a different
risk: if any constant is wrong, there is no recovery path.

### 2. Delegatecall Context Tracking

Standard analysis tools track control flow within one EVM context. Delegatecall creates a
second analysis context with shared storage but different code. For each of the 10 modules:

- Which storage slots does the module read? Which does it write?
- Does any module call `address(this)` — and does that correctly refer to `DegenerusGame`, not the module address?
- Does any module emit events — and do they appear as if from `DegenerusGame`?

### 3. Invariant Tracing Across Call Chains

The core financial invariant (`balance + stETH >= claimablePool`) must hold after every
possible cross-contract call sequence. The call chain for a single `advanceGame()` invocation
crosses: `DegenerusGame` → `AdvanceModule` → `JackpotModule` → `EndgameModule` → `BurnieCoin`
→ `DegenerusJackpots`. The invariant must be verified to hold at every intermediate state,
not just at entry and exit.

### 4. Callback Reentrancy Across Boundaries

The `fulfillRandomWords` callback comes from an external coordinator. The reentrancy surface
spans: external call → `DegenerusGame.fulfillRandomWords` → delegatecall → module. Standard
single-function reentrancy guards don't protect against multi-step callback chains.

---

## Data Flow Direction

### ETH Inflow Paths (audit: every path should credit exactly one pool)

```
User ETH payment
    |
    +-- purchase() ---------> currentPrizePool (% varies by mechanic)
    |                      -> futurePrizePool  (10% split)
    |                      -> claimableWinnings (affiliate/referral %)
    |
    +-- purchaseWhaleBundle -> currentPrizePool
    |
    +-- purchaseLazyPass ----> currentPrizePool
    |
    +-- purchaseDeityPass ---> claimableWinnings (directly claimable by deity holders)
    |
    +-- Vault deposits ------> Vault share classes (independent of game pools)
```

### ETH Outflow Paths (audit: each should only reduce what it was credited)

```
claimWinnings(player)
    |
    +-- pull-pattern --------> player address (from claimableWinnings[player])

Daily jackpot resolution
    |
    +-- JackpotModule -------> claimableWinnings[winner] += share (from currentPrizePool)

Level jackpot (end of jackpot phase)
    |
    +-- EndgameModule -------> claimableWinnings[level jackpot winners]
    |                       -> nextPrizePool (carries to next level)

Game over settlement
    |
    +-- GameOverModule ------> claimableWinnings[all remaining winners]

Timeout / sweep paths
    |
    +-- AdminTimeout --------> creator (inactivity guard after 365 days)
```

### VRF Randomness Flow (audit: no actor can predict or replay)

```
advanceGame() [via AdvanceModule delegatecall]
    |
    +-- VRF request ---------> VRFCoordinator.requestRandomWords()
    |                          rngRequestTime = block.timestamp (lock set)
    |
VRFCoordinator callback
    |
    +-- fulfillRandomWords() -> vrfRandomWords[requestId] stored
    |                          rngRequestTime = 0 (lock cleared)
    |
advanceGame() [second call, picks up fulfilled words]
    |
    +-- words distributed ---> dailyRandomWords[dailyIdx]
                            -> used by EntropyLib.entropyStep() for jackpot draws
                            -> used by LootboxModule for lootbox outcomes
```

### Storage Write Flow (audit: no module should write outside its logical domain)

```
delegatecall dispatch (in DegenerusGame context)
    |
    +-- MintModule ---------> slot 0 (levelStartTime), slot 2 (price), mappings (tickets, lootboxes)
    +-- AdvanceModule ------> slot 0 (rngRequestTime, dailyIdx), slot 1 (flags), vrfRandomWords map
    +-- JackpotModule ------> claimableWinnings mapping, jackpotCounter (slot 1)
    +-- EndgameModule ------> level (slot 0), jackpotPhaseFlag (slot 0), prize pool vars
    +-- WhaleModule --------> whalePasses mapping, lazyPasses mapping
    +-- LootboxModule ------> playerLootboxes mapping, activityScore mapping
```

---

## Architectural Patterns and Their Audit Implications

### Pattern 1: Delegatecall Module Dispatch

**What:** `DegenerusGame` stores all state. Logic is dispatched via `delegatecall` to stateless
module contracts whose addresses are compile-time constants in `ContractAddresses`.

**Audit implication:** Standard reentrancy guards on `DegenerusGame` functions protect the outer
entry point, but each module that makes further external calls creates a new reentrancy surface
within the same transaction. Module calls to `BurnieCoin`, `DegenerusJackpots`, etc. happen in
`DegenerusGame`'s context — any ETH value changes there affect `DegenerusGame`'s accounting.

**Verification method:** For each module, list every external call and verify:
(1) does the module update state before or after the external call?
(2) can the callee callback into `DegenerusGame` or any module?

### Pattern 2: Packed Storage Slots

**What:** Slots 0 and 1 pack multiple logical fields into single 32-byte words for gas efficiency.
`uint48 levelStartTime | uint48 dailyIdx | uint48 rngRequestTime | uint24 level | uint16 lastExterminatedTrait | bool jackpotPhaseFlag` — all in slot 0.

**Audit implication:** Solidity's automatic pack/unpack is correct in isolation. The risk is in
`unchecked` blocks that perform arithmetic on packed fields, or in modules that read a full slot
word and interpret it manually (BitPackingLib). Any misalignment between declared variable order
and BitPackingLib's manual extraction would be a critical silent corruption.

**Verification method:** Compare `DegenerusGameStorage` declared variable order against
`BitPackingLib` bit-offset constants. Verify with `forge inspect DegenerusGame storage-layout`.

### Pattern 3: RNG Lock State Machine

**What:** `rngRequestTime != 0` locks the game against state transitions while VRF is in-flight.
The lock prevents anyone from purchasing, advancing, or modifying state until randomness is fulfilled.
An 18-hour timeout allows manual retry if VRF stalls.

**Audit implication:** The lock is a critical security primitive. Questions: Is the lock set
atomically with the VRF request (no gap)? Is it cleared atomically with consuming the result
(no double-consume)? Can the 18-hour timeout be used by a validator to force a fresh VRF word?

**Verification method:** Trace all paths that set and clear `rngRequestTime`. Verify no path
exists where the lock is cleared before the random words are consumed.

### Pattern 4: Compile-Time Address Constants

**What:** All cross-contract addresses are constants baked into bytecode at compile time.
No runtime address lookup or upgradeable registry.

**Audit implication:** Eliminates address injection attacks. Creates a different risk: addresses
patched to address(0) in the source file (`ContractAddresses.sol`) would compile to contracts
that silently no-op on all cross-contract calls (call to address(0) succeeds but does nothing).
Verify that zero-address reverts exist at all critical call sites, or that the deploy pipeline
is reviewed for correctness.

**Verification method:** Grep all `ContractAddresses.*constant` usages. For each: does the
consuming contract check for address(0) before calling? (Note: this is more of a deploy-time
risk than a runtime security risk since the addresses are immutable post-deploy.)

### Pattern 5: Pull-Pattern Withdrawals

**What:** Winnings accumulate in `claimableWinnings[player]` mapping. Players call
`claimWinnings(player)` to withdraw. No push of ETH to arbitrary addresses during jackpot runs.

**Audit implication:** Eliminates push-to-arbitrary-address reentrancy during jackpot distribution.
Reentrancy risk is localized to the `claimWinnings` function itself. Verify `claimableWinnings[player]`
is zeroed before the ETH transfer (CEI pattern), and that `claimWinningsStethFirst` variant has
the same protection.

---

## Anti-Patterns to Avoid in the Audit Process

### Anti-Pattern 1: Per-Contract Isolation

**What people do:** Review each of 22 contracts in sequence as isolated units.
**Why it's wrong:** Critical vulnerabilities in this system span contract boundaries.
The ETH accounting invariant requires tracing across 5+ contracts simultaneously. Reviewing
`DegenerusGame` in isolation misses how `AdvanceModule` manipulates the same storage.
**Do this instead:** Map cross-contract call graphs before per-contract review. Ensure Phase 7
cross-contract synthesis is explicitly scheduled, not treated as a byproduct of per-contract work.

### Anti-Pattern 2: Trusting Tests as Coverage Proof

**What people do:** See 884 tests passing and assume the security surface is covered.
**Why it's wrong:** Tests verify intended behavior. Security audits find unintended behavior.
The test suite is written by the protocol team against their own mental model — it won't contain
tests for scenarios they didn't consider. The access control and edge case test files are valuable
inputs to understand what was thought about, but their existence doesn't prove absence of issues.
**Do this instead:** Use tests as a specification baseline. Focus audit effort on paths not
covered by tests, especially multi-step sequences and adversarial orderings.

### Anti-Pattern 3: Reviewing Modules Without Storage Context

**What people do:** Open `DegenerusGameMintModule.sol` and review it like a standalone contract.
**Why it's wrong:** The module has no storage of its own. Every storage read/write it performs
is into `DegenerusGame`'s slots. Without holding the slot layout in mind, slot 0's packed fields
look like individual state variables that are never set.
**Do this instead:** Keep `DegenerusGameStorage.sol` open in a side window. For every storage
access in a module, explicitly map it to the slot layout.

### Anti-Pattern 4: Treating VRF as a Black Box

**What people do:** Assume Chainlink VRF output is "truly random and safe" and don't audit
the request/fulfill state machine.
**Why it's wrong:** VRF randomness is cryptographically unmanipulable, but the surrounding
state machine — when to request, when to fulfill, what to do with the result — is pure Solidity
and can have bugs. The 2022 VRF v2 vulnerability allowed a malicious subscription owner to
reroll randomness. Timeout handling, request cancellation, and callback reversion are all
attack surfaces.
**Do this instead:** Audit the RNG state machine as a first-class security concern in Phase 2.
Treat the VRF output itself as trusted, but treat everything around it as untrusted.

---

## Integration Points

### External Services

| Service | Integration Point | Audit Surface |
|---------|------------------|---------------|
| Chainlink VRF V2.5 | `DegenerusGame.fulfillRandomWords()` callback from coordinator | Caller validation, request ID matching, reentry from callback, fulfillment reversion risk |
| Chainlink VRF V2.5 | `DegenerusAdmin.createSubscription()` at constructor | Subscription ownership, consumer list, LINK balance |
| Lido stETH | `DegenerusVault` holds stETH; `DegenerusGame.claimWinningsStethFirst()` | Rebasing behavior affecting accounting, `transfer` vs `transferFrom` correctness |
| LINK token (ERC-677) | `DegenerusAdmin.onTokenTransfer()` receives LINK donations | ERC-677 callback safety, reentrancy from token |

### Internal Boundaries

| Boundary | Communication | Audit Surface |
|----------|--------------|---------------|
| Game → Modules | `delegatecall` with compile-time addresses | Storage layout alignment, return value handling, failed delegatecall silent failure |
| AdvanceModule → JackpotModule | Inner delegatecall chain | Nested delegatecall context correctness |
| Vault → Game | Direct external calls (`purchase`, `advanceGame`, `claimWinnings`) | Operator approval scope, reentrancy from Vault into Game |
| Stonk → Game | `claimWhalePass`, `setAfKingMode` at constructor and runtime | Constructor-time ordering safety |
| Admin → VRF Coordinator | Subscription management, `wireVrf()` after deploy | Post-deploy setup atomicity, subscription ID persistence |
| Coinflip → BurnieCoin | `burnForCoinflip`, `mintForCoinflip` | Token supply manipulation via burn/mint gating |

---

## Scalability of the Review Process

This is an audit, not a deployed system, so "scaling" refers to reviewer allocation:

| Scope | Review Approach |
|-------|----------------|
| 1 reviewer | Strictly sequential, Phases 1-7 in order. Minimum viable. |
| 2 reviewers | Phase 1-2 together, then split Phase 3 sub-phases (one takes 3a/3b/3c, other takes 3d/3e/3f). Reconvene for Phases 4-7. |
| 3+ reviewers | Phase 1-2 pair, Phase 3 three-way split, dedicated economic modeler for Phase 5. All reconvene for Phase 7. |

The storage foundation (Phase 1) and synthesis (Phase 7) should never be split across reviewers —
they require a single consistent mental model.

---

## Sources

- Hacken Smart Contracts Audit Methodology: [https://docs.hacken.io/methodologies/smart-contracts/](https://docs.hacken.io/methodologies/smart-contracts/) (MEDIUM confidence — authoritative firm methodology)
- Cyfrin: How To Approach A Smart Contract Audit: [https://www.cyfrin.io/blog/10-steps-to-systematically-approach-a-smart-contract-audit](https://www.cyfrin.io/blog/10-steps-to-systematically-approach-a-smart-contract-audit) (MEDIUM confidence — practitioner guide)
- Chainlink VRF V2 Security Considerations: [https://docs.chain.link/vrf/v2/security](https://docs.chain.link/vrf/v2/security) (HIGH confidence — official Chainlink documentation)
- MixBytes: Collisions of Solidity Storage Layouts: [https://mixbytes.io/blog/collisions-solidity-storage-layouts](https://mixbytes.io/blog/collisions-solidity-storage-layouts) (MEDIUM confidence — security firm technical post)
- AuditOne: Auditing Delegatecall: [https://www.auditone.io/blog-posts/auditing-a-solidity-contract-episode-2---delegatecall](https://www.auditone.io/blog-posts/auditing-a-solidity-contract-episode-2---delegatecall) (MEDIUM confidence — audit firm guide)
- Degenerus Protocol Codebase: direct analysis of `DegenerusGameStorage.sol`, `DegenerusGame.sol`, `DegenerusGameAdvanceModule.sol`, `ContractAddresses.sol`, `predictAddresses.js` (HIGH confidence — primary source)

---

*Architecture research for: Smart contract security audit of the Degenerus Protocol*
*Researched: 2026-02-28*
