# ETH exit assurance

## Conclusion and scope

The retained symbolic run reports passes for eight local accounting properties of its recorded
production storage helpers. A finite model also rules out funding a new whale-pass purchase with an
immediate loan against that purchase's ticket award. These results do **not** constitute a proof that
every protocol execution or economic strategy is unexploitable.

The model treats the Vault as having one authorized owner. Owner-directed spending is an authorized
exit. This assumption does not make the VRF coordinator, stETH, compiler, deployment configuration,
or other accounts trusted by implication. The adversarial target is an outsider obtaining value
beyond the entitlements and authority specified by the contracts.

The [run input hashes](eth-exit-proof-2026-10-28/source-sha256.json) identify the retained
campaign's contracts. They are evidence provenance, not an alternative audit freeze. The audit
target and repository hash manifest are defined in [AUDIT.md](../AUDIT.md). Integration tests use
deterministic address pins and mock external contracts; they do not attest to deployed mainnet
bytecode.

The retained source hashes differ from 38 current contract files, including `DegenerusQuests.sol`,
`DegenerusVault.sol`, `GNRUS.sol` and `sDGNRS.sol`. The helper hashes identify three copied harnesses;
two differ from the current harnesses. Integration and boundary run metadata records deterministic
fixture address processing; their contract input hashes match the retained campaign manifest, not
the current contracts. Results below apply to those recorded inputs. The four named standalone
contracts are not the subject of the eight helper properties below, and the evidence does not
certify the complete package or replace review of their behavior.

## What was proved

The [symbolic harness](../../test/halmos/EthLedgerProductionProof.t.sol) inherits
`DegenerusGameStorage` and invokes its real helpers. It does not copy their implementations into an
arithmetic model. Halmos executes the compiled harness bytecode, including the inlined production
helper bodies.

| Property | Verified statement |
|---|---|
| Claimable credit | Crediting account A increases its claimable balance by exactly the amount; its AFKing balance and a distinct account B are unchanged. The aggregate liability is unchanged by this primitive, so its caller still has to fund or reclassify the credit. |
| AFKing credit | Crediting prepaid funding increases the account's AFKing balance and `claimablePool` by the same amount, leaving claimable and the other account unchanged. |
| Combined debit | With both balances sufficient, the claimable and AFKing halves each fall by their respective debit. Neither borrows bits from the other half. |
| Overdraw rejection | If either debit exceeds its balance, the production debit reverts and the packed balance remains unchanged. Debit amounts here span all `uint256` values. |
| Purchase shortfall | For a covered cost, the claimable and AFKing draws sum to that cost, the account and aggregate liability each decrease by that cost, and the claimable 1-wei sentinel remains. Disallowing claimable spending forces that draw to zero. |
| Redemption reserve release | Releasing a protected reserve moves its value into sDGNRS claimable without changing aggregate liability; the reserve becomes zero and a second release adds nothing. |
| Prize contribution | Each contribution reaches exactly the intended next/future pool halves: pending while frozen, live otherwise. The other buffer is unchanged. This also implies conservation of their sum. |
| Surplus calculation | `_untrackedYield` returns exactly `max(ETH + stETH − obligations, 0)`, counting current, next, future, claimable, accumulated yield, and both pending pool amounts. |

**Domain:** target-account monetary inputs and pool components are `uint96` (up to approximately
79.2 billion ETH), except the unrestricted overdraw amounts. The comparison account's packed balance
can be any `uint256`. Tested additions stay below packed-ledger saturation/truncation limits.
Account identifiers are symbolic `uint32` values, subject to a nonzero target and distinct comparison
account. These are transition properties from harness-seeded states, not an inductive proof that
every reachable production state satisfies the premises. They do not
independently establish registration, ownership, reward eligibility, or the funding correctness of
every caller.

