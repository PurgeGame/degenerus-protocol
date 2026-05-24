# 321 — Call-Graph Attestation: AfKing Cancel-Tombstone (H-CANCEL-SWAP-MISS)

**Scope:** READ-ONLY attestation of every `file:line` anchor in
`.planning/PLAN-V47-AFKING-CANCEL-TOMBSTONE.md` against the CURRENT source tree.
**Sources of truth (this attestation):**
- `contracts/AfKing.sol` (846 lines)
- `contracts/modules/DegenerusGameMintStreakUtils.sol` (176 lines)
- `test/gas/CrankLeversAndPacking.t.sol` (testGas04 + helpers)

**Verdict legend:** `MATCH` (anchor lands on the claimed line) · `SHIFTED(±N)`
(content present but N lines off) · `ABSENT` (content not found / materially
diverged).

---

## A. Anchor reconciliation table

| # | Anchor (claimed) | ACTUAL (contracts/AfKing.sol) | Verdict |
|---|---|---|---|
| 1 | `setDailyQuantity(uint8 q)` body `:455-468` | `:455-472` (`function setDailyQuantity` opens at **:455**; `q==0` branch :458-468; `q>0` tail :470-471; closes :472) | **MATCH** (open line exact; body extends to :471/472) |
| 2 | `_removeFromSet(msg.sender)` call inside cancel `:459` | `_removeFromSet(msg.sender);` at **:459** | **MATCH** |
| 3 | `_subOf` delete-vs-preserve logic `:460-467` | preserve/delete branch at **:460-467** (`preservePaidWindow` :460; preserve :461-463; delete :464-467) | **MATCH** |
| 4 | NatSpec mislabel "SUB-07 tombstone" `:449` | `@dev SUB-07 tombstone-on-cancel:` at **:449** (claims "the swap-pop removes the set membership" — conflates swap-pop with tombstone, exactly as flagged) | **MATCH** |
| 5 | `_removeFromSet(address)` swap-and-pop body `:825-837` | `function _removeFromSet(address player)` at **:825**; body :826-836; closes :837 | **MATCH** |
| 6 | Sweep loop `~:609-745` | `while (...)` opens at **:609**; per-player ladder runs to the InsufficientPool kill `continue` at :744; loop closes :774 | **MATCH** (loop top exact; body runs to :774) |
| 7 | `lastSweptDay >= today` skip `:613-621` | comment :613, `if (sub.lastSweptDay >= today)` at **:614**, skip block :615-620 | **SHIFTED(+1)** on the `if`; block within :613-621 envelope |
| 8 | `_sweepCursor` slot-4 decl `:215` | `uint224 private _sweepCursor; // slot 4 (offset 4)` at **:215** | **MATCH** |
| 9 | cursor read at `:579` (`cursor = _sweepDay == today ? _sweepCursor : 0`) | `uint256 cursor = _sweepDay == today ? uint256(_sweepCursor) : 0;` at **:579** | **MATCH** |
| 10 | cursor persist write at `:777` | `_sweepCursor = uint224(cursor);` at **:777** | **MATCH** |
| 11 | auto-pause swap-pop `:642-644` (no-`++i`) | sentinel `sub.dailyQuantity = 0;` :642; `sub.flags &= ~FLAG_WINDOW_PAID;` :643; `_removeFromSet(player);` :644; then `continue` with only `++processed` (NO `++cursor`) :646-649 | **MATCH** |
| 12 | funding-kill swap-pop `:737-739` | `sub.dailyQuantity = 0;` :737; `sub.flags &= ~FLAG_WINDOW_PAID;` :738; `_removeFromSet(player);` :739; then `continue` with only `++processed` (NO `++cursor`) :741-744 | **MATCH** |
| 13 | NO loop-top `dailyQuantity == 0` reclaim branch today | Confirmed ABSENT. The loop top (:609-614) reads `player`/`sub` then goes straight to the `lastSweptDay >= today` skip. There is no `if (sub.dailyQuantity == 0)` reclaim anywhere in the loop. A tombstoned-but-in-set entry would fall through `lastSweptDay`, hit auto-extract / approval / quantity, and `cost = mp * 0 = 0` → never floor-skipped if ticket mode, etc. (i.e. the in-set tombstone is **not** the design at HEAD — cancel does an immediate swap-pop, never leaves a tombstone in the set) | **CONFIRMED ABSENT** (matches plan claim "NO loop-top reclaim today") |
| 14 | `subscribe(...)` signature `:375` | `function subscribe(` opens at **:375**; params :376-381 (`address player, bool drainGameCreditFirst, bool useTickets, uint8 dailyQuantity, uint8 reinvestPct, address fundingSource`); closes :382 | **MATCH** (6-arg incl. `address fundingSource` — the v46 OPEN-E shape) |
| 15 | `dailyQuantity == 0` "paused" semantics `:70` | NatSpec `offset 0 uint8 dailyQuantity — 0 = paused / never-subscribed (minimum 1 when active)` at **:70** | **MATCH** |
| 16 | `SubscriptionUpdated` event shape `:156` | event decl opens :160; the `:156` anchor is the NatSpec line `Manual pause (setDailyQuantity(0)) emits with dailyQuantity == 0.` at **:156** | **MATCH** (NatSpec at :156; struct fields :160-167) |
| 17 | cursor self-heal `:579` | identical to #9 — `_sweepDay == today ? uint256(_sweepCursor) : 0` at **:579** | **MATCH** |
| 18 | `setDailyQuantity(q>0)` reactivation `:470` | `s.dailyQuantity = q;` at **:470** + emit :471 | **MATCH** |
| 19 | `Sub` struct field list + widths (6 fields, 31 used bytes, one slot) | `struct Sub` :79-86: `uint8 dailyQuantity;`(:80) `uint32 lastSweptDay;`(:81) `uint32 paidThroughDay;`(:82) `uint8 reinvestPct;`(:83) `uint8 flags;`(:84) `address fundingSource;`(:85). Widths: 1+4+4+1+1+20 = **31 bytes**, 6 fields, single slot (offset 31 free, per NatSpec :69-78) | **MATCH** (exactly as plan claims) |
| 20 | `_subOf` / `_poolOf` mappings + stranded ETH withdrawal | `_poolOf` slot 0 (:194); `_subOf` slot 1 (:197). Stranded `_poolOf` ETH is withdrawn via `withdraw(uint256 amount)` (:317-330) — caller-scoped CEI debit on `_poolOf[msg.sender]`, independent of subscription state | **MATCH** |

