# DegenerusAffiliate v6.0 Delta Adversarial Audit

**Status:** Complete
**Auditor:** Three-agent system (Mad Genius / Skeptic / Taskmaster)
**Scope:** All 8 UNPLANNED DegenerusAffiliate changes (commit a3e2341f)
**Contract:** `contracts/DegenerusAffiliate.sol` (880 lines)

> **NOTE: UNPLANNED change** -- no prior design review existed for these changes.
> The default referral code system ("every address is an affiliate") was added after
> all planned v6.0 phases completed. This audit verifies the change cannot be exploited
> for ETH flow manipulation, front-running, or affiliate fee theft.

---

## Executive Summary

8 functions audited with full three-agent methodology. The default referral code system uses `bytes32(uint256(uint160(addr)))` to derive a deterministic code for every address. Custom codes must have `uint256(code) > type(uint160).max`, guaranteeing zero overlap between the two namespaces. Default codes carry 0% kickback and route all affiliate rewards to the address-derived owner.

**Result: 0 VULNERABLE, 0 INVESTIGATE, 8 SAFE.** The namespace separation is mathematically collision-free, ETH flow is correct under all code types, and no BAF-class cache-overwrite patterns exist.

---

## 1. `defaultCode(address)` -- NEW (line 349-351)

### Call Tree

```
defaultCode(address addr) [line 349-351]
  (pure function -- no calls, no storage reads/writes)
```

### Storage Writes (Full Tree)

None. Pure function.

### Attack Analysis

**State coherence (BAF-class):** N/A -- pure function, no storage interaction.

**Access control:** Public pure -- anyone can call, which is correct. This is a helper for frontend link generation. It produces the same deterministic result for any caller. No authorization needed.

**Collision with custom codes:**
- Default code = `bytes32(uint256(uint160(addr)))`. For any valid Ethereum address, `uint160(addr) <= type(uint160).max`.
- Therefore `uint256(defaultCode) <= type(uint160).max` ALWAYS.
- Custom codes are rejected by `_createAffiliateCode` if `uint256(code_) <= type(uint160).max` (line 768).
- **CONCLUSION: The default code namespace (0 to 2^160-1) and custom code namespace (2^160 to 2^256-1) are mathematically disjoint. Zero collision possible.**

**Two addresses producing same default code:**
- `bytes32(uint256(uint160(addr)))` is injective: different addresses produce different default codes because `uint160` preserves the full address. Two different `addr` values cannot map to the same `uint160` value.
- **COLLISION-FREE: proven by injectivity of uint160 identity.**

