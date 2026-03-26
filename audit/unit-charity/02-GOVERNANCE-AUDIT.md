# DegenerusCharity Governance Audit

**Contract:** `contracts/DegenerusCharity.sol` (lines 143-523)
**Methodology:** v5.0 Three-Agent Adversarial System (Mad Genius / Skeptic / Taskmaster)
**Scope:** 5 governance functions: `propose`, `vote`, `resolveLevel`, `getProposal`, `getLevelProposals`
**Date:** 2026-03-26

---

## 1. DegenerusCharity::propose(address recipient) (lines 355-394)

### Call Tree

```
propose(address recipient) [EXTERNAL, lines 355-394]
  +-- sdgnrs.totalSupply() [EXTERNAL READ, line 362] -- only on first proposal of level
  +-- vault.isVaultOwner(proposer) [EXTERNAL READ, line 368]
  +-- sdgnrs.balanceOf(proposer) [EXTERNAL READ, line 375] -- only for community proposers
  (no internal helper calls)
```

### Storage Writes (Full Tree)

| Variable | Line | Condition |
|----------|------|-----------|
| `levelSdgnrsSnapshot[level]` | 362 | First proposal of level (levelProposalCount == 0) |
| `levelVaultOwner[level]` | 370 | Vault owner, first vault-owner action of level |
| `creatorProposalCount[level]` | 372 | Vault owner path |
| `hasProposed[level][proposer]` | 377 | Community path |
| `proposalCount` | 380 | Always |
| `levelProposalStart[level]` | 382 | First proposal of level |
| `levelProposalCount[level]` | 384 | Always |
| `proposals[proposalId]` | 386-391 | Always (new struct) |

### Attack Analysis

#### A. Flash-loan sDGNRS to meet propose threshold
**Attack:** Attacker flash-loans sDGNRS to get >= 0.5% of snapshot supply, proposes, returns tokens.

**Analysis:** sDGNRS (StakedDegenerusStonk) is soulbound -- it has no `transfer()` function (confirmed: contract has `wrapperTransferTo` restricted to DGNRS wrapper only, no public transfer). sDGNRS cannot be flash-loaned because it cannot be transferred at all. The only way to acquire sDGNRS is through game reward pools or unwrapping DGNRS (which itself requires owning DGNRS and waiting for non-VRF-stall conditions).

**VERDICT: SAFE** -- sDGNRS is soulbound; flash-loan attack on propose threshold is impossible.

#### B. Vault owner privilege abuse (lines 368-373)
**Attack:** Flash-loan DGVE to become vault owner (>50.1%), propose 5 times, return DGVE.

**Analysis:** DGVE (DegenerusVaultShare) IS a standard ERC-20 with `transfer()` (confirmed in DegenerusVault.sol line 225). `vault.isVaultOwner()` checks current DGVE balance > 50.1% of supply. If DGVE were available in a flash-loan pool (Aave, dYdX, etc.), an attacker could atomically: (1) flash-loan >50.1% DGVE, (2) call `propose()` up to 5 times, (3) return DGVE. Each proposal would pass the vault-owner check.

However, DGVE is a custom protocol token deployed at a protocol-specific address. It would only be in a flash-loan pool if the protocol team or users deposited it. For a fresh deployment, DGVE supply is entirely held by the creator. In practice, flash-loan availability requires significant DGVE liquidity on a lending protocol.

Additionally, even if the attacker proposes 5 times, those proposals still need community approval via sDGNRS-weighted votes. The attacker cannot force votes.

**VERDICT: SAFE** -- DGVE flash-loan requires external liquidity pool listing (unlikely for protocol-internal share token). Even if achieved, proposals still require sDGNRS-weighted approval. Risk is theoretical and attacker-unprofitable.

#### C. Snapshot manipulation on first proposal (lines 361-363)
**Attack:** Attacker front-runs the first legitimate proposal to set a manipulated sDGNRS snapshot.

**Analysis:** `levelSdgnrsSnapshot[level] = uint128(sdgnrs.totalSupply())` reads the actual sDGNRS total supply. The attacker cannot manipulate `totalSupply()` because sDGNRS is soulbound (no transfers) and minting is restricted to game reward pools (onlyGame modifier). The only way to change supply is through the game's reward distribution or burn mechanisms, which cannot be atomically triggered by an external attacker.

Even if the attacker is the first proposer, the snapshot reflects the real supply. A low snapshot would make the 0.5% threshold easier to meet, but since the attacker cannot manipulate the supply, the snapshot is always accurate.

**VERDICT: SAFE** -- totalSupply() reflects actual sDGNRS supply; cannot be manipulated atomically.

#### D. Recipient validation bypass (lines 356-357)
**Attack:** Propose a CREATE2 pre-computed address (code.length == 0 at proposal time, deploy contract later).