### Mint-streak cross-ref (`contracts/modules/DegenerusGameMintStreakUtils.sol`)

| # | Anchor (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| 21 | `_mintStreakEffective` reset-on-skip `:51-63` | `function _mintStreakEffective(` opens **:51**; reset-on-skip `if (uint256(currentMintLevel) > lastCompleted + 1) return 0;` at **:59**; closes :63 | **MATCH** |
| 22 | `_playerActivityScore` 1%/level cap +50% `:114-115` | comment `// Mint streak: 1% per consecutive level minted, max 50%` at **:114**; `uint256 streakPoints = streak > 50 ? 50 : uint256(streak);` at **:115** (then `bonusBps = streakPoints * 100;` at :130 → 1% per point = 1% per consecutive level, capped at 50 points = +50%) | **MATCH** |

### Stale test cross-ref (`test/gas/CrankLeversAndPacking.t.sol`)

| # | Anchor (claimed) | ACTUAL | Verdict |
|---|---|---|---|
| 23 | `testGas04...SourcePresence` asserts pre-OPEN-E `Sub` (standalone bools + 7-field/13-byte sum), panics 0x11 at HEAD | fn at **:302-333**. Asserts `bool drainGameCreditFirst;`(:312) + `bool useTickets;`(:313) as standalone fields; 7-term sum `assertEq(subBytes, 13, ...)` at :319. `_structFieldBytes` (:431-437) returns `type(uint256).max` when a decl is ABSENT → two absent bools each return max → `max + max` in checked arithmetic → **Panic 0x11 (overflow)** before the assert is even reached | **CONFIRMED STALE** (panics 0x11 at HEAD) |

