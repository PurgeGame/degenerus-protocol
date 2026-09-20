# Terminal affiliate award

The terminal decimator is removed. Its burn, boost, resolution, claim, and view
functions no longer exist. The regular milestone decimator and its outstanding
claim rounds remain available, including their existing terminal claim behavior.

Terminal settlement first reserves existing claim liabilities and applies any
early-game paid-deity refunds. Of the remaining distributable ETH/stETH value:

- `floor(available / 50)` is credited as claimable ETH to the top affiliate for
  the terminal ticket level.
- The rest goes to the existing terminal ticket jackpot. Integer rounding dust
  stays in that jackpot allocation.
- If the level has no ranked affiliate, the jackpot receives the entire amount.

The affiliate uses exactly the terminal jackpot's phase-correct level: the current
level in jackpot phase or an already-promoted last-purchase transition; otherwise
the upcoming purchase level. The existing terminal cohort latch keeps that level
stable across a multi-transaction drain.

The cutoff is the transaction that latches the terminal cohort, before the terminal word
is requested. Accrued AFKing affiliate rewards claimed before that count toward the
leaderboard. Later claims can still change the leaderboard but cannot change the credited
winner, the pool the terminal draw receives, or repeat the terminal payment. Ties
retain the existing leader, matching the affiliate contract's strict-greater rule.

The award uses the game's existing claimable ledger and payout latch. The affiliate
address receives no callback during advance and needs no new claim endpoint.
`TerminalAffiliatePaid` identifies the winner, terminal level, and credited share;
the normal `PlayerCredited` event records the balance movement. Withdrawal and the
30-day final sweep retain their existing rules. Unallocated jackpot amounts from
empty trait buckets also retain their existing final-sweep treatment.

The retired storage positions 47–49 now hold `deityPassSales`, `protocolBoonPools`,
and `protocolBoonEntries`, respectively. These three fields move from slots 69–71;
all other surviving game fields retain their slots and offsets. The retired bet
and claim structs are deleted, with no reserved padding. This layout is for a new
deployment, not an in-place migration of deployed state.

The focused regressions live in `test/fuzz/TerminalAffiliatePayout.t.sol`. They
exercise real terminal advance across the four phase cases, exact funding after
claims/refunds, missing affiliates, dust, ties, the claim deadline, replay, and
recipient contracts that reject calls. The cold terminal fixtures cover 30 paid
deity refunds, all 305 jackpot award slots, and the affiliate payment together.

## Verification

September 19, 2026:

- **91 focused Foundry tests passed**, including 1,000 fuzz cases for the phase and
  payout split and the existing regular-decimator, deity, boon, and lens regressions.
  The 10 terminal-affiliate tests also pass with the final liability assertion:
  every emitted refund, affiliate, and jackpot credit is reserved exactly once.
- **131 Hardhat tests passed** across game over, FLIP, and affiliate behavior.
- Cold terminal advance uses **10,308,272 gas** with a recorded word and
  **10,396,960 gas** with a fresh word, including intrinsic gas. Both fixtures
  include 30 paid-pass refunds, 305 ticket award slots, and the affiliate credit.
- All 31 deployment contracts fit the 24,576-byte runtime limit. GAME is
  **24,226 bytes** in the Hardhat deployment build, leaving **350 bytes** of room.
- The storage-layout oracle matches all updated snapshots and verifies module
  consistency. Interface coverage and all source-based safety gates pass. Retired
  selectors are absent from the affected contract ABIs.

These are measured fixture bounds, not a proof over every reachable game state.
