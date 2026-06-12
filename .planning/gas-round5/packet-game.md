# Gas round-5 packet — DegenerusGame.sol (+ MintModule/LootboxModule counterparts)

6 findings: GAME-14, GAME-16, RT-CLAIMS-08 (APPROVED) · GAME-08, GAME-15, LOOTBOX-12 (NEEDS_HUMAN_REVIEW, adjudicated below).
Ledger line numbers are audit-time (2026-06-10) — locate all code by CONTENT. Rounds 1-4 moved things.

## Adjudications (round-5 orchestrator)

- **GAME-08 — APPLY, with mandatory verification steps.** Residual scope after round-4 MINT-04
  (the recordMintData delegatecall-back is already gone; recording is already a direct internal
  call at the self-call return point): relocate the payment processing (_processMintPayment +
  recordMint's validation) into the mint path as an internal function taking explicit
  `uint256 ethForLeg`, delete Game.recordMint + Game._processMintPayment, drop the dispatcher
  entry. Hazard class = the round-1 consumePurchaseBoost msg.value trap: EVERY msg.value read in
  the relocated body MUST become ethForLeg (a missed read binds to the OUTER purchase tx value and
  breaks Claimable-leg validation inside ETH-carrying combined purchases, e.g. the
  buyLootboxAndPresaleBox split). Verification: enumerate all msg.value reads pre-move; grep-confirm
  recordMint's sole caller is the module self-call at HEAD; re-declare ClaimableSpent/AfkingSpent in
  the module only if not already visible via the shared storage base; full payment-path test sweep.
  Solvency-accounting relocation → flag prominently in the user diff review (that review satisfies
  the skeptic's "needs the user's line-by-line diff review" condition before any commit).
- **GAME-15 — APPLY, exact guarded form only.** New storage helper
  `_debitClaimableAndAfking(address p, uint256 c, uint256 a)`: one SLOAD; explicit
  `uint128(w) < c` revert; explicit `(w >> 128) < a` revert; one SSTORE of `w - c - (a << 128)`.
  ADD the helper — never modify the existing four (modules share them). Change only the two call
  sites (claim path + relocated mint-payment shortfall path). The explicit low-half borrow guard is
  the load-bearing line: full-word checked math is blind to a low-half borrow.
- **LOOTBOX-12 — APPLY (subsumes RT-CLAIMS-08).** The skeptic's pre-existing-correctness blocker
  (payable Game fn delegatecalling non-payable module fn) was found independently and FIXED in
  403afc62 (2026-06-11, REDEMPTION-PAYABLE) — verify the module external is payable at HEAD, then
  proceed. Move the full Game.resolveRedemptionLootbox body into LootboxModule as the payable
  external (auth → msg.value bound → stETH pull → frozen/unfrozen pool credit → chunk loop with
  per-chunk `rngWord = keccak256(abi.encode(rngWord))` rehash, byte-identical order); per-chunk
  resolver becomes a private helper called in a plain internal loop (NO this.-calls); Game function
  becomes the same `delegatecall(msg.data)` thin stub as creditRedemptionDirect. External signature
  (consumed by StakedDegenerusStonk) unchanged. RNG seed chain identical.
- **RT-CLAIMS-08 — APPLIED VIA LOOTBOX-12** (the in-module loop is the same elision, plus the
  bigger bytecode win). No separate change.

## Sequencing
1. LOOTBOX-12 first (independent region), 2. GAME-08 relocation, 3. GAME-14 + GAME-15 applied to the
relocated payment body (GAME-14's merged pool debit uses the checked uint128+uint128 form; GAME-16
uses the loop-peel form per skeptic).

## Ledger bodies

#### GAME-14 — contracts/DegenerusGame.sol (L1104-L1117)
**Category:** redundant_sload · **Frequency:** hot · **Confidence:** high · **Batch:** game

_processMintPayment performs two separate checked `claimablePool -= ...` storage read-modify-writes when a mint draws from BOTH claimable and afking (L1105 and L1115). claimablePool is one slot; the second subtraction re-loads and re-stores it (warm SLOAD 100 + dirty-slot SSTORE 100 + checked-math overhead).

**Change:** Combine: `uint256 poolDebit = claimableUsed + afkingUsed; if (poolDebit != 0) claimablePool -= uint128(poolDebit);` placed before the two (unchanged, separately-conditioned) event emissions. Identical revert behavior: the sum underflows exactly when sequential subtraction would.

**Savings:** runtime ~150-250 gas on combined claimable+afking-funded mints; 0 on single-source mints. Subsumed by GAME-08 if that lands (the logic moves either way) · bytecode ~20-40 bytes · skeptic-revised: ~200 gas, ONLY on mints that draw from both claimable and afking tiers (warm SLOAD 100 + warm dirty SSTORE 100); 0 on single-source mints; ~20-40 bytes

**Skeptic (APPROVED, risk low, invariant impact none):** Verified at L1104-1117: two separate checked `claimablePool -= uint128(...)` read-modify-writes of the same slot-1 field when a mint draws both claimable and afking. Merging is behaviorally identical with one correction to the proposed code: `uint128(poolDebit)` where poolDebit = claimableUsed + afkingUsed could in principle silently truncate (each addend is bounded by a uint128 balance half, so the uint256 sum can exceed 2^128 only at physically impossible ETH amounts — but do not encode a silent-truncation pattern into the solvency ledger). Use `claimablePool -= uint128(claimableUsed) + uint128(afkingUsed);` — the checked uint128 addition reverts exactly when sequential subtraction would (pool < 2^128 always), preserving revert semantics with zero truncation window. Event conditions, contents, and relative order are unchanged (both emits stay in their own if-blocks after the single subtraction).

**Implementation notes:** Keep checked math; use the checked uint128+uint128 form above (NOT a uint256-sum cast). Note this site is deleted wholesale if GAME-08 lands — sequence accordingly.

**Finder risk notes:** Solvency-accounting line — keep checked math (no unchecked); uint128 cast of the sum is safe (both addends are <= a uint128-tracked pool and the subtraction reverts on excess). Event ordering/contents unchanged.


#### GAME-16 — contracts/DegenerusGame.sol (L1742-L1749)
**Category:** redundant_sload · **Frequency:** warm · **Confidence:** high · **Batch:** game

degeneretteResolve reads degeneretteBets[players[0]][betIds[0]] for the probe (L1744), then the loop's first iteration re-reads the identical slot at L1749 (warm, +100 gas) — the code comment even acknowledges 'reusing the SLOAD item 0 needs anyway', but the reuse is not actually implemented.

**Change:** Drop the pre-loop probe and move the check into the loop: `uint256 betPacked = degeneretteBets[players[i]][betIds[i]]; if (i == 0 && betPacked == 0) revert BatchAlreadyTaken();` — one SLOAD serves both purposes.

**Savings:** runtime ~100 gas per degeneretteResolve call (+ ~15 for the i==0 branch cost; net ~85) · bytecode ~20-30 bytes · skeptic-revised: ~85 gas/call with the peel form at any batch size; with the proposed in-loop branch, ~85 gas for <8 items decaying to ~0/negative for larger batches

**Skeptic (APPROVED, risk low, invariant impact none):** Verified at L1735-1765: the empty-array counterexample is already covered — `if (len == 0 || betIds.length != len) revert E();` (L1740) runs BEFORE the probe, so folding the probe into iteration 0 cannot skip the check on empty input. The probe slot (L1744) and the loop's first read (L1749) are the identical mapping slot with nothing executing in between, and the merged form reverts at i==0 before the first try/external call, so no state is written before the same BatchAlreadyTaken revert. However the savings claim needs revision: the per-iteration `i == 0 &&` branch costs ~10-15 gas on EVERY iteration, so the net ~85 gas win at small batches decays to roughly zero around 8 items and goes slightly negative for larger keeper batches — which is the realistic usage shape for a permissionless batch resolver. Safe, but marginal value; prefer the loop-peel form or skip.

**Implementation notes:** If implemented, peel iteration 0 out of the loop (read slot, check ==0 revert, then resolve item 0, then loop from 1) instead of an in-loop `i == 0` branch — that keeps the +~85 gas for all batch sizes at the cost of ~40-60 bytes. Honest assessment: lowest-value approved item in this batch.

**Finder risk notes:** Revert-before-loop becomes revert-on-first-iteration — externally identical (same error, no state written before it). The loser-gas-cap property is preserved.


#### RT-CLAIMS-08 — contracts/DegenerusGame.sol (L1971-L1991 (resolveRedemptionLootbox chunk loop))
**Category:** redundant_external_call · **Frequency:** warm · **Confidence:** medium · **Batch:** flow-claims

The Game's resolveRedemptionLootbox issues ONE DELEGATECALL PER 5-ETH CHUNK (abi.encodeWithSelector + delegatecall + revert-bubble per iteration). A 25 ETH redemption pays ~4 avoidable delegatecall round-trips (~1.5-2.5k gas each: call stipend, calldata encode, memory expansion, module dispatch). The per-chunk seed rehash (`rngWord = keccak256(abi.encode(rngWord))`) and per-chunk module body are pure logic that can run inside the module unchanged.

**Change:** Add a module entrypoint `resolveRedemptionLootboxes(address player, uint256 totalAmount, uint256 rngWord, uint16 activityScore)` that contains the identical while-loop (5 ether chunking, identical per-chunk seed rehash order, calling the existing resolveRedemptionLootbox body internally per chunk), and have the Game make a single delegatecall. The Game's EXTERNAL signature (consumed by StakedDegenerusStonk L794) stays unchanged - only the internal loop relocates. Bonus: removes the loop + encode from the EIP-170-constrained Game bytecode.

**Savings:** runtime ~1,500-2,500 gas per chunk beyond the first (0 for redemptions <= 5 ETH; ~6-10k for a 25 ETH claim) · bytecode ~80-150 removed from DegenerusGame (strategic: Game is near the EIP-170 ceiling); module grows correspondingly · skeptic-revised: ~1,000-2,000 gas per chunk beyond the first (0 for <=5 ETH claims); ~80-150 bytes off the EIP-170-constrained Game — the Game-bytecode relief is the primary value

**Skeptic (APPROVED, risk medium, invariant impact none):** Cross-contract trace verified: the Game's resolveRedemptionLootbox has exactly one external caller (StakedDegenerusStonk.sol L794) whose payable signature stays untouched; the module side already exposes resolveRedemptionLootbox in IDegenerusGameModules.sol (L362) and the new batch entrypoint is a straightforward interface addition. The per-chunk delegatecall loop (Game L1971-1991) is pure plumbing: the funding mix (msg.value + stETH pull L1954-1958) and pool credit (L1963-1969) complete BEFORE the loop and stay in the Game, so CEI/solvency ordering is unchanged. Size check from artifacts: Game at 23,709/24,576 (867 bytes headroom — every byte removed is strategic), LootboxModule at 16,844 (~7.7KB headroom, absorbs the loop easily). The chunking (5 ether) and seed rehash order (rngWord = keccak256(abi.encode(rngWord)) AFTER each chunk) must be reproduced byte-identically — mechanical, and the existing redemption-chunk tests are the oracle.

**Implementation notes:** New module external resolveRedemptionLootboxes wrapping the existing body via an internal sibling (do NOT use this.-calls inside the module — that would be a CALL switching storage context). Game keeps the SDGNRS gate, value checks, stETH pull, and pool credit, then makes one delegatecall. Add the selector to IDegenerusGameModules. Note this edits a mainnet Game function — falls under the contract-approval gate.

**Finder risk notes:** Must reproduce the chunking and rehash order byte-identically so every chunk's seed and EV-cap draw matches today's outcomes. The funding/pool-credit logic (msg.value + stETH pull + futurePrizePool credit) stays in the Game before the delegatecall, unchanged. Requires an interface addition to IDegenerusGameModules.


#### GAME-08 — contracts/DegenerusGame.sol (L489-L523, L1043-L1118, L1162-L1178)
**Category:** redundant_external_call · **Frequency:** hot · **Confidence:** medium · **Batch:** game

Hot-path round trip on every ticket/lootbox purchase: MintModule (already executing in the Game's storage via delegatecall) makes a value-carrying external self-call IDegenerusGame(address(this)).recordMint{value: value}(...) (DegenerusGameMintModule.sol:1703) purely to re-scope msg.value for _processMintPayment; recordMint then delegatecalls BACK into the same MintModule for recordMintData (_recordMintDataModule). The self-CALL with nonzero value costs ~9,000 G_callvalue (minus 2,300 stipend ≈ net 6,700) for a no-op self-to-self ETH move, plus encode/dispatch (~400-700), plus the return-trip delegatecall encode/dispatch (~500-800). recordMint's only caller anywhere is MintModule:1703 (grep-verified).

**Change:** Relocate the recordMint body (payment-mode validation + pool split + claimablePool/event accounting, i.e. _processMintPayment) into MintModule (or into the shared DegenerusGameMintStreakUtils base) as an internal function taking an explicit `uint256 ethForLeg` parameter instead of reading msg.value; recordMintData becomes a plain internal call inside MintModule. Then delete recordMint, _processMintPayment, and _recordMintDataModule from DegenerusGame.sol (re-declare ClaimableSpent/AfkingSpent events in the module — delegatecall emits from the Game address, logs identical).

**Savings:** runtime ~7,500-9,000 gas per direct-ETH purchase; ~1,500-2,500 per claimable/afking-funded purchase (no G_callvalue). This is the largest per-call runtime item found — player-paid on every mint · bytecode ~600-1,000 bytes off the Game (recordMint + _processMintPayment + _recordMintDataModule + dispatcher entries); MintModule grows correspondingly (it has headroom relative to the Game) · skeptic-revised: ~6,700-8,500 gas per direct-ETH purchase; ~1,500-2,500 per claimable/afking-funded purchase; ~600-1,000 bytes off the Game

**Skeptic (NEEDS_HUMAN_REVIEW, risk medium, invariant impact possible):** Every factual claim verified: MintModule:1703 is the SOLE caller of recordMint (grep-confirmed, including interfaces); the value-carrying self-CALL exists purely to re-scope msg.value for _processMintPayment (Game L1043-1118), which reads msg.value at L1053/1056/1070-1072; recordMint then delegatecalls back into MintModule via _recordMintDataModule (L1162-1178) whose target recordMintData lives at MintModule:179; the pool helpers (_get/_setPrizePools, _get/_setPendingPools, prizePoolFrozen) are all in DegenerusGameStorage (:718-:736, :328) and accessible to the module; the events (ClaimableSpent L1532, AfkingSpent) re-declare cleanly and delegatecall emits from the Game address. The savings math checks out (~6,700 net for the nonzero-value self-CALL after stipend + ~1,000-1,500 encode/dispatch/return-trip = ~7,700-8,500 per direct-ETH mint; ~1,500-2,500 for claimable/afking-funded). This is the single largest per-call runtime item in the batch AND it relocates the mint-payment solvency accounting (claimablePool tandem debits, claimable sentinel, prize-pool split) with a semantic pivot (every msg.value read must become the explicit ethForLeg parameter — one missed read silently binds to the OUTER purchase tx's msg.value and breaks payment validation). Per the hard floor, a change rewriting solvency-accounting code cannot be self-approved here; it needs the user's line-by-line diff review.

**Counterexample:** Not a refutation — a hazard: in the relocated copy, leaving ANY msg.value read intact (e.g. the Claimable branch's `if (msg.value != 0) revert E()` at L1056) changes its meaning from 'this leg's allocated value' to 'the whole purchase tx value', which would wrongly revert Claimable legs inside ETH-carrying combined purchases (e.g. the buyLootboxAndPresaleBox split path).

**Implementation notes:** If pursued: replace ALL msg.value reads with ethForLeg; pass the exact `value` MintModule:1703 computes; keep checked math on claimablePool; re-declare ClaimableSpent/AfkingSpent in the module with identical signatures; copy PURCHASE_TO_FUTURE_BPS (private in Game L157); convert recordMintData to a direct internal call; preserve the freshEth computation at MintModule:1715 (it re-reads _claimableOf rather than using recordMint's return — keep or provably simplify, separately). Mandatory: full payment-path test sweep (DirectEth overpay, Claimable sentinel, Combined partial, afking shortfall revert) + the existing mint-event assertions.

**Finder risk notes:** Touches solvency accounting (claimablePool, prize pools) — logic must move byte-equivalently with msg.value replaced by the explicit leg value the caller already computes. The msg.value re-scoping semantics (DirectEth overpay-ignored, Combined msg.value<=amount) must be reproduced exactly on the parameter. The Skeptic should diff _processMintPayment line-by-line against the relocated copy and confirm MintModule:1703 is the sole call site (verified here) including the buyLootboxAndPresaleBox leg-split path.


#### GAME-15 — contracts/DegenerusGame.sol (L1569-L1596 and L1043-L1101)
**Category:** redundant_sload · **Frequency:** warm · **Confidence:** medium · **Batch:** game

balancesPacked[player] packs claimable (low 128) and afking (high 128) into ONE slot (DegenerusGameStorage.sol:428), but _claimWinningsInternal touches that slot up to 6 times: _claimableOf (SLOAD), _afkingOf (SLOAD), _debitClaimable (SLOAD + check + SSTORE), _debitAfking (SLOAD + SSTORE). Same multi-touch pattern in _processMintPayment's claimable-then-afking tiers (L1057/1074 read, L1065/1084 debit re-read+write, L1098 read, L1100 debit re-read+write). A single read -> compute both halves -> single write does the same work with 1 SLOAD + 1 SSTORE.

**Change:** Add a combined helper in DegenerusGameStorage (layout-neutral — helpers don't move slots), e.g. `_debitClaimableAndAfking(address p, uint256 c, uint256 a)` doing one load, both checks, one store; use it in _claimWinningsInternal (post-gameOver branch) and in _processMintPayment's shortfall path. Keep per-half underflow checks byte-equivalent.

**Savings:** runtime ~200-400 gas per claim / per multi-tier mint payment (3-4 warm SLOADs + 1 dirty SSTORE eliminated) · bytecode ~0 net (new helper offsets removed call sequences) · skeptic-revised: ~100 gas per pre-gameOver claim; ~400 per post-gameOver claim and per dual-tier mint payment; ~0 bytecode net

**Skeptic (NEEDS_HUMAN_REVIEW, risk medium, invariant impact possible):** Claims verified: balancesPacked packs afking(high128)|claimable(low128) (DegenerusGameStorage:417-428); _claimWinningsInternal (Game L1569-1589) touches that one slot up to 4 SLOADs + 2 SSTOREs via _claimableOf/_afkingOf/_debitClaimable/_debitAfking (storage :902-:938), all straight-line BEFORE the external payout (CEI preserved, no reentrancy window between touches); _processMintPayment has the same multi-touch shape. A combined load-check-both-store-once helper is equivalence-PROVABLE — but the helper must replicate the low-half borrow guard exactly (storage:919-923: `uint128(packed) < amount` revert BEFORE full-word subtract), because 0.8's full-word checked math is explicitly blind to a low-half borrow (the existing comment says so). A naive `packed - c - (a<<128)` silently corrupts the afking half — a solvency-ledger corruption, the exact bug class the current helpers were written to prevent. Given the modest saving (~100 gas pre-gameOver claims, ~400 on gameOver claims / dual-tier mints) against the highest-sensitivity ledger in the system, this is a user sign-off decision, not a Skeptic auto-approve.

**Counterexample:** Not a refutation — the hazard: implementing the combined debit as a single full-word checked subtraction without the explicit low-half (`uint128(packed) >= c`) guard lets a claimable debit borrow from the afking half without reverting whenever afking > 0, silently moving another bucket's ETH.

**Implementation notes:** If approved: new storage helper `_debitClaimableAndAfking(address p, uint256 c, uint256 a)` = one SLOAD; `if (uint128(w) < c) revert E();` ; `if ((w >> 128) < a) revert E();` ; one SSTORE of `w - c - (a << 128)`. ADD the helper (never modify the existing four — many modules share them); change only the two Game call sites. Layout-neutral (functions do not move slots).

**Finder risk notes:** Touches the claimable/afking solvency ledger — the v61-packed slot whose helpers many modules share. Adding (not changing) helpers keeps existing module behavior intact; only the two Game call sites change. Checked-math revert semantics must match the sequential debits exactly.


#### LOOTBOX-12 — contracts/DegenerusGame.sol (DegenerusGame.sol L1943-L1992 (with module counterpart L866-L892, L903-L914))
**Category:** bytecode_dedup · **Frequency:** warm · **Confidence:** medium · **Batch:** lootbox

Game.resolveRedemptionLootbox carries a full body in the size-critical Game: SDGNRS auth, msg.value/stETH funding-mix pull, prize-pool credit, and a 5-ETH chunk loop that issues one DELEGATECALL to this module PER CHUNK (a 50 ETH redemption = 10 delegatecalls, each with selector encoding + revert plumbing). The sibling entrypoint creditRedemptionDirect already uses the thin-stub pattern (Game L2002-2007: forward msg.data via one delegatecall; body lives in this module at L903-914). The module already has everything the body needs: steth (L156), _getPrizePools/_setPendingPools (storage base L718-736), and the per-chunk resolver as an internal path.

**Change:** Move the body of Game.resolveRedemptionLootbox into this module as the external resolveRedemptionLootbox (absorbing the current per-chunk function as a private helper called in a plain internal loop), and reduce the Game function to the same `delegatecall(msg.data)` stub as creditRedemptionDirect. The N per-chunk delegatecalls become internal calls.

**Savings:** runtime ~800-1200 per chunk beyond the first (delegatecall frame + abi encode + returndata copy); a 50 ETH redemption claim saves ~8-11k · bytecode ~300-600 off DegenerusGame runtime bytecode (strategic: Game is near the EIP-170 ceiling); module grows ~similar amount · skeptic-revised: ~500-1000 gas per chunk beyond the first (the 800-1200 estimate is high for a warm delegatecall; abi-encode + frame + returndata is closer to 500-800) + ~300-600 bytes off the size-critical Game.

**Skeptic (NEEDS_HUMAN_REVIEW, risk medium, invariant impact possible):** The dedup claim itself verifies: Game L1943-1992 carries the full body with one delegatecall per 5-ETH chunk; the sibling creditRedemptionDirect already uses the thin-stub pattern (Game L2002-2007 / module L903-914); the module has steth and the pool helpers. Real Game-bytecode lever. HOWEVER, validation surfaced a pre-existing correctness concern in this exact flow that must be resolved by humans BEFORE any restructure: the Game's payable resolveRedemptionLootbox delegatecalls the module's NON-payable resolveRedemptionLootbox (module L866, interface L362 — non-payable) while msg.value can be non-zero (StakedDegenerusStonk L793-794 sends value ethForLootbox = min(balance, lootboxEth)). DELEGATECALL preserves msg.value into the callee frame, and solc's non-payable dispatch enforces callvalue()==0 — so every chunk delegatecall should revert whenever sDGNRS forwarded ANY ETH, stranding live-game redemption claims until the sDGNRS ETH balance is zero. The test suite does not contradict this: RedemptionStethFallback.t.sol L118-122 mocks the Game-side call and V62RedemptionReentrancy.t.sol L112-114 mocks the module-side selector, so the real module body never executes with msg.value>0 in tests. The payable sibling creditRedemptionDirect (module L903 IS payable) suggests the asymmetry is an oversight. If confirmed, the minimal fix (make the module function payable) and the LOOTBOX-12 restructure overlap — but this is a correctness decision on a solvency-path mainnet contract, with exact ordering (auth -> msg.value bound -> stETH pull -> frozen/unfrozen pool credit -> chunked rngWord rehash) to preserve, requiring explicit approval and an unmocked end-to-end test.

**Implementation notes:** Sequence: (1) human-verify the non-payable-under-delegatecall behavior with an unmocked test (sDGNRS holding ETH, live-game claim through the REAL module); (2) decide minimal-payable-fix vs full LOOTBOX-12 restructure; (3) if restructuring, the module external must be payable, absorb the per-chunk function as a private helper, and keep the per-chunk rngWord keccak rehash (Game L1990) byte-identical.

**Finder risk notes:** Touches mainnet Game (commit approval required). Must preserve EXACT ordering: auth -> msg.value bound -> stETH pull -> pool credit (frozen/unfrozen branch) -> chunked resolution with the same per-chunk rngWord rehash (L1990). msg.value forwards correctly through delegatecall. Verify the module has EIP-170 headroom for the added body. No RNG-derivation change: identical seed chain.


