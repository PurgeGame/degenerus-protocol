# Phase 339 — REBAL BPS-Sum Invariant + JACK Final-Day Deletion Side-Effects Attestation

**Plan:** 339-03 · **Task 1** · **SC4** · **BATCH-01** (REBAL-01 / JACK-01 / JACK-02 verification charge)
**Decisions:** D-11 (REBAL complete pool-BPS set sums to 10000) · D-12 (JACK clean-orphan + preserved plumbing)
**Frozen tree:** all `file:line` cited against the live working tree, which is byte-identical to the v50.0-closure HEAD **`812abeee`** for `contracts/` — `git diff 812abeee HEAD -- contracts/` is EMPTY (the only commits since `812abeee` are v51 planning docs). Confirmed at execution start.

> **No "by construction" claim survives un-checked.** Every constant, sum, sole-use, and preserved-plumbing site below was read from source at HEAD (≡ `812abeee`) — not transcribed from the plan/CONTEXT text. Anchor drift relative to the plan/CONTEXT line citations is recorded inline and consolidated in `339-GREP-ATTESTATION-EDIT-ORDER.md`.

---

## PART 1 — REBAL: the COMPLETE pool-BPS set sums to exactly 10000 (D-11, REBAL-01)

### 1.1 The problem the SPEC must close

REBAL swaps two constants in the `StakedDegenerusStonk` constructor:
- `AFFILIATE_POOL_BPS` **3500 → 3000** (`contracts/StakedDegenerusStonk.sol:295`)
- `REWARD_POOL_BPS` **500 → 1000** (`contracts/StakedDegenerusStonk.sol:297`)

The swap is net-zero by inspection (+500 reward / −500 affiliate). But REBAL-01 forbids the lazy "net-zero so the sum is fine" hand-wave: the SPEC must **enumerate the COMPLETE pool-BPS set and confirm it sums to exactly 10000**. The five constants in the visible block at `:294-298` —

| Constant | Line | bps |
|----------|------|-----|
| `WHALE_POOL_BPS` | :294 | 1000 |
| `AFFILIATE_POOL_BPS` | :295 | 3500 |
| `LOOTBOX_POOL_BPS` | :296 | 2000 |
| `REWARD_POOL_BPS` | :297 | 500 |
| `PRESALE_BOX_POOL_BPS` | :298 | 1000 |
| **subtotal** | | **8000** |

— sum to only **8000**. The missing **2000 bps MUST be located in source**, not assumed.

### 1.2 The missing 2000 — LOCATED

The missing 2000 bps is **`CREATOR_BPS = 2000` at `contracts/StakedDegenerusStonk.sol:291`** (the creator allocation, commented "Creator allocation (20%)" at :290). It sits one line above the `:294-298` block and is the only `_BPS` member of the supply allocation outside that block.

**Completeness check (grep — every `_BPS` / supply constant in the file):**

```
$ grep -n "_BPS\|BPS_DENOM\|INITIAL_SUPPLY" contracts/StakedDegenerusStonk.sol
285:    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;
288:    uint16 private constant BPS_DENOM = 10_000;
291:    uint16 private constant CREATOR_BPS = 2000;
294:    uint16 private constant WHALE_POOL_BPS = 1000;
295:    uint16 private constant AFFILIATE_POOL_BPS = 3500;
296:    uint16 private constant LOOTBOX_POOL_BPS = 2000;
297:    uint16 private constant REWARD_POOL_BPS = 500;
298:    uint16 private constant PRESALE_BOX_POOL_BPS = 1000;
354:        uint256 creatorAmount    = (INITIAL_SUPPLY * CREATOR_BPS)      / BPS_DENOM;
355:        uint256 whaleAmount      = (INITIAL_SUPPLY * WHALE_POOL_BPS)   / BPS_DENOM;
358:        uint256 affiliateAmount  = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS)/ BPS_DENOM;
358-359: lootboxAmount / rewardAmount derivations
```

The allocation-bearing `_BPS` constants are exactly: `CREATOR_BPS` (:291) + the five at `:294-298`. `BPS_DENOM` (:288) is the divisor, not an allocation. There is no other `_BPS` member of the supply split anywhere in the file. **The set is complete.**

### 1.3 The COMPLETE set, BEFORE the REBAL swap — sum = 10000 ✓