---

## B. Exact current `setDailyQuantity` body (AfKing.sol:447-472)

```solidity
    /// @notice Update caller's daily buy units. q == 0 is the tombstone cancel
    ///         (removes from the iterable set + writes 0); q > 0 updates in place.
    /// @dev SUB-07 tombstone-on-cancel: the swap-pop removes the set membership and
    ///      writes the sentinel, but the `_subOf` record is preserved when the
    ///      window is paid and unexpired (windowPaid set AND paidThroughDay > today)
    ///      — the player keeps the service window they paid for. A free or expired
    ///      window is deleted (nothing to preserve; re-subscribe is fresh). Stranded
    ///      `_poolOf` ETH always stays withdrawable.
    function setDailyQuantity(uint8 q) external {
        if (_subscriberIndex[msg.sender] == 0) revert NotSubscribed();
        Sub storage s = _subOf[msg.sender];
        if (q == 0) {
            _removeFromSet(msg.sender);
            bool preservePaidWindow = (s.flags & FLAG_WINDOW_PAID) != 0 && s.paidThroughDay > _currentDay();
            if (preservePaidWindow) {
                s.dailyQuantity = 0;
                emit SubscriptionUpdated(msg.sender, 0, (s.flags & FLAG_DRAIN_FIRST) != 0, (s.flags & FLAG_USE_TICKETS) != 0, s.reinvestPct, s.fundingSource);
            } else {
                delete _subOf[msg.sender];
                emit SubscriptionUpdated(msg.sender, 0, false, false, 0, address(0));
            }
            return;
        }
        s.dailyQuantity = q;
        emit SubscriptionUpdated(msg.sender, q, (s.flags & FLAG_DRAIN_FIRST) != 0, (s.flags & FLAG_USE_TICKETS) != 0, s.reinvestPct, s.fundingSource);
    }
```

**Key finding:** the `q==0` branch calls `_removeFromSet(msg.sender)` (:459) — the
**immediate swap-pop on cancel** that the plan identifies as the regression. The
NatSpec at :449 mislabels this swap-pop as "SUB-07 tombstone-on-cancel" while the
LOCKED SUB-07 spec (316-SPEC.md:152) requires cancel to "move nothing". The
delete-vs-preserve decision (`_subOf`) executes **in the cancel tx** (:460-467),
NOT deferred to an in-sweep reclaim. There is **no** in-set tombstone path today.

---

## C. Exact current sweep-loop structure (the no-`++i` swap-pop pattern)

Loop top at `:609`. The two in-loop swap-pops both use the no-cursor-advance
pattern; there is **no** loop-top `dailyQuantity == 0` reclaim branch.

