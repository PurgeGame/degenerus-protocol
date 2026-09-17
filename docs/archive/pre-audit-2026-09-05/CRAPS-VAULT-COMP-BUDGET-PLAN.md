> Historical document. Superseded by the [current audit handoff](../../AUDIT.md). Claims and test counts below apply only to their original revision.

# Craps vault comp budget — implementation plan

Status: proposed; no production changes made for this plan.
Source reviewed: `e013043d9`, with the current working tree on 2026-09-04.

## Agreed behavior

- Earn 2% of the starting bankroll represented by completed craps battle seats.
- Normal, high, paid, pass-funded and comped seats are equivalent for accrual.
- Exclude bounties, donations, boosts, returns and progressive awards from accrual.
- Credit once when the final seat completes the battle, independent of settlement chunking.
- Vault owner may spend the allowance on every player entry type, charged at the actual
  entry price where priced, otherwise the existing expected-value pass denomination.
- The budget is a FLIP-wei accounting allowance, not a token balance. Grants burn/mint no
  FLIP merely to manufacture a payment. Ordinary settlement still pays the granted seats.
- Unused budget carries forward. No discretionary refill or adjustable rate.

Planning assumptions: include custom and scheduled battles and actual protocol-body seats,
just like other seats. Unplayed pass credits earn nothing. A custom battle accrues comps
but still does NOT contribute to the separate scheduled boost-emission books.

Open product choice: start at zero, or convert the existing 200 normal-pass allowance to
4,560,000 FLIP-equivalent of starting credit. The user has been asked; implement this as a
single deployment initializer choice, not an owner-settable refill. Do not retain both
an independent 200-pass grant path and its converted credit.

## 1. Accrual requires no new per-seat or per-batch accumulator

At `_payout`, the main scoreboard already supplies the complete entrant count, including
its folded-in day seats. `_highField[w.key]` supplies the high-seat count. Slot terms
supply one bankroll and one high multiple for all seats.

Let B = `uint256(w.bankroll)`, N = total seats and K = high seats:

    eligibleBankroll = B * N
    if K != 0:
        eligibleBankroll += B * K * (w.highMult - 1)
    earned = eligibleBankroll / 50

Guard the high term with K != 0: custom battles may have no high lane, with highMult = 0.
Widen all arithmetic before multiplying. Confirm field bounds and K <= N in tests.
Round once per battle, not per seat or partial batch. No outcome-dependent quantity enters
this expression. Upgraded day tickets use the high count for THIS window, not an all-day flag.

Do NOT reuse `_dayStaked` or the staked return from `_resolve`: `_foldHigh` adds the sole
high roller's extra bounty capital to those existing action books. It is deliberately
excluded here. Do not change those existing boost books to implement the comp policy.

`_scoreBattle` stores the completed scoreboard before calling `_payout`; `_resolve` folds
the last high seat before scoring the main board. Preserve that ordering. The existing
completion path is the once-only trigger; no extra credited mapping is necessary if the
existing invariant is retained. A reverted transaction rolls back completion and credit.

Implementation: a typed `creditCrapsCompBudget(amount)` on the Vault, callable only by
canonical CRAPS, updates one uint256 balance and emits the earned amount/new balance.
Emit a companion battle-key/eligible-bankroll event from the table for reconciliation.
Make this part of finalization, outside any nonzero-pot, contested-high or scheduled-only
branch: a custom battle with zero bounty is still eligible. Skip zero-amount calls.
The callback performs only fixed accounting and emits; no owner lookup, external call,
or configurable dependency. Preserve atomic failure propagation.

## 2. Grant surface and pricing

One vault-owner batch entry point takes typed comp requests. A fixed CRAPS-only accounting
callback debits the allowance before the table writes an award; insufficient allowance
reverts. Each request is authorized by the Vault calling the table's vault-only grant door.
Users cannot invoke a free-entry mode through a public paid entry point.

Suggested request kinds: PASS_CREDIT, FUTURE_DAYS, WINDOW, CURRENT_DAY, DAY_UPGRADE.
WINDOW identifies either a custom slot or an opened scheduled slot. Normal/high selection,
recipient, chips, counts and upgrade mask are explicit; reject irrelevant/malformed fields.
Keep the ABI typed and bounded, with no caller-supplied selector or arbitrary target.