**Analysis:** `recipient.code.length != 0` is checked at proposal time only. A CREATE2 address with no deployed code passes this check. After the proposal wins and GNRUS is distributed, a contract could be deployed at that address. However, GNRUS is soulbound -- `transfer()` reverts with `TransferDisabled()`. The contract at the recipient address cannot move the tokens. The tokens are permanently stuck. This is self-harm by the proposer, not a protocol vulnerability.

**VERDICT: SAFE** -- soulbound enforcement makes contract-recipient a self-inflicted loss, not a protocol exploit.

#### E. Vault owner double-propose (propose as vault owner + community)
**Attack:** Vault owner proposes 5 times (vault path, lines 368-373). Then sells DGVE. Then calls propose again as community member (lines 374-377). Since `hasProposed` was never set on the vault-owner path, the community path succeeds.

**Analysis:** The vault owner path (lines 368-373) does NOT set `hasProposed[level][proposer] = true`. It only increments `creatorProposalCount[level]`. If the vault owner later loses vault ownership (e.g., sells DGVE) and has >= 0.5% sDGNRS, they could call `propose()` again and take the community path, which would succeed because `hasProposed` was never set.

This allows 6 proposals from one address (5 as vault owner + 1 as community). However:
1. It requires selling >50.1% DGVE mid-level (losing vault ownership).
2. The former vault owner needs 0.5% sDGNRS independently.
3. 6 proposals instead of 5 is minor -- proposals still need votes to win.
4. The attacker loses vault ownership (and its 5% vote bonus) permanently for this level.

**VERDICT: SAFE (INFO)** -- Technically 6 proposals possible but requires losing vault ownership mid-level, which removes the 5% vote bonus. Net effect is neutral-to-negative for the attacker.

#### F. proposalCount overflow (line 380)
**Analysis:** `proposalCount` is uint48 (max 281,474,976,710,655). At 1 proposal per block (12s), overflow takes ~107 million years.

**VERDICT: SAFE** -- Overflow infeasible within protocol lifetime.

#### G. levelProposalCount double-zero-check consistency (lines 361, 381)
**Analysis:** Both `levelProposalCount[level] == 0` checks on lines 361 and 381 execute in sequence within a single transaction. Nothing between them modifies `levelProposalCount`. The increment is on line 384, after both checks. No reentrancy vector exists (no external calls between the two checks). Both checks are always consistent.

**VERDICT: SAFE** -- Single-transaction atomicity guarantees consistency.

### Cached-Local-vs-Storage Check

No ancestor caches a storage value that a descendant writes. The function reads `currentLevel` once into `level` (line 358) and `proposalCount` into `proposalId` (line 380), but these are used after all writes complete. No BAF-class vulnerability.

**VERDICT: SAFE**

---

## 2. DegenerusCharity::vote(uint48 proposalId, bool approveVote) (lines 406-431)

### Call Tree

```
vote(uint48 proposalId, bool approveVote) [EXTERNAL, lines 406-431]
  +-- sdgnrs.balanceOf(voter) [EXTERNAL READ, line 416]
  +-- vault.isVaultOwner(voter) [EXTERNAL READ, line 418] -- conditional
  (no internal helper calls)
```

### Storage Writes (Full Tree)

| Variable | Line | Condition |
|----------|------|-----------|
| `hasVoted[level][voter][proposalId]` | 414 | Always |
| `levelVaultOwner[level]` | 419 | Vault owner, first vault-owner action of level |
| `proposals[proposalId].approveWeight` | 425 | approveVote == true |
| `proposals[proposalId].rejectWeight` | 427 | approveVote == false |

### Attack Analysis

#### A. Flash-loan sDGNRS for vote weight inflation
**Attack:** Flash-loan sDGNRS, vote with inflated weight, return sDGNRS.

**Analysis:** sDGNRS is soulbound -- no `transfer()` function. Cannot be flash-loaned, borrowed, or atomically moved between addresses. `sdgnrs.balanceOf(voter)` at line 416 reads the voter's actual sDGNRS holdings, which cannot be temporarily inflated.

**VERDICT: SAFE** -- sDGNRS soulbound; flash-loan vote weight inflation impossible.

#### B. Vault owner double-weight (lines 418-421)
**Attack:** Vault owner gets sDGNRS balance PLUS 5% of snapshot as bonus weight per vote.

**Analysis:** Line 418-420: `if (voter == levelVaultOwner[level] || (levelVaultOwner[level] == address(0) && vault.isVaultOwner(voter)))`. The vault owner gets `weight += uint128((uint256(levelSdgnrsSnapshot[level]) * VAULT_VOTE_BPS) / BPS_DENOM)` which is 5% of snapshot supply per vote.

