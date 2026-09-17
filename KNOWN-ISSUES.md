# Known issues and accepted assumptions

The following are disclosed design/acceptance boundaries for this handoff. A mechanism
or impact outside a stated bound remains a separate review question.

| Case | Disclosed behavior / boundary |
| --- | --- |
| Scheduled operation | Daily opening and on-schedule battle resolution are assumed. They are operational expectations, not ordering enforced on every permissionless entry point. |
| Daily VRF retry | Only while the requested word has not been received: the vault owner gets first opportunity after 11 hours; anyone can retry after 12 hours. The single retry replaces the request ID, discarding a late fulfillment of the original request. A governance coordinator swap re-arms the retry. |
| Unopened craps comp window | If a future craps comp window's day never opens, the whole-day lapse sweep skips that window-only reservation without replacement or comp-budget restitution. Accepted under the scheduling assumption. |
| Cross-day progressive qualification | One day marker per winner can be overwritten by another day's routine win before the earlier event resolves; this can remove its doubling. Accepted under scheduled resolution. Shared progressive-pool depletion is also resolution-order-dependent. |
| Extended unattended advance | Gap backfill is bounded. Beyond the supported history window, skipped-day coinflip positions may remain unresolved. |
| Terminal RNG fallback | Catastrophic prolonged VRF failure can use historical words with prevrandao for terminal release. The accepted terminal fallback is not a live-game entropy guarantee. |
| Degenerette resolution | Assumes roughly chronological resolution; capped bonus allocation can depend on resolution order. |
| Small Thanos balance | A lone balance can truncate to zero on division at high shifts. The accepted bound is under 0.64 whole tickets (about 0.153 ETH at the highest ticket price), confined to the small position. |
| Affiliate rounding/selection | Deterministic affiliate selection and bounded floor-of-sum rounding differences; not a general allowance for redirecting funds or arbitrary rounding loss. |
| Governance | Outcomes requiring valid sDGNRS governance approval are governance decisions, not findings. Bypasses of authorization, voting or execution rules remain in scope. Genesis-only self-disruption is excluded. |

## Token and integration semantics

- sDGNRS and GNRUS are soulbound, not conventional transferable ERC-20s.
- DGNRS restricts transfers to its own wrapper address.
- FLIP protocol-authorized spending, coinflip auto-claim and special VAULT/sDGNRS routing
  are intentional; wallet supply, virtual allowance and backing are not interchangeable.
