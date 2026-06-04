# AFF — Deterministic-Split PULL Affiliate Settlement (v56 amendment DRAFT)

**Status:** FOLDED into 353-SPEC.md + REQUIREMENTS + ROADMAP 2026-06-01; re-locked. (Adversarially re-cleared — economic-analyst + zero-day-hunter, NO Medium+ — and folded into `353-SPEC.md` AFF-01/AFF-02/Accumulator/AGG/Threat/XMODEL/SPEC-Lock + REQUIREMENTS AFF/AGG/GAS-02/SEC-01 + ROADMAP, SUPERSEDING the XMODEL roll-unification. Retained as the design-rationale of record.)
**Baseline anchors:** live push mechanism `contracts/DegenerusAffiliate.sol:380 payAffiliate` / roll `:558-582` / buyer-never-wins `:579` / leaderboard `affiliateCoinEarned[lvl]` `:509` + `_updateTopAffiliate :776` / `_routeAffiliateReward → creditFlip :745-751`.
**USER decisions (2026-06-01):** adopt deterministic-split PULL; the affiliate-leaderboard claim-time distortion is ACCEPTED (small #1 reward; afking = a small slice of total affiliate revenue).

## Why drop the roll
The live `payAffiliate` rolls `keccak % 20` and pays ONE winner (affiliate 75% / upline1 20% / upline2 5%) via a single `creditFlip`. The roll is a **push-model gas trick** — pay one winner per buy instead of three. Winner-takes-all @ 75/20/5 odds = the same EV as a 75/20/5 proportional split, with variance. In a PULL model each recipient lazily claims their own batched share, so "pay all three" is no longer 3× per-buy — the roll's reason-to-exist disappears. Dropping it also **deletes the entire seed/settle-timing manipulability surface** (no seed → no XMODEL "free option" → no fixed-boundary-day machinery).

## Mechanism

### 1. Accrue (per-buy, in the STAGE) — truly flat, no branches
Per afking buy, accrue a **flat 7% BURNIE-equivalent affiliate base** (whole BURNIE) into the sub's own packed accumulator slot:
- base = `_ethToBurnie(ethSpent) × 7 / 100` — a **FLAT 7% of the ETH spent, valued in BURNIE at the ETH-equivalent rate** (USER 2026-06-01; `_ethToBurnie` = the v55 helper). Replaces the live `payAffiliate` 25/20/5 level/freshness tiers (`:486-498`) → no rate branch, no `isFreshEth` determination.
- **NO activity taper** (USER 2026-06-01): `_applyLootboxTaper` is NOT applied to afking — truly flat 7%, zero branches on the hot path. *Consequence:* afking affiliate BURNIE emission is **linear in spend, no anti-concentration cap** (the AFF-02 anti-farming taper applies to manual buys only). This is an emission-policy choice, not a security change — it's BURNIE flip-credit OFF the ETH/`claimablePool` solvency path, the split never over-mints, and buyer-never-wins + the intra-chain bound still hold. Removing a reducing-mechanism cannot add an attack surface.
- **NO kickback for afking** (USER 2026-06-01): the gross 7% base accrues; the affiliate's `kickbackPct` rebate-to-buyer is NOT honored on auto-buys (manual buys still get it via the live path). One fewer value flow.
- One warm SSTORE per buy, captured **immutably** at buy time (the 7% of THAT buy is frozen into the running sum). No roll, no cross-contract, no leaderboard write on the hot path.
- One warm SSTORE into the sub's slot (`affiliateBase += base`). NO roll, NO cross-contract, NO leaderboard write on the hot path.
- `affiliateBase` IS a **running unclaimed balance**: buys add to it, claim zeroes it. No "window," no day marker.
- Packed accumulator SHRINKS vs the locked layout — **`settledThroughDay`/`windowStartDay` are DROPPED** (they were scheduled-flush/window bookkeeping; pull has neither): `affiliateBase uint32 (whole-BURNIE, 100M clamp) + questProgress uint8` (+ the freed uint24 = extra packing headroom). **GAS-02 "fit in the Sub slot / no new cold per-buy SSTORE" is preserved** — the only new storage (`pendingClaim`) is touched at claim/withdraw, never per-buy.

### 2. No flush FOR AFFILIATE (the AFFILIATE legs of AGG-02/AGG-03 → pull)
- The accrued `affiliateBase` is the **uplines' money**, not the sub's — captured at each buy's immutable rate. A sub mutation (`setDailyQuantity` / funding change / unsub) does NOT settle the affiliate base; it persists in the slot for the uplines to PULL (an unsub does NOT forfeit the uplines' accrued affiliate). → no affiliate scheduled flush, no affiliate mutation flush, no "mutator pays settle gas" coupling, no keeper `mintBurnie` affiliate leg.
- **The QUEST leg KEEPS an automatic flush** (USER 2026-06-01 — quests settle automatically, see §5). So AGG-02 SURVIVES carrying quest only; AGG-03 reduces to a quest-settle-on-unsub.