```solidity
        while (processed < maxCount && cursor < _subscribers.length) {
            address player = _subscribers[cursor];
            Sub storage sub = _subOf[player];

            // (1) AlreadySweptToday — cheapest SLOAD-only skip.
            if (sub.lastSweptDay >= today) {            // :614
                emit PlayerSkipped(player, 2);
                unchecked { ++cursor; ++processed; }    // ADVANCES cursor
                continue;
            }

            // (2) Day-31 auto-extract branch ...
            if (sub.paidThroughDay <= today) {
                if (hasAnyLazyPass) { ... free extend ... }
                else {
                    ... burnForKeeper ...
                    if (burned != extractCost) {
                        // AUTO-PAUSE swap-pop — NO ++cursor
                        sub.dailyQuantity = 0;          // :642
                        sub.flags &= ~FLAG_WINDOW_PAID;  // :643
                        _removeFromSet(player);          // :644  swap-pop
                        emit SubscriptionExpired(player, 1);
                        unchecked { ++processed; }       // :646-648  NO ++cursor
                        continue;                        // :649  re-process mover at same index
                    }
                    ... paid success ...
                }
            }

            // (3) NotApproved skip   — ADVANCES cursor (++cursor; ++processed)  :660-667
            // (4) effectiveQty / cost computation                               :669-680
            // (5) LootboxFloor transient skip — ADVANCES cursor                 :684-691
            //     OPENE-02 src resolution                                       :697
            //     funding waterfall (payKind / msgValue)                        :699-719

            // (6) InsufficientPool funding skip → two-tier skip-kill
            if (_poolOf[src] < msgValue) {                                       // :728
                if (player == ContractAddresses.VAULT || player == ContractAddresses.SDGNRS) {
                    emit PlayerSkipped(player, 3);
                    unchecked { ++cursor; ++processed; } // EXEMPT: ADVANCES cursor :731-734
                    continue;
                }
                // FUNDING-KILL swap-pop — NO ++cursor
                sub.dailyQuantity = 0;                  // :737
                sub.flags &= ~FLAG_WINDOW_PAID;          // :738
                _removeFromSet(player);                  // :739  swap-pop
                emit SubscriptionExpired(player, 1);
                unchecked { ++processed; }               // :741-743  NO ++cursor
                continue;                                // :744  re-process mover at same index
            }

            // (7) CEI debit + accumulate slice + day-stamp — ADVANCES cursor     :747-773
            unchecked { ++cursor; ++processed; }          // :770-773
        }

        _sweepCursor = uint224(cursor);                   // :777  persist
```

**no-`++i` pattern (the iteration-safety contract):** after a swap-pop
(`_removeFromSet`), the tail subscriber has been moved into the current `cursor`
slot. The loop `continue`s incrementing **only `++processed`**, leaving `cursor`
unchanged, so the moved (pending) entry is re-read at the same index on the next
iteration. This is the pattern the plan's Edit-2 reclaim branch must mirror
(:644 / :739 are the two existing instances).

**The gap (confirmed):** there is no loop-top branch that reclaims an in-set
`sub.dailyQuantity == 0` tombstone. At HEAD this is consistent because cancel
never leaves an in-set tombstone (it swap-pops immediately) — which is exactly the
regression the plan reverses. Once Edit-1 stops swap-popping on cancel, the loop
needs Edit-2's reclaim branch or tombstones would persist as dead slots.

---

## D. Exact current `Sub` struct (AfKing.sol:79-86)

```solidity
struct Sub {
    uint8 dailyQuantity;     // offset 0,  1 byte
    uint32 lastSweptDay;     // offset 1,  4 bytes
    uint32 paidThroughDay;   // offset 5,  4 bytes
    uint8 reinvestPct;       // offset 9,  1 byte
    uint8 flags;             // offset 10, 1 byte  (bit0 windowPaid, bit1 drainGameCreditFirst, bit2 useTickets)
    address fundingSource;   // offset 11, 20 bytes (address(0) = self)
}
```

- **6 fields, 31 used bytes** (1+4+4+1+1+20), single 32-byte slot, offset 31 free
  padding. **Exactly matches the plan's claimed HEAD shape.**
- The two pre-OPEN-E standalone bools (`drainGameCreditFirst`, `useTickets`) are
  collapsed into `flags` (FLAG_DRAIN_FIRST=2 at :244, FLAG_USE_TICKETS=4 at :248).
- `address fundingSource` is the v46 OPENE-01/319.1 addition.

---

## E. testGas04 staleness — CONFIRMED

`test/gas/CrankLeversAndPacking.t.sol::testGas04PackingAndNoNewHotPathStorageSourcePresence`
(:302-333) asserts the **pre-OPEN-E** `Sub` layout:

```solidity
        uint256 subBytes =
            _structFieldBytes(afking, "uint8 dailyQuantity;", 1) +
            _structFieldBytes(afking, "bool drainGameCreditFirst;", 1) +   // :312 ABSENT at HEAD
            _structFieldBytes(afking, "bool useTickets;", 1) +             // :313 ABSENT at HEAD
            _structFieldBytes(afking, "uint32 lastSweptDay;", 4) +
            _structFieldBytes(afking, "uint32 paidThroughDay;", 4) +
            _structFieldBytes(afking, "uint8 reinvestPct;", 1) +
            _structFieldBytes(afking, "uint8 flags;", 1);
        assertLe(subBytes, 32, ...);
        assertEq(subBytes, 13, "GAS-04: Sub is 13 used bytes ...");        // :319 7-field/13-byte sum
```

