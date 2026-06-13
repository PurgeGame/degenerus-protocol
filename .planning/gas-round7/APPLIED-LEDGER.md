# Round 7 — applied ledger (2026-06-12)

Batch: the small-contract sweep — 22 ledger IDs dispositioned via 20 distinct edits
across 15 contract files (2 subsumption pairs), plus 2 already-applied residues finished.

## Applied

| ID(s) | File(s) | Edit |
|---|---|---|
| ADMIN-05 | DegenerusAdmin | linkAmountToEth internalized as `_linkAmountToEth(amount, feed)` (try/catch on latestRoundData + mandatory pre-mul overflow guard reproducing the old revert→catch→0 outcome); external fn kept as thin wrapper (ABI preserved; accepted delta: overflow now returns 0 instead of reverting — view-only, zero on-chain callers) |
| ADMIN-06 | DegenerusAdmin | onTokenTransfer computes getSubscription+mult only when `feed != address(0)`; funding transferAndCall unconditional; feed==0 exits at the existing `mult == 0` return after funding (outcome-identical) |
| ADMIN-10 | DegenerusAdmin | 1-active-proposal guards now reuse the EXISTING `_isActiveProposal` (DEVIATION-as-improvement vs the packet's new-helper proposal: `createdAt == 0` short-circuit proven unreachable for real proposal ids — reviewer-verified); both void loops cache a per-iteration storage pointer |
| DEITY-01 | DegenerusDeityPass | tokenURI tries the external renderer first; _renderSvgInternal only on unset/failure/empty (byte-identical output all paths) |
| JACKPOTS-06 + RT-CLAIMS-13 (subsumed) | DegenerusJackpots | slices D/D2 collapsed to a 2-pass loop, `++salt` first statement — salt sequence 2,3 and entropy chain provably unchanged |
| JACKPOTS-09 | DegenerusJackpots | _updateBafTop Case 1 → shift-then-place (mirrors Cases 2/3); strict-> predicate identical (truth-table verified incl. tie-stop) |
| JACKPOTS-11 ⚠ | DegenerusJackpots | onlyCoin tightened to COINFLIP-only (BurnieCoin provably cannot call; access STRICTLY NARROWED); 5 natspec sites updated. **Flagged for explicit user confirmation in the diff review** (tests had encoded COIN-as-valid as spec) |
| STONK-01 | StakedDegenerusStonk | burnWrapped caches `isOver` (burnForSdgnrs makes no external calls; gate boolean identical) |
| STONK-02 | DegenerusStonk | yearSweep's gameOver() staticcall deleted (goTime==0 dominates, same SweepNotReady selector; latch writes GO_TIME atomically) |
| STONK-03 | DegenerusStonk | unreachable BURNIE-forward leg + burnie constant + IERC20Minimal deleted (gameOver path returns burnieOut=0 structurally); ABI/event unchanged |
| STONK-04 | DegenerusStonk | burnForSdgnrs → auth + `_burn(player, amount)` (byte-identical body dedup) |
| STONK-08 | StakedDegenerusStonk | single pendingRedemptions load in _claimRedemptionFor (1-slot struct memory copy), bool return; claimRedemption reverts NoClaim on false; Many keeps skip semantics; CEI untouched. Accepted both-fail revert-priority deltas: NoClaim→NotResolved / NoClaim→Unauthorized |
| LIBS-01 + LIBS-02 | PriceLookupLib | first-cycle branches collapsed into the modulo chain + branch-free nibble table 0x4333222111 (unchecked mul, max 0.16e18). Output proven identical over uint24 (R7LibEquivalence: verbatim old-body reference, dense 0..10k + boundary strides + fuzz) |
| LIBS-03 | Lootbox/Degenerette(×2)/JackpotModule(×3)/AdvanceModule(×2)/StakedStonk | remaining two-word keccak idiom sites → EntropyLib.hash2 (all preimages re-verified exactly two full words; imports added to Degenerette/Advance/StakedStonk). DegenerusJackpots ×4 were ALREADY applied (stale sub-entries) |
| LIBS-04 | EntropyLib + LootboxModule | new hash1 (single-word scratch keccak); the redemption-chunk reseed (relocated to LootboxModule:925 by round-5 LOOTBOX-12) migrated — byte-identical preimage |
| MINT-12 | MintStreakUtils + MintModule | (cl, oneTicketWei, seed) computed once per entry point and threaded; new `_farFutureSeed` holds the seed expression verbatim (preview/exec parity by construction); helper signatures drop `player` |
| MINT-15 | MintStreakUtils + DegenerusGame | external curseCountOf relocated VERBATIM into the Game; 4 module dispatchers shed the entry (Bingo already shed it via round-6 SMALLMODS-09) |
| RT-AFKING-WHALE-07 | MintStreakUtils + DegenerusGame | hot path was ALREADY APPLIED (FromPacked variant, earlier round); residual finished: ethMintStats now uses the packed variant + the orphaned `_mintStreakEffective` wrapper deleted |
| STORAGE-03 + RT-IDIOMS-08 (subsumed) | DegenerusGameStorage | _queueTicketRange hoists rngLockedCached + writeSlotBit (algebraic identity verified); per-level RngLocked check observes the same value; ~10k saved per 100-level whale bundle |

## Test recalibrations
- DegenerusJackpots.test.js: recordBafFlipAsCoin helper deleted; 32 call sites → recordBafFlipAsCoinflip; COIN-caller acceptance test inverted to an OnlyCoin-reverts pin; destructurings rebound (incl. 2 multi-line ones the reviewer caught).
- BafRebuyReconciliation.t.sol + BafFarFutureTickets.t.sol: vm.prank(coin) → vm.prank(address(coinflip)).
- RedemptionEdgeCases EDGE-13: repinned NoClaim → NotResolved (the documented STONK-08 both-fail overlap; resolveRedemptionPeriod early-returns on zero-ethBase days so the day stays unresolved).
- NEW test/fuzz/R7LibEquivalence.t.sol: 8 equivalence gates (price old-vs-new + 5 hash shapes), all green.

## Verification
- 3 sonnet reviewers vs pristine /tmp/r7-baseline (c8c3f8cc): all contract findings FAITHFUL; all 11 RNG-site migrations independently proven byte-identical; 1 test-harness deviation caught (missed destructurings) and fixed.
- forge full suite green (845 incl. the 8 new gates / 0 / 110) after two test-side repins.
- Game bytecode 19,143 → 19,001 (headroom 5,575); Degenerette 9,554 → 9,293.

## Residuals for a future round
- AdvanceModule:~484 carries one more `abi.encodePacked(rngWord, BONUS_TRAITS_TAG)` site NOT listed in the audit's LIBS-03 body — same shape/proof class, left unmigrated this round (packet discipline).