### 3. `claim(address[] subs)` — permissionless, SAME-AFFILIATE batch, AGGREGATED credits
**Array constraint (USER 2026-06-01):** every sub in `subs[]` MUST share the same direct affiliate `A`. Read `A` from `subs[0]` (`playerReferralCode` → owner); `require` every other sub resolves to the same `A`; mixed arrays `revert`. → the whole upline chain `A / U1 = _referrerAddress(A) / U2 = _referrerAddress(U1)` is read **ONCE** for the batch, and all credits aggregate to the same three recipients.

Walk the array, accumulating **ONE running total `sumB`** (the split math happens ONCE at the end, not per-sub):
1. `B = affiliateBase[sub]`; if `B == 0` → skip. **Read-and-zero ATOMICALLY per iteration** — set `affiliateBase[sub] = 0` immediately (NEVER pre-load bases into a memory array first; that would reopen the duplicate-sub double-credit).
2. `sumB += B`.
3. **Buyer-never-wins (rare — the only reason this isn't a single line):** `A ≠ sub` is GUARANTEED (self-referral resolves to VAULT in the referral layer), so the **75% leg never skips**. The ONLY skip is the mutual-referral *cycle* where `U1 == sub` or `U2 == sub` (the sub is also their affiliate's upline) → accumulate `skipU1 += B` / `skipU2 += B` for those (near-always 0). *(Knob: or accept the bounded intra-chain self-deal and drop the two comparisons → pure one-accumulator. USER call.)*

