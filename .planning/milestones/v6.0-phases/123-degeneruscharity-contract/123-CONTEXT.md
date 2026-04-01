# Phase 123: DegenerusCharity Contract - Context

**Gathered:** 2026-03-25
**Status:** Ready for planning

<domain>
## Phase Boundary

Standalone DegenerusCharity.sol contract at nonce N+23 with:
- Soulbound GNRUS token (1T supply, ERC20-like interface, no transfers)
- Proportional burn-for-ETH/stETH redemption
- Per-level sDGNRS-weighted governance that controls GNRUS distribution
- Deploy pipeline integration (ContractAddresses, predictAddresses, DeployProtocol, DeployCanary)

This phase creates the contract and its tests. Phase 124 wires it into the existing game (yield routing, resolveLevel hook, allowlist, claimYield).

</domain>

<decisions>
## Implementation Decisions

### GNRUS Distribution
- **D-01:** Distribution is governance-driven. Each level transition, the winning proposal receives 2% of remaining unallocated GNRUS via direct transfer.
- **D-02:** Decaying allocation — 2% of what remains, so each level distributes less. No rollover on skip.
- **D-03:** If no proposals exist or all proposals have net-negative votes, the allocation is skipped. The 2% stays in the unallocated pool for future levels.

### Governance — Proposals
- **D-04:** Creator can submit up to 5 proposals per level. Each proposal is a recipient address.
- **D-05:** Any sDGNRS holder with >0.5% of total sDGNRS supply can propose once per level.
- **D-06:** A proposal is simply a recipient address (charity wallet, project, etc.) that receives the GNRUS allocation if it wins.

### Governance — Voting
- **D-07:** Any sDGNRS holder can vote. Vote weight is proportional to total allocated sDGNRS at the start of the level (snapshot-based).
- **D-08:** VAULT gets a standing vote worth 5% of the snapshot amount.
- **D-09:** Holders can cast approve OR reject on every proposal independently (not limited to one vote per level).
- **D-10:** Winner = proposal with highest (approve - reject) net weight. Ties and >100% from mid-level mints are acceptable — only net weight matters.

### Governance — Resolution
- **D-11:** resolveLevel() is called by the game contract only (via AdvanceModule at level transition). This is wired in Phase 124.
- **D-12:** For Phase 123, resolveLevel() exists on the contract but the game hook comes in Phase 124. Testing uses direct calls.

### Contract Structure
- **D-13:** Mirror sDGNRS soulbound pattern — flat contract, balanceOf, totalSupply, Transfer events for indexers, no transfer/transferFrom/approve.
- **D-14:** Pull model for funding — claimYield() permissionlessly pulls accumulated ETH/stETH from DegenerusGame claimable balances.
- **D-15:** Constructor takes game address and stETH address as immutables (same pattern as sDGNRS).

### Burn Mechanics (from CHAR-03)
- **D-16:** Burning GNRUS returns proportional share of BOTH ETH and stETH: `(amount / totalSupply) * balance` for each asset.
- **D-17:** Minimum burn enforcement and last-holder sweep per requirements (exact thresholds to be determined during planning).

### Claude's Discretion
- Storage layout and packing decisions
- Event design and naming
- Error naming conventions (follow existing codebase patterns)
- NatSpec documentation depth
- Test file organization

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Soulbound Token Pattern
- `contracts/StakedDegenerusStonk.sol` — Primary pattern reference for soulbound ERC20-like token (balanceOf, totalSupply, Transfer events, no transfer/approve)
- `contracts/DegenerusDeityPass.sol` — Alternative soulbound pattern (ERC721, reverts on all transfer ops)

### Burn-for-Redemption Pattern
- `contracts/DegenerusVault.sol` lines 739-820 — burnCoin() and burnEth() implement proportional share redemption (`reserve * sharesBurned / totalSupply`)

### Deploy Pipeline
- `contracts/ContractAddresses.sol` — Compile-time constants for all contract addresses (CHARITY must be added at N+23)
- `scripts/lib/predictAddresses.js` — DEPLOY_ORDER array and address prediction (must add CHARITY entry)
- `scripts/lib/patchForFoundry.js` — Patches ContractAddresses.sol for Foundry test builds
- `test/fuzz/helpers/DeployProtocol.sol` — Abstract test base deploying all protocol contracts (must add CHARITY)
- `test/fuzz/DeployCanary.t.sol` — Verifies predicted addresses match actual deploys

### Game Integration Points (Phase 124 scope, read for interface awareness)
- `contracts/modules/DegenerusGameJackpotModule.sol` lines 885-916 — `_distributeYieldSurplus()` currently splits to VAULT and SDGNRS
- `contracts/DegenerusGame.sol` lines 1352-1358 — `claimWinningsStethFirst()` allowlist (currently VAULT and SDGNRS only)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **StakedDegenerusStonk.sol** — Direct pattern to mirror for soulbound token: error/event naming, balanceOf mapping, Transfer emission on mint/burn
- **DegenerusVault.burnEth()** — Proportional redemption math with ETH-first stETH-fallback payout
- **ContractAddresses library** — All addresses are `internal constant`, CHARITY follows same format
- **predictAddresses.js DEPLOY_ORDER** — Array of constant names maps 1:1 to nonce offsets

### Established Patterns
- All protocol contracts use Solidity 0.8.34, AGPL-3.0-only license
- Soulbound tokens emit Transfer events for indexer compatibility despite blocking actual transfers
- Immutable constructor args for cross-contract references (no storage slots for known addresses)
- Custom errors (not require strings) throughout codebase

### Integration Points
- CHARITY deploys at nonce N+23 (after ADMIN at N+22)
- resolveLevel(uint24 lvl) called by game during advanceGame (Phase 124)
- claimYield() pulls from DegenerusGame.claimableWinnings[CHARITY]
- stETH-first claim requires allowlist entry in DegenerusGame (Phase 124)

</code_context>

<specifics>
## Specific Ideas

- Governance is the distribution mechanism — there is no separate airdrop or sale. Proposals compete for 2% of remaining GNRUS each level.
- VAULT gets a standing 5% vote on every proposal automatically — this is a protocol-level voice, not a player.
- The 0.5% sDGNRS threshold for proposing prevents spam without being prohibitively high.
- Creator's 5-proposal cap per level allows curated options alongside community proposals.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 123-degeneruscharity-contract*
*Context gathered: 2026-03-25*