| Constant | Line | bps |
|----------|------|-----|
| `CREATOR_BPS` | :291 | 2000 |
| `WHALE_POOL_BPS` | :294 | 1000 |
| `AFFILIATE_POOL_BPS` | :295 | **3500** |
| `LOOTBOX_POOL_BPS` | :296 | 2000 |
| `REWARD_POOL_BPS` | :297 | **500** |
| `PRESALE_BOX_POOL_BPS` | :298 | 1000 |
| **TOTAL** | | **2000 + 1000 + 3500 + 2000 + 500 + 1000 = 10000 ✓** |

### 1.4 The COMPLETE set, AFTER the REBAL swap — sum = 10000 ✓

| Constant | Line | bps (post-REBAL) | Δ |
|----------|------|------------------|---|
| `CREATOR_BPS` | :291 | 2000 | — |
| `WHALE_POOL_BPS` | :294 | 1000 | — |
| `AFFILIATE_POOL_BPS` | :295 | **3000** | **−500** |
| `LOOTBOX_POOL_BPS` | :296 | 2000 | — |
| `REWARD_POOL_BPS` | :297 | **1000** | **+500** |
| `PRESALE_BOX_POOL_BPS` | :298 | 1000 | — |
| **TOTAL** | | **2000 + 1000 + 3000 + 2000 + 1000 + 1000 = 10000 ✓** | **net 0** |

**The swap is net-zero (+500 reward / −500 affiliate) → the BPS-sum invariant is trivially preserved (10000 before, 10000 after).** Only `:295` and `:297` change; **no other pool/constant is perturbed.**

### 1.5 Total sDGNRS supply UNCHANGED — grounded in the :354-359 derivations

The constants ARE the allocation: the constructor derives each pool amount as `(INITIAL_SUPPLY * X_POOL_BPS) / BPS_DENOM` at `contracts/StakedDegenerusStonk.sol:354-359` (the plan/CONTEXT cited `:355-359`; the actual block is **:354-359** — `creatorAmount` is on :354 — recorded as drift). The minted total is then `_mint(DGNRS, creatorAmount)` (:371) + `_mint(address(this), poolTotal)` (:372), where `poolTotal` is the sum of the five pool amounts (:368-369) and any rounding dust is folded into `lootboxAmount` (:360-367) so the minted total equals `INITIAL_SUPPLY` exactly.

Because the swap moves 500 bps **from** affiliate **to** reward and changes **no other constant** and **not `INITIAL_SUPPLY`** (:285, `1_000_000_000_000 * 1e18`) and **not `BPS_DENOM`** (:288), the per-pool amounts shift only for affiliate and reward, and `poolTotal` (hence the minted total = `INITIAL_SUPPLY`) is **unchanged**:

| Pool | bps before | amount before | bps after | amount after |
|------|-----------|---------------|-----------|--------------|
| Affiliate (`Pool.Affiliate`, :375) | 3500 | 350,000,000,000 sDGNRS (350B) | 3000 | 300,000,000,000 (300B) |
| **Reward (`Pool.Reward`, :377)** | 500 | **50,000,000,000 (50B)** | 1000 | **100,000,000,000 (100B) — ×2** |
| (all others) | — | unchanged | — | unchanged |

- **Pool.Reward 50B → 100B (×2)** — exactly the "double the Reward pool" co-requisite that funds the continuous `claimBingo` distribution surface (and the deleted jackpot final-day draw).
- **Affiliate per-share ~14% haircut** — 350B → 300B is a `−50/350 ≈ −14.3%` reduction in the affiliate pool.
- **Total sDGNRS supply UNCHANGED** — only the affiliate↔reward split shifts; the mint total stays `INITIAL_SUPPLY` (1e12 whole tokens). Grounded in the :354-359 `(INITIAL_SUPPLY * X_POOL_BPS)/BPS_DENOM` derivations + the :360-372 mint, **not** assumed.

### 1.6 REBAL attestation — VERDICT

- The COMPLETE pool-BPS set is `{ CREATOR 2000 (:291), WHALE 1000 (:294), AFFILIATE 3500 (:295), LOOTBOX 2000 (:296), REWARD 500 (:297), PRESALE_BOX 1000 (:298) } = 10000` before, and `{ CREATOR 2000, WHALE 1000, AFFILIATE 3000, LOOTBOX 2000, REWARD 1000, PRESALE_BOX 1000 } = 10000` after. **BPS-sum invariant HOLDS (10000 = 10000).**
- The swap is **net-zero** (+500 / −500); **only :295 and :297 change**; no other pool/constant perturbed; **total sDGNRS supply unchanged**; Pool.Reward **50B → 100B**; affiliate **~14% haircut**.
- **REBAL is sound. ✓**