The vault owner can vote on EVERY proposal independently (different proposalIds). With N proposals, the vault owner gets N * 5% bonus weight total across all votes. However, each vote is independent -- approving one proposal doesn't reduce weight on another. The vault owner's total approve weight on their preferred proposal is `sDGNRS_balance + 5% * snapshot`. Their reject weight on each competitor is the same amount.

This is by design: the vault owner (>50.1% DGVE = protocol creator) gets a governance bonus. The 5% is modest relative to the total sDGNRS supply, and the vault owner's actual voting power scales with their sDGNRS holdings like anyone else.

**VERDICT: SAFE** -- By design. Vault owner bonus is 5% of snapshot, bounded and intentional.

#### C. Vault ownership transfer mid-level
**Attack:** Alice is vault owner, proposes. Alice sells DGVE to Bob. Bob is now vault owner for voting. But `levelVaultOwner[level]` was locked to Alice on first vault-owner action (line 370 or 419). Bob's `vault.isVaultOwner(voter)` returns true but `levelVaultOwner[level]` is already Alice, so Bob takes the first branch `voter == levelVaultOwner[level]` which is false. Bob then hits the second branch `levelVaultOwner[level] == address(0)` which is also false (it's Alice). Bob does NOT get the vault bonus.

Wait -- re-read line 418: `if (voter == levelVaultOwner[level] || (levelVaultOwner[level] == address(0) && vault.isVaultOwner(voter)))`. If `levelVaultOwner[level] == Alice`, then for Bob: `voter == Alice` is false, and `levelVaultOwner[level] == address(0)` is false. Bob does NOT get vault bonus. Bob votes with pure sDGNRS weight only.

This means if vault ownership changes mid-level, the original vault owner retains the bonus for this level. The new vault owner gets no bonus until the next level. This is a reasonable locking mechanism.

**VERDICT: SAFE** -- Vault owner locked on first action per level; mid-level ownership changes don't grant double bonus.

#### D. Vote on all proposals (whale strategy)
**Analysis:** A single voter can vote approve on their preferred proposal AND reject on all competitors. With N proposals, a whale can cast N votes total. This gives large holders disproportionate influence because they can both promote and suppress.

However, this is by design. The hasVoted check is per-proposal-per-voter (`hasVoted[level][voter][proposalId]`), not per-level-per-voter. Each voter gets one approve/reject per proposal. This is an intentional multi-proposal voting system, not a bug.

**VERDICT: SAFE** -- By design. Per-proposal voting is intentional.

#### E. Zero-weight vote prevention (line 422)
**Analysis:** `if (weight == 0) revert InsufficientStake()` prevents non-sDGNRS holders from voting. Even if a non-vault-owner has zero sDGNRS, the revert fires.

**VERDICT: SAFE** -- Zero-weight votes correctly rejected.

#### F. approveWeight/rejectWeight overflow (lines 425-428)
**Analysis:** `uint128` max = 3.4e38. sDGNRS total supply is ~1e30 (1T * 1e18). Even if every sDGNRS holder voted the same way on one proposal, total weight <= ~1.05e30 (supply + 5% vault bonus). Well under uint128 max.

**VERDICT: SAFE** -- uint128 sufficient for maximum possible vote weight.

#### G. Proposal range validation edge case (line 410)
**Analysis:** `proposalId < start || proposalId >= start + count`. `start` is uint48, `count` is uint8 (max 255). `start + count` max = 281T + 255, which fits in uint48. No overflow.

**VERDICT: SAFE** -- Arithmetic fits within uint48.

### Cached-Local-vs-Storage Check

`level` (line 407), `start` (line 408), `count` (line 409), `weight` (line 416) are all local variables read from storage. No descendant call writes to any of these storage slots. The only storage writes are `hasVoted`, `levelVaultOwner`, and `proposals[].approveWeight/rejectWeight`. None conflict with cached locals.

**VERDICT: SAFE**

---

## 3. DegenerusCharity::resolveLevel(uint24 level) (lines 443-498)

### Call Tree

```
resolveLevel(uint24 level) [EXTERNAL, lines 443-498]
  (no external or internal calls -- pure storage reads and writes)
```

### Storage Writes (Full Tree)

| Variable | Line | Condition |
|----------|------|-----------|
| `levelResolved[level]` | 446 | Always |
| `currentLevel` | 449 | Always |
| `balanceOf[address(this)]` | 494 | Winner exists and distribution > 0 |
| `balanceOf[recipient]` | 495 | Winner exists and distribution > 0 |

### Attack Analysis

