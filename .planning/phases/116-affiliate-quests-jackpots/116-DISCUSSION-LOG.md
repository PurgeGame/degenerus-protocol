# Phase 116: Affiliate + Quests + Jackpots - Discussion Log

**Phase:** 116-affiliate-quests-jackpots
**Created:** 2026-03-25

## Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Categories B/C/D only, no Category A | Standalone contracts, not delegatecall modules |
| 2 | Full Mad Genius treatment for all Category B | Per ULTIMATE-AUDIT-DESIGN.md methodology |
| 3 | MULTI-PARENT standalone for Category C | Functions called from multiple parents get own sections |
| 4 | Fresh adversarial analysis, no prior trust | v5.0 methodology: everything guilty until proven innocent |
| 5 | Three-contract scope as single unit | Affiliate + Quests + Jackpots tightly coupled via BurnieCoin |
| 6 | Cross-module trace for state coherence | Verify assumptions about game state, mint price, presale flag |
| 7 | Report format per ULTIMATE-AUDIT-DESIGN.md | Consistent with all prior v5.0 units |

## Discussion

No discussion items -- this phase follows the established v5.0 unit audit pattern exactly.
