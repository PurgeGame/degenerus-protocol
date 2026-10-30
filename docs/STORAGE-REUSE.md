# Retained storage layouts

Several per-account records keep their storage word after use, so later writes overwrite a nonzero
slot instead of creating one. This page gives the behavior and the raw-read layouts. The layout
goldens in `scripts/layout/golden/` pin the compiler slots. [Storage packing](STORAGE-PACKING.md)
includes the bit fields and compiler-derived struct layouts.

## Player behavior

Coinflip settles at most the last **90 resolved days** (`COIN_CLAIM_DAYS`). Older stake and rolling
carry forfeit; banked `claimableStored` does not expire. Claims consume days with `lastClaim` and
keep the stake pages. The Game banks the Vault's winnings every 45 resolved days and at the x0
purchase seal; its stamp (`vaultFlipSettledDay`) records only a successful Game-initiated
settlement. Neither daily RNG application nor terminal resolution depends on this external
settlement.

Affiliate scores saturate at **34,359,738,367 whole FLIP per wallet per level** (2^35 − 1). The
global denominator adds only the accepted score increase. Commission, kickback, quest and AFKing
payouts use the uncapped inputs. Exact individual scores are kept for the latest credited level and
its predecessor; older exact history comes from events. Five older lanes clipped to 500,000 feed the
activity bonus exactly: 500,000 at the minimum price already reaches the bonus cap (25 ETH of
weighted volume).

BAF keeps the closing and next bracket in two alternating records. The Game finishes the closing
draw before it can reach the bracket that reuses that record; the recorder has no revert for it.
Skipped-bracket WWXRP consolation expires when its record is reused; claiming it clears only the
total and keeps the tags.

## Storage readers

Let `H(key, root) = keccak256(abi.encode(uint256(key), uint256(root)))`. Read all words and tags
from the **same block**, verify the deployed runtime, and resolve addresses to permanent wallet IDs.

| Record | Address and decoding |
| --- | --- |
| Coinflip ring (`coinflipStakeRing`, root 0) | `page = day / 7`; `H(id, 0) + page % 15` |
| Coinflip overflow (`coinflipStakeOverflow`, root 9) | `H(page, H(id, 9))` |
| Stake page | Seven uint32 amounts in bits 0–223; uint24 `page + 1` in 224–247; overflow hint in 248–255 |
| Game Vault stamp | `vaultFlipSettledDay`: Game slot 4, byte offset 20, uint24 |
| BAF player (`bafPlayer`, root 0) | `H(id, 0) + ((bracket / 10) & 1)`; uint168 total at bit 0, uint64 epoch at 168, uint24 bracket at 232 |
| Affiliate earnings (`affiliateCoinEarned`) | `H(id, R + 1)`, where `R` is the affiliate's ERC-7201 namespace root (`AFFILIATE_STORAGE_ROOT`); layout below |

For a stake read, accept the ring only if its full page tag matches. Otherwise read the overflow and
require the same full tag. A missing matching tag means zero. Decode the amount at `32 * (day % 7)`.
**Readers ignore the hint.** Retained amounts behind the claim cursor are consumed, not additional
assets. Apply the 90-day cutoff and the seed window before valuing pending winnings. A zero-amount
stake credit returns before storage access and emits no `CoinflipStakeUpdated`; a nonzero credit at
the daily cap emits a zero accepted amount.

BAF readers require **both** the bracket tag and the bracket's current epoch to match. The global
BAF state is roots 1–3 (`bafLevel`, `lastBafResolvedDay`/`bafTopLevels`, `bafTop`); the top board
packs two wallet-ID/uint96-score entries per word.

Affiliate word, with `T = uint24(word >> 165)`:

| Bits | Contents |
| --- | --- |
| 0–34, 35–69 | Exact capped score at T, T−1 |
| 70–88, 89–107, 108–126, 127–145, 146–164 | Score clipped to 500,000 at T−2 through T−6 |
| 165–188 | Latest credited level T |
| 189–220, 221–252 | Immutable upline wallet IDs |
| 253, 254 | Upline validity flags |
| 255 | Unused, zero |

Production credits target the monotonic Game level + 1. A level-zero or backward target adds no
score and leaves the word untouched without blocking the commission. A zero score does not roll the
word. A gap of seven or more levels clears all score lanes and keeps the cache. The exact-score
getter returns zero outside T/T−1, including future levels. Clipped lanes are bonus inputs only. The
global `_levelScore` words are separate (`AffiliateEarningsLib`, `DegenerusAffiliate`).

The test fixtures `test/helpers/CoinflipStorage.sol` and `test/helpers/AffiliateStorage.sol` decode
these records independently; BAF tests decode the tags directly.

## Other retained words

- Boon slot 1 keeps bit 24 (`BP_SLOT1_RETAINED`) after awards, consumption and expiry. The public
  getter includes that bit; it conveys no live boon, and the box expiry gate ignores it.
- The craps pass/preference word keeps bit 118 (`CrapsPreferenceLib.RETAINED`) after its first
  credit. Bits 86..117 carry a wallet ID only in memory; `_paidDoor` truncates that ID before
  building its separate fee/account word.
- sDGNRS stores redemption queue counts in slot 6, bytes 24..31 (`_batchPlayerCounts`, even parity
  in the low 32 bits). Roots 8/9 (`_batchPlayers[parity]`) map word index to two packed 128-bit
  entries: `keccak256(abi.encode(index / 2, 8 + parity))`. Entries hold amount80/ID32/(activity + 1)16. A
  finished batch resets only its count; its data is overwritten by the next batch. Locators and
  cursors prevent stale claims; terminal manual claims clear their lane.
- Jackpot battle rounds occupy five words each in the fixed `_jackpotRounds` array
  (`JackpotRound[512]`, CrapsBattle slot 271). `drawWord` is frozen during preparation; `started`
  becomes true only when the draw seals, and the table and high-reserve draws use the same frozen
  entropy after sealing. `jackpotBattleOf` returns this struct with an explicit `started` field.