#### A. Permissionless calling -- front-running game's resolveLevel (CRITICAL PATH)
**Attack:** `resolveLevel()` has NO access control modifier. Anyone can call it. The game's `DegenerusGameAdvanceModule._finalizeRngRequest` calls `charityResolve.resolveLevel(lvl - 1)` on line 1364 as a raw external call (no try/catch). If an attacker front-runs this by calling `resolveLevel(currentLevel)` before the game does, the game's subsequent call reverts with `LevelAlreadyResolved` (line 445). Since the call is not wrapped in try/catch, the entire `_finalizeRngRequest` reverts, which means day advancement is bricked.

**Trace:**
1. Level is at N. Game processes daily RNG and reaches line 1364: `charityResolve.resolveLevel(N)`.
2. Attacker monitors mempool, sees pending `_finalizeRngRequest`, front-runs with `resolveLevel(N)`.
3. Attacker's call succeeds: `levelResolved[N] = true`, `currentLevel = N + 1`.
4. Game's `_finalizeRngRequest` executes `charityResolve.resolveLevel(N)`, hits `levelResolved[N] == true`, reverts with `LevelAlreadyResolved`.
5. `_finalizeRngRequest` reverts entirely (no try/catch wrapping the call).
6. Day advancement fails.

**But wait** -- re-read. The `resolveLevel` call is inside `_finalizeRngRequest` which is called during VRF fulfillment (`rawFulfillRandomWords`). VRF fulfillment is called by the Chainlink VRF coordinator. The attacker cannot front-run VRF fulfillment in the traditional sense because the VRF callback is a direct transaction from the coordinator, not pending in the public mempool.

However, there is a subtler issue: the game calls `resolveLevel(lvl - 1)` where `lvl` is the NEW level. The charity's `currentLevel` must equal `lvl - 1` at the time of the call. If someone calls `resolveLevel(currentLevel)` externally before the game does, `currentLevel` advances to `lvl`. The game then calls `resolveLevel(lvl - 1)` but `currentLevel` is now `lvl`, and `lvl - 1 != currentLevel`, so it would fail with `LevelNotActive()` -- but actually no, line 444 checks `level != currentLevel` where `level` is the parameter and `currentLevel` was already advanced by the attacker's call. Wait, re-read carefully:

The attacker calls `resolveLevel(N)` where N = `currentLevel`. This sets `levelResolved[N] = true` and `currentLevel = N + 1`. When the game then calls `resolveLevel(N)`, the check on line 444 `if (level != currentLevel)` evaluates `N != N+1` = true, so it reverts with `LevelNotActive()`.

So there are TWO revert paths, but the result is the same: game's resolveLevel call reverts, and since it's not try/catch, `_finalizeRngRequest` reverts.

**Severity assessment:** The resolveLevel call is inside the `isTicketJackpotDay && !isRetry` conditional on line 1356. It only runs on ticket jackpot days (days where `lastPurchaseDay == true`). If the attacker front-runs and causes revert, the VRF fulfillment fails. The VRF request can be retried after the 12h timeout. On retry, `isRetry` would be true, so the resolveLevel call is SKIPPED (line 1356 `!isRetry`). The game advances but the charity governance resolution is permanently skipped for that level.

Actually wait -- re-check. On retry, `isRetry` is true, so the `if (isTicketJackpotDay && !isRetry)` block is entirely skipped. The `level = lvl` assignment on line 1357 is ALSO skipped. So the game level does not advance on retry either? Let me re-read the code flow...

Actually, the level advancement on line 1357 (`level = lvl`) is already inside the `if (isTicketJackpotDay && !isRetry)` block. If retry skips this block, the game level doesn't advance. But the retry still processes daily tickets and other logic. The level advancement would be attempted again on the next non-retry ticket jackpot day.

The real question: does the attacker's `resolveLevel(N)` call advance `currentLevel` to N+1 in the charity, while the game's level stays at N? This creates a desync: charity thinks it's on level N+1, game thinks it's on level N. On the next ticket jackpot day, the game calls `resolveLevel(N)` again (because game level is still N), but charity's `levelResolved[N]` is already true.

This is a griefing vector but the impact is limited:
1. The attacker can externally resolve level N before the game does, choosing the timing.
2. The game's VRF callback reverts, requiring a retry.
3. On retry, level advancement is skipped; level advances on the next non-retry ticket jackpot.
4. But the charity governance for level N was already resolved (correctly) by the attacker -- the same proposals and votes exist regardless of who calls resolveLevel.
5. The charity's `currentLevel` and the game's `level` would desync by +1 from the charity's perspective.

Wait, actually -- the retry skips the `level = lvl` and `resolveLevel` entirely. On the NEXT ticket jackpot day (fresh request, not retry), the game increments level to lvl+1 and calls `resolveLevel(lvl)`. But charity's `currentLevel` is already N+1 (from the attacker's call). So `resolveLevel(N+1-1)` = `resolveLevel(N)`, which is already resolved. The game's call would fail again.

