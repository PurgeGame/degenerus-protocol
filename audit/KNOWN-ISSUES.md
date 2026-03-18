# Known Issues

Pre-disclosure for audit wardens. If you find something listed here, it's already known.

---

## Intentional Design (Not Bugs)

**stETH rounding strengthens invariant.** 1-2 wei per transfer retained by contract, pushing `balance >= claimablePool` further into safety. Not a leak.

**Non-VRF entropy for affiliate winner roll.** Deterministic seed (gas optimization). Worst case: player times purchases to direct affiliate credit to a different affiliate. No protocol value extraction.

---

## Design Mechanics

These are architectural decisions, not vulnerabilities.

**VRF swap governance (WAR-01/WAR-02).** Emergency VRF coordinator rotation requires a 20h+ stall and sDGNRS community approval with time-decaying threshold. Worst case: admin key compromised + attackers hold >5% of circulating sDGNRS + attacker approve weight exceeds defender reject weight. This is the intended trust model.

**Chainlink VRF V2.5 dependency.** Sole randomness source. Game stalls but no funds are lost if VRF goes down. Governance-based coordinator rotation and 120-day inactivity timeout provide independent recovery paths.

**Lido stETH dependency.** Prize pool growth depends on staking yield. If yield goes to zero, positive-sum margin disappears. Protocol remains solvent — the solvency invariant does not depend on yield.

**_sendToVault uses hard reverts (GO-05-F01).** `_sendToVault` reverts on any ETH or stETH transfer failure. Vault and sDGNRS are immutable protocol-owned contracts with unconditional `receive()` functions. Lido stETH has never paused transfers. Recipients can't reject funds.
