# Retained Coinflip, BAF and affiliate storage

This is a **new-deployment layout**, not a migration of an existing deployment. The implementation
is under verification. Native Glamsterdam comparisons are recorded in
[`GAS-CALIBRATION.md`](../scripts/audit/storage-reuse/GAS-CALIBRATION.md); final release gates remain separate.
Compiler settings remain solc 0.8.34, via IR, 1,000 optimizer runs, Osaka bytecode.

## Player behavior

Coinflip settles at most the last **90 resolved days**. Older stake and rolling carry forfeit;
already banked `claimableStored` does not expire. Claims consume days with `lastClaim` and retain
stake pages. The Game banks the Vault's winnings every 45 resolved days and at the existing x0
purchase seal. Its stamp records only a successful Game-initiated settlement. Neither daily RNG
application nor terminal resolution adds this external settlement dependency.

Affiliate scores saturate at **34,359,738,367 whole FLIP per wallet per level**. The global denominator
adds only the accepted score increase. Actual commission, kickback, quest and AFKing payouts retain
their existing inputs. Exact individual scores are retained for the latest credited level and its
predecessor. Older exact history comes from events. Five older clipped lanes preserve the activity
bonus calculation exactly: 500,000 at the minimum price already reaches its cap.

BAF retains the closing and next bracket in two alternating records. The Game finishes the closing
draw before advancing far enough to reuse its home; the recorder adds no defensive revert.
Skipped-bracket WWXRP consolation expires when its record is
reused; claiming it clears only the total and retains the tags.

## Storage readers

Let `H(key, root) = keccak256(abi.encode(uint256(key), uint256(root)))`. Read all words and tags from
the **same block**, verify the deployed runtime/schema, and resolve addresses to permanent wallet IDs.

| Record | Address and decoding |
| --- | --- |
| Coinflip ring | `page = day / 7`; `H(id, 0) + page % 15` |
| Coinflip overflow | `H(page, H(id, 9))` |
| Stake page | Seven uint32 amounts in bits 0–223; uint24 `page + 1` in 224–247; credit hint in 248–255 |
| Game Vault stamp | Slot 5, byte offset 20, uint24; all prior fields and slot 6 remain fixed |
| BAF player | `H(id, 0) + ((bracket / 10) & 1)`; uint168 total at bit 0, uint64 epoch at 168, uint24 bracket at 232 |
| Affiliate earnings | `H(id, 1)`; layout below |

For a stake read, accept the ring only if its full page tag matches. Otherwise read the absolute
overflow and require the same full tag. A missing matching tag means zero. Decode the amount at
`32 * (day % 7)`. **Readers ignore the hint.** Retained amounts behind the claim cursor are consumed,
not additional assets. Apply the 90-day cutoff and the seed window before valuing pending winnings.
Coinflip roots 1–8 and all existing packed field offsets are unchanged.
Zero-amount stake credits return before storage access and no longer emit `CoinflipStakeUpdated`.
Indexers must not depend on an event for a zero credit. At-cap nonzero inputs can still emit a zero accepted amount.

BAF readers require **both** the bracket tag and the bracket's current epoch to match. Global BAF
roots 1–3 remain unchanged. Its top board already packs two wallet-ID/uint96-score entries per word;
do not revive the older address-based decoder.

Affiliate word, with `T = uint24(word >> 165)`:

| Bits | Contents |
| --- | --- |
| 0–34, 35–69 | Exact capped score at T, T−1 |
| 70–88, 89–107, 108–126, 127–145, 146–164 | Score clipped to 500,000 at T−2 through T−6 |
| 165–188 | Latest credited level T |
| 189–220, 221–252 | Immutable upline wallet IDs |
| 253, 254 | Upline validity flags |
| 255 | Unused, zero |

Production credits target the monotonic Game level + 1. An invalid level-zero or backward target
adds no score and leaves the input word untouched without blocking commissions. Zero score does not
roll the word. A gap of seven levels retires all score lanes while preserving the cache. The public
exact-score getter returns zero outside T/T−1, including future levels. Clipped lanes are bonus
inputs only. Global `_levelScore` retains its existing root and field layout.

## Integration inventory