Actually no. Let me be more precise. The game tracks its own `level` state variable, separate from charity's `currentLevel`. The game calls `charityResolve.resolveLevel(lvl - 1)` where `lvl` is `level` in the game (the new level after increment). If the game's level is at M and increments to M+1, it calls `charityResolve.resolveLevel(M)`. If the charity's `currentLevel` is M, this works. If the charity's `currentLevel` is already M+1 (because attacker resolved M externally), the call fails with `LevelNotActive`.

This creates a permanent desync: the game can never advance level again because every attempt to call `resolveLevel(M)` fails (charity already resolved it). The game is permanently bricked for level transitions.

Unless... the game catches the revert. Let me verify one more time: line 1364 `charityResolve.resolveLevel(lvl - 1);` -- this is a regular external call, NOT try/catch. A revert here propagates up.

**VERDICT: INVESTIGATE** -- Permissionless `resolveLevel` can be called by anyone. If called before the game's `_finalizeRngRequest`, it causes the game's VRF callback to revert. This is a potential griefing vector that could brick day advancement. The severity depends on whether: (1) the attacker can reliably front-run VRF callbacks, (2) whether the retry mechanism recovers, and (3) whether the level desync is permanent.

#### B. Winner selection -- tie-breaking (lines 465-473)
**Analysis:** Ties broken by lowest index (first-submitted). Deterministic, not manipulable post-vote.

**VERDICT: SAFE** -- Deterministic tie-breaking.

#### C. Distribution calculation rounding (lines 482-483)
**Analysis:** `distribution = (unallocated * 200) / 10000 = 2%`. Integer division rounds down. For unallocated < 50 tokens (50e18 wei), distribution is 0 and level is skipped (line 485-487). This is correct -- no rounding exploit.

**VERDICT: SAFE** -- Rounding down, zero-distribution handled.

#### D. Unchecked balance transfer (lines 493-496)
**Analysis:** `balanceOf[address(this)] = unallocated - distribution` is safe because distribution = unallocated * 200 / 10000 <= unallocated. `balanceOf[recipient] += distribution` in unchecked block: recipient max balance is bounded by initial supply (1T * 1e18 = 1e30), well under uint256 max.

**VERDICT: SAFE** -- Arithmetic bounds proven safe.

#### E. Level parameter validation (line 444)
**Analysis:** `if (level != currentLevel) revert LevelNotActive()`. Prevents resolving any level other than the current one.

**VERDICT: SAFE** -- Only current level can be resolved.

#### F. Permissionless resolveLevel as vote-timing attack
**Attack:** Attacker accumulates sDGNRS, proposes, votes, then immediately calls `resolveLevel()` to "close" voting before opposition arrives.

**Analysis:** Anyone can call `resolveLevel()` at any time. There is no minimum voting period. The attack sequence is: (1) attacker proposes at start of level, (2) attacker votes approve on own proposal, (3) attacker immediately calls `resolveLevel()`. With no opposition votes, the proposal wins.

However, this is by design -- the game calls `resolveLevel()` at level transitions, which happen at a pace determined by gameplay (ticket purchases advancing levels). The governance window is the duration of a game level. If a level lasts 1 block (extremely unlikely but possible), the governance window is 1 block.

The real concern is: can an attacker call resolveLevel() BEFORE the game does, choosing favorable timing? Yes. But the governance outcome is determined by existing votes at resolution time, and the attacker's proposal still needs net-positive approval weight. If the attacker is the only voter, they win trivially. But this is true of any governance system with low participation.

**VERDICT: SAFE (INFO)** -- Permissionless resolution is by design. Governance window equals level duration. Low participation risk is inherent to the design, not a bug.

### Cached-Local-vs-Storage Check

`count` (line 451), `start` (line 459), `bestId`/`bestNet` (lines 462-463), `unallocated` (line 482), `distribution` (line 483), `recipient` (line 490) are all local. No descendant call exists (no external or internal calls). No BAF-class vulnerability possible.

**VERDICT: SAFE**

---

## 4. DegenerusCharity::getProposal(uint48 proposalId) (lines 513-518)

### Call Tree

```
getProposal(uint48 proposalId) [EXTERNAL VIEW, lines 513-518]
  (no calls -- pure storage read)
```

### Storage Writes (Full Tree)

None -- view function.

### Attack Analysis

View function returning proposal data from storage. No state changes, no external calls, no computation that could revert beyond OOG.

**VERDICT: SAFE** -- View function, zero attack surface.

---

## 5. DegenerusCharity::getLevelProposals(uint24 level) (lines 521-523)

### Call Tree

```
getLevelProposals(uint24 level) [EXTERNAL VIEW, lines 521-523]
  (no calls -- pure storage read)
```