| Request | Debit in FLIP wei |
| --- | --- |
| Banked normal pass | count × 22,800 ether |
| Banked high pass | count × 433,200 ether |
| Specific future normal/high days | count × current fixed 25,000 / 450,000 ether price |
| Custom/scheduled window | (bankroll + bounty) × valid selected multiple |
| Today's whole day | sum of the seven window entry prices |
| Selected day-window upgrades | sum of (bankroll + bounty) × (H - 1) for newly high windows |

These are the current code's prices/denominations, not a new EV calibration. Accrual excludes
bounty; priced comp DEBITS include it, because the requested debit is the entry's price.
Banked passes retain their existing redemption and 19:1 conversion rights. That means their
expected-value price is intentionally different from a guaranteed future-date purchase.

Keep prices in one contract-side implementation shared by paid and comp paths. Do not let
the operator supply a price. An optional maxDebit bounds a grant if terms change before
inclusion. A quote method must call the same pricing helpers, not maintain a second schedule.

Refactor `_place`, `_enterDayLane`, `_reserveRun`, and `upgradeDayWindows` into recipient-aware
internal helpers. Existing paid doors pass msg.sender and retain their burn/report logic.
Comp doors pass the recipient and consume budget. Both paths use the same validation,
seat writers, day/window counters and event encoders. Preserve the recipient's standing,
chip restrictions, closed/armed/future-word checks, duplicate exclusions and valid multiples.

New comp seats have no burn-consumed boon or paid-burn quest report. Existing boons on a
seat receiving a comp upgrade are preserved, not consumed again or cleared. Settlement and
legitimate entry-derived state otherwise follow the existing seat path. Grant events
identify the funding mode without pretending a burn occurred; update upgrade reporting
so a quoted comp debit is not labelled as FLIP actually burned.

For pass credits, use exact delivery or prevalidate room: the existing delivery/credit
helpers can saturate. Never charge for silently dropped passes. Retain existing automatic
tomorrow reservation semantics only if requested by that comp kind and account for what
was actually reserved/banked. Invalid recipients and any failed item revert the whole batch.

## 3. Space strategy: move finalization, keep the seat loop local

Measured existing Foundry artifacts, with matching current source files:

| Contract | Runtime bytes | Margin below 24,576 |
| --- | ---: | ---: |
| CrapsBattle | 24,357 | 219 |
| DegenerusVault | 10,900 | 13,676 |

These use the pinned 0.8.34/via-IR/1,000-run/Osaka build and Foundry address constants.
Remeasure with actual deployment pins; do not treat these as final deployment sizes.

Recommended extraction: a fixed `CrapsBattlePayoutModule`, invoked by one typed delegatecall
at completed-battle finalization. Move `_payout` and its tightly coupled payout/progressive/
record helpers as a coherent group. Keep the dice engine, settlement walk, seat scoring,
ordinary credit batching, joins and reservations in the core contract.

The module executes against the table's storage and calls Vault/Coinflip as canonical CRAPS.
The credited budget remains stored in the Vault. Its ample space holds grant batching,
allowance accounting and the owner-facing interface; it cannot itself replace the table's
private seat writers through ordinary external calls.

Extract declarations into an exact-layout `CrapsBattleStorage` base shared by core/module.
Preserve inherited layout, every existing field, packing and struct definition. Move only
the helper dependency closure actually required by each runtime. Simply moving source to
an inherited base does NOT reduce bytecode; the external module boundary creates the saving.
Avoid importing the entire core into the module and redeploying all its public methods.

Pin the module address in ContractAddresses; no setter, proxy admin or upgrade mechanism.
Reject direct module execution outside the canonical table context. Preserve revert data.
Use a fixed typed selector, not an exposed generic delegatecall router. Do not delegate the
constructor or change initial storage defaults. Core stores completion before delegation.

Append the new module to the predicted deployment order, preserving all existing contract
addresses. Extend constants, deploy mappings/scripts, local/Foundry fixtures, verification,
source bundling and module bytecode checks. Events under delegatecall still originate at
CRAPS; update ABI union generation if moving declarations changes artifact exposure.