All eight checks passed with no bounded-loop cutoff and no unresolved query in the final run. The
loop bound was 2; these particular helpers have no loop whose truncation limits the result. The
toolchain was Solidity 0.8.38, via-IR, optimizer runs 1000, Osaka, Foundry
`c07d504b4ae67754584f4e05ff0c547a43c50f7b`, Halmos 0.3.3, and Yices. This retains the usual
compiler, EVM-model and solver assumptions. It verifies helper behavior in the harness, not bytecode
equivalence of a separately compiled deployment.

## Loan economics: a narrow extraction loop is bounded

The [finite checker](../../scripts/check-eth-loan-bootstrap.py) enumerates 218,000 combinations:
pass start levels 1–109, both possible active-ticket levels, and paid quantities 1–1,000. Levels 1–9
cover introductory pricing; 10–109 cover every position in the repeating price cycle. It grants the
maximum 35% first-pass discount for free, includes the one-per-five bulk award, and uses the
earliest due level. A later due level removes nonnegative collateral and cannot increase the
immediate quote. The checker pins its reviewed sources.

For **only the new pass's ticket award**, the exact maximum is:

```text
immediate principal / purchase cost <= 8207 / 62400
                                    = 13.1522435897…%
```

The maximizing model case buys one introductory pass for 1.56 ETH and quotes 0.205175 ETH of
principal. This witness and 1,000 fuzz cases were checked against the actual `_queueEntryRange`,
`_queueHalfPassAward` and `_quoteLoan` helpers in
[EthLoanBootstrap.t.sol](../../test/unit/EthLoanBootstrap.t.sol). The test seeds the award; it does
not exercise the complete purchase's eligibility and funding path. Omitting those restrictions makes
the numerical upper bound more generous to the borrower.

This rules out making the isolated buy→borrow step self-financing. It does not bound the pass's
bundled token/box/affiliate rewards, later outcomes, prizes won elsewhere, pre-existing collateral,
subsidized acquisitions, or portfolios of interacting strategies. It also does not prove the lender
recovers principal from a seized account: ticket face price is not guaranteed liquidation value.

## Composition evidence and its limits

The integration campaign includes the following production-path suites:

- ETH solvency and custody reconciliation;
- loan accounting against an independent ledger;
- redemption reserve, claim, supply and wrapper invariants;
- pool backing and conservation bounds;
- daily and mid-day RNG-window freezing;
- ordinary lootbox and redemption commitment binding;
- jackpot and daily-jackpot commitment freezing;
- terminal loan conservation, Degenesis solvency, Degenerette solvency;
- mature-game loan/redemption/terminal composition.

Campaign result: **59 passed, 0 failed, 0 skipped across 16 suites**, including seven helper/fixture
checks. There are 20 invariant properties, each exercised for 256 runs × 128 calls. The ordinary
fuzz default is 1,000 cases; the mature composition test uses 64 and the two V73 token-spin tests
use 400 each. These are bounded tests, not universal proofs. Several suites require real progress
and include deliberately broken-state checks to show their assertions can fail.

A second campaign passed **74 tests across 11 suites**, covering actual ETH Degenerette
caps/overflow and frozen resolution, dead-VRF endings, hard-stall loan settlement, stETH-loss
liveness, and coordinator rotation after fulfillment. The stETH-loss and terminal-loan settlement
fuzz tests each use 24 cases. The stETH-loss test's success permits claims to fail with the documented
shortfall error; it establishes progress, not
protection against asset loss. With repeated helper suites counted once and the four new concrete
harness checks included, **130 distinct concrete tests passed** (137 executions). No test failed or
was skipped in either completed campaign or the final helper run.

The independent split-arithmetic checker passed 24 checks, including sensitivity controls. Those are
source-pinned mathematical models, not symbolic execution of every production payout caller.
Structural gates also passed: 103 pool accesses, 141 VRF-window accesses, 406 RNG-taint sites, 200
reviewed hash sites, including 142 RNG sites across 113 tags (plus one raw-bit exception), and 1,575
recipient/call expressions. These gates detect missing classifications and source drift. A manifest
entry does not prove its classification correct.