### Storage Writes (Full Tree)

None -- view function.

### Attack Analysis

View function returning level proposal range. No state changes, no external calls.

**VERDICT: SAFE** -- View function, zero attack surface.

---

## Flash-Loan Attack Assessment

### sDGNRS (StakedDegenerusStonk) Flash-Loan Capability

**Result: NOT FLASH-LOANABLE**

sDGNRS is soulbound. The contract has no public `transfer()` function. The only transfer mechanism is `wrapperTransferTo()` (line 310 of StakedDegenerusStonk.sol), restricted to the DGNRS wrapper contract. There is no ERC-3156 flash-loan interface, no approve/transferFrom mechanism, and no way to atomically move sDGNRS between addresses.

sDGNRS acquisition paths:
1. Game reward pool distributions (requires game actions over time)
2. DGNRS unwrapping (requires owning liquid DGNRS, which requires buying on market or creator allocation)

**Conclusion:** Flash-loan attacks on sDGNRS-weighted governance (propose threshold, vote weight) are **impossible**.

### DGVE (DegenerusVaultShare) Flash-Loan Capability

**Result: TRANSFERABLE BUT PRACTICALLY NOT FLASH-LOANABLE**

DGVE is a standard ERC-20 with `transfer()` and `transferFrom()` (DegenerusVault.sol lines 225, 237). In theory, if DGVE were deposited in a flash-loan pool (Aave, dYdX, etc.), an attacker could flash-loan >50.1% to become vault owner.

However:
1. DGVE is a custom protocol token -- unlikely to be listed on lending protocols at launch.
2. >50.1% of supply must be available in a single flash-loan pool, requiring massive liquidity.
3. Even if vault ownership is flash-loaned, the vault owner can only: propose (up to 5 proposals) and get a 5% vote bonus. Proposals still need sDGNRS-weighted votes to win, and sDGNRS is soulbound.
4. The vault owner bonus is 5% of sDGNRS snapshot -- a modest advantage that cannot override community opposition.

**Conclusion:** DGVE flash-loan for vault ownership is **theoretically possible but practically infeasible** and has limited impact (proposal submission + 5% vote bonus, not outcome control).

---

## Threshold Gaming Assessment

### 0.5% Propose Threshold

The propose threshold requires `sdgnrs.balanceOf(proposer) * BPS_DENOM >= uint256(snapshot) * PROPOSE_THRESHOLD_BPS`, which simplifies to `balance >= totalSupply * 0.005`.

If sDGNRS total supply is 1T tokens (1e30 wei), the threshold is 5B tokens (5e27 wei). This is 0.5% of the total supply.

**Gaming analysis:**
- sDGNRS is soulbound and earned through game participation (reward pools).
- An attacker would need to accumulate 0.5% of all sDGNRS through legitimate gameplay.
- The snapshot is taken on the first proposal of each level, locking the threshold for that level's governance cycle.
- An attacker who meets the threshold for level N may not meet it for level N+1 if supply grows.

**VERDICT: SAFE** -- Threshold is proportional to supply and requires genuine sDGNRS accumulation.

### 5% Vault Vote Bonus

The vault owner (>50.1% DGVE) gets a bonus of `(levelSdgnrsSnapshot[level] * 500) / 10000 = 5%` of snapshot supply per vote.

**Maximum vault owner influence per level:**
- Assume N proposals. Vault owner votes on all N proposals.
- On their preferred proposal: approve weight = `sDGNRS_balance + 5% * snapshot`
- On each competitor: reject weight = `sDGNRS_balance + 5% * snapshot`
- Total influence: (N) votes, each with `balance + 5%` weight.

**Comparison with a community member holding equal sDGNRS:**
- Community member with same sDGNRS balance: weight = `balance` per vote.
- Vault owner advantage: `5% * snapshot` per vote = fixed bonus regardless of personal sDGNRS holding.

**Example:** Total sDGNRS supply = 1T. Vault owner has 0 sDGNRS but >50.1% DGVE. Vault owner's vote weight = 0 + 5% * 1T = 50B per vote. A community member with 50B sDGNRS has weight = 50B per vote. Equal influence.

**Scenario with vault owner having 100B sDGNRS:** Weight = 100B + 50B = 150B per vote. Community member with 100B sDGNRS: weight = 100B. Vault owner has 50% more influence.

**VERDICT: SAFE (INFO)** -- The 5% vault bonus is bounded and intentional. It gives the protocol creator meaningful but not dominant governance weight. A sufficiently motivated community can always outvote the vault owner.

---

## Vote Manipulation Scenarios

### Scenario 1: Accumulate-Propose-Resolve Attack

**Setup:** Attacker accumulates sDGNRS over time (legitimate gameplay), proposes, votes approve, immediately calls `resolveLevel()`.

