# Automated analysis — bot-race baseline

**Subject:** `contracts/` tree `49b36da3` @ tag `degenerus-c4a`. Run 2026-07-10.

These are the pre-run static-analysis findings. Per [`KNOWN-ISSUES.md`](../../KNOWN-ISSUES.md) §7,
any finding whose category + mechanism is captured here is a publicly-known issue and is **not
eligible** for awards. Full per-finding detail is in the two reports beside this file; the
category-level dispositions (why each is by-design / defended / not-applicable) are in KNOWN-ISSUES §7.

## Tools & reproduction

| Tool | Version | Command | Report |
|------|---------|---------|--------|
| Slither | 0.11.5 | `slither . --filter-paths "test/\|contracts/mocks/\|contracts/test/\|lib/\|node_modules/\|script/\|scripts/" --checklist` | `slither-checklist.md` |
| Aderyn | 0.6.8 | `aderyn .` | `aderyn-report.md` |

(4naly3er was not run; Aderyn serves as the second independent static analyzer.)

## Slither — 2,551 results, 101 detectors, 125 contracts

By impact: **Informational 1,661 · Medium 376 · Low 333 · High 136 · Optimization 45**.

| Detector | Count | Detector | Count |
|----------|------:|----------|------:|
| unused-state | 1343 | reentrancy-benign | 49 |
| uninitialized-local | 156 | constable-states | 43 |
| reentrancy-events | 138 | timestamp | 39 |
| uninitialized-state | 109 | unused-return | 38 |
| calls-loop | 91 | missing-inheritance | 36 |
| reentrancy-no-eth | 81 | incorrect-equality | 35 |
| low-level-calls | 81 | cyclomatic-complexity | 32 |
| costly-loop | 67 | too-many-digits | 28 |
| divide-before-multiply | 63 | assembly | 14 |
| naming-convention | 60 | weak-prng | 9 |
| shadowing-local | 9 | reentrancy-balance | 6 |
| missing-zero-check | 6 | delegatecall-loop | 5 |
| arbitrary-send-eth | 2 | reentrancy-eth | 2 |
| shadowing-state | 2 | locked-ether | 2 |
| immutable-states | 2 | incorrect-exp | 1 |
| boolean-cst | 1 | events-maths | 1 |

### On the 136 "High"-impact results

Dominated by **`uninitialized-state` (109)** — a false-positive class for this architecture: the 12
game modules share `DegenerusGameStorage` via `delegatecall`, so Slither reads the router's storage
as "uninitialized" in each module's isolated compilation context. The genuinely-notable High
detectors — all pre-triaged in KNOWN-ISSUES §7:

- **weak-prng (9)** — entropy derivations that consume VRF words. By-design: VRF V2.5 is the sole
  randomness source and every RNG input is committed *before* the VRF request (see the RNG-freeze
  invariants). Not player/proposer-manipulable on a live coordinator.
- **arbitrary-send-eth (2)** — `_payoutWith*Fallback` / `_payEth` send to access-controlled
  recipients (`msg.sender` or player addresses read from game state).
- **reentrancy-eth (2) / reentrancy-balance (6)** — CEI is followed; recipients are player addresses
  (self-grief only) or known protocol contracts with minimal `receive()` (`steth.transfer`,
  `dgnrs.transferFromPool`).
- **shadowing-state (2)** — the per-module `JACKPOT_LEVEL_CAP` constants intentionally mirror the same
  literal declared on the shared `DegenerusGameMintStreakUtils` base; identical value, no divergence.
- **incorrect-exp (1) / delegatecall-loop (5)** — the `^`-vs-`**` scan and the module-dispatch loop
  pattern; reviewed, no exponentiation bug and delegatecall targets are compile-time constants.

## Aderyn — 9 High, 22 Low

| # | Title | Disposition |
|---|-------|-------------|
| H-1 | `abi.encodePacked()` hash collision | KNOWN-ISSUES §7 `[L-4]`: entropy inputs are fixed-width; SVG strings not used as keys. |
| H-2 | Contract locks Ether without a withdraw function | Prize/claim pools are withdrawn via the game's claim surface; the vault/GNRUS paths have explicit exits. |
| H-3 | ETH transferred without address checks | Recipients are `msg.sender` / player addresses from game state (access-controlled). |
| H-4 | Incorrect use of caret operator (`^`) | Reviewed — no bit-XOR used where exponentiation was intended. |
| H-5 | Reentrancy: state change after external call | CEI followed; overlaps Slither reentrancy-* (by-design, LOW threat tier). |
| H-6 | Contract name reused in different files | Interfaces/mocks share names across files; no deployment ambiguity (addresses are nonce-pinned). |
| H-7 | Storage array edited with memory | Reviewed against the packed-storage ticket/queue writes. |
| H-8 | Unsafe casting of integers | KNOWN-ISSUES §7 unchecked-downcasting: each cast is range-guarded or width-proven (ticket counts now saturate). |
| H-9 | Weak randomness | Same as Slither weak-prng — VRF committed-before-request (by-design). |

Low issues (22) are the conventional NC/QA set (naming, magic numbers, zero-checks, etc.) — see the
report and KNOWN-ISSUES §7.
