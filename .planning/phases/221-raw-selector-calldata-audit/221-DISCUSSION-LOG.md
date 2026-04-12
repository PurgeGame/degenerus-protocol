# Phase 221: Raw Selector & Calldata Audit — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-12
**Phase:** 221-raw-selector-calldata-audit
**Areas discussed:** Gate script & Makefile wiring, Classification scope for abi.encode*, Mocks treatment, Catalog shape & severity calibration

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Gate script & Makefile wiring | Should Phase 221 produce a regression script (scripts/check-raw-selectors.sh) wired into make test like Phase 220's check-delegatecall-alignment.sh? | ✓ (Claude's Discretion) |
| Classification scope for abi.encode* | Which of the 46 abi.encode*/abi.encodePacked sites get a verdict? All 46 (including keccak256 hash inputs), or only sites that feed .call/.delegatecall/.staticcall/transferAndCall? | ✓ (Claude's Discretion) |
| Mocks treatment | The 3 abi.encodeWithSignature sites are in contracts/mocks/ (MockVRFCoordinator, MockLinkToken) simulating Chainlink callbacks. Classify as JUSTIFIED in-catalog, exclude from gate scope via path filter, or ignore entirely? | ✓ (Claude's Discretion) |
| Catalog shape & severity calibration | Single 221-01-AUDIT.md (Phase 220 style) or split by CSI-04/05/06? Severity for hypothetical FLAGGED sites? | ✓ (Claude's Discretion) |

**User's choice:** "I don't know any of this, I just want to be sure we don't have any bugs plz"
**Notes:** User explicitly deferred all technical decisions to Claude's discretion. Goal restated as "prove absence of raw-selector/calldata-bypass bugs + install regression gate." Recommended defaults were accepted for all four areas.

---

## Area 1: Gate script & Makefile wiring

| Option | Description | Selected |
|--------|-------------|----------|
| Produce regression script | Sister to Phase 220's check-delegatecall-alignment.sh, wired into make test-foundry/test-hardhat via Makefile prerequisite | ✓ (recommended) |
| Audit-only (no script) | Produce catalog doc only; rely on future reviewers to catch raw selectors | |

**Claude's pick:** Produce regression script. Matches CSI-03 precedent (Phase 220) and enforces "no bugs" goal at `make test` time, not just once during audit.
**Notes:** Gate runs path-excluded on `contracts/mocks/`; script exits 0 clean / 1 on finding. Mirrors Phase 220 architecture — proven sub-1s runtime.

---

## Area 2: Classification scope for abi.encode*

| Option | Description | Selected |
|--------|-------------|----------|
| All 46 sites | Classify every abi.encode/abi.encodePacked including keccak256 hash inputs and NFT metadata strings | |
| Call-feeders only | Only classify abi.encode* whose output is passed to .call/.delegatecall/.staticcall/transferAndCall | ✓ (recommended) |
| Structural regex rule | Use a regex that matches selector-bearing patterns only | |

**Claude's pick:** Call-feeders only.
**Notes:** Hash inputs (keccak256 salts for RNG entropy, storage keys, bonus traits) and string concatenation (NFT tokenURI construction) are not selectors — classifying them would produce 40+ noise entries. Scope is bounded by "what could cause a runtime calldata mismatch."

---

## Area 3: Mocks treatment

| Option | Description | Selected |
|--------|-------------|----------|
| JUSTIFIED in catalog + gate-excluded via path filter | List 3 mock sites as JUSTIFIED with Chainlink-interop rationale; gate skips contracts/mocks/ | ✓ (recommended) |
| JUSTIFIED in catalog + gate flags them | Require explicit allowlist per site | |
| Ignore entirely | Don't list, don't gate | |

**Claude's pick:** Catalog with JUSTIFIED + path-level gate exclusion.
**Notes:** The 3 sites simulate Chainlink VRF v2 coordinator wire format (`rawFulfillRandomWords(uint256,uint256[])`). Target interface lives externally. Path-level exclusion is visible in the script (not hidden in inline comments), satisfying the visible-diff property Phase 220 established.

---

## Area 4: Catalog shape & severity calibration

| Option | Description | Selected |
|--------|-------------|----------|
| Single 221-01-AUDIT.md, FLAGGED=HIGH | Phase 220 style catalog; HIGH severity for any FLAGGED site (mintPackedFor class) | ✓ (recommended) |
| Split by requirement (4 files) | Separate AUDIT per CSI-04/05/06/07 | |
| FLAGGED=MEDIUM | Treat raw selectors as brittleness only | |

**Claude's pick:** Single catalog + HIGH severity for FLAGGED.
**Notes:** Empty sections show "0 sites (SATISFIED)" with grep command used to prove absence. HIGH severity matches the v27.0 core-value framing: runtime mismatch = same bug class that motivated the milestone.

---

## Claude's Discretion

All four areas were resolved via Claude's Discretion after user deferred ("I don't know any of this, I just want to be sure we don't have any bugs"). Decisions captured in CONTEXT.md D-01 through D-14.

## Deferred Ideas

None surfaced in discussion. Phase scope stayed within CSI-04/05/06/07.