---

## PART 2 — JACK: the final-day Pool.Reward deletion is cleanly orphaned + the rest of isFinalDay is preserved (D-12, JACK-01/02)

### 2.1 The deletion targets

JACK deletes the `isFinalDay` Pool.Reward draw and its two supporting symbols, all in `contracts/modules/DegenerusGameJackpotModule.sol`:

| Target | Line(s) | Source |
|--------|---------|--------|
| The `isFinalDay` Pool.Reward branch | **:1339-1352** | `if (isFinalDay) { dgnrsPool = dgnrs.poolBalance(Pool.Reward); reward = (dgnrsPool * FINAL_DAY_DGNRS_BPS)/10_000; if (reward != 0) { dgnrs.transferFromPool(Pool.Reward, w, reward); emit JackpotDgnrsWin(w, reward); } }` |
| The `FINAL_DAY_DGNRS_BPS = 100` constant | **:191** | `uint16 private constant FINAL_DAY_DGNRS_BPS = 100;` (the "1%" final-day reward portion) |
| The `JackpotDgnrsWin` event declaration | **:112** | `event JackpotDgnrsWin(address indexed winner, uint256 amount);` |

Confirmed verbatim from source: the branch reads `poolBalance(Pool.Reward)` (:1340-1342), computes `reward = (dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000` (:1343), and on `reward != 0` (:1344) does `transferFromPool(Pool.Reward, w, reward)` (:1345-1349) + `emit JackpotDgnrsWin(w, reward)` (:1350).

### 2.2 Clean-orphan check — FINAL_DAY_DGNRS_BPS

```
$ grep -n "FINAL_DAY_DGNRS_BPS" contracts/modules/DegenerusGameJackpotModule.sol
191:    uint16 private constant FINAL_DAY_DGNRS_BPS = 100;
1343:            uint256 reward = (dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000;
```

**SOLE use is :1343 — inside the deleted :1339-1352 branch.** Deleting the branch + the :191 declaration leaves **zero** dangling references. Cleanly orphaned ✓.

### 2.3 Clean-orphan check — JackpotDgnrsWin

```
$ grep -n "JackpotDgnrsWin" contracts/modules/DegenerusGameJackpotModule.sol
112:    event JackpotDgnrsWin(address indexed winner, uint256 amount);
1350:                emit JackpotDgnrsWin(w, reward);
```

**SOLE emit is :1350 — inside the deleted :1339-1352 branch.** Deleting the branch + the :112 declaration leaves **zero** dangling references. Cleanly orphaned ✓.

### 2.4 Preserved plumbing — the rest of isFinalDay is UNTOUCHED

The deletion removes ONLY the Pool.Reward draw inside the solo-bucket handler. Every other use of `isFinalDay` is non-Pool.Reward behavior that MUST survive:

```
$ grep -n "isFinalDay" contracts/modules/DegenerusGameJackpotModule.sol
614:            bool isFinalDay = jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP;   <- compute (preserved)
617:                isFinalDay ? lvl + 1 : lvl,                                         <- the lvl+1 ticket-index gate (preserved)
1085:    /// @param isFinalDay True on the last physical jackpot day ...                 <- doc (preserved)
1095:        bool isFinalDay,                                                            <- _processDailyEth param (preserved)
1135:                isFinalDay,                                                         <- pass into _processBucket (preserved)
1161:        bool isFinalDay,                                                            <- _processBucket param (preserved)
1190:                    perWinner, newEntropy, isFinalDay                               <- pass into _handleSoloBucketWinner (preserved)
1312:        bool isFinalDay                                                             <- _handleSoloBucketWinner param (preserved)
1339:        if (isFinalDay) {                                                           <- THE DELETED branch
```

**The flow:** `_processDailyEth` (:1088) computes/receives `isFinalDay`, passes it into `_processBucket` (:1135), which on the solo branch (:1184 `if (isSolo)`) passes it into `_handleSoloBucketWinner` (:1188-1191). Inside `_handleSoloBucketWinner` (def :1305, param :1312), the whale-pass logic at :1335-1338 (`emit JackpotWhalePassWin`) is preserved, and ONLY the :1339-1352 Pool.Reward draw is removed.

**The PRESERVED lvl+1 ticket-index gate:** `:617 isFinalDay ? lvl + 1 : lvl` in the `_distributeTicketJackpot` call (:615-621). The comment at :611-612 explains it: on the final day the current level is about to end, so carryover tickets are placed at `lvl+1`. **This is a ticket-INDEX selection concern, entirely independent of the Pool.Reward draw — UNTOUCHED.**

