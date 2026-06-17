# Adversarial Delegatecall-Integrity Review — Degenerus Protocol spinal column (v67.0 phase 419 DELEGATE)

You are an independent senior smart-contract auditor reviewing **delegatecall integrity** on a real-money on-chain ETH game. Read-only; subject = the FROZEN `contracts/` tree at git `4921a428` in this repo. Cite `file:line`. Assume **honest admin/governance** (key-compromise out of scope).

## The structure under test

`DegenerusGame.sol` dispatches to 13 modules in `contracts/modules/*` via **`delegatecall`** — each module executes IN THE GAME'S STORAGE CONTEXT (it inherits the shared `contracts/storage/DegenerusGameStorage.sol` base). So a module's storage writes land in the GAME's slots, and any layout drift, mis-shifted packed write, nested-`msg.value` mishandling, or swallowed module revert silently corrupts the Game.

**CLAIM (find any reachable counterexample):**
1. **Storage-layout alignment (DELEGATE-01):** every one of the 13 modules writes only the Game-storage slot/offset it intends — no module writes a slot the Game uses for a different variable. The modules pack via `BitPackingLib` shifts; verify the shifts/masks match the slot/offset table for the multi-module packed slots (0, 1, 5, 7, 9, 34, 40, 51, 54). Module storage layouts: `forge inspect <Module> storageLayout`; Game layout: `.planning/phases/417-colmap-re-derive-call-graph/417-game-storage-layout.json`.
2. **Nested-delegatecall `msg.value`/`msg.sender` (DELEGATE-02):** the payable nested DC paths (Mint→Boon `consumePurchaseBoost` ~Mint:2062, Lootbox→Boon `consumeActivityBoon`/`checkAndClearExpiredBoon` ~Lootbox:1281/1418, `subscribe`, `resolveRedemptionLootbox`, `creditRedemptionDirect`, `resolveLootboxDirect`) keep `msg.value` in flight across the nested dispatch — verify it neither double-spends nor strands ETH, and that the value/consent guards live in the MODULE BODY (delegatecall preserves `msg.sender`, so the authorized actor is end-to-end correct).
3. **Raw `delegatecall(msg.data)` dispatch (DELEGATE-03):** the HUB `consumeCoinflipBoon` (~:836) forwards raw `msg.data` to a FIXED `GAME_BOON_MODULE` constant, and the afking router dispatches to `GAME_AFKING_MODULE`. Confirm NO `delegatecall(msg.data)` can reach an attacker-chosen target or selector; calldata forwarding, return-data handling, and revert bubbling are correct; no selector collision.
4. **Revert bubbling (DELEGATE-04):** the ~10 Advance→{Jackpot,Mint,Afking,GameOver} nested DC sites bubble via `_revertDelegate`; Lootbox→{Boon,Degenerette}; Afking→Lootbox `resolveAfkingBox:1474`; Decimator→Lootbox `resolveLootboxDirect:669`. Verify every thin dispatch stub bubbles a module revert (no swallowed failure that leaves partial state committed and makes the Game assume a transition succeeded). Note the ONE deliberately-swallowed path (`_handleGameOverPath`) and confirm it is intentional + safe.
5. **Module wiring (DELEGATE-05):** module addresses are `ContractAddresses` constants/immutables — confirm the column cannot delegatecall a zero/unset/wrong module, and no module is reachable as a DIRECT external call that would execute against its own (empty) storage (a self-storage-corruption / unauthorized-entry vector).

## Priority hotspots (from the column map)
- **Depth ≥3 recirculation:** Game→Lootbox→Degenerette `resolveEthSpinFromBox:2136`→Lootbox `resolveLootboxDirect`. Verify `allowEthSpin=false` truly blocks a cascade, and that `address(this)` / `msg.value` assumptions hold at delegatecall depth ≥3.
- **`msg.value`-in-flight at depth:** can a nested payable DC observe a stale or double-counted `msg.value` (it is preserved, not reset, across delegatecall)?
- **Packed multi-module slots:** slot 7 `balancesPacked` (8+ module writers), slot 34 `lootboxRngPacked` (5 writers), slot 5 `totalFlipReversals`/`lastVrfProcessedTimestamp` (masked RMW) — a dropped mask in one module corrupts a field another module owns.

## Output
For each of DELEGATE-01..05 and each hotspot: verdict (REAL / REFUTED / UNCERTAIN), severity (CATASTROPHE for silent storage corruption or a hijackable dispatch, else HIGH/MED/LOW/INFO), reachability under honest governance, the concrete trigger if REAL, and reasoning with `file:line`. Default to REFUTED only when you can show the guard is real and covers the whole window. Be concrete and skeptical.