After the walk, split + credit **ONCE for the whole batch**:
4. `u1 = (sumB − skipU1)*20/100`, `u2 = (sumB − skipU2)*5/100`, `aShare = sumB − u1 − u2` (A never skips; remainder→A; `Σ ≤ sumB`, never over-mints).
5. `pendingClaim[A] += aShare`, `pendingClaim[U1] += u1`, `pendingClaim[U2] += u2` — **3 local SSTOREs for the whole batch** (cheap, in-contract, NO cross-contract here).
6. Leaderboard **once**: `affiliateCoinEarned[lvl][A] += sumB` (full base to the direct affiliate, mirroring live `:509`) + one `_updateTopAffiliate(A,…)` at the **claim level** (lazy; USER-accepted distortion). *(Knob: or skip afking's leaderboard entirely — afking is a small revenue slice.)*

**noReferrer subs:** form their OWN claim group (no upline chain). Split the aggregated `ΣB` **deterministically 50/50 VAULT / DGNRS** — `pendingClaim[VAULT] += ΣB/2`, `pendingClaim[DGNRS] += ΣB/2` (remainder to VAULT). This **EV-matches the live no-referrer VAULT/DGNRS 50/50 flip** (`:539-554`) WITHOUT entropy, so it preserves the sDGNRS-pool (`DGNRS`) funding leg rather than zeroing it. The same-affiliate-batch rule generalizes to "same distribution-target group" (all-same-real-affiliate `A`, OR all-noReferrer).

**Chain resolved at CLAIM — NON-ISSUE (USER 2026-06-01, supersedes zero-day AFF-1):** `A / U1 / U2` are read from `playerReferralCode` at claim, not snapshotted at accrue. The zero-day hunt flagged this as a "retroactive upline-selection" degree of freedom; the USER correctly observed it grants **nothing**: (a) a **real** upline is set-once / `REF_CODE_LOCKED` → cannot be swapped retroactively at all; (b) an **unset** upline resolves to `VAULT`, and pointing it at one's own wallet is a choice available **at any time with the identical outcome** (the affiliate captures the same 20%/5% regardless of WHEN they set the sybil upline) — there is no timing edge. It is simply the affiliate occupying their own upline slot (the would-be-VAULT slice), which is the always-available, already-accepted intra-chain redistribution (`:556-557`), equally available under the live roll. So claim-time resolution ≡ buy-time resolution in value terms; **no new property to name, no mitigation needed.** The direct-75% leg `A` is itself locked-immutable. 

**Quest double-credit (econ-review #6, IMPL-verification item):** the accumulator→`pendingClaim` refactor MUST preserve the `lastCompletedDay` write/ordering (`DegenerusQuests.sol:1596`) — pull changes WHEN BURNIE mints, never WHAT streak/day is recorded. Verify at IMPL 354; not a design hole. 
**Permissionless + caller-agnostic:** anyone may call; credits route to the rightful `A/U1/U2`, never `msg.sender` — the same-affiliate rule is purely for AGGREGATION, not authorization. The common caller is `A` settling their own downline (or a keeper grouping by affiliate). Doubles as a free crank; no theft vector, no griefing payoff (worst case = forcing a leaderboard level the USER already accepts). Only the per-sub `affiliateBase` zeroing is O(N); the recipient + leaderboard writes are O(1).

### 4. `withdraw()` — the ONLY cross-contract leg
Mints `pendingClaim[msg.sender]` BURNIE via `coinflip.creditFlip`, zeroes it first (**CEI**). Batched per recipient across all their claims — one `creditFlip` regardless of how many subs fed them.
- *(Optimization knob: `claim` may auto-`withdraw` the caller's own freshly-credited share at the end — one `creditFlip` for the active claimer — while uplines withdraw themselves. Default keeps them separate for clean batching.)*

### 5. Quest — AUTOMATIC push (NOT pull) — USER 2026-06-01
The quest reward is the **sub's OWN** reward for participating → it pays AUTOMATICALLY, no sub action (good UX; the sub earned it). Mechanism = the original v56 quest batching:
- The slot-0 delivered-day BURNIE accrues per delivered day into `questProgress` (a **running balance**, cheap in-slot, no cross-contract on the hot path); the ±10 streak progresses in the `DegenerusQuests` core.
- A **scheduled ~10-day `mintBurnie` flush** (keeper-cranked — **AGG-02 SURVIVES, quest-only**) drains `questProgress` → one `creditFlip` to the sub + applies the streak bonus, then zeroes it. On unsub, a lightweight quest-settle drains the sub's accrued quest (AGG-03 quest-only).
- **No day marker needed** here either: the flush DRAINS the pre-accrued running balance (self-marking — a double-fire finds `questProgress == 0`), so the AGG-05 `lastSettledDay` double-settle gate is unnecessary.
- The ±10 streak / confirmed-vs-provisional (bonuses read the confirmed-delivered streak) / `lastCompletedDay` double-credit guards are UNCHANGED; slot rewards never suppressed.
→ one `creditFlip` to the sub per ~10 days; the per-buy hot path stays a cheap accrue.

## Storage delta
- KEEP: the in-Sub-slot accumulator, now SHRUNK to `affiliateBase uint32 + questProgress uint8` (running balances, zeroed on claim).
- ADD: `mapping(address => uint256) pendingClaim` (post-split per-recipient ledger; off the STAGE). No per-buy cold SSTORE → GAS-02 preserved.
- REMOVE: the scheduled `mintBurnie` settlement-due leg, the mutation-flush, the AFF-01 fixed-boundary-day roll seed, **and `settledThroughDay`/`windowStartDay`** (the zeroed running balance is self-marking; no double-settle window exists in pull).

## Threat model (NEW — the old roll/seed analysis does NOT transfer)
Surfaces to clear:
- **Double-claim** → `affiliateBase` zeroed; second claim sees `B==0` → no-op. Idempotent with no day marker (the zeroed running balance is self-marking).
- **Claim-griefing** → permissionless but always-correct-recipient → no theft; worst case = a forced leaderboard level (USER-accepted).
- **Self-referral / buyer-wins** → skip-position (drop, not redirect) preserves `:579`.
- **Reentrancy on withdraw** → CEI (zero before `creditFlip`); `creditFlip` target is trusted.
- **Rounding / over-mint** → floor splits, remainder to A, `Σshares == B`. Dust 5%-of-small-buy rounds to 0 whole-BURNIE (immaterial, off solvency, round-down favors protocol).
- **Sybil / 2-wallet intra-chain** → identical EV to the live roll (75/20/5); intra-upline-chain-only, value-conserving — the EXISTING USER-accepted `:556-557` semantic. No NEW edge; the XMODEL "free option" cannot exist (single deterministic path).
- **Solvency** → BURNIE flip-credit, OFF the ETH/`claimablePool` path; SOLVENCY-01 untouched. BURNIE minted lazily at withdraw (mintable, off solvency).
- **Unclaimed balances** → lazy affiliates leave BURNIE unminted (no solvency impact; "claim to receive/rank").

## What this changes in `353-SPEC.md`
- **AFF-01** — replace the roll-unification lock with the **flat-7% deterministic-split PULL** lock (no seed, no roll; `claim`/`withdraw`).
- **AFF-02** — taper now **afking-N/A** (flat 7%, taper applies to manual buys only); leaderboard claim-time-credited (USER-accepted).
- **AGG (split affiliate vs quest):** affiliate AGG-02/AGG-03 legs → **pull**. **AGG-02 SURVIVES quest-only** (the ~10-day flush mints the sub's quest BURNIE + streak); **AGG-03 → quest-settle-on-unsub**; AGG-04 (uniform ticket+lootbox settle) applies to the quest flush; **AGG-05 double-settle markers DROPPED** (affiliate + quest both use self-marking running balances zeroed at settle).
- **Accumulator layout** — SHRUNK: `affiliateBase uint32 (whole-BURNIE, 100M clamp) + questProgress` (both running balances), `settledThroughDay`/`windowStartDay` DROPPED; ADD the `pendingClaim` mapping (affiliate recipients, off the STAGE).
- **Threat re-attestation** — swap the seed/roll non-gameability argument for the deterministic-split/pull argument (no seed surface; chain-at-claim is a non-issue per USER; CEI on withdraw; over-mint-impossible).
