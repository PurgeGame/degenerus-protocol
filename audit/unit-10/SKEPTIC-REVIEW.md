# Unit 10: BURNIE Token + Coinflip -- Skeptic Review

**Skeptic:** Claude Opus 4.6 (1M context)
**Phase:** 112-burnie-token-coinflip
**Date:** 2026-03-25

---

## Review Summary

The Mad Genius attack report identified **0 VULNERABLE** and **0 INVESTIGATE** findings across all 43 state-changing functions in BurnieCoin.sol and BurnieCoinflip.sol. Three INFO-level observations were noted.

Per the Skeptic mandate: every VULNERABLE and INVESTIGATE finding must receive a verdict. Since none exist, this review validates the Mad Genius's SAFE verdicts on the critical attack surfaces and evaluates the 3 INFO findings.

---

## Critical Attack Surface Validation

### 1. Auto-Claim Callback Chain (B2/B3 -> C4 -> BurnieCoinflip -> B5 -> C2)

**Mad Genius Verdict:** SAFE -- no stale cache.

**Skeptic Independent Verification:**

I traced the exact execution path in BurnieCoin.sol:

1. `transfer(to, amount)` at L408 calls `_claimCoinflipShortfall(msg.sender, amount)` at L409
2. Inside _claimCoinflipShortfall (L590): reads `balanceOf[msg.sender]` at L593 into local `balance`
3. If `balance < amount`: calls `claimCoinflipsFromBurnie(msg.sender, amount - balance)` at L596
4. BurnieCoinflip processes claim, then calls `mintForCoinflip(msg.sender, toClaim)` at L393
5. This calls `_mint(msg.sender, toClaim)` at L539: `balanceOf[msg.sender] += toClaim` at L490
6. Control returns to `_claimCoinflipShortfall` which returns
7. `_transfer(msg.sender, to, amount)` at L410: reads `balanceOf[msg.sender]` fresh at L456

**Key check:** At step 7, `balanceOf[msg.sender]` has been increased by the mint at step 5. The local `balance` from step 2 is dead at this point -- it was only used to compute the shortfall delta. The fresh storage read at L456 reflects the post-mint balance.

**Arithmetic verification:** Post-mint balance = original_balance + toClaim. `_transfer` subtracts `amount`. For this to succeed: original_balance + toClaim >= amount. Since toClaim = min(claimable, amount - original_balance), if claimable >= amount - original_balance, then toClaim = amount - original_balance, so post-mint balance = amount. Exactly sufficient. If claimable < amount - original_balance, then toClaim < amount - original_balance, so post-mint balance < amount, and _transfer reverts on underflow. **Correct behavior.**

**Skeptic Verdict: CONFIRMED SAFE.** The callback chain is correctly ordered. No stale cache.

### 2. Supply Invariant Across Vault Redirects

**Mad Genius Verdict:** SAFE -- invariant maintained.

**Skeptic Independent Verification:**

I verified all 6 vault redirect paths:

| Path | totalSupply delta | vaultAllowance delta | Sum delta |
|------|-------------------|---------------------|-----------|
| _transfer to VAULT (L458-467) | -amount128 | +amount128 | 0 |
| _mint to VAULT (L482-488) | 0 | +amount128 | +amount128 |
| _burn from VAULT (L502-509) | 0 | -amount128 | -amount128 |
| _transfer normal (L456-472) | 0 | 0 | 0 |
| _mint normal (L489-491) | +amount128 | 0 | +amount128 |
| _burn normal (L512-514) | -amount128 | 0 | -amount128 |

For _mint to VAULT: only vaultAllowance increases -- this represents virtual BURNIE credited to vault. `supplyIncUncirculated` increases, but no tokens enter circulation. Correct.

For _burn from VAULT: only vaultAllowance decreases -- vault allowance consumed without creating tokens. `supplyIncUncirculated` decreases. Correct.

All deltas are symmetric: totalSupply + vaultAllowance changes are consistent. **CONFIRMED SAFE.**

### 3. RNG Lock Guards Coverage

**Mad Genius Verdict:** SAFE -- comprehensive guards.

**Skeptic Independent Verification:**

