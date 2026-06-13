# Round 6 packet — WrappedWrappedXRP.sol (6 findings, all APPROVED)

Source verified 2026-06-12 at HEAD 4e5ef35b. Ledger bodies: audit/GAS-AUDIT-2026-06-10.md.
All cross-contract dominations RE-VERIFIED against current source (post-round-5).

## TOKENS-13 — delete dominated `amount == 0` revert in mintPrize
- Site: `if (amount == 0) revert ZeroAmount();` in `mintPrize` (currently L246).
- All 5 reachable call sites re-verified to guarantee amount != 0:
  - DegeneretteModule:426 `if (acc.wwxrpMint != 0)`
  - LootboxModule:766 `wwxrpOut = LOOTBOX_WWXRP_PRIZE` (1 ether constant)
  - LootboxModule:1318 constant `LOOTBOX_WWXRP_CONSOLATION`
  - LootboxModule:1937 constant + `if (wwxrpAmount != 0)`
  - BurnieCoinflip:582-584 `if (lossCount != 0)` × 1-ether constant (checked mul)
- Also delete: `ZeroAmount` error decl (L62-63, no other use site) + the
  `@custom:reverts ZeroAmount` natspec line (L236).
- Residual failure mode if ever reached: harmless zero-mint Transfer event.

## TOKENS-14 — remove permanently-unreachable MINTER_COIN auth branch
- Site: `msg.sender != MINTER_COIN &&` in the mintPrize gate (L241) + the
  MINTER_COIN constant + doc comment (L120-121).
- Re-verified: `grep -cin wwxrp contracts/BurnieCoin.sol` = 0 — the code at
  ContractAddresses.COIN has no path to call mintPrize. Frozen contracts ⇒ permanent.
- Keep MINTER_GAME first (dominant caller short-circuits).
- Update mintPrize dev natspec "(game/coin/coinflip contracts)" → "(game/coinflip contracts)".
- ⚠ AUTH-SET NARROWING on an immutable token — surfaced explicitly for the user diff review.
- Test check: no test pranks COIN to call wwxrp.mintPrize (grep-verified); CoverageGap222
  only asserts non-authorized rejection (unaffected).

## TOKENS-15 — delete dominated `to == address(0)` check in vaultMintTo
- Site: `if (to == address(0)) revert ZeroAddress();` (L260). `_mint` L204 carries the
  identical check; the vaultAllowance decrement rolls back on revert. Same error, same outcome.
- Natspec `@custom:reverts ZeroAddress` stays (still true via _mint).

## TOKENS-16 — delete dominated `amount == 0` early-return in vaultMintTo
- Site: `if (amount == 0) return;` (L261).
- Sole caller re-verified in CURRENT source: DegenerusVault.wwxrpMint (L660-662) guards
  `if (amount == 0) return;` at L661 before calling; L259 gate admits only VAULT. Both frozen.
- Residual if reached: allowance check passes (0 > x false), decrement no-op, zero-mint
  events — benign. With TOKENS-15 also applied, (to==0, amount==0) reverts in _mint.

## TOKENS-19 — drop non-standard Approval emission in transferFrom
- Site: `emit Approval(from, msg.sender, allowed - amount);` (L180).
- ERC-20 specifies Approval for approve() only; matches OZ 5.x. ~1,750 gas per
  finite-allowance transferFrom. Allowance stays queryable via the public mapping.
- Observable delta: event-only (third-party allowance indexers); no protocol consumer.

## TOKENS-21 — delete dominated `from == address(0)` check in _burn
- Site: `if (from == address(0)) revert ZeroAddress();` (L216).
- Sole caller burnForGame early-returns amount==0 (L281); for amount ≥ 1 the balance
  check catches from==0 because balanceOf[address(0)] is invariantly 0 (_mint L204 and
  _transfer L191 both reject to==address(0) — HARD PRECONDITION, both kept).
- Revert-shape change on an impossible input only: ZeroAddress → InsufficientBalance.
- Natspec: remove burnForGame's `@custom:reverts ZeroAddress` line (now inaccurate).

## Test impact
- No test pins ZeroAmount / MINTER_COIN / Approval-on-transferFrom / vaultMintTo
  zero-paths (grep-verified). Expect zero recalibrations from this packet.