Raw readers in this repository use the independent fixtures `test/helpers/CoinflipStorage.sol` and
`AffiliateStorage.sol`, with BAF tests decoding tags directly. The layout goldens pin the changed
roots and preserve all unrelated slots. External repositories require corresponding changes before
pointing at the new deployment:

- Sim: `src/strategyArena/pendingFlipValue.ts`, `nativeCoinflipBacklog.ts`, `nativeBafRanks.ts`.
- Website: `app/chain/games.js`, generated `app/chain/schema.js` via `db/build-chain-schema.mjs`.
- Database: `src/utils/chain-readers.ts` and ABI synchronization via `scripts/sync-abis.mjs`.

The inspected sim readers still target older address-based/two-lane layouts. Regenerate schemas and
match runtime hashes; replacing only a root number is insufficient. This change does not edit those
other repositories or alter their existing deployments.

## Gas and verification

The calculation schedule is EIP-8037/8038: 97,920 state gas per newly created storage slot, 10,000
for the first change plus access costs, and 11,616 clearing refund. Existing initialized pages are
retained so normal future credits overwrite rather than recreate them. A live collision uses an
overflow record and a hint update; it never forces a claim or rejects credit for capacity.

`StorageReuseCreditGas` and `GlamsterdamCoinflipWalk` record production-call storage accesses and
apply that schedule. These estimates are distinct from native Glamsterdam execution. Read-only Sepolia
`eth_simulateV1` comparisons cover 27 matched calls plus daily/gap/terminal contexts. Retained-home
credits cost 35.6k versus 129.8k in the old same-window codec; new overflow credits cost 148.0k.
Craps/Growth and Degenesis per-credit reserves increased from 140k to 160k. Existing
admission reserves are not reduced based on estimates alone. Required release evidence includes
whole-call native maxima, refund/warmth checks, batch envelopes, the 90-day Vault helper, deployment
size checks, full repository suites and the independent accounting/codec comparisons.

See `.planning/STORAGE-REUSE-PLAN.md` for the design invariants and implementation work packages,
and `scripts/audit/storage-reuse/` for pinned baseline and verification evidence.

## Phase 2: retained boons, passes and redemption queues; packed rounds

Implemented after Phase 1 commits `c4c1effe5` / `dfe5fb03f`; verification is recorded
separately in `scripts/audit/storage-reuse-phase2/`. These remain new-deployment changes.

- Boon slot 1 retains bit 24 after awards, consumption and expiry. The public getter
  includes that bit; it conveys no live boon. All lane positions are unchanged and
  the box expiry gate ignores the sentinel. Slot 0 keeps its existing behavior.
- The pass/preference word retains bit 117 after its first credit. Balances and
  board encoding are unchanged. Bits 85..116 carry a wallet ID only in memory;
  `_paidDoor` truncates that ID before constructing its separate fee/account word.
- sDGNRS stores queue counts in slot 7, bytes 24..31, even parity first. Roots 9/10
  now map word index to two packed 128-bit entries: `keccak256(abi.encode(index/2,
  9+parity))`. Entries retain amount80/ID32/activity16. A finished batch resets only
  its count, retaining data for overwrite. Locators and cursors prevent stale claims;
  terminal manual claims still clear their lane. Other storage offsets are unchanged.
- Jackpot rounds occupy five words at the existing mapping root 17. `drawWord` is
  frozen during preparation; `started` becomes true only when the draw seals.
  The table and high-reserve draws use the identical frozen entropy after sealing.
  `jackpotBattleOf` returns the reordered/narrowed struct and an explicit `started`
  field: ABI consumers must regenerate this tuple before the new deployment.

Under the Glamsterdam schedule used in Phase 1, avoiding a creation saves 97,920
state gas gross. A retained boon/pass word saves 86,304 per separate-transaction
clear/recreate cycle if the foregone 11,616 clearing refund would have been fully
realized, before added instructions. Saved-board accounts already retain their pass
word, so the new bit adds no avoided creation there. Queue counts remove their own
length-slot creations; accounting in the shared word still follows its existing
lifecycle. Jackpot packing removes at most three nonzero slot creations per round,
or 293,760 state gas gross. These are operation-level bounds, not measured annual
savings or native Phase 2 benchmarks; actual savings depend on the fields written.