| Guard Location | What It Protects | Condition |
|---------------|------------------|-----------|
| _claimCoinflipShortfall L592 | Auto-claim during VRF | `degenerusGame.rngLocked()` |
| _consumeCoinflipShortfall L605 | Auto-consume during VRF | `degenerusGame.rngLocked()` |
| _setCoinflipAutoRebuy L706 | Carry extraction before known loss | `degenerusGame.rngLocked()` |
| _setCoinflipAutoRebuyTakeProfit L756 | Take-profit change before known loss | `degenerusGame.rngLocked()` |
| _addDailyFlip L645 | Bounty arming after RNG known | `game.rngLocked()` |
| _coinflipLockedDuringTransition L1000-1013 | Deposits during BAF resolution | Complex condition |
| _claimCoinflipsInternal L570-577 | BAF credit during resolution | Complex condition |

All paths that could extract value based on RNG knowledge are guarded. **CONFIRMED SAFE.**

### 4. processCoinflipPayouts RNG Quality

**Mad Genius Verdict:** SAFE -- unbiased.

**Skeptic Independent Verification:**

- `seedWord = keccak256(rngWord, epoch)`: keccak256 of VRF word + deterministic epoch produces uniformly distributed 256-bit output. **Correct.**
- `roll = seedWord % 20`: 2^256 mod 20 = 0 (2^256 is divisible by 20: 2^256 / 20 = 2^256 / (4*5) = 2^254 / 5, remainder = 2^254 mod 5... Actually, 2^256 mod 20: 2^256 = (2^4) * 2^252 = 16 * 2^252. 2^252 mod 5: by Fermat, 2^4 = 1 mod 5, so 2^252 = (2^4)^63 = 1 mod 5. Thus 2^256 mod 20 = 16 * 1 mod 20 = 16. So there IS a negligible modulo bias: 2^256 mod 20 = 16, meaning values 0-15 are each hit (2^256 / 20 + 1) times and 16-19 are hit (2^256 / 20) times. The bias is 1/(2^256/20) = 20/2^256, which is ~1.7e-76. **Negligible -- SAFE.**
- `seedWord % 38 + 78`: Similar negligible bias. 2^256 mod 38 = 2^256 mod (2*19). 2^256 mod 19: by Fermat, 2^18 = 1 mod 19, 256 = 14*18 + 4, so 2^256 = 2^4 = 16 mod 19. 2^256 mod 38 = 2*16 mod 38 = 32. Bias: 32/(2^256/38) ~ negligible. **SAFE.**
- `(rngWord & 1) == 1`: LSB of 256-bit VRF word. Perfectly unbiased (VRF produces uniform bits). **SAFE.**

**CONFIRMED SAFE.** RNG bias is cryptographically negligible for all modular operations.

---

## INFO Finding Review

### INFO-01: ERC20 Approve Race Condition

**Mad Genius Verdict:** INFO

**Skeptic Verdict: CONFIRMED INFO.** Standard ERC20 design limitation. Not protocol-specific. No action needed. All ERC20 tokens share this characteristic.

### INFO-02: Vault Self-Mint Path in vaultMintTo

**Mad Genius Verdict:** INFO -- vault can mint to itself, no economic impact.

**Skeptic Verification:** If vault calls `vaultMintTo(VAULT, amount)`:
- `vaultAllowance -= amount128` (L711)
- `totalSupply += amount128` (L712)
- `balanceOf[VAULT] += amount` (L713)

The vault now has circulating tokens in balanceOf AND reduced allowance. Supply invariant: `totalSupply` increased and `vaultAllowance` decreased by same amount. `supplyIncUncirculated` unchanged. **No inflation.**

If vault later transfers to someone: `_transfer(VAULT, recipient, amount)` hits the vault redirect at L458: decreases totalSupply, increases vaultAllowance. Net: back to original state.

**Skeptic Verdict: CONFIRMED INFO.** No economic impact. Self-mint-then-transfer is a no-op for the supply invariant.

### INFO-03: Error Reuse in burnForCoinflip/mintForCoinflip

**Mad Genius Verdict:** INFO -- uses OnlyGame() error for coinflip access control.

**Skeptic Verdict: CONFIRMED INFO.** Cosmetic. Does not affect security. The access control check at L529 is correct (`msg.sender != coinflipContract`), only the error name is misleading.

---

## Overall Skeptic Assessment

The Mad Genius conducted a thorough analysis of all 43 state-changing functions with properly expanded call trees, complete storage write maps, and explicit cached-local-vs-storage checks. The four critical attack surfaces (auto-claim callback, supply invariant, RNG locks, payout entropy) were correctly analyzed and verified safe.

**No findings require escalation.** The 3 INFO items are cosmetic observations with no security impact.

**Skeptic Sign-Off: All SAFE verdicts CONFIRMED.**