**Panic mechanism (verified):** `_structFieldBytes` (:431-437) returns
`type(uint256).max` when the decl is ABSENT (`_countOccurrences == 0`). At HEAD,
`bool drainGameCreditFirst;` (:312) and `bool useTickets;` (:313) are absent from
`contracts/AfKing.sol` (grep-confirmed — they exist only in this stale test).
Two terms each return `type(uint256).max`; the `+` chain runs in checked
arithmetic, so `max + max` reverts with **Panic 0x11 (arithmetic overflow)**
before `assertLe`/`assertEq` evaluate. This is a test-only staleness — the
contract is correct (320-01 SWP-OPENE NEGATIVE-VERIFIED).

**Fix the plan prescribes (§3 last para):** drop the two standalone-bool checks,
add `address fundingSource;` (width 20), and change the sum assert 13→31 with a
6-field list. This restores the documented 44-fail baseline (this test is the
45th failure in the 565/45 HEAD count).

Other byte-presence tests in the same file (G1-G13 at :343-397) reference AfKing
only via stable identifiers (`burnForKeeper(`, `isOperatorApproved(`,
`_removeFromSet(`, `lastSweptDay`, `_sweepDay == today`, `rngLocked()) revert
SweepAborted`) — none key on the old `Sub` field shape, so they are NOT stale.

---

## F. Summary counts

- **Anchors checked:** 23 (20 AfKing.sol + 2 mint-streak + 1 stale-test).
- **MATCH:** 21
- **SHIFTED:** 2 — both ±1 and immaterial:
  - #7 `lastSweptDay >= today` `if` at :614 (claimed :613-621 envelope; comment is
    at :613, the `if` at :614 — within envelope).
  - #6/#16 minor: the loop top is exact at :609 and the `SubscriptionUpdated`
    NatSpec is exact at :156 (the struct opens :160). Counted as MATCH; only #7 is
    a true SHIFTED(+1).

  (Re-tallying strictly: exactly **1 SHIFTED(+1)** — anchor #7. The "loop runs to
  :745" claim is actually :744/:774, an envelope estimate the plan flagged with
  `~`, not a hard anchor.)
- **ABSENT (as predicted by the plan — these are the gaps the fix fills):**
  - No loop-top `dailyQuantity == 0` reclaim branch (#13) — **CONFIRMED ABSENT**,
    matches plan claim.
  - The plan's own description of the desired in-set tombstone behaviour is
    correctly NOT present (the IMPL swap-pops on cancel instead).
- **Unexpected ABSENT / material drift:** **NONE.** Every edit-target anchor lands
  on or within ±1 of its claimed line; the `Sub` struct, both swap-pop sites, the
  cursor read/persist, the mint-streak reset, and the stale-test panic all verify
  exactly as the plan describes.

## G. Blockers

**NONE.** The plan's anchors are accurate against HEAD. The two coordinated edits
(Edit-1 in-place tombstone at :455-468; Edit-2 loop-top reclaim mirroring the
:644/:739 no-`++cursor` pattern) and the testGas04 fix (13→31, drop 2 bools, add
`fundingSource`) all target verified, current code.

**Notes for the v47 plan-time re-grep (not blockers):**
- All line anchors will shift once the v47 batched diff lands; re-grep at
  plan-time per the plan's own footer.
- The NatSpec at :449 ("SUB-07 tombstone-on-cancel" describing a swap-pop) should
  be rewritten by Edit-1 to describe the true in-place tombstone, per
  `feedback_no_history_in_comments` (describe what IS).
- Edit-2's reclaim branch must apply the deferred `_subOf` delete-vs-preserve
  decision currently inlined at :460-467 (preserve iff
  `FLAG_WINDOW_PAID && paidThroughDay > today`, else delete).