| Option | Assessment |
| --- | --- |
| Small in-place refactors only | Try shared recipient/pricing helpers, but 219 bytes is not a credible allowance for the whole feature. |
| Fixed finalization module | Preferred: meaningful extraction opportunity with one extra boundary per finished battle. Exact bytes saved must be measured. |
| External dice engine per seat | Could free space, but adds call/encoding cost to the hottest repeated operation; fallback only after measurement. |
| Optimizer-run reduction/removing preview | Possible measured alternatives, but not the baseline plan; require explicit gas/API tradeoff evaluation. |

Prototype the module extraction BEFORE adding comp behavior. Require both runtimes below
24,576 bytes, with a planning target of <=23,500 bytes for the final core (>=1,076 bytes
headroom). If extraction cannot achieve useful headroom after actual compilation, enlarge
the coherent helper group or revisit the split; do not claim an unmeasured byte saving.
Do not solve a deployment limit by lifting the test environment's code-size limit.

## 4. Execution sequence and review gates

1. Capture baseline artifacts, layout, canonical source hashes, replay outputs, and partial/
   final-batch gas using current source and production compiler settings.
2. Extract storage and payout module with NO economic change. Require identical state,
   winners, all payouts, emitted records and revert behavior in differential scenarios.
   Confirm core/module runtime and deployment initcode/gas, including pinned-address builds.
3. Add the Vault allowance and once-per-finalization credit using the count formula.
   Keep the existing boost books and all settlement payouts unchanged.
4. Refactor recipient-aware placement with paid-path parity first. Add comp request kinds,
   exact budget debit, rollback semantics and optional quote/maxDebit. Replace the old
   independent 200-pass counter/API or provide a wrapper that spends this same budget.
5. Update deployment/fixtures, ABI consumers, grant UI and budget/award event indexing.
   Budget reconstruction must reconcile credits/debits and respect ordinary chain rollback.
6. Run focused correctness and gas gates, then the required repository-wide source,
   storage-layout, contract-size and deployment checks. Report the final size/gas deltas.

## 5. Acceptance tests

- Accrual oracle: independently sum B × actual seat multiple and compare to final credit.
  Cover normal-only, mixed/high-only, no high lane, sole high, comp/pass/protocol-body seats,
  custom zero-bounty battles, and upgrades affecting only selected day windows.
- Identical credit across settlement batch partitions, keeper/direct resolution, seat order,
  and retrying completed slots. Zero credit before finalization; exactly one afterward.
- Seven-window day: earn each window's bankroll once, not seven copies of a day total.
  Different bounty amounts/donations/boosts and winning/losing outcomes cannot change credit
  when B, seat counts and high multiple remain the same. Sole-high extra bounty stays out.
- Grant ledger: owner-only issuance, CRAPS-only credit/debit callbacks, insufficient budget,
  zero recipient/count, batch rollback, pass capacity, and once-only charging of upgrade bits.
- For every request kind: compare comp seat ownership, standing, chips, counters, eligibility
  and subsequent settlement to the equivalent paid/pass seat. Account explicitly for burn
  events/quest/boon differences rather than accidentally recreating paid-burn side effects.
- Round-trip economic accounting: granted seats earn the same 2% when resolved; unused passes
  earn zero. The credit ledger never mints spendable FLIP by itself. Verify initial allowance
  is neither duplicated nor reset by any public call.
- Module: direct calls cannot act as the table, fixed routing cannot be overridden, shared
  layouts match the pre-extraction baseline, and callback failures roll back finalization.
- Gas: worst partial batch and last-seat/finalization batch, zero/nonzero initial budget,
  contested/sole high, progressive/record payout cases, keeper routing, and grant batches.
  Revise the deterministic work reserve to cover the extra finalization overhead; do not
  rely on average gas. Existing combined box/craps advance envelope must still hold.

Relevant existing suites: VaultCrapsComps, CrapsPasses, CrapsPassAwards,
LootboxCrapsPasses, CrapsKeeperBudgetGas, CrapsGas and the battle payout/progressive suites.
Add dedicated CompBudgetAccrual, CompGrantParity and module/layout parity coverage.

## Completion definition

All supported comps spend the correct allowance and belong to their named recipients;
all completed battles earn exactly 2% of eligible bankroll once; legacy payouts and paid
entry behavior retain parity; canonical builds deploy with measured headroom and remain
inside the existing advance/keeper gas envelope. Production implementation and deployment
are subsequent work; this document authorizes no publication by itself.
