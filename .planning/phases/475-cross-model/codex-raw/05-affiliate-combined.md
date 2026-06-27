Reviewed frozen `contracts/` matching `3986926c`; no files changed.

Affiliate scaling, tapering, kickbacks, winner credit, and `cachedLevel + 1` attribution conserve exactly across the boundary. Legacy rolls used identical entropy, so pooling does not change winner selection. The only divergence is at most three whole FLIP of daily quest-progress rounding per transaction; it creates no direct credit and fails the mainnet profitability filter.

FINDINGS:
NONE
