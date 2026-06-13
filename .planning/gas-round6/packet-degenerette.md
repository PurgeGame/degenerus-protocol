# Round 6 packet — DegenerusGameDegeneretteModule.sol (+ _lrAdd in DegenerusGameStorage.sol)

Source verified 2026-06-12 at HEAD 4e5ef35b. 4 live edits, 2 subsumed (no edit).

## DEGENERETTE-02 (APPROVED) — replace inline shortfall waterfall with _settleShortfall
- Site: `_collectBetFunds` ETH arm, the `if (ethPaid < totalBet) { ... }` body (L579-598).
- Re-verified operation-identical to `DegenerusGameStorage._settleShortfall(player,
  totalBet - ethPaid, true)` (storage L852-876): same `claimable > 1` sentinel tier, same
  min() draw, same paired claimablePool debits, same AfkingSpent emit. Module inherits
  storage via DegenerusGamePayoutUtils.
- ONE behavioral delta: insufficient afking now reverts `E()` (storage L870) instead of
  `InvalidBet()` — failure path only; no test pins this selector (grep-verified).
- Value: single-sink consistency (the helper's own comment names drift as the hazard);
  net bytecode ~wash (helper body gets pulled in on first reference).

## DEGENERETTE-05 (APPROVED) — lazy prizePoolFrozen snapshot
- Delete `acc.poolFrozen = prizePoolFrozen;` from resolveBets (L415); add it inside
  `_distributePayout`'s `if (!acc.poolLoaded)` block (L863-870), after `poolLoaded = true`.
- Consumers verified: L872 branch (after the block), L432 flush (guarded by poolLoaded).
  Writers of prizePoolFrozen: only the advanceGame chain — nothing reachable from
  resolveBets flips it, so the value read at first-ETH-win == value at call start.
- Update struct comment L392: "stable across the call" → "loaded with the pool locals".
- ~97 gas saved per resolveBets with no ETH pool-touching win (the majority).

## DEGENERETTE-10 (APPROVED) — merge double currency dispatch
- Sites: maxSpins nested ternary (L490-494) + `_validateMinBet` (L557-567, sole call L503).
- Replace with one if/else chain producing maxSpins + minBet, explicit WWXRP arm,
  `else revert UnsupportedCurrency()`; min-bet check joins the count/amount/hero checks;
  delete `_validateMinBet`. Update the L488-489 comment that references it.
- Accept/reject SET identical (skeptic-verified). Revert ORDER/selector deltas on
  compound-invalid inputs only (e.g. currency=2 + ticketCount=0: InvalidBet →
  UnsupportedCurrency; below-min ETH during rng-locked window: RngNotReady → InvalidBet).
  No test pins these (grep-verified: only a comment mention in DegeneretteHeroScore).
- Currency values: 0=ETH, 1=BURNIE, 3=WWXRP; 2 is the invalid value the explicit arm rejects.

## RT-CLAIMS-11 (APPROVED) — _lrAdd single-SLOAD read-modify-write
- Sites: `_lrWrite(S, M, _lrRead(S, M) + delta)` at L608 (ETH) and L613 (BURNIE) in
  `_collectBetFunds`.
- Add to DegenerusGameStorage (next to _lrRead/_lrWrite, L1506-1514):
  `_lrAdd(shift, mask, delta)` — ONE load, field' = ((field + delta) & mask), ONE store.
  EXACT-SEMANTICS REQUIREMENT: preserves _lrWrite's `(value & mask)` truncation (no new
  checked-overflow revert on the masked merge; the `field + delta` add stays checked,
  same as the current call-site `_lrRead(...) + delta`).
- Internal-function addition to the storage base: NO layout change (slot-hardcoded
  harnesses unaffected), no bytecode in non-referencing contracts.
- ~100 gas per ETH/BURNIE bet placement.

## SUBSUMED — no edit
- RT-CLAIMS-14: already applied — round 2's DEGENERETTE-04 (commit dd09cb99) cached
  `uint24 lvl = level` in _placeDegeneretteBet and threaded it into core; both former
  re-read sites now use `lvl + 1` (verified at L453/L461/L473/L513). Ledger → Handled.
- DEGENERETTE-03 (NHR, adjudicated in-packet): same two RMW sites as RT-CLAIMS-11; the
  skeptic's gate was "verify via_ir hasn't already CSE'd the second SLOAD". Applying
  _lrAdd makes the question moot — one SLOAD by construction, and the truncation
  semantics it flagged as the hazard are preserved verbatim. Subsumed by RT-CLAIMS-11.

## Test impact
- No selector/order pins found in test/ for the changed revert paths.
- Source-pin tests grasping DegenerusGameStorage extract _queueTickets* bodies only —
  _lrAdd insertion does not perturb them.
