# Plan: Whale Halfpass for WWXRP 8-Match Jackpot

**Status:** Not started
**Scope:** Award a whale halfpass to the first 5 players who hit 8 matches on a Degenerette bet of ≥1 WWXRP.

## Changes (~15 lines)

### 1. Storage variable — `DegenerusGameStorage.sol`

```solidity
uint8 internal wwxrpJackpotWhalePassesAwarded; // 0→5 then stops
```

### 2. Constant + event — `DegenerusGameDegeneretteModule.sol`

```solidity
uint8 private constant MAX_WWXRP_JACKPOT_WHALE_PASSES = 5;

event WwxrpJackpotWhalePass(address indexed player, uint8 indexed passNumber);
```

### 3. Logic in spin loop — `DegenerusGameDegeneretteModule.sol` (~line 661, after DGNRS reward block)

```solidity
// Whale halfpass for first 5 WWXRP 8-match jackpots (≥1 WWXRP bet)
if (matches == 8 && currency == CURRENCY_WWXRP
    && amountPerTicket >= MIN_BET_WWXRP
    && wwxrpJackpotWhalePassesAwarded < MAX_WWXRP_JACKPOT_WHALE_PASSES) {
    unchecked { ++wwxrpJackpotWhalePassesAwarded; }
    whalePassClaims[player] += 1;
    emit WwxrpJackpotWhalePass(player, wwxrpJackpotWhalePassesAwarded);
}
```

## Why this works

- `DegenerusGameDegeneretteModule` inherits `DegenerusGamePayoutUtils` → has direct access to `whalePassClaims[player]`
- `matches == 8` short-circuits first → zero gas overhead on normal spins (SLOAD only fires on the 1-in-10M jackpot)
- Directly increments `whalePassClaims[player]` (skips `_queueWhalePassClaimCore` which does ETH→halfpass conversion we don't want)
- Player claims via existing `claimWhalePass()` flow — no UI changes needed
- Counter is permanent and monotonic — once 5 are awarded, promotion is over

## Open questions

- **Same player twice?** As written, one player could claim multiple of the 5. Add a mapping if 1-per-player is desired.
- **Retroactive?** Only catches future spins. Already-resolved 8-matches won't count.
- **View function?** Consider adding `wwxrpJackpotWhalePassesRemaining()` so the frontend can show "3 of 5 claimed".