For a full solvency proof, let `A` be held ETH plus supported stETH value and `L` the complete
liability ledger, including reserved and pending value. Starting from `A >= L`, a deposit adding the
same amount to both, a correctly funded reclassification preserving `L`, and a payout subtracting
the same amount from both all preserve the inequality. Spending only measured surplus also preserves
it. The eight helper checks establish parts of these transitions. The missing step is proving that
**every reachable caller** meets those premises, including the amount, recipient, single-consumption
rule and implicit terminal reserves. Separately, fair entitlement and economic profitability need
stronger properties than solvency.

The upstream credit families that must satisfy those premises are:

| Credit producer | Funding / single-consumption obligation | Evidence in this review |
|---|---|---|
| Daily and level jackpots, BAF, golden awards | Debits or reservations must cover cash and sub-pass remainders; settlement cursors must prevent replay; frozen winners must receive the awards. | Split models, pool/solvency invariants, jackpot commitment tests; no complete caller proof. |
| Decimator awards | The reserved round pool and added jackpot funding must cover the final payout schedule; the payment cursor advances once per winner. | Source tracing and shared pool checks; no end-to-end symbolic proof of the ranking and payment engine. |
| ETH Degenerette spins, including box/foil-triggered spins | Cash is limited by available future-pool funding; credited cash must be deducted from that running pool; overflow rewards must not duplicate cash. | Source tracing and targeted production tests; no universal proof of every reward combination. |
| Redemption direct credits / box delivery | Only sDGNRS may invoke delivery; the protected Game reserve falls by the delivered value; batch claims are consumed once. | Reserve helper proof, redemption invariants, commitment and mature-composition tests. |
| Degenesis reservation and split | The paid amount enters aggregate liability once; the cohort splits once; retained protocol balances are reclassifications of the reservation. | Degenesis solvency vectors and real split fixture. |
| Loan repayment / automatic repayment / acquired-account sweeps | Lender credits must equal fresh ETH plus the debited source balances; sweeps only move existing value between account ledgers. | Independent loan ledger, terminal-loan conservation and mature composition. |
| Purchase overpayment / AFKing funding | New funding credits must match received ETH or an explicitly debited existing balance. | AFKing helper and shortfall proofs; purchase/custody tests. |
| Early-deity refunds / terminal and dead-VRF entitlements | Refunds and payout weights must fit the available terminal pot; entitlement records must be consumed before reuse. | Source tracing and terminal tests; aggregate post-game solvency alone is insufficient. |
| Protocol yield allocation | Only surplus beyond every counted obligation may be allocated, and credited shares plus retained yield must fit that surplus. | Production surplus-helper proof and earlier yield-solvency tests. |

Specific gaps prevent promoting these results to a global proof:

1. **An aggregate backing bound is weaker than correct entitlement.** A caller can incorrectly
   credit an account while a large initial reserve keeps `assets >= obligations` true.
   `PoolConservation` starts with substantial spare backing and checks inequalities, so its name
   must not be read as an exact proof that every credit has a matching source debit. Custody
   reconciliation detects missing assets, but by itself also cannot distinguish a rightful payment
   from a payment to the wrong entitled account.
2. **Terminal liabilities have a different representation.** The shared `SolvencyObligations` test
   helper counts only `claimablePool` after game over. Outstanding dead-VRF entitlement is converted
   into claimable when tickets are consumed. Proving all terminal entitlements therefore also
   requires the terminal-pot and consumed-weight bounds; the aggregate helper alone is insufficient.
3. **Frozen-input coverage is enumerated.** Passing the selected commitment tests and slot manifests
   supports the listed consumers and state transitions. It is not a machine-checked proof that all
   registered word-carrying sites are immune to outcome-dependent action ordering, identity changes,
   and reward interactions.
4. **Lifecycle composition is sampled.** No induction over every entry point, account family, phase,
   terminal transition and callback was completed.

