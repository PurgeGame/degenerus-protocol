# Round 7 packet — DegenerusAdmin.sol + DegenerusDeityPass.sol

Source verified 2026-06-12 at round-6 HEAD 307d5312. Ledger bodies: audit/GAS-AUDIT-2026-06-10.md.

## ADMIN-06 (APPROVED) — skip discarded valuation work while no feed is configured
- Site: onTokenTransfer (L995-1039). Today getSubscription + _linkRewardMultiplier run on
  EVERY donation even when linkEthPriceFeed == address(0) (deploy default — rewards
  disabled until a governance feed-swap installs one); the work is always discarded
  (linkAmountToEth returns 0 → return at the zero check).
- Shape (single funding leg, no duplication):
  `address feed = linkEthPriceFeed;` after the subId/gameOver checks; compute
  `mult` only `if (feed != address(0))` (getSubscription → _linkRewardMultiplier,
  exact current ordering); funding transferAndCall stays UNCONDITIONAL; the existing
  `if (mult == 0) return;` then also covers the feed-unset path.
- Outcome-equivalent on every path: feed==0 today yields ethEquivalent==0 → return with
  no credit/no event; now returns at mult==0 right after the funding leg. mult is still
  computed from the PRE-donation balance when feed != 0.

## ADMIN-05 (APPROVED) — internalize the linkAmountToEth try/catch self-call
- Site: `try this.linkAmountToEth(amount)` (L1024) — a full external self-CALL purely
  for try/catch; the file already uses internal try/catch in _feedStallDuration/_feedHealthy.
- New `_linkAmountToEth(uint256 amount, address feed) private view returns (uint256)`:
  try/catch ONLY around IAggregatorV3(feed).latestRoundData(), same validation chain
  (answer<=0 / updatedAt==0 / answeredInRound<roundId / future / LINK_ETH_MAX_STALE),
  and the MANDATORY pre-multiplication overflow guard
  `if (amount > type(uint256).max / a) return 0;` (replicates the old
  checked-mul-revert→catch→return outcome for an absurd governance-installed feed answer).
- onTokenTransfer: `uint256 ethEquivalent = _linkAmountToEth(amount, feed);` (feed from
  ADMIN-06's cached load — read ordering moves from after to before the transferAndCall;
  divergence requires a governance-installed hostile coordinator reentering during
  transferAndCall, outside the trust boundary per the skeptic).
- External linkAmountToEth KEPT as a thin wrapper (`return _linkAmountToEth(amount,
  linkEthPriceFeed);`) — off-chain use unconfirmed, ABI surface preserved. Accepted
  delta: the external view now returns 0 instead of reverting on the absurd-answer
  overflow (view-only, zero on-chain callers).

## ADMIN-10 (APPROVED) — governance dedup: shared active-guard + void-loop storage pointer
- Sites: 1-active-proposal guards (proposeFeedSwap L496-503 vs propose L666-673) and the
  void loops (_executeFeedSwap L616-625 vs _voidAllActive L942-954, each deriving the
  mapping slot twice per killed entry).
- Edits: extract `_revertIfActive(ProposalState state, uint40 createdAt, uint256 lifetime)
  private view`; in both void loops cache `... storage q = ...[i];` per iteration.
  Order of checks, events, watermark updates unchanged. NO struct unification.

## DEITY-01 (APPROVED) — external renderer first in tokenURI
- Site: tokenURI — _renderSvgInternal always runs, then the result is discarded when the
  external renderer succeeds nonempty.
- Invert: try external first when renderer != address(0); call _renderSvgInternal only
  when renderer unset, call failed, or returned empty. Byte-identical output per path
  (_renderSvgInternal is effect-free). 0 on-chain gas (no on-chain tokenURI caller —
  eth_call/marketplace only).

## Test impact
- None expected (no revert/event surface changes on reachable paths).
