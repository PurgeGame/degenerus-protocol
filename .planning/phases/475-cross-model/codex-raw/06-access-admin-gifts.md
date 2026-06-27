The frozen contract tree matches commit `3986926c`. One issue survived the skeptic filter; the settlement and gift paths preserved payer/owner boundaries.

FINDINGS:

1. MEDIUM | contracts/DegenerusAdmin.sol:762 | Recovery does not permanently invalidate active proposals | `vote()` checks only whether the latest VRF processing was within 44 hours; it never invalidates a proposal whose creation predates an intervening recovery, so recorded votes survive while quorum continues decaying. Trigger: partially vote during a genuine stall, process a healthy VRF word without poking the proposal, then encounter another ≥44-hour stall before expiry; a zero-weight poke can execute the stale proposal at the day-six 5% threshold and install its arbitrary coordinator.