**Analysis:**
1. Attacker meets 0.5% threshold, proposes recipient = attacker's EOA.
2. Attacker votes approve with full sDGNRS weight.
3. Attacker immediately calls `resolveLevel(currentLevel)`.
4. No other voters had time to react. Attacker's proposal wins by default.
5. Attacker receives 2% of unallocated GNRUS.

**Mitigations in place:**
- `resolveLevel` is designed to be called by the game at level transitions. External calling is permitted but the game will also call it.
- In practice, the game calls `resolveLevel` during `_finalizeRngRequest` (VRF callback). The attacker must call resolveLevel BEFORE the game's VRF callback.
- If the attacker front-runs the game, the game's call reverts (see resolveLevel Attack A above).

**VERDICT: INVESTIGATE** -- This scenario IS possible if the attacker calls resolveLevel before the game does. However, the game's level transition may be disrupted. The governance outcome itself is not manipulated (attacker's vote was legitimate), but the timing attack has side effects on game advancement. See resolveLevel Attack A for full analysis.

### Scenario 2: Vault Owner Multi-Proposal Strategy

**Setup:** Vault owner proposes 5 candidates, votes approve on preferred, reject on all others.

**Analysis:**
1. Vault owner creates proposals P1-P5 with different recipients.
2. Vault owner votes approve on P1, reject on P2-P5.
3. P1 has approve weight = `sDGNRS_balance + 5%_bonus`. P2-P5 have reject weight = same amount.
4. Community members must collectively outvote the vault owner's approve on P1 to block it.

**Required community opposition:** Need reject weight on P1 > vault owner's approve weight. If vault owner has V sDGNRS and bonus = 5% * snapshot, community needs > V + 5% * snapshot total reject weight on P1.

This is achievable if community holds sufficient sDGNRS. The vault owner's advantage is bounded by the 5% bonus.

**VERDICT: SAFE** -- By design. Vault owner has meaningful but overridable governance influence.

### Scenario 3: Sybil Attack (Split sDGNRS Across Addresses)

**Setup:** Attacker holds X sDGNRS, splits across addresses A1...An, each votes separately.

