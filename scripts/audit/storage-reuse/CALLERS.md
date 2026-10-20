# Credit callers and admission accounting

`credit-callers.tsv` inventories 35 direct production `creditFlip`, `creditFlipPair`
and `creditFlipBatch` call sites. `JackpotBattle._creditFlip` is a shared adapter;
its callers include ordinary and daily battle settlement. Coinflip's own deposit,
gift, quest and claim/rebuy routes are covered separately by the account/carry tests.

| Context | Reservation / evidence |
| --- | --- |
| Craps, jackpot battle, Growth flush | Shared `CRAPS_CREDIT_GAS_MAX = 160,000` per recipient, plus each worker's separate frame/checkpoint reserve. Native worst measured cold marginal is 129,571; full 32-recipient spill batch is 4,174,955. |
| Degenesis credit accumulation and flush | `DEGENESIS_FLIP_CREDIT_GAS` prices queue accumulation, not Coinflip. The actual flush additionally reserves `DEGENESIS_FLUSH_PER_CREDIT = 160,000` per recipient and `DEGENESIS_TAIL_GAS`. |
| Miner reward | `ENGINE_RETURN = 200,000` includes the caller credit; full standalone new-overflow credit is 148,025. Caller registration/dispatch belongs to the engine preamble. |
| Daily word, century and protocol boon work | `DAILY_APPLY = 7,200,000`; full native century and six-boon witnesses are 3,788,553 and 3,457,590. Caller tails remain separate. |
| Level-one trait draw | `LEVEL_ONE_DRAW = 7,500,000`; native full 50-share draw and seal is 6,376,789. |
| Vault checkpoint and x0 seal | `BAF_VAULT_SETTLE = 3,500,000`, plus `DAILY_PHASE_TAIL`; native full 90-day helper is 447,516 and actual miner checkpoint with 76 days is 470,850. The larger prior envelope is retained. |
| WWXRP incinerator | One Coinflip winner credit inside `POOL_CONSOLIDATION = 1,650,000`. Prior conservative 1,368,000 envelope plus 20,000 extra credit allowance is 1,388,000. |
| Golden award / foil pack | The credit is part of the complete `FOIL_PACK = 3,000,000` operation, not an independently admitted unbounded batch. The prior 2,263,000 envelope retains room for the changed credit path. |
| sDGNRS redemption | At most one direct FLIP credit in `REDEMPTION_BASE_GAS = 600,000`; any lootbox leg has its own per-box allowance. Prior 496,300 base plus 20,000 credit allowance is 516,300. |
| Subscriber whale purchase | Prior 2,378,000 purchase plus 20,200 AFKing top-up and up to three 20,000 credit increments totals 2,458,200 below `SUBSCRIBER_WHALE_GAS = 2,800,000`. |
| Purchases, affiliate commissions/claims, AFKing, lootbox and quest routing | Several calls can compose; count each distinct recipient within the complete order/claim bound. Existing whole-order tests remain necessary. Referral history reuse reduces rollover allocation but is not used to reduce those bounds. |
| Player WWXRP/Bingo/DGNRS claims, donations and direct purchases | These entry points do not admit a fixed number of credits from `MineFlipGasBounds`; gas estimation covers the user's complete call. Their automatic nested paths still belong to their enclosing worker's reserve. |

The 20,000 increments above are conservative component checks, **not additional
native full-call measurements**. The measured standalone change from old fresh
credit to R90 new overflow is 18,177; the 32-recipient batch difference is 16,239.5
per recipient. Seven-lane scanning is bounded; no per-player history scan is added.
Native witnesses and these component sums must remain labeled separately.

Daily application resolves Coinflip before calling `openBonusDay`. Daily-phase
work therefore usually sees a current frontier. Even in the exceptional spill
case, reservations use the more expensive retained-page collision path. Fixed
slots do not create a capacity revert. The larger per-credit reserve can reduce
work per call: the 250-winner Growth fixture now needs eleven 4.4M chunks instead
of ten, while retaining exact payouts and resumable progress.

These are scoped checks for this implementation/compiler/fork. They are not a
proof of an absolute gas maximum over arbitrary future callers or protocol changes.