**Crafting malicious address:**
- An attacker could generate an address whose default code matches a *desired* default code (that IS another address's default code). But this is just address collision -- equivalent to finding two addresses that are the same, which is computationally infeasible (2^160 space).
- An attacker CANNOT craft an address whose default code falls in the custom code range (`> type(uint160).max`) because `uint160(addr)` is always `<= type(uint160).max`.

**Edge cases:**
- `defaultCode(address(0))` returns `bytes32(0)`. This is handled safely because `_resolveCodeOwner(bytes32(0))` returns `address(0)` (line 735-736: `affiliateCode[0].owner` is zero, then `uint256(bytes32(0)) = 0 <= type(uint160).max`, so returns `address(uint160(0)) = address(0)`). And `address(0)` is rejected as invalid by all callers (e.g., line 329, 436).

**VERDICT: SAFE**

### Cached-Local-vs-Storage Check

N/A -- pure function with no storage interaction.

---

## 2. `_resolveCodeOwner(bytes32)` -- NEW (lines 734-742)

### Call Tree

```
_resolveCodeOwner(bytes32 code) [line 734-742]
  affiliateCode[code].owner  -- SLOAD (read only)
  address(uint160(uint256(code)))  -- pure conversion
```

### Storage Writes (Full Tree)

None. View function (private, but only reads).

### Attack Analysis

**State coherence (BAF-class):** No writes, no caching concern.

**Resolution priority -- custom vs default:**
- Line 735: `address owner = affiliateCode[code].owner;`
- Line 736: `if (owner != address(0)) return owner;`
- Custom code ALWAYS takes priority over default code. If a custom code is registered at `affiliateCode[code]`, that owner is returned.
- Default resolution (line 738-739) only executes when no custom code exists AND `uint256(code) <= type(uint160).max`.

**Can someone create a custom code that hijacks another address's default code?**
- No. `_createAffiliateCode` rejects any code where `uint256(code_) <= type(uint160).max` (line 768).
- All default codes satisfy `uint256(code) <= type(uint160).max`.
- Therefore no custom code can ever occupy the same `bytes32` value as any default code.
- The namespaces are completely disjoint -- the priority check at line 735-736 is defense-in-depth but never actually resolves a conflict.

**Can _resolveCodeOwner return a wrong address?**
- For custom codes: returns `affiliateCode[code].owner` which was set at code creation. Correct.
- For default codes: returns `address(uint160(uint256(code)))`. Since `defaultCode(addr)` = `bytes32(uint256(uint160(addr)))`, the round-trip is: `address(uint160(uint256(bytes32(uint256(uint160(addr)))))) = addr`. Correct -- lossless round-trip.

**Edge case -- code in neither namespace:**
- If `uint256(code) > type(uint160).max` AND `affiliateCode[code].owner == address(0)`, returns `address(0)`.
- This represents an unregistered custom code. Callers handle `address(0)` as invalid.

**Edge case -- code = REF_CODE_LOCKED (bytes32(uint256(1))):**
- `uint256(1) <= type(uint160).max`, so falls into default code range.
- Returns `address(uint160(1)) = address(1)`. This is a valid address but not a real participant.
- However, `REF_CODE_LOCKED` is never passed to `_resolveCodeOwner` by `referPlayer` (line 327 passes user-supplied code which would need to be exactly `bytes32(1)` -- possible but harmless since `address(1)` is just a dead address getting affiliate credit).
- In `payAffiliate`, `REF_CODE_LOCKED` stored code is handled at line 472-475 before reaching `_resolveCodeOwner`.

**VERDICT: SAFE**

### Cached-Local-vs-Storage Check

No storage writes in call tree. N/A.

---

## 3. `createAffiliateCode(bytes32, uint8)` -- MODIFIED (line 308-310)

### Call Tree

```
createAffiliateCode(bytes32 code_, uint8 kickbackPct) [line 308-310]
  _createAffiliateCode(msg.sender, code_, kickbackPct) [line 759-779]
    affiliateCode[code_].owner  -- SLOAD (read, line 771-773)
    affiliateCode[code_]        -- SSTORE (write, line 774-776)
    emit Affiliate(1, code_, owner)
```

### Storage Writes (Full Tree)

| Variable | Written At | Description |
|----------|-----------|-------------|
| `affiliateCode[code_]` | line 774 | Sets owner and kickback for new code |

### Attack Analysis

**State coherence (BAF-class):**
- `_createAffiliateCode` reads `affiliateCode[code_]` at line 771 (via `.owner` check) then writes at line 774.
- No descendant call between read and write that could modify the same slot. The emit at line 778 is an event log, not a storage write.
- **BAF-SAFE: single read-then-write with no intervening external call or descendant storage write.**

**Access control:** Anyone can call `createAffiliateCode`. This is by design -- affiliate code creation is permissionless.

**Collision guard (NEW for default codes):**
- Line 768: `if (uint256(code_) <= type(uint160).max) revert Zero();`
- This blocks any code in the default code address range from being registered as a custom code.
- Combined with `_resolveCodeOwner`'s priority logic, this means a custom code can NEVER shadow a default code.
- **COLLISION GUARD CORRECT.**

**Can someone claim another address's default code as a custom code?**
- No. Any `defaultCode(addr)` has `uint256(...) <= type(uint160).max`, so line 768 reverts.

**Front-running:** Custom codes are first-come-first-served (line 773: revert if owner != 0). A front-runner could claim a code before the intended owner. This is inherent to permissionless registration and not a bug -- it's documented behavior. The owner could just pick a different code.

**Zero/sentinel rejection:**
- `bytes32(0)`: line 766 rejects.
- `REF_CODE_LOCKED` (= `bytes32(1)`): line 766 rejects.
- Both are in range `<= type(uint160).max`, so line 768 would also reject them.

**Kickback bounds:** Line 770: `if (kickbackPct > MAX_KICKBACK_PCT) revert InvalidKickback()`. MAX_KICKBACK_PCT = 25. Correct.

**VERDICT: SAFE**

### Cached-Local-vs-Storage Check

| Ancestor Cache | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `info.owner` (line 771 SLOAD) | `affiliateCode[code_]` (line 774 SSTORE) | SAFE -- no intervening call between read and write |

---

## 4. `referPlayer(bytes32)` -- MODIFIED (lines 326-335)

### Call Tree

```
referPlayer(bytes32 code_) [line 326-335]
  _resolveCodeOwner(code_) [line 734-742]
    affiliateCode[code].owner  -- SLOAD (read)
  playerReferralCode[msg.sender]  -- SLOAD (read, line 330)
  _vaultReferralMutable(existing) [line 714-717]  -- (if existing != 0)
    game.lootboxPresaleActiveFlag()  -- external view call (read-only)
  _setReferralCode(msg.sender, code_) [line 720-730]
    playerReferralCode[player]  -- SSTORE (write, line 721)
    _resolveCodeOwner(code) [line 734-742]  -- (view call)
    emit ReferralUpdated(...)
  emit Affiliate(0, code_, msg.sender)
```

### Storage Writes (Full Tree)

| Variable | Written At | Description |
|----------|-----------|-------------|
| `playerReferralCode[msg.sender]` | line 721 (via `_setReferralCode`) | Sets player's referral code |

### Attack Analysis

**State coherence (BAF-class):**
- Reads `playerReferralCode[msg.sender]` at line 330, then writes via `_setReferralCode` at line 333.
- No intervening external call between read and write that could modify the same slot. The `_vaultReferralMutable` call at line 332 calls `game.lootboxPresaleActiveFlag()` which is a view on the Game contract -- cannot modify `playerReferralCode`.
- **BAF-SAFE: read and write to same slot with no intervening storage modification.**

**Access control:** Anyone can call. By design -- players register their own referrals.

**Default code support (MODIFIED):**
- `_resolveCodeOwner(code_)` now resolves both custom and default codes (line 327).
- A player can refer themselves using another address's default code. This is correct behavior.

**Self-referral prevention:**
- Line 329: `if (referrer == address(0) || referrer == msg.sender) revert Insufficient();`
- If a player passes their OWN default code (`defaultCode(msg.sender)`), `_resolveCodeOwner` returns `msg.sender`, which triggers the revert. **Self-referral blocked.**

**Referrer switching via default codes:**
- A player cannot switch referrers: line 332 checks `existing != bytes32(0)` and reverts unless `_vaultReferralMutable(existing)` returns true (presale only, VAULT/locked referrals only).
- Once a referral is set to a real code (custom or default), it cannot be changed. Correct.

**Edge case -- referring with `bytes32(0)`:**
- `_resolveCodeOwner(bytes32(0))`: `affiliateCode[0].owner` is `address(0)` (uninitialized), then `uint256(0) <= type(uint160).max`, so returns `address(0)`.
- Line 329 rejects `address(0)`. Correct.

**Edge case -- referring with `REF_CODE_LOCKED`:**
- `_resolveCodeOwner(bytes32(1))`: returns `address(1)`.
- `address(1) != address(0)` and `address(1) != msg.sender` (for any real player). So referral would succeed, pointing to `address(1)`.
- This is harmless -- `address(1)` is a precompile (ecrecover), affiliate rewards routed there via `coin.creditFlip(address(1), ...)` would be effectively burned. INFO-level at worst.

**VERDICT: SAFE**

### Cached-Local-vs-Storage Check

| Ancestor Cache | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `existing` = `playerReferralCode[msg.sender]` (line 330) | `playerReferralCode[player]` (line 721 via `_setReferralCode`) | SAFE -- no external call between the `existing` read and the `_setReferralCode` write that could modify `playerReferralCode[msg.sender]`. The `_vaultReferralMutable` call is a view on a different contract. |

---

## 5. `payAffiliate(...)` -- MODIFIED (lines 396-641)

### Call Tree

```
payAffiliate(amount, code, sender, lvl, isFreshEth, lootboxActivityScore) [line 396-641]
  // ACCESS CONTROL
  msg.sender check (line 408-411)

  // REFERRAL RESOLUTION
  playerReferralCode[sender]  -- SLOAD (read, line 416)
  _resolveCodeOwner(code) [line 734-742]  -- if code != 0 (multiple paths)
    affiliateCode[code].owner  -- SLOAD (read)
  _setReferralCode(sender, code_) [line 720-730]  -- various paths
    playerReferralCode[player]  -- SSTORE (write, line 721)
    _resolveCodeOwner(code)  -- view
    emit ReferralUpdated(...)
  _vaultReferralMutable(storedCode) [line 714-717]  -- if stored != 0 path
    game.lootboxPresaleActiveFlag()  -- external view call
  affiliateCode[storedCode]  -- SLOAD (read, line 478/461)

  // REWARD CALCULATION
  affiliateCommissionFromSender[lvl][affiliateAddr][sender]  -- SLOAD+SSTORE (line 525, 535)
  affiliateCoinEarned[lvl][affiliateAddr]  -- implicit via earned mapping (line 539-540)
  _totalAffiliateScore[lvl]  -- SSTORE (line 541)
  _updateTopAffiliate(affiliateAddr, newTotal, lvl) [line 825-832]
    affiliateTopByLevel[lvl]  -- SLOAD+SSTORE (line 827, 829)
  _applyLootboxTaper(scaledAmount, lootboxActivityScore) [line 836-844]  -- pure

  // DISTRIBUTION (noReferrer path)
  _routeAffiliateReward(winner, totalAmount) [line 794-800]
    coin.creditFlip(player, amount)  -- external call (line 799)

  // DISTRIBUTION (real affiliate path)
  coin.affiliateQuestReward(affiliateAddr, affiliateShareBase) [line 602]  -- external call
  _referrerAddress(affiliateAddr) [line 750-756]  -- view
    playerReferralCode[affiliateAddr]  -- SLOAD
    _resolveCodeOwner(code)  -- view
  coin.affiliateQuestReward(upline, baseBonus) [line 609]  -- external call
  _referrerAddress(upline) [line 750-756]  -- view
  coin.affiliateQuestReward(upline2, bonus2) [line 616]  -- external call
  _rollWeightedAffiliateWinner(...) [line 847-879]  -- view (uses keccak256)
  _routeAffiliateReward(winner, totalAmount) [line 794-800]
    coin.creditFlip(player, amount)  -- external call
```

### Storage Writes (Full Tree)

| Variable | Written At | Description |
|----------|-----------|-------------|
| `playerReferralCode[sender]` | line 721 (via `_setReferralCode`) | Set/lock referral on first interaction |
| `affiliateCommissionFromSender[lvl][affiliateAddr][sender]` | line 535 | Update per-sender commission tracking |
| `affiliateCoinEarned[lvl][affiliateAddr]` (via `earned` ref) | line 540 | Update affiliate earnings |
| `_totalAffiliateScore[lvl]` | line 541 | Increment level total |
| `affiliateTopByLevel[lvl]` | line 829 (via `_updateTopAffiliate`) | Update top affiliate if new high |

### Attack Analysis

**State coherence (BAF-class):**

1. **`playerReferralCode[sender]`**: Read at line 416, written via `_setReferralCode` in multiple paths (lines 429, 438, 444, 460). The read and write happen in the SAME execution flow with no intervening external call that could modify `playerReferralCode[sender]`. The external calls (`game.lootboxPresaleActiveFlag` at line 716, `coin.affiliateQuestReward` at lines 602/609/616, `coin.creditFlip` at line 799) are to different contracts that do not write to DegenerusAffiliate storage. **BAF-SAFE.**

2. **`affiliateCommissionFromSender`**: Read at line 525, written at line 535. Sequential with no intervening call. **BAF-SAFE.**

3. **`affiliateCoinEarned` (via `earned`)**: Written at line 540. The `earned` reference is created at line 497. No intervening external call between creation and write. The external calls to `coin.affiliateQuestReward` (lines 602, 609, 616) and `coin.creditFlip` (line 799) happen AFTER this write. **BAF-SAFE.**

4. **`_totalAffiliateScore`**: Written at line 541, after `earned` write. Same analysis. **BAF-SAFE.**

5. **`affiliateTopByLevel`**: Read and written inside `_updateTopAffiliate` (lines 827-829). No external call between. **BAF-SAFE.**

6. **Cross-function concern**: After all storage writes (lines 535-551), the external calls begin (lines 577-636 in distribution). Could `coin.creditFlip` or `coin.affiliateQuestReward` call back into `payAffiliate`? Only if `msg.sender == ContractAddresses.COIN || msg.sender == ContractAddresses.GAME` -- the access control at line 408-411 prevents arbitrary reentrancy. BurnieCoin is a trusted contract and would not re-enter. **SAFE.**

**Access control:**
- Line 408-411: Only COIN or GAME can call. These are immutable contract addresses. Correct.

**ETH flow with default codes:**
- Default codes have 0% kickback (line 450, 465, 482). The full `scaledAmount` goes to the affiliate (no kickback to player). This is correct -- the address-derived owner gets the reward.
- If a player is referred by a default code for address X, `affiliateAddr` = X. X receives BURNIE via `coin.creditFlip`. No ETH is directly transferred -- rewards are BURNIE-denominated flip credits. **ETH flow not affected by default codes.**

**Self-referral via default codes:**
- Line 436: `if (resolved == address(0) || resolved == sender) {...}` -- self-referral locks to VAULT. Correct.
- A player cannot profit by referring themselves through their own default code.

**Default code with unclaimed address (no wallet interaction):**
- If address X has never interacted with the protocol, `defaultCode(X)` still resolves to X. Rewards are credited via `coin.creditFlip(X, amount)`. These rewards accumulate in BURNIE/FLIP balance. X can claim them if they ever interact.
- No ETH is lost or redirected. The rewards are legitimately earned by whoever referred the player.

**Edge case -- storedCode is a default code (line 477-484):**
- When `storedCode` is a previously stored default code, line 478: `affiliateCode[storedCode].owner` is `address(0)` (no custom code registered). So line 479 falls through to line 482: `_resolveCodeOwner(storedCode)` which returns the address. Correct.

**Commission cap interaction:**
- The per-sender commission cap (line 522-536) applies identically to default and custom code affiliates. No bypass possible.

**Weighted roll manipulation:**
- The PRNG uses `keccak256(AFFILIATE_ROLL_TAG, currentDay, sender, storedCode)` (line 858-865).
- Inputs: `sender` is the buyer (cannot be manipulated by affiliate), `storedCode` is fixed once set, `currentDay` changes daily.
- An attacker cannot manipulate which recipient wins the weighted roll. The comment at line 596 acknowledges this is not VRF-grade randomness but is EV-neutral by design.

**`winner != sender` check (line 633):**
- If the weighted roll selects `sender` as winner (possible if sender is also an affiliate), the reward is silently skipped. This prevents a buyer from getting their own affiliate reward. Correct and intentional.

**VERDICT: SAFE**

### Cached-Local-vs-Storage Check

| Ancestor Cache | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `storedCode` = `playerReferralCode[sender]` (line 416) | `playerReferralCode[sender]` (line 721 via `_setReferralCode`) | SAFE -- `storedCode` local is updated in tandem (line 430, 439, 452, 467); the local is never used stale after the write. After the referral resolution block (ends ~line 486), all subsequent code uses the final `storedCode` value which matches storage. |
| `info` = `AffiliateCodeInfo` (various lines) | `affiliateCode[...]` (never written in payAffiliate) | SAFE -- `affiliateCode` mapping is only written by `_createAffiliateCode`, never by `payAffiliate`. |
| `alreadyEarned` (line 525) | `affiliateCommissionFromSender[...][...][sender]` (line 535) | SAFE -- sequential read-then-write, no intervening call. |

---

## 6. `_setReferralCode(address, bytes32)` -- MODIFIED (lines 720-730)

### Call Tree

```
_setReferralCode(address player, bytes32 code) [line 720-730]
  playerReferralCode[player]  -- SSTORE (write, line 721)
  _resolveCodeOwner(code) [line 734-742]  -- (if not locked/VAULT path)
    affiliateCode[code].owner  -- SLOAD (read)
  emit ReferralUpdated(player, code, referrer, locked)
```

### Storage Writes (Full Tree)

| Variable | Written At | Description |
|----------|-----------|-------------|
| `playerReferralCode[player]` | line 721 | Sets player's referral code |

### Attack Analysis

**State coherence (BAF-class):**
- Single write at line 721. `_resolveCodeOwner` at line 727 is a read-only call after the write. No caching issue.
- **BAF-SAFE.**

**Access control:** Private function -- only callable from within the contract. Callers: `constructor`, `referPlayer`, `payAffiliate`, `_bootstrapReferral`. All have appropriate guards.

**Default code resolution in event (MODIFIED):**
- Line 727: `referrer = _resolveCodeOwner(code)` now resolves default codes to their owner address for the `ReferralUpdated` event. This is correct -- event shows the actual referrer address regardless of code type.

**Edge case -- code is REF_CODE_LOCKED:**
- Line 722: `bool locked = code == REF_CODE_LOCKED;` -> true.
- Line 724-725: `referrer = ContractAddresses.VAULT`. Correct.

**Edge case -- code is AFFILIATE_CODE_VAULT:**
- Line 724: handled same as locked case. `referrer = ContractAddresses.VAULT`. Correct.

**VERDICT: SAFE**

### Cached-Local-vs-Storage Check

No ancestor caching -- single write followed by read-only operations.

---

## 7. `_referrerAddress(address)` -- MODIFIED (lines 750-756)

### Call Tree

```
_referrerAddress(address player) [line 750-756]
  playerReferralCode[player]  -- SLOAD (read, line 751)
  _resolveCodeOwner(code) [line 734-742]  -- if not locked/VAULT/zero
    affiliateCode[code].owner  -- SLOAD (read)
```

### Storage Writes (Full Tree)

None. View function (private but read-only).

### Attack Analysis

**State coherence (BAF-class):** No writes. N/A.

**Access control:** Private function -- only callable from within the contract. Callers: `payAffiliate` (lines 607, 614), `_setReferralCode` (indirectly, no -- `_setReferralCode` calls `_resolveCodeOwner` directly). Actually only `payAffiliate` calls `_referrerAddress`.

**Default code resolution (MODIFIED):**
- If `playerReferralCode[player]` stores a default code (e.g., `bytes32(uint256(uint160(someAddr)))`), line 753 calls `_resolveCodeOwner(code)` which returns `someAddr`. Correct.
- If the resolved owner is `address(0)` (impossible for valid default codes since any non-zero address maps to a non-zero owner, but guarded), returns VAULT as fallback (line 754). Correct.

**Edge case -- player with no referral:**
- `code == bytes32(0)`: line 752 returns VAULT. Correct.

**VERDICT: SAFE**

### Cached-Local-vs-Storage Check

N/A -- no storage writes.

---

## 8. `_createAffiliateCode(...)` -- MODIFIED (lines 759-779)

### Call Tree

```
_createAffiliateCode(address owner, bytes32 code_, uint8 kickbackPct) [line 759-779]
  affiliateCode[code_].owner  -- SLOAD (read, line 771, via info.owner)
  affiliateCode[code_]        -- SSTORE (write, line 774)
  emit Affiliate(1, code_, owner)
```

### Storage Writes (Full Tree)

| Variable | Written At | Description |
|----------|-----------|-------------|
| `affiliateCode[code_]` | line 774 | Sets owner and kickback for new code |

### Attack Analysis

**State coherence (BAF-class):**
- Read at line 771 (`info.owner`), write at line 774. Sequential, no intervening call. **BAF-SAFE.**

**Access control:** Private function. Callers: `createAffiliateCode(external)` at line 309, `constructor` at line 266. Correct -- only code creation paths.

**Default code range guard (MODIFIED -- key change):**
- Line 768: `if (uint256(code_) <= type(uint160).max) revert Zero();`
- This is the NEW guard that prevents custom codes from overlapping with the default code address space.
- `type(uint160).max = 2^160 - 1`. Any code with `uint256(code_) <= 2^160 - 1` is rejected.
- Default codes are `bytes32(uint256(uint160(addr)))` which always satisfies this condition.
- **Guard is correct and complete.** No custom code can ever collide with a default code.

**Can the guard be bypassed?**
- The function is private, so only called via `createAffiliateCode` (passes `msg.sender` as owner, user-supplied `code_`) and `constructor` (bootstrap data).
- Constructor runs once at deployment. Bootstrap codes would need to pass the same check. Correct.

**Existing sentinel protection:**
- Line 766: `bytes32(0)` and `REF_CODE_LOCKED` (`bytes32(1)`) both rejected.
- Both have `uint256(...) <= type(uint160).max`, so line 768 also rejects them. Defense in depth.

**First-come-first-served:**
- Line 773: `if (info.owner != address(0)) revert Insufficient();`
- Cannot overwrite an existing code. Correct.

**VERDICT: SAFE**

### Cached-Local-vs-Storage Check

| Ancestor Cache | Descendant Write | Verdict |
|---------------|-----------------|---------|
| `info` (storage pointer at line 771) | `affiliateCode[code_]` (line 774) | SAFE -- `info` is used only for the `owner != address(0)` check before the write. No external call between. |

---

## Default Code Collision Analysis

### Namespace Separation Proof

The default code system introduces two disjoint namespaces:

1. **Default codes:** `bytes32(uint256(uint160(addr)))` for any address `addr`. Value range: `[0, 2^160 - 1]`.
2. **Custom codes:** Any `bytes32` value where `uint256(code_) > type(uint160).max`. Value range: `[2^160, 2^256 - 1]`.

**Separation enforcement:**
- `_createAffiliateCode` (line 768): `if (uint256(code_) <= type(uint160).max) revert Zero();` -- blocks custom codes in default range.
- `_resolveCodeOwner` (line 738): `if (uint256(code) <= type(uint160).max)` -- interprets low-range codes as default codes.
- These two checks use the SAME boundary (`type(uint160).max`), so the partition is exact with no gap.

**Pre-existing reserved codes:**
- `AFFILIATE_CODE_VAULT = bytes32("VAULT")` = `0x5641554c540000...0000`. `uint256(...)` = a large number >> `type(uint160).max`. In the custom namespace. Correct.
- `AFFILIATE_CODE_DGNRS = bytes32("DGNRS")` = `0x44474e52530000...0000`. Same analysis. In the custom namespace. Correct.

**Constructor bootstrap codes:** All bootstrap codes pass through `_createAffiliateCode`, so they must be in the custom namespace. Correct.

### Collision Verdict

**COLLISION-FREE.** The two namespaces are mathematically disjoint. No value can exist in both. No custom code can shadow a default code. No default code can shadow a custom code. The boundary is enforced at both creation and resolution.

---

## ETH Flow Verification (payAffiliate with default codes)

### Flow Analysis

1. **Referral resolution with default code:** When a player's first purchase provides a default code:
   - `_resolveCodeOwner(code)` returns the derived address (line 435).
   - `_setReferralCode(sender, code)` stores the default code permanently (line 444).
   - `info` is set to `AffiliateCodeInfo({ owner: resolved, kickback: 0 })` (line 450).
   - `affiliateAddr = info.owner = resolved` (line 491).

2. **Reward calculation:** Standard BPS scaling applies. No difference between custom and default code affiliates for reward amounts.

3. **Kickback:** Default codes always have `kickback: 0` (line 450). Player receives zero kickback. Full `scaledAmount` goes to affiliate. This is by design -- default codes have no incentive structure.

4. **Distribution:** `_routeAffiliateReward(winner, totalAmount)` calls `coin.creditFlip(player, amount)`.
   - For default code affiliates, `player` = the address-derived owner.
   - BURNIE flip credits are minted to that address. No ETH is transferred.
   - The affiliate can claim their BURNIE normally.

5. **Upline chain:** Default code affiliates have uplines resolved via `_referrerAddress(affiliateAddr)`.
   - If the default code affiliate has no stored referral code, `_referrerAddress` returns VAULT (line 752). Correct -- upline rewards go to VAULT.

### ETH Flow Verdict

**CORRECT.** No ETH is directly transferred by `payAffiliate`. All rewards are BURNIE flip credits via `coin.creditFlip`. Default codes route rewards to the address-derived owner with 0% kickback. No ETH flow manipulation is possible through default referral codes.

---

## Skeptic Validation

### Summary

All 8 functions received SAFE verdicts from Mad Genius. With 0 VULNERABLE and 0 INVESTIGATE findings, the Skeptic has no findings to validate.

**Skeptic observation:** The namespace separation is mathematically sound. The guard at `_createAffiliateCode` line 768 and the resolution at `_resolveCodeOwner` line 738 use the same boundary (`type(uint160).max`), creating an exact partition. There is no off-by-one or gap. The collision analysis is complete.

**Skeptic observation on `REF_CODE_LOCKED` edge:** A user could call `referPlayer(bytes32(1))` which resolves to `address(1)` (ecrecover precompile). This would set their referrer to an unrecoverable address. However, this is self-inflicted damage (user explicitly chose this code) and has no protocol-level impact. INFO-level at most, not a finding.

**Skeptic verdict: CONFIRMED -- all 8 functions are SAFE.**

---

## Taskmaster Coverage Matrix

### Function Checklist

| # | Function | Analyzed? | Call Tree Complete? | Storage Writes Complete? | Cache Check Done? |
|---|----------|-----------|--------------------|-----------------------|------------------|
| 1 | `defaultCode(address)` | YES | YES | YES (none) | YES (N/A -- pure) |
| 2 | `_resolveCodeOwner(bytes32)` | YES | YES | YES (none) | YES (N/A -- view) |
| 3 | `createAffiliateCode(bytes32, uint8)` | YES | YES | YES (1 write) | YES |
| 4 | `referPlayer(bytes32)` | YES | YES | YES (1 write) | YES |
| 5 | `payAffiliate(...)` | YES | YES | YES (5 writes) | YES |
| 6 | `_setReferralCode(address, bytes32)` | YES | YES | YES (1 write) | YES |
| 7 | `_referrerAddress(address)` | YES | YES | YES (none) | YES (N/A -- view) |
| 8 | `_createAffiliateCode(...)` | YES | YES | YES (1 write) | YES |

### Gaps Found

None. All 8 functions have complete analysis with:
- Full recursive call tree expansion
- All storage writes mapped (total: 8 write points across 5 unique storage variables)
- BAF-class cached-local-vs-storage check on every function with storage writes
- Default code collision analysis as dedicated subsection
- ETH flow verification as dedicated subsection

### Interrogation Log

**Q1 (Taskmaster):** "payAffiliate has external calls to coin.affiliateQuestReward and coin.creditFlip. These happen AFTER storage writes. Could BurnieCoin re-enter payAffiliate?"
**A1 (Mad Genius):** No. payAffiliate has access control at line 408-411 requiring msg.sender == COIN or GAME. A re-entrant call from BurnieCoin would have msg.sender == COIN, which passes the check. However, BurnieCoin is a trusted protocol contract deployed at a deterministic address -- it does not contain re-entrant call patterns. Additionally, the storage writes (lines 535-551) are all complete before any external call, so even if re-entrance occurred, the referral resolution would read the UPDATED storage values, not stale ones. The writes-before-calls pattern is correct.

**Q2 (Taskmaster):** "In the storedCode != 0 path (line 456-485), what happens when _vaultReferralMutable returns true but the new code resolves to address(0) or sender?"
**A2 (Mad Genius):** Line 459: `if (resolved != address(0) && resolved != sender)` -- if resolution fails, the entire `if` block at line 457 is skipped. Execution falls to line 471: `if (!infoSet)` which is still true, so line 472-484 handles the existing stored code. The referral remains unchanged. Correct -- invalid upgrade attempts are silently ignored, preserving the existing referral.

**Q3 (Taskmaster):** "For _referrerAddress, if a player's stored code points to a default code whose address was later registered as a custom code owner for a DIFFERENT code, does the resolution still work?"
**A3 (Mad Genius):** Yes. The stored code IS the default code (e.g., `bytes32(uint256(uint160(X)))`). `_resolveCodeOwner` first checks `affiliateCode[storedCode].owner` -- since no custom code can exist in the default range (guard at line 768), this always returns `address(0)`. Then it falls through to the address derivation, returning X. The fact that X might own custom codes elsewhere is irrelevant -- those are different `bytes32` keys in the `affiliateCode` mapping.

### Verdict: PASS

All 8 functions fully analyzed. All call trees expanded recursively. All storage writes mapped. All BAF-class checks explicit. Default code collision analysis proves mathematical disjointness. ETH flow verification confirms no manipulation possible. 100% coverage achieved.

---

## Final Verdict

| # | Function | Mad Genius | Skeptic | Final |
|---|----------|-----------|---------|-------|
| 1 | `defaultCode(address)` | SAFE | N/A (no findings) | **SAFE** |
| 2 | `_resolveCodeOwner(bytes32)` | SAFE | N/A (no findings) | **SAFE** |
| 3 | `createAffiliateCode(bytes32, uint8)` | SAFE | N/A (no findings) | **SAFE** |
| 4 | `referPlayer(bytes32)` | SAFE | N/A (no findings) | **SAFE** |
| 5 | `payAffiliate(...)` | SAFE | N/A (no findings) | **SAFE** |
| 6 | `_setReferralCode(address, bytes32)` | SAFE | N/A (no findings) | **SAFE** |
| 7 | `_referrerAddress(address)` | SAFE | N/A (no findings) | **SAFE** |
| 8 | `_createAffiliateCode(...)` | SAFE | N/A (no findings) | **SAFE** |

**VERDICT: 0 VULNERABLE, 0 INVESTIGATE, 8 SAFE.**

All 8 unplanned DegenerusAffiliate functions pass the three-agent adversarial audit. The default referral code system is collision-free, ETH flow is correct, self-referral is blocked, and no BAF-class cache-overwrite patterns exist.
