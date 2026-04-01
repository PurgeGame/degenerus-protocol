# Phase 123: DegenerusCharity Contract - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-25
**Phase:** 123-degeneruscharity-contract
**Areas discussed:** GNRUS distribution, Contract structure

---

## GNRUS Distribution

### How should GNRUS tokens be distributed?

| Option | Description | Selected |
|--------|-------------|----------|
| Game reward pools | Mirror sDGNRS pattern — pre-split into named pools drawn down as rewards | |
| Permissionless claim | Players claim based on eligibility (snapshot, score) | |
| Creator-controlled | Creator/admin distributes via transfer-from-contract function | |
| Direct sale / bonding | Players send ETH/stETH, receive proportional GNRUS | |
| (Custom) | Governance-driven: winning proposal each level gets 2% of remaining unallocated | ✓ |

**User's choice:** Every level at level transition, the highest net-approve proposal receives 2% of remaining unallocated GNRUS via direct transfer.
**Notes:** Distribution is inherently tied to governance — proposals compete for the allocation.

### Who can submit proposals?

| Option | Description | Selected |
|--------|-------------|----------|
| Any sDGNRS holder | Anyone with sDGNRS balance can propose | |
| Minimum sDGNRS threshold | Must hold minimum to propose | |
| Creator-only proposals | Only creator submits candidates | |
| (Custom) | Creator up to 5 + any sDGNRS holder >0.5% once per level | ✓ |

**User's choice:** Dual-track: creator can submit up to 5 proposals per level, any sDGNRS holder with >0.5% of total holdings can propose once per level.
**Notes:** Combines curated and community proposals.

### Who can vote?

| Option | Description | Selected |
|--------|-------------|----------|
| Any sDGNRS holder, 1:1 weight | Vote weight = sDGNRS balance at vote time | |
| Snapshot at level start | Balances snapshot when level begins | |
| Activity-gated + weighted | Requires game activity score AND sDGNRS | |
| (Custom) | sDGNRS holder, proportional to total allocated at level start. VAULT gets 5% vote. | ✓ |

**User's choice:** sDGNRS holders vote proportional to total allocated sDGNRS at level start. VAULT gets a standing vote worth 5% of that snapshot. >100% from mid-level mints is fine; only net approve-reject matters.

### What happens with no valid winner?

| Option | Description | Selected |
|--------|-------------|----------|
| Skip allocation | 2% stays unallocated, next level calculates from same pool | ✓ |
| Roll over to next level | Carries forward and adds to next level's allocation | |
| Creator default | Goes to creator-specified default address | |

**User's choice:** Skip allocation. No rollover.

### How are GNRUS delivered to winners?

| Option | Description | Selected |
|--------|-------------|----------|
| Direct transfer | resolveLevel() moves GNRUS immediately | ✓ |
| Claimable balance | Winner has a claimable balance to pull | |

**User's choice:** Direct transfer at resolution.

### Can holders vote on multiple proposals?

| Option | Description | Selected |
|--------|-------------|----------|
| One vote per level | Pick one proposal to approve | |
| Approve/reject each | Cast approve or reject on every proposal independently | ✓ |
| Single approve + rejects | Approve one, optionally reject others | |

**User's choice:** Full approve/reject on each proposal independently.

---

## Contract Structure

### Soulbound token pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror sDGNRS | Flat contract, balanceOf, totalSupply, Transfer events, no transfer/approve | ✓ |
| Minimal non-ERC20 | No balanceOf view, no Transfer events, pure accounting | |

**User's choice:** Mirror sDGNRS pattern.

### ETH/stETH funding model

| Option | Description | Selected |
|--------|-------------|----------|
| receive() + direct stETH transfer | Accept raw ETH, stETH via ERC20 transfer | |
| Explicit deposit function | depositEth() + depositSteth() with access control | |
| Pull from game | claimYield() pulls from DegenerusGame claimable balances | ✓ |

**User's choice:** Pull model — claimYield() permissionlessly pulls from game.

### Who calls resolveLevel()?

| Option | Description | Selected |
|--------|-------------|----------|
| Game contract only | Only DegenerusGame (AdvanceModule) can call | ✓ |
| Permissionless | Anyone can call after level advances | |
| Game with permissionless fallback | Game calls, anyone can trigger after grace period | |

**User's choice:** Game contract only (wired in Phase 124).

---

## Claude's Discretion

- Storage layout and packing
- Event/error naming conventions
- NatSpec depth
- Test organization

## Deferred Ideas

None — discussion stayed within phase scope.
