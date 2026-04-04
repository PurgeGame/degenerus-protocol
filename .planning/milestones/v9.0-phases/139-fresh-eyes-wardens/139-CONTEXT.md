# Phase 139: Fresh-Eyes Wardens - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Five independent specialist wardens audit all attack surfaces with fresh eyes. Each warden receives ONLY contract source + C4A README + KNOWN-ISSUES.md (no prior audit findings or SAFE verdicts). Each produces PoC exploits or SAFE proofs for every attack surface in their domain. Wardens run in parallel.

</domain>

<decisions>
## Implementation Decisions

### Scope and Cross-Domain Reporting
- **D-01:** Every warden receives ALL 29 production contracts + GNRUS. No domain-restricted subsets.
- **D-02:** Wardens report anything important they find, regardless of whether it falls in their primary domain. If the RNG warden spots a money issue, it reports it.

### PoC and SAFE Proof Requirements
- **D-03:** Every finding requires a real runnable Foundry PoC with concrete calldata — no pseudocode, no hand-waving.
- **D-04:** Every SAFE proof requires a rigorous cross-contract trace showing why the attack surface is not exploitable. Not just "this looks fine" — trace the actual code paths.

### Warden Domains (from ROADMAP)
- **D-05:** WARD-01 (RNG): VRF commitment windows, request-to-fulfillment paths, all RNG consumers cross-contract.
- **D-06:** WARD-02 (Gas): advanceGame execution paths under adversarial state, all delegatecall modules.
- **D-07:** WARD-03 (Money): ETH/token flows, BPS rounding chains, cross-token interactions (sDGNRS/DGNRS/BURNIE/GNRUS/wXRP) across all contracts.
- **D-08:** WARD-04 (Admin): Admin-accessible paths, bootstrap vs post-distribution distinction, Chainlink-death-gated governance paths.
- **D-09:** WARD-05 (Composition): Cross-domain attack sequences, delegatecall module seam interactions.

### Context Isolation (WARD-06)
- **D-10:** Wardens receive ONLY contract source + C4A README + KNOWN-ISSUES.md. Zero prior audit findings, SAFE verdicts, or internal documentation.

### Output Format
- **D-11:** Claude's discretion on report structure. Must clearly separate findings (with PoC) from SAFE proofs (with trace).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Warden Input Documents
- `audit/C4A-CONTEST-README.md` — Contest README wardens receive (priorities, scope, severity tiers)
- `KNOWN-ISSUES.md` — Pre-disclosed known issues wardens receive

### Contract Source
- `contracts/` — All production contracts (wardens receive the full set)

### Requirements
- `.planning/REQUIREMENTS.md` — WARD-01 through WARD-07 definitions

</canonical_refs>

<code_context>
## Existing Code Insights

### Contract Inventory
- 29 production contracts + GNRUS (DegenerusCharity)
- Core game: DegenerusGame.sol + 7 delegatecall modules
- Tokens: DGNRS, sDGNRS, BURNIE, GNRUS, wXRP, DegenerusVaultShare
- Infrastructure: DegenerusAdmin, DegenerusAffiliate, DegenerusQuests, DegenerusJackpots, BurnieCoinflip, DegenerusDeityPass, DegenerusVault

### Test Infrastructure
- Hardhat test suite (1351 passing)
- Foundry available for PoC development

</code_context>

<specifics>
## Specific Ideas

- User wants full-scope wardens that report cross-domain findings, not siloed specialists that ignore issues outside their lane
- Every finding needs the "full deal" — real Foundry PoCs, not summaries

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 139-fresh-eyes-wardens*
*Context gathered: 2026-03-28*