## Claims that are false without extra assumptions

### Every loan is eventually repaid or seized

This claim does not hold in a hard-stall ending: the borrower keeps the principal and the account,
and the loan is not later settled. A purchase-timeout ending settles loans, but a hard stall during
that work can leave the remaining suffix unsettled. See [ACCOUNT-LOANS.md](../ACCOUNT-LOANS.md) and
`DegenerusGameGameOverModule._handleGameOverAdvance`. The terminal tests executed include
`test_DeadVrfAtTheDecisionLeavesLoansUntouched` and
`test_HardDeadlineInterruptsTerminalLoanBookWithoutReversingPaidPrefix`.

This observation does not establish an outsider can cheaply cause the required stall. It does
disprove unconditional repayment/seizure. A stronger economic claim requires either a liveness
assumption or a bound on the attacker's ability and cost to cause the stall. No such universal cost
bound was proved here.

### RNG cannot be replaced even by its coordinator

This is false for an arbitrary authorized coordinator. In `GameFacade.rawFulfillRandomWords`,
another valid callback with the retained request's low 64-bit ID and a word greater than 1 writes
`rngWordCurrent` again. There is no local write-once check. The accepted design relies on the
supported coordinator's one-fulfillment behavior, as recorded in
[SECURITY.md](../../SECURITY.md#vrf-callback-trust-and-request-ids). The low 64-bit request
comparison also assumes no relevant collision. A random outsider cannot impersonate the coordinator
merely by knowing an ID.

### ETH-equivalent backing can never fall below obligations

This is false without an external-asset assumption. If assets and obligations are both 100
ETH-equivalent and stETH backing loses 1 ETH-equivalent, the result is 99 backing against 100 owed.
Internal debit/credit conservation cannot repair that loss. Mock 1:1 staking tests do not prove real
Lido behavior or ETH market parity. The owner staking path also relies on the supported staking
endpoint honoring the exchange. A single Vault owner does not remove this dependency.

## Reproduction and evidence

From the repository root, with the scratch environment from [Testing](../TESTING.md#setup-and-sliced-build):

```sh
python3 scripts/prove-eth-ledgers.py --output "$AUDIT_SCRATCH/eth-ledger-proof"
python3 scripts/check-eth-loan-bootstrap.py --json-output "$AUDIT_SCRATCH/loan-bootstrap-results.json"
python3 scripts/check-split-arithmetic.py --json-output "$AUDIT_SCRATCH/split-results.json"
ETH_EVIDENCE=docs/audit/eth-exit-proof-2026-10-28
for campaign in integration boundaries; do
  set --
  while IFS= read -r source; do
    set -- "$@" --file "$source"
  done < "$ETH_EVIDENCE/$campaign-focused-01-files.txt"
  python3 scripts/test-foundry-groups.py "$@" --threads 1 \
    --log-dir "$AUDIT_SCRATCH/logs/eth-exit-$campaign"
done
make check-pool-writes check-rng-window check-rng-taint check-rng-shape check-recipient-calls
```

The first command creates and retains an isolated project, copies the production contracts and the
three harnesses, and runs symbolic and concrete checks. It does not patch the active checkout. The
loan model refuses changed source hashes until its correspondence to those sources is reviewed
again. Choose a new helper-proof output directory for each run. The grouped runs use 1,000 fuzz
cases and 256 invariant runs at depth 128, subject to the per-test overrides stated above. Clear
caller run-limit/profile overrides to reproduce those settings. The campaigns use mocks and do not
require an external RPC endpoint. Real-Lido fork regressions are a separate check described in
[Testing](../TESTING.md#mainnet-forks-and-deep-invariants).

Results are retained in [eth-exit-proof-2026-10-28](eth-exit-proof-2026-10-28/): source hashes,
symbolic results, concrete output, finite loan results, split-arithmetic results and structural-gate
output. The records describe bounded runs of the named inputs.