**Analysis:** Each address votes once per proposal. Total vote weight across all sybil addresses = X (sDGNRS is additive -- splitting doesn't create new weight). Compare with single address holding X: votes once per proposal with weight X. Same total influence.

The only "benefit" of sybilling: each sybil address could propose (if they each meet 0.5% threshold). But proposals still need votes, and total vote weight is unchanged.

**VERDICT: SAFE** -- Sybil attack provides no benefit due to additive vote weight.

### Scenario 4: Grief-Loop via Permissionless resolveLevel

**Setup:** Attacker repeatedly calls `resolveLevel()` every time a new level starts, before anyone can propose.

**Analysis:**
1. Level N starts. No proposals exist yet.
2. Attacker calls `resolveLevel(N)`. `levelProposalCount[N] == 0`, so the level is skipped (line 454-457). `currentLevel` advances to N+1.
3. Level N+1 starts. Attacker repeats.
4. Attacker can advance charity levels indefinitely with zero proposals/votes.

**Impact:**
- Each skipped level emits `LevelSkipped` but distributes zero GNRUS.
- The unallocated GNRUS pool is preserved (2% of unallocated * 0 proposals = skip).
- Charity governance levels desync from game levels. Game calls `resolveLevel(M)` but charity's `currentLevel` is at M + K (attacker advanced K times).
- When the game calls `resolveLevel(M)`, the level is already resolved (if M < currentLevel), causing revert.

This is the same issue as resolveLevel Attack A. The attacker can grief by advancing charity levels past the game's level, causing permanent desync and game revert.

**VERDICT: INVESTIGATE** -- Same root cause as resolveLevel Attack A. Permissionless `resolveLevel` allows advancing governance levels independently of the game, causing desync that bricks game's VRF callback.

---

## Skeptic Validation

### INVESTIGATE-01: resolveLevel permissionless calling / game desync

**Mad Genius Verdict:** INVESTIGATE
**Skeptic Verdict:** CONFIRMED -- INVESTIGATE (potential MEDIUM)

**Analysis:** I traced the call path in `DegenerusGameAdvanceModule._finalizeRngRequest` (line 1364). The call `charityResolve.resolveLevel(lvl - 1)` is indeed a raw external call with no try/catch wrapper. If it reverts, `_finalizeRngRequest` reverts, which means the VRF callback (`rawFulfillRandomWords`) reverts, which means the day cannot advance.

The mitigating factor is that VRF callbacks are not in the public mempool -- they come directly from the Chainlink coordinator. A standard mempool front-running attack doesn't apply. However, the attacker doesn't need to front-run. They can call `resolveLevel(currentLevel)` at any time -- even well before the VRF callback. Once called, the level is resolved and `currentLevel` advances. When the game's VRF callback eventually fires, it will call `resolveLevel(M)` where M is the game's level, but charity's `currentLevel` is already M+1. The check on line 444 (`level != currentLevel`) fails.

**Specific guard that prevents this:** None. There is no `onlyGame` modifier on `resolveLevel`.

**Severity assessment:** If the attacker calls `resolveLevel(N)` before the game, the game's callback fails. But the game has a 12h VRF retry mechanism. On retry (`isRetry == true`), the `isTicketJackpotDay && !isRetry` block is skipped, so `resolveLevel` is not called, and the retry may succeed for the rest of the logic. However, `level = lvl` (game level increment) is ALSO in the skipped block, so the game level doesn't advance on retry. This prevents permanent bricking of the game but delays level advancement.

The attacker can repeat this on every ticket jackpot day, permanently preventing level advancement. This is a griefing DoS.

**Proposed severity:** MEDIUM -- Permissionless `resolveLevel` can desync charity governance from game levels, causing VRF callback revert on ticket jackpot days. Repeated griefing prevents level advancement. Fix: add `onlyGame` modifier to `resolveLevel`, or wrap the call in try/catch in `_finalizeRngRequest`.

### INVESTIGATE-02: Accumulate-propose-resolve timing attack (Scenario 1)

**Mad Genius Verdict:** INVESTIGATE
**Skeptic Verdict:** DOWNGRADE TO INFO

**Analysis:** This scenario is a subset of INVESTIGATE-01. The attacker calling `resolveLevel` before the game is the same root issue. The governance outcome itself (attacker's proposal winning with legitimate sDGNRS votes) is not a vulnerability -- it's low-participation governance working as designed. The timing concern is fully captured by INVESTIGATE-01.

### INVESTIGATE-03: Grief-loop via permissionless resolveLevel (Scenario 4)

**Mad Genius Verdict:** INVESTIGATE
**Skeptic Verdict:** CONFIRMED -- Subsumed by INVESTIGATE-01

**Analysis:** Same root cause: permissionless `resolveLevel`. The grief-loop (advancing charity levels past game levels) is a specific exploitation pattern of INVESTIGATE-01. Fix is the same: access control or try/catch.

---

## Taskmaster Coverage Report

| # | Function | Lines | Priority | Analyzed | Verdict |
|---|----------|-------|----------|----------|---------|
| 1 | `propose(address)` | 355-394 | HIGH | YES | SAFE (7 attack angles) |
| 2 | `vote(uint48, bool)` | 406-431 | HIGH | YES | SAFE (7 attack angles) |
| 3 | `resolveLevel(uint24)` | 443-498 | HIGH | YES | INVESTIGATE (1 finding, 6 attack angles) |
| 4 | `getProposal(uint48)` | 513-518 | LOW | YES | SAFE (fast-track: view function) |
| 5 | `getLevelProposals(uint24)` | 521-523 | LOW | YES | SAFE (fast-track: view function) |

**Coverage: 5/5 governance functions analyzed (100%)**

**Dedicated Assessment Sections:**
- [x] Flash-Loan Attack Assessment (sDGNRS + DGVE)
- [x] Threshold Gaming Assessment (0.5% propose + 5% vault bonus)
- [x] Vote Manipulation Scenarios (4 scenarios analyzed)
- [x] Skeptic Validation (3 findings validated)

---

## Summary of Findings

| ID | Function | Severity | Title | Verdict |
|----|----------|----------|-------|---------|
| GOV-01 | `resolveLevel` | INVESTIGATE (potential MEDIUM) | Permissionless resolveLevel desync with game | Skeptic CONFIRMED |
| GOV-02 | `propose` | INFO | Vault owner can get 6th proposal by losing vault status | SAFE |
| GOV-03 | `resolveLevel` | INFO | No minimum governance voting period | SAFE (by design) |
| GOV-04 | `vote` | INFO | Vault owner 5% bonus is per-vote, accumulates across proposals | SAFE (by design) |

**Actionable:** 1 (GOV-01 -- permissionless resolveLevel)
**Informational:** 3 (GOV-02, GOV-03, GOV-04)

### GOV-01 Recommended Fixes (choose one):

**Option A (preferred):** Add `onlyGame` modifier to `resolveLevel`:
```solidity
function resolveLevel(uint24 level) external onlyGame {
```

**Option B:** Wrap the `charityResolve.resolveLevel()` call in try/catch in `_finalizeRngRequest`:
```solidity
try charityResolve.resolveLevel(lvl - 1) {} catch {}
```

Option A is cleaner and prevents external callers entirely. Option B is more resilient but silently skips failed resolutions.
