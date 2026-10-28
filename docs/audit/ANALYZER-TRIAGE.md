# Analyzer triage

Reviewed dispositions for Slither and Aderyn output on the audit tree. Every Slither High and
Medium detector and every Aderyn High category is covered below; Low, Informational and
Optimization output is summarized by detector. The project's disposition is that no instance
is open; that disposition, its assumptions and the evidence it relies on are stated in
[Project disposition](#project-disposition). It is the project's classification, not an
independent verification, and it does not substitute for call-path review.

| | |
| --- | --- |
| Tree | `main` at `76e8748ca`; `contracts/` unmodified. File:line references are to that tree; the current scoped sources ([snapshot](snapshot.json)) include later contract changes, so lines may shift |
| Compiler | solc 0.8.38, `viaIR`, EVM `osaka` (`hardhat.config.js`) |
| Slither | 0.11.5, hardhat framework, all detectors and tiers: 293 contracts, 101 detectors, 5,678 results; no "Impossible to generate IR", "Function not found" or parse errors |
| Aderyn | 0.6.8, 88 detectors: 176 files, 32,257 nSLOC, 12 High and 25 Low categories, 2,857 instances |
| Slither raw totals | High 251 · Medium 774 · Low 531 · Informational 4,041 · Optimization 81 |
| Slither in scope | High 249 · Medium 756 · Low 527 · Informational 4,001 · Optimization 81 (5,614) |
| Excluded | 34 results in `contracts/mocks/` or `contracts/test/`, 30 in `node_modules/` (OpenZeppelin) |

A result is attributed to the file of its first source element. Counts are per reporting
contract: shared storage and the module bases are inherited by many deployments and by both
profile trees (`profiles/eip170`, `profiles/glamsterdam`), so one source location can be reported
many times. The "distinct" column counts source locations.

## Reproduce

From a clean checkout with no untracked Solidity files:

```sh
rm -rf artifacts cache
npx hardhat compile
slither . --compile-force-framework hardhat --json slither.json   # exit status 255 = results present
aderyn . -o aderyn.md
```

The JSON output is about 0.9 GB; the Slither run needs up to about 24 GB of memory.

`make check-slither` is a parsing-integrity gate, not a detector run. It checks fresh foundry
build-info covering every file in [`scope.txt`](../../scope.txt) and fails on incomplete parsing or
SlithIR. Build its input with
`forge build --skip test --build-info --force --out forge-out-slither --cache-path .foundry-cache-slither`.
CI runs the detectors as an informational report
(`slither . --compile-force-framework foundry --ignore-compile --foundry-out-directory forge-out-slither --fail-none --exclude-informational --exclude-optimization`).

## Trust model used for reentrancy and send classes

The Game executes its modules by `delegatecall` in one shared storage
(`DegenerusGameStorage`, see [Architecture](../ARCHITECTURE.md)); under `eip170`, `CrapsBattle` does
the same for `JackpotBattle` through `CrapsLifecycleRouter`. Every module target and every protocol
contract the code calls is a compile-time constant in `ContractAddresses.sol`. The non-protocol
call targets are Lido stETH, the Chainlink VRF coordinator (the deployment constant, or one
installed by an approved governance swap), the ENS reverse registrar (best-effort, constructors
only), tokens named in Vault-owner sweeps, and an approved governance proposal's target. See
[Security](../../SECURITY.md#external-dependencies-and-settlement). No protocol mint or credit makes
a receiver callback; only a holder-initiated `AFKingSubscriptionToken.safeTransferFrom` does.

## Slither High

| Detector | In scope | Distinct | Excluded | Disposition |
| --- | ---: | ---: | ---: | --- |
| uninitialized-state | 202 | 76 variables | 0 | False positive |
| incorrect-shift | 21 | 21 lines | 0 | False positive |
| incorrect-exp | 7 | 7 lines | 1 node_modules | False positive |
| incorrect-return | 8 | 1 helper | 0 | False positive |
| weak-prng | 5 | 5 | 0 | False positive |
| arbitrary-send-eth | 3 | 3 | 1 mock | By design |
| reentrancy-eth | 1 | 1 | 0 | False positive |
| reentrancy-balance | 1 | 1 | 0 | False positive |
| encode-packed-collision | 1 | 1 | 0 | False positive |

**uninitialized-state.** 194 of 202 are `DegenerusGameStorage` variables that the reporting module
never writes; another module writes them in the same storage, e.g. `foilWriteSlot`
(`storage/DegenerusGameStorage.sol:4376`) is toggled in `modules/DegenerusGameRngUtils.sol:41`.
Every one of the 76 variables has a production writer (assignment, `.push`, storage pointer or
assembly `.slot` store). The remaining 8 are `CrapsBattleStorage._bonus` (`storage/CrapsBattleStorage.sol:641`,
written at `modules/CrapsBattleCore.sol:111`, read by `JackpotBattle` in the same storage) and
`WWXRP._incinEntry` (written through a storage pointer, `WWXRP.sol:1140-1142`). The 33
`DegenerusGameLens` uses take only `.slot`/`.offset` and read the Game's storage through its raw-slot
reader (`DegenerusGameLens.sol:177`); the Lens reads none of its own storage.

**incorrect-shift.** Every hit is a Yul `shl(shift, value)` with a constant value operand, which is
the correct operand order: `let bit := shl(traitId, 1)` (`storage/DegenerusGameStorage.sol:2191`),
`shl(mul(lane, 32), 0xffffffff)` (`libraries/PackedTicketShuffle.sol:18`).

**incorrect-exp.** `^ 1` toggles a parity bit or buffer index (`storage/DegenerusGameStorage.sol:553`,
`DegenerusQuests.sol:2444`, `JackpotBattle.sol:785`); exponentiation is not intended.

**incorrect-return.** The eight external entries of `CrapsLifecycleRouter` forward to
`_delegateLifecycle` (`modules/CrapsLifecycleRouter.sol:90-100`), which delegatecalls the lifecycle
module and ends with assembly `return(data, returndatasize())`. This is a proxy forwarder; no
internal caller expects control back.

**weak-prng.** `(block.timestamp - 82_620) % 1 days` is the 22:57 UTC day-boundary calculation
(`GameTimeLib.JACKPOT_RESET_TIME`), not a random draw: `modules/GameMiner.sol:329`,
`modules/DegenerusGameRngModule.sol:109`, `storage/DegenerusGameStorage.sol:1312`,
`modules/CrapsBattleCore.sol:1616`, `modules/CrapsLifecycleViews.sol:170`.

**arbitrary-send-eth.** Each is the payout leg to the authorized recipient: an account's claim to its
payee (`modules/GameActions.sol:67-81`, after the claimable debit and `claimablePool` update at
`:57-58`); a game-over sDGNRS redemption to the claimant resolved by `_claimant`
(`sDGNRS.sol:1062-1091`, `:1347`); Vault share redemption to `msg.sender`
(`DegenerusVault.sol:962-965`, called at `:818`). State is written before the call in each.

**reentrancy-eth.** `sDGNRS._runRedemptionWork` (`sDGNRS.sol:513-579`) is reported because
`_claimRedemptionFor` can reach `_payGameOverValue`. The live settlement calls it with
`isTerminal = false` (`:569`), and that branch calls only the Game and Coinflip
(`:1206-1226`). The ETH send is only on the `isTerminal` branch (`:1199-1203`), reached from the
post-game-over `claimRedemption` (`:1125`), which deletes the claim before paying.

**reentrancy-balance.** `GameActions._payoutWithEthFallback` reads the stETH balance, then sends
stETH (`modules/DegenerusGamePayoutUtils.sol:34-42`: Lido stETH, or `sDGNRS.depositSteth`) and
re-reads `address(this).balance` for the ETH leg (`modules/GameActions.sol:70-80`). Neither call
target can call back, and the ETH check uses a fresh read.

**encode-packed-collision.** `AFKingSubscriptionToken._renderSvgInternal` concatenates SVG strings
(`AFKingSubscriptionToken.sol:748-758`); the result is never hashed.

## Slither Medium

| Detector | In scope | Distinct | Excluded | Disposition |
| --- | ---: | ---: | ---: | --- |
| divide-before-multiply | 232 | 83 | 6 mock/test, 10 node_modules | By design |
| incorrect-equality | 167 | 115 functions | 0 | False positive |
| uninitialized-local | 165 | 165 | 1 mock/test | False positive |
| reentrancy-no-eth | 133 | 100 functions | 0 | False positive |
| unused-return | 55 | 49 | 0 | By design |
| write-after-write | 3 | 3 | 0 | False positive |
| erc20-interface | 1 | 1 | 0 | False positive |
| locked-ether | 0 | 0 | 1 mock (`MockStETH`) | Not in scope |

**divide-before-multiply.** 150 of 232 are two compile-time constants
(`VRF_STRESS_COST`, `VRF_NATIVE_LOW_WATER`/`VRF_NATIVE_TARGET`,
`storage/DegenerusGameStorage.sol:1167-1173`) reported once per inheriting contract. The 81 other
locations are deliberate quantization or sequential splits: rounding to a unit
(`sDGNRS.sol:430` to 1 gwei, `modules/DegenerusGameJackpotModule.sol:527` to `ETH_PRIZE_UNIT`,
`modules/DegenerusGameJackpotDrawModule.sol:106-108` to `FLIP_ROUND_UNIT`), whole-pass and
whole-ticket counts (`modules/DegenerusGameWhaleModule.sol:1172`, `modules/GamePurchase.sol:499`
on a `ticketWei` already a multiple of `price`, `modules/DegenerusGameMintStreakUtils.sol:154`),
step schedules (`modules/GameMiner.sol:307-310`), bps-then-percent splits
(`DegenerusAffiliate.sol:646-657`), and remainder-preserving forms such as
`(p / r) * y + ((p % r) * y) / r` (`modules/CrapsBattleCore.sol:1790`). The truncation is the
specified rounding in each.

**incorrect-equality.** Strict comparisons of IDs, flags, counters, levels, days and packed-field
tags (`id == 0`, `passType == 3`, `day == nowDay`). One compares a contract balance:
`if (address(this).balance == 0) return;` in `_refillVrfNative`
(`storage/DegenerusGameStorage.sol:1220`), an early exit; forced ETH only lets the bounded
refill attempt proceed.

**uninitialized-local.** Locals that rely on zero default: accumulators, flags set on one branch,
loop cursors, named-return helpers (e.g. `start` in `DegenerusAffiliate.sol:895`, `existing` in
`modules/CoinflipCore.sol:1086`, `minBet` assigned on every non-reverting branch in
`modules/GameDegeneretteBet.sol:183-195`).

**reentrancy-no-eth.** The external calls are delegatecalls to module constants
(`modules/GameComponentCall.sol:8-14` and `modules/GameMiner.sol:180-211`, all targets from
`ContractAddresses`), self-calls, calls to protocol contracts at constant addresses (Game, sDGNRS,
FLIP, Coinflip, Quests, Affiliate, Jackpots, WWXRP, DeityPass, AFKing token, Craps, RecordBounty,
Parimutuel, GNRUS),
the DGVE token fixed at construction (`DegenerusOwnerGovernance.sol:67-69`), and the governance-
approved VRF coordinator in `DegenerusAdmin._executeSwap` (`DegenerusAdmin.sol:796-853`, which
advances `validFromId` before its calls). None is an arbitrary or caller-supplied contract.

**unused-return.** Ignored values are informational to the caller: quest results whose reward Quests
already credits internally (`DegenerusQuests.sol:1497-1498`; callers
`modules/GameDegeneretteBet.sol:175`, `modules/CoinflipCore.sol:2153`); `payAffiliate(0, ...)`
link-only calls, which return zero (`modules/GamePurchase.sol:307`,
`modules/DegenerusGameWhaleModule.sol:877`); the transferred amount of best-effort sDGNRS pool
rewards (`sDGNRS.sol:880`); bounded-call success flags for best-effort external steps
(`storage/DegenerusGameStorage.sol` `_topUpVrfNative`, `DegenerusAdmin.shutdownVrf`); Lido
`submit` shares; and unneeded tuple members of view calls.

**write-after-write.** Assembly scratch variables in `DegenerusGameLens` reused for a second slot
base (`DegenerusGameLens.sol:950-953`, `:82-86`, `:151-154`).

**erc20-interface.** `IERC721Sweep.transferFrom` (`DegenerusVault.sol:46-48`) is an ERC-721
interface; ERC-721 `transferFrom` returns nothing.

## Aderyn High

| ID | Category | In scope | Excluded | Disposition |
| --- | --- | ---: | ---: | --- |
| H-1 | `abi.encodePacked()` hash collision | 30 | 0 | False positive |
| H-2 | Contract locks Ether without a withdraw function | 15 | 2 | By design |
| H-3 | `delegatecall` to an arbitrary address | 35 | 0 | False positive |
| H-4 | ETH transferred without address checks | 8 | 1 | By design |
| H-5 | Incorrect use of caret operator | 6 | 0 | False positive |
| H-6 | Incorrect assembly shift parameter order | 23 | 0 | False positive |
| H-7 | Reentrancy: state change after external call | 42 | 0 | False positive |
| H-8 | Contract name reused in different files | 20 | 0 | Accepted |
| H-9 | Storage array edited with memory | 2 | 0 | False positive |
| H-10 | Strict equality on contract balance | 1 | 0 | False positive |
| H-11 | Unsafe casting of integers | 56 | 2 | Accepted |
| H-12 | Yul block contains `return` | 3 | 0 | False positive |

- **H-1.** String building for token metadata and SVG in `AFKingSubscriptionToken`,
  `DegenerusDeityPass`, `DegenerusRecordBounty` and `DeityPassCustomizationRenderer`; nothing is hashed.
- **H-2.** Module and profile contracts (`DegenerusGameWhaleModule`, `Eip170Mint`, ...) whose payable
  entries run in the Game's context by delegatecall; the ETH lands in the Game, which pays it out.
  A direct call to a module address with value strands only the caller's own ETH.
- **H-3.** The Game facade and module dispatch. Every target is a `ContractAddresses` constant
  (`modules/GameFacade.sol:248-250`, `modules/GameComponentCall.sol:8-14`).
- **H-4.** Recipients are `msg.sender` (`DGNRS.sol:304`, `GNRUS.sol:381`, `DegenerusVault.sol:818`), protocol constants
  (`DGNRS.sol:397-401`, `GNRUS.sol:499`, the game-over sweep to Vault, sDGNRS and GNRUS at
  `modules/DegenerusGameGameOverModule.sol:802-804`), the redeemed holder itself (`GNRUS.sol:469-478`),
  or an approved governance proposal's target (`DegenerusOwnerGovernance.sol:136`).
- **H-5.** Same sites as Slither `incorrect-exp`.
- **H-6.** Same sites as Slither `incorrect-shift`, plus `JackpotBattle.sol:312` and
  `storage/DegenerusGameStorage.sol:2074`; all use `shl(shift, value)`.
- **H-7.** Calls to protocol contracts at constant addresses, mostly view reads (`isVaultOwner`,
  `rngLocked`, `balanceOf`), and the configured coordinator in the `DegenerusAdmin` constructor
  (`DegenerusAdmin.sol:485`). Same target set as Slither `reentrancy-no-eth`.
- **H-8.** Small file-local interfaces share names (e.g. `IDegenerusVaultOwner` in six files). Where
  same-named interfaces declare the same function, the signatures are identical, so the
  selectors match. Slither resolves every function on this tree.
- **H-9.** A storage string passed to the pure check `_isGoldHex` (`DegenerusDeityPass.sol:312`, `:369`)
  and a storage struct passed to the view reader `_effectiveBaseStreak` (`DegenerusQuests.sol:1620`);
  neither function is meant to write.
- **H-10.** Same site as the Slither balance equality (`storage/DegenerusGameStorage.sol:1220`).
- **H-11.** Narrowing casts are field extraction from packed words (`uint32(packed)` for an ID lane,
  `modules/DegenerusGameJackpotDrawModule.sol:420`; `uint80(entry)`, `sDGNRS.sol:546`), wei amounts
  stored in `uint96`/`uint112`/`uint128` fields far above any reachable ETH amount
  (`modules/DegenerusGameDegeneretteModule.sol:885`, `modules/GameDegeneretteBet.sol:331`,
  `sDGNRS.sol:1408`), and small counters and indices. Width truncations that cannot be reached, or
  could only misstate value, are accepted; a truncation that can make mining, a claim, a withdrawal
  or the terminal path revert or stall stays in scope. The widest user-controlled case is noted under
  [Project disposition](#project-disposition).
- **H-12.** Assembly `return` ending external functions: the lifecycle forwarder
  (`modules/CrapsLifecycleRouter.sol:98`), `extsload` (`modules/CrapsBattleCore.sol:657`) and the
  `creditMiddayRng` result pass-through (`modules/GameFacade.sol:1218`).

## Slither Low, Informational and Optimization

| Tier | Detector | In scope | Excluded | Note |
| --- | --- | ---: | ---: | --- |
| Low | reentrancy-events | 242 | 0 | Events after calls to the trusted targets above |
| Low | calls-loop | 157 | 0 | Bounded batches calling protocol contracts |
| Low | reentrancy-benign | 80 | 0 | Same targets as `reentrancy-no-eth` |
| Low | timestamp | 34 | 0 | Deadlines, day boundaries, governance and stall timers |
| Low | shadowing-local | 9 | 1 | Parameters named after storage fields (e.g. `level`) |
| Low | events-maths | 5 | 0 | Parameter writes without a dedicated event |
| Low | missing-zero-check | 0 | 3 | Mocks only |
| Info | unused-state | 3,333 | 0 | Shared-storage variables each module does not use (250 distinct) |
| Info | naming-convention | 225 | 0 | Style |
| Info | assembly | 160 | 16 | Deliberate packed-storage and forwarding assembly |
| Info | low-level-calls | 86 | 4 | ETH payouts, bounded external calls, delegate dispatch |
| Info | cyclomatic-complexity | 56 | 0 | Style |
| Info | too-many-digits | 50 | 5 | Literal masks and constants |
| Info | missing-inheritance | 34 | 13 | Local interfaces not inherited |
| Info | costly-loop | 20 | 0 | Bounded loops |
| Info | dead-code | 19 | 0 | Internal helpers and profile overrides with no caller in the reporting unit |
| Info | redundant-statements | 18 | 0 | `ok;` after the best-effort ENS reverse-name call in constructors (e.g. `DegenerusAffiliate.sol:412`) |
| Info | pragma, solc-version | 0 | 2 | `node_modules` only |
| Opt | constable-states | 73 | 0 | Shared-storage variables written by other modules |
| Opt | immutable-states | 8 | 0 | Same (e.g. `dailyIdx`, `purchaseStartDay`) |

All 75 variables reported by `constable-states` and `immutable-states` have production writers.

## Aderyn Low

| ID | Category | In scope | Excluded |
| --- | --- | ---: | ---: |
| L-1 | Centralization risk | 7 | 0 |
| L-2 | Costly operations inside loop | 71 | 0 |
| L-3 | Dead code | 1 | 0 |
| L-4 | `delegatecall` in loop | 13 | 0 |
| L-5 | Incorrect order of division and multiplication | 9 | 0 |
| L-6 | Empty block | 2 | 0 |
| L-7 | Empty `require()` / `revert()` | 1 | 2 |
| L-8 | Internal function used only once | 17 | 0 |
| L-9 | Large numeric literal | 331 | 1 |
| L-10 | Literal instead of constant | 1,724 | 10 |
| L-11 | Local variable shadows state variable | 2 | 0 |
| L-12 | Missing inheritance | 14 | 9 |
| L-13 | Modifier invoked only once | 5 | 0 |
| L-14 | Redundant statement | 18 | 0 |
| L-15 | Loop contains `require`/`revert` | 68 | 0 |
| L-16 | State change without event | 43 | 17 |
| L-17 | Address state variable set without checks | 1 | 0 |
| L-18 | State variable could be immutable | 2 | 0 |
| L-19 | Unchecked return | 96 | 0 |
| L-20 | Uninitialized local variable | 38 | 0 |
| L-21 | Unsafe ERC20 operation | 15 | 0 |
| L-22 | Unused error | 6 | 0 |
| L-23 | Unused import | 46 | 0 |
| L-24 | Public function not used internally | 8 | 0 |
| L-25 | Unused state variable | 34 | 0 |

These overlap the Slither classes above (L-5 with `divide-before-multiply`, L-19 with
`unused-return`, L-20 with `uninitialized-local`, L-25 with shared storage) or are style. L-1 is the
owner authority described in [Security](../../SECURITY.md). L-21 is token `transfer`/`approve`
(stETH, DGVE, Vault token sweep) with the boolean result checked.

## Project disposition

The project classifies every Slither High and Medium instance and every Aderyn High instance
above as not requiring a code change. That classification rests on these assumptions:

- the [trust model](#trust-model-used-for-reentrancy-and-send-classes): every called protocol
  contract and module is a compile-time constant, and Lido stETH, the Chainlink VRF coordinator,
  the ENS registrar and governance-approved targets behave as described in
  [Security](../../SECURITY.md#external-dependencies-and-settlement);
- the authority model in [Security](../../SECURITY.md#roles): owner-only and governance-only paths
  are evaluated as trusted decisions within their stated powers;
- the per-detector reasoning recorded above, including the source manifests (`check-*` gates) it
  cites, which are review aids rather than proofs.

Where a group's reasoning relies on a trusted-target label, an auditor should still check the
call path, gas forwarding and failure behavior of the specific instance; the
[Security](../../SECURITY.md#audit-boundaries) boundary states that a `view`, `pure` or
trusted-address label alone does not establish safety.

For completeness, the widest user-controlled narrowing in H-11: `_callTicketPurchase` charges
`priceWei * quantity / 400` on the full `uint256` quantity, then queues `uint32(adjustedQuantity)`
entries (`modules/GamePurchase.sol:1024`, `:1053`). It truncates only when the boosted quantity
reaches 2^32 purchase units (10,737,418 whole tickets; the boost adds at most 10 ETH of value,
`LOOTBOX_BOOST_MAX_VALUE`), which takes a single purchase of about 107,000 ETH at the 0.01 ETH
minimum price. The excess would be the buyer's own loss; no other account or path is affected.