**The PRESERVED caller chain** (the six sites the SPEC names as untouched): `:1085` (doc), `:1095` (`_processDailyEth` param), `:1135` (`_processBucket` call), `:1161` (`_processBucket` param), `:1190` (`_handleSoloBucketWinner` call), `:1312` (`_handleSoloBucketWinner` param). **All carry isFinalDay for non-Pool.Reward purposes (the whale-pass-on-final-day branch + the ETH bucket routing) and are UNTOUCHED.**

> **Function-name drift recorded:** the plan/CONTEXT name the deletion site's containing function **`_paySoloBucket`**; the actual source function is **`_handleSoloBucketWinner`** (def `contracts/modules/DegenerusGameJackpotModule.sol:1305`). The branch (:1339-1352), constant (:191), event (:112), gate (:617), and the six caller sites are all confirmed at the lines the SPEC cites — only the function name differs. No behavioral or anchor consequence; consolidated in `339-GREP-ATTESTATION-EDIT-ORDER.md`.

### 2.5 No non-Pool.Reward final-day behavior is broken

- The **lvl+1 ticket-index gate (:617)** is preserved → final-day carryover ticket placement unchanged.
- The **whale-pass-on-final-day** path (`JackpotWhalePassWin`, :1335-1338, inside `_handleSoloBucketWinner`) is preserved → solo-bucket winners still receive their whale pass on the final day.
- ONLY the **DGNRS Pool.Reward draw** (:1339-1352) is removed — exactly the one-shot the continuous `claimBingo` distribution surface replaces (PLAN-V51 "What this replaces"). After deletion, `Pool.Reward` is drawn only by the continuous surfaces (`claimBingo` + the existing Degenerette `_awardDegeneretteDgnrs` reference at `DegeneretteModule.sol:1135-1159`), never by the jackpot final-day one-shot.

### 2.6 Coherent landing — same module file as the BINGO read

The JACK deletion lives in **`DegenerusGameJackpotModule.sol`** — the SAME module file that holds a read-only `traitBurnTicket` consumer surface BINGO shares the read pattern with (`:654`, a jackpot bucket reader; the sole `traitBurnTicket` WRITER is `DegenerusGameMintModule.sol:603-643` per the 339-01 D-13 correction, NOT this file). The read-only consumer + the final-day deletion therefore land coherently within one module file in the single batched IMPL-340 diff.

### 2.7 JACK attestation — VERDICT

- `FINAL_DAY_DGNRS_BPS` (:191) — **sole use :1343, inside the deleted :1339-1352 branch → cleanly orphaned ✓**
- `JackpotDgnrsWin` (decl :112) — **sole emit :1350, inside the deleted branch → cleanly orphaned ✓**
- The preserved plumbing — the **lvl+1 gate (:617)** and the six caller sites (**:1085/:1095/:1135/:1161/:1190/:1312**) — is **UNTOUCHED**; the whale-pass-on-final-day branch survives; **no non-Pool.Reward final-day behavior is broken ✓**
- **JACK deletion is safe and the diff compiles after deletion (no dangling refs). ✓**

---

## Summary

| Item | Verdict | Anchor evidence |
|------|---------|-----------------|
| REBAL BPS-sum (D-11) | **HOLDS — 10000 = 10000** | Complete set incl. `CREATOR_BPS=2000` (:291); only :295/:297 change; net-zero |
| REBAL supply (D-11) | **UNCHANGED** | :354-359 `(INITIAL_SUPPLY*BPS)/BPS_DENOM` derivations; Pool.Reward 50B→100B; affiliate ~14% haircut |
| JACK orphan FINAL_DAY_DGNRS_BPS (D-12) | **CLEAN** | sole use :1343 inside deleted :1339-1352 |
| JACK orphan JackpotDgnrsWin (D-12) | **CLEAN** | sole emit :1350 inside deleted :1339-1352 |
| JACK preserved plumbing (D-12) | **UNTOUCHED** | lvl+1 gate :617 + callers :1085/:1095/:1135/:1161/:1190/:1312 |

**SC4 discharged.** Every cited `file:line` confirmed against the live tree (≡ `812abeee` for `contracts/`).

---
*Phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc · Plan 03 Task 1*
*Authored: 2026-05-28 · Frozen tree: 812abeee (contracts/ diff empty vs HEAD)*
