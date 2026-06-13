# Round 6 packet — DegenerusGameBingoModule.sol (4 live edits, 1 already-applied)

Source verified 2026-06-12 at HEAD 4e5ef35b.

## SMALLMODS-03 (APPROVED) — hoist loop-invariant mapping hash in claimBingo
- Site: the 8-iteration ownership loop (L139-149). `traitBurnTicket[level]` keccak
  recomputed per iteration (solc LICM cannot hoist keccak256); `(quadrant << 6) | symInQ`
  also loop-invariant.
- Hoist `address[][256] storage levelBuckets = traitBurnTicket[level];` and
  `uint256 traitBase = (uint256(quadrant) << 6) | uint256(symInQ);` before the loop;
  inside: `levelBuckets[uint8(traitBase | (c << 3))]`.
- Bit-disjointness exact: quadrant<<6 = bits 6-7, c<<3 = bits 3-5, symInQ = bits 0-2;
  max 255 so the uint8 cast is lossless. Loop is strictly read-only, no external calls.
- Keep the `slot >= holders.length` guard exactly as-is. ~300-450 per claimBingo.

## SMALLMODS-05 (APPROVED) — cache firstQuadrant/firstSymbol, plain assignments
- Site: tier cascade (L160-175). fq/fs each SLOADed for the booleans then re-SLOADed by
  the `|=` RMWs; the intervening firstQuadrant SSTORE defeats conservative cross-keccak
  aliasing analysis, so the saving is real.
- Cache `uint8 fq = firstQuadrant[level]; uint32 fs = firstSymbol[level];` (types match
  storage decls at Storage:1825/1829), derive both booleans from the caches, replace the
  three `|=` with plain assignments (`fq | qMask`, `fs | sMask`) — bit-identical values
  (distinct base slots; no other writer in the tx frame).
- CEI unchanged: effects still complete before dgnrs/coinflip interactions.

## SMALLMODS-08 (APPROVED) — collapse _requireApproved into _resolvePlayer
- Site: L267-279. _requireApproved's `msg.sender != player` first conjunct is dominated
  by its sole caller (_resolvePlayer invokes it under `player != msg.sender`).
- Inline: `if (player == address(0)) return msg.sender; if (player != msg.sender &&
  !operatorApprovals[player][msg.sender]) revert NotApproved(); return player;`
  Delete _requireApproved. Input-equivalent on all three cases (zero/self/operator);
  operator-approval semantics (USER-locked trust boundary) unchanged.
- Update the section comment (L204-205) that names both helpers.

## SMALLMODS-09 (APPROVED) — drop unused parent inheritance
- Change `contract DegenerusGameBingoModule is DegenerusGamePayoutUtils,
  DegenerusGameMintStreakUtils` → `is DegenerusGameStorage`; swap imports.
- Re-verified against CURRENT source: every member the module uses is declared in
  DegenerusGameStorage (coinflip:127, affiliate:131, dgnrs:133, PRICE_COIN_UNIT:148,
  gameOver:271, traitBurnTicket:427, mintPacked_:436, operatorApprovals:1099,
  affiliateDgnrs*:1110-1118, bingo bitfields:1825-1829, level, error E); BitPackingLib +
  PriceLookupLib imported directly. Both parents are storage-free abstracts over
  DegenerusGameStorage (verified) — layout cannot shift.
- methodIdentifiers delta: loses ONLY curseCountOf (the external fn at
  MintStreakUtils:410). No test calls curseCountOf on the module address (grep-verified;
  V61 fuzz suites call it on the Game, which keeps MintStreakUtils).
- MANDATORY post-edit gates: `forge inspect DegenerusGameBingoModule storageLayout`
  byte-identical pre/post; methodIdentifiers diff = {curseCountOf} only.

## ALREADY APPLIED — no edit (stale ledger entry)
- SMALLMODS-17: both Game stubs already forward msg.data with unnamed params —
  claimBingo (DegenerusGame.sol:317-326) and claimAffiliateDgnrs (:1292-1297), with
  natspec documenting the selector-parity contract. Applied in an earlier round
  (round-1 msg.data forwarding family). Ledger → Handled as already-applied.

## Test impact
- No source-pin tests grasp BingoModule functions (grep-verified).
- DeployCanary/DeployProtocol reference GAME_BINGO_MODULE for deploy plumbing only.
