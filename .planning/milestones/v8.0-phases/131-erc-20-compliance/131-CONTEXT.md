# Phase 131: ERC-20 Compliance - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning

<domain>
## Phase Boundary

Verify ERC-20 interface compliance across all 4 token contracts (DGNRS, sDGNRS, BURNIE, GNRUS). Document intentional deviations. Produce a single consolidated compliance report for Phase 134 consumption.

</domain>

<decisions>
## Implementation Decisions

### Deviation Policy
- **D-01:** sDGNRS and GNRUS are NOT ERC-20 tokens. Frame them explicitly as "soulbound tokens that implement balanceOf/totalSupply for compatibility but are not ERC-20 compliant by design." Wardens cannot file ERC-20 compliance issues against non-ERC-20 tokens.
- **D-02:** DGNRS and BURNIE are the actual ERC-20 tokens — these get full compliance auditing.
- **D-03:** Carries from Phase 130 D-05: default disposition is DOCUMENT, not fix. No contract code changes.

### Edge Case Scope
- **D-04:** Deep + weird edge case coverage for DGNRS and BURNIE:
  - Standard: zero-amount transfers, self-transfer, max-uint approval, return value handling
  - Deep: approve race condition (ERC-20 known issue), permit/EIP-2612 absence, transfer-to-zero-address, transfer-to-contract behavior, callback reentrancy via receiver
- **D-05:** For sDGNRS and GNRUS: verify soulbound restrictions are airtight (no bypass paths), verify view functions return correct values, document what IS implemented vs what ISN'T.

### Output Format
- **D-06:** Single consolidated document (`audit/erc-20-compliance.md`) with sections per token. Easier for Phase 134 to consume than 4 separate files.

### Claude's Discretion
- Per-finding severity assessment
- Whether to include ERC-20 metadata (name, symbol, decimals) compliance in the audit or focus on transfer mechanics

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Token Contracts
- `contracts/DegenerusStonk.sol` — DGNRS transferable ERC-20 wrapper (transfer, transferFrom, approve)
- `contracts/StakedDegenerusStonk.sol` — sDGNRS soulbound token (balanceOf, transfer in interface only)
- `contracts/BurnieCoin.sol` — BURNIE token (transfer, transferFrom, approve, totalSupply)
- `contracts/GNRUS.sol` — GNRUS soulbound token (all transfer/approve functions revert with TransferDisabled)

### Interfaces
- `contracts/interfaces/IStakedDegenerusStonk.sol` — sDGNRS interface definitions
- `contracts/interfaces/IDegenerusCoin.sol` — BURNIE interface definitions

### Prior Audit Coverage
- `audit/v5.0-FINDINGS.md` — Unit 11 (sDGNRS + DGNRS) and Unit 10 (BURNIE) adversarial audit results
- `audit/v7.0-findings-consolidated.md` — Delta audit of token changes

</canonical_refs>

<code_context>
## Existing Code Insights

### Token Architecture
- DGNRS wraps sDGNRS — holds sDGNRS and issues transferable ERC-20
- sDGNRS is soulbound — game rewards go here, cannot be transferred between players
- BURNIE is the game's currency token — used in coinflip, burned for gameplay
- GNRUS is charity token — soulbound, burn-redeemable for proportional ETH/stETH

### ERC-20 Surface Area
- DGNRS: transfer, transferFrom, approve, balanceOf (from interface) — most ERC-20-like
- BURNIE: transfer, transferFrom, approve, totalSupply — full ERC-20-like
- sDGNRS: Only balanceOf and transfer in interface — no approve/transferFrom/allowance functions
- GNRUS: transfer/transferFrom/approve all revert with `TransferDisabled()`

### Integration Points
- Output goes to `audit/erc-20-compliance.md`
- Feeds into Phase 134 KNOWN-ISSUES.md consolidation

</code_context>

<specifics>
## Specific Ideas

- The "not an ERC-20" framing for sDGNRS/GNRUS is a defensive strategy — wardens who try to file "missing approve()" on a token explicitly declared non-ERC-20 get their finding invalidated
- Deep edge cases on DGNRS/BURNIE because those are the tokens wardens will actually poke at

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 131-erc-20-compliance*
*Context gathered: 2026-03-27*
