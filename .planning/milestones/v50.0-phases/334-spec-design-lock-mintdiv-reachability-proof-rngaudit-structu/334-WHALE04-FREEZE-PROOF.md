# WHALE-04 — RNG-Freeze-Safety Proof for the Deferred Whale-Pass Claim Split (SC2)

**Phase:** 334 — SPEC (paper-only; zero `contracts/*.sol` edits)
**Requirement:** WHALE-04
**Baseline:** v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` (`contracts/` working tree byte-identical to `b0511ca2`; `git diff b0511ca2 HEAD -- contracts/` empty).
**Verdict:** **FREEZE-SAFE.**

---

## 0. Posture — this is a re-attestation of EXISTING gates, NOT a novel claim system (D-20)

WHALE-01/02/04 is a **CONVERGENCE refactor** onto already-deployed machinery, not a greenfield build. Every gate this proof relies on is present at `b0511ca2`:

- `claimWhalePass(address player)` **already exists** — `DegenerusGameWhaleModule.sol:1018`. It is already permissionless-with-beneficiary-arg (D-01), already claim-time-anchored to `level + 1` (D-03, `WhaleModule:1030`), already backed by a `whalePassClaims[player]` **uint count** (D-02, read at `WhaleModule:1020`, zeroed at `:1024`), and already applies `_applyWhalePassStats` at claim (D-04, `WhaleModule:1032`).
- It is fed today by the jackpot/payout path: `_queueWhalePassClaimCore` (`DegenerusGamePayoutUtils.sol:45`, the reference `whalePassClaims[winner] += ...` writer) and `DegenerusGameJackpotModule.sol:1410` (`whalePassClaims[winner] += whalePassCount`).

**WHALE-01's job is to route the box-open boon (`_activateWhalePass`, `DegenerusGameLootboxModule.sol:1240`, the inline 100-loop at `:1250-1260`) onto this SAME machinery** — an O(1) `whalePassClaims[beneficiary] += grant` mirroring `PayoutUtils.sol:45`, NOT a new `pendingWhalePasses` map and NOT a new claim function.

> **D-20 relabel note:** D-02's `pendingWhalePasses` is a **RELABEL of the existing `whalePassClaims`**. There is no parallel claim system. Building a second counter would double this freeze-proof surface (research "Pitfall 1") and is explicitly rejected. Wherever this proof or the IMPL says `pendingWhalePasses`, read `whalePassClaims`.

Because of this convergence, the freeze proof below is **largely a re-attestation that the existing `_queueTickets` / `_queueTicketRange` far-future + `rngLock` gates and the `claimWhalePass` `_livenessTriggered()` revert continue to hold for the box-open path once it is routed through the existing claim** — not a fresh argument about new code.

---

## Write-set map (the two surfaces this proof must cover)

| Path | Write set | Frozen-slot risk |
|------|-----------|------------------|
| **Box-open O(1) record** (new WHALE-01 site, replacing the `_activateWhalePass:1250-1260` loop) | `{ whalePassClaims[beneficiary] += grant }` | **None** — `whalePassClaims` is a pending-claim counter, not a VRF-influenced slot. NO `mintPacked_` write. NO `ticketsOwedPacked` write at open. |
| **`claimWhalePass(player)`** (existing, `WhaleModule:1018`) | `{ whalePassClaims[player] ← 0; mintPacked_[player] future-anchored (via `_applyWhalePassStats`); ticketsOwedPacked[future levels] (via `_queueTicketRange`) }` | far-future band (`currentLevel+6..+100`) `rngLock`-gated to **revert**; near-future band (`currentLevel+1..+5`) lands in a **disjoint write keyspace** from the current read slot; the whole claim **reverts** under `_livenessTriggered()`. |

The five sections below prove each member of these write sets is freeze-safe.

---

## §1 — Box-open O(1) record writes ONLY `whalePassClaims`; NO `mintPacked_`, NO `ticketsOwedPacked` at open

After WHALE-01, the box-open path replaces the `_activateWhalePass` inline loop **and** its `_applyWhalePassStats` call (`DegenerusGameLootboxModule.sol:1247`) with a single O(1) increment:

```solidity
// WHALE-01 box-open record (replaces _activateWhalePass:1247-1260)
whalePassClaims[beneficiary] += grant;   // mirrors PayoutUtils.sol:45 / JackpotModule.sol:1410
```

- `whalePassClaims` is a **pending-claim accumulator** — a uint counter consumed only later by `claimWhalePass` (`WhaleModule:1020`). It does **not** participate in any VRF-derived output of the current resolution window.
- **No `mintPacked_` write at box-open** (D-04). The stats application (`_applyWhalePassStats`) moves to claim-time; box-open touches no freeze/levelCount state.
- **No `ticketsOwedPacked` write at box-open.** The 100-level `_queueTickets` loop (`:1250-1260`) is deleted; box-open queues no tickets.

The current-window VRF-derived outputs (the day's lootbox/jackpot trait derivation) read `ticketsOwedPacked` (the current read slot) and `mintPacked_` (freeze state) — **neither of which box-open now touches.** The box-open record is therefore freeze-safe: it writes one non-participating counter slot and nothing else.

**Box-open write set = `{ whalePassClaims }`.**

---

## §2 — `claimWhalePass` queues ONLY future levels: far-future band `rngLock`-gated to revert; near-future band a disjoint keyspace; the whole claim reverts under liveness

Claim-time anchoring (D-03) sets `startLevel = level + 1` (`WhaleModule:1030`) and `_queueTicketRange(player, startLevel, 100, halfPasses, false)` (`WhaleModule:1034`) queues `startLevel .. startLevel+99` = `currentLevel+1 .. currentLevel+100`. The `rngBypass` arg is `false` (`WhaleModule:1034`), so the gate is **not** bypassed.

`_queueTicketRange` (def `DegenerusGameStorage.sol:647`) runs, per level, the SAME gate as `_queueTickets`:

```solidity
// DegenerusGameStorage.sol — _queueTicketRange body
if (_livenessTriggered()) revert E();                               // :655 — terminal-jackpot freeze
...
bool isFarFuture = lvl > currentLevel + 5;                          // :660
if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked(); // :661 — the current-window gate
```

(Identical shape to `_queueTickets:571/572/573`.) Partition the queued band by the `targetLevel > level + 5` boundary (the **far-future** test — addressing research Pitfall 4: do NOT assert "future levels therefore safe" without this boundary):

- **`currentLevel+6 .. currentLevel+100` — FAR-FUTURE (`lvl > currentLevel + 5`).** `isFarFuture == true`. Under `rngLock` (`rngLockedFlag == true`) with `rngBypass == false`, `_queueTicketRange:661` executes `revert RngLocked()`. **A claim during `rngLock` that would write a far-future slot REVERTS entirely** — no partial write, no frozen-window mutation. This is 95 of the 100 queued levels.

- **`currentLevel+1 .. currentLevel+5` — NEAR-FUTURE (`lvl <= currentLevel + 5`).** `isFarFuture == false`, so the `rngLock` revert at `:661` does **not** fire for these 5 levels. Freeze-safety here rests on **keyspace disjointness**, not the gate: these target levels are all strictly **greater** than the current resolving level (`lvl >= currentLevel + 1 > level`). The current daily resolution consumes the **current** level's read slot (the active `ticketLevel` read key); near-future writes land in `_tqWriteKey(lvl)` for `lvl > level` (`Storage:576/662`) — a **distinct keyspace** from the current read slot. They cannot perturb the current window's frozen input. (This is the v48 disjoint-keyspace argument: near-future cursor band vs current read slot.)

- **Liveness backstop (covers ALL 100 levels).** Independently of the far-future/near-future split, `claimWhalePass:1019` executes `if (_livenessTriggered()) revert E();` at the top of the function (def `Storage:1213`). During the terminal-jackpot freeze window the **entire claim reverts** before any queue write — so a claim cannot add tickets after the VRF word that resolves the terminal jackpot becomes known. This is the same gate `_queueTickets:571` and `_queueTicketRange:655` enforce, applied once at the claim entrypoint.

**`claimWhalePass` `ticketsOwedPacked` write set = `{ future levels: far-future (rngLock-gated to revert) ∪ near-future (disjoint keyspace) }`.** No current read slot is ever written.

---

## §3 — `_applyWhalePassStats` at claim writes `mintPacked_` future-anchored; the two preserved immediate-apply callers are UNTOUCHED

`_applyWhalePassStats` (def `DegenerusGameStorage.sol:1111`) runs **inside the claim** (`WhaleModule:1032`), anchored to the same claim-time `ticketStartLevel = currentLevel + 1` (`WhaleModule:1030`) as the tickets. It writes `frozenUntilLevel`, `levelCount`, `bundleType`, `lastLevel`, `day` into `mintPacked_[player]` — all anchored to `currentLevel+1` and beyond (`targetFrozenLevel = ticketStartLevel + 99`). These are **future-level** freeze-extension stats; they do not alter any value the **current** day's VRF-derived output reads.

The SAME internal is already called **immediate-apply** from two callers that **STAY UNTOUCHED per D-04**:

- **`DegenerusGameWhaleModule.sol:1032`** — the whale-bundle purchase path (immediate-apply, untouched).
- **`DegenerusGameDecimatorModule.sol:588`** — the Decimator win path (immediate-apply, untouched).

(These two are the only `_applyWhalePassStats` callers besides the claim; v49 already proved them freeze-safe.) WHALE-01 moves the **box-open** caller's invocation from box-open-time to claim-time (D-04). This changes **WHEN** the stats are written, **not WHICH** slots — and claim-time is gated by §2's reverts. There is no new slot and no regression versus the immediate-apply callers.

**`claimWhalePass` `mintPacked_` write = future-anchored stats, freeze-safe; the WhaleModule:1032 + DecimatorModule:588 immediate-apply callers are explicitly out of scope (D-04).**

---

## §4 — Liveness gate keeps the pass claimable-eventually (never marooned)

The `whalePassClaims[beneficiary]` counter (§1) **persists across `rngLock` windows** — it is never gated; only the materializing claim is. A claim attempted during `rngLock` / liveness reverts (§2 far-future band, and the §2 liveness backstop at `WhaleModule:1019`), but the count is **untouched**. The beneficiary (or any caller, since the claim is permissionless — D-01) simply claims after the window. The grant is never trapped: the only state that could be lost is a far-future ticket write, and that write is *deferred*, not dropped, because the counter survives the revert.

**Corollary (D-23, record-only):** Unclaimed `whalePassClaims` at `gameOver` are **forfeit** — there are no future levels left to materialize and `claimWhalePass:1019` reverts under `_livenessTriggered()`. Consistent with "claim whenever is fine"; no auto-claim-at-gameOver. (One-sentence record per D-23; not a freeze concern.)

---

## §5 — Re-attestation of the `v45-vrf-freeze-invariant` for the split

The **`v45-vrf-freeze-invariant`** (named explicitly): *"every variable interacting with a VRF word must be frozen [rng request → unlock] vs players; `advanceGame` is exempt; verify consumed-this-cycle, not buffered-for-next."*

Apply it to the WHALE-01 split's full write set:

| Slot written | By | VRF-interaction within the locked window | Disposition |
|--------------|----|------------------------------------------|-------------|
| `whalePassClaims[beneficiary]` | box-open record (§1) + claim zero (§2) | **None** — pending-claim accumulator, not a current-window output input | Non-participating → freeze-safe |
| `ticketsOwedPacked[far-future]` | `_queueTicketRange` in claim (§2) | Would interact, but **reverts** under `rngLock` (`Storage:661`) | Gated → freeze-safe |
| `ticketsOwedPacked[near-future +1..+5]` | `_queueTicketRange` in claim (§2) | **Disjoint** write keyspace from the current read slot (`lvl > level`) | Buffered-for-next, NOT consumed-this-cycle → freeze-safe |
| `mintPacked_[player]` | `_applyWhalePassStats` in claim (§3) | Future-anchored (`currentLevel+1 .. +99`); current freeze state untouched | Future-anchored → freeze-safe |

The current-window VRF-derived outputs (daily trait buckets, jackpot, lootbox trait derivation) read only the **current-level** `ticketsOwedPacked` + the **current** `mintPacked_` freeze state — **none of which the deferred box-open record or the gated claim mutate within the locked window.** This is precisely the v45 "consumed-this-cycle, not buffered-for-next" distinction: every WHALE-01 write is either non-participating, gated-to-revert, or buffered for a future level. **The `v45-vrf-freeze-invariant` HOLDS for the split.**

---

## Verdict

**FREEZE-SAFE.** The box-open → deferred-claim split writes no current-RNG-window slot during `rngLock`:

- box-open writes only the `whalePassClaims` counter (§1);
- the claim queues only `currentLevel+1..+100`, of which the far-future band (`+6..+100`) reverts under `rngLock` (§2) and the near-future band (`+1..+5`) lands in a disjoint keyspace (§2);
- the whole claim reverts under `_livenessTriggered()` (§2 backstop);
- claim-time `_applyWhalePassStats` writes future-anchored `mintPacked_`, identical-slot to the two untouched immediate-apply callers (§3);
- the counter persists across `rngLock`, so no grant is marooned (§4);
- the `v45-vrf-freeze-invariant` is re-attested member-by-member (§5).

This authorizes the WHALE-01/02/03 box-open → deferred-claim split at IMPL (335). Because the machinery (`claimWhalePass:1018` / `whalePassClaims` / `_queueTicketRange:647` / `_applyWhalePassStats:1111` / the `Storage:661` gate / the `WhaleModule:1019` liveness revert) all already exists and is grep-attested at `b0511ca2`, this verdict is a re-attestation of existing gates, not a claim about unwritten code.

---

## Anchor citations (all confirmed vs `b0511ca2` — see 334-RESEARCH.md grep-attestation table)

| Fact | `file:line` |
|------|-------------|
| `claimWhalePass(address player)` def | `DegenerusGameWhaleModule.sol:1018` |
| `claimWhalePass` `_livenessTriggered()` revert | `DegenerusGameWhaleModule.sol:1019` |
| `whalePassClaims[player]` read / zero | `DegenerusGameWhaleModule.sol:1020` / `:1024` |
| claim-time anchor `startLevel = level + 1` | `DegenerusGameWhaleModule.sol:1030` |
| claim `_applyWhalePassStats` call (claim-time, D-04) | `DegenerusGameWhaleModule.sol:1032` |
| claim `_queueTicketRange(player, startLevel, 100, halfPasses, false)` | `DegenerusGameWhaleModule.sol:1034` |
| reference O(1) writer `_queueWhalePassClaimCore` (`whalePassClaims += ...`) | `DegenerusGamePayoutUtils.sol:45` |
| jackpot writer `whalePassClaims[winner] += whalePassCount` | `DegenerusGameJackpotModule.sol:1410` |
| box-open `_activateWhalePass` (WHALE-01 edit site) | `DegenerusGameLootboxModule.sol:1240` |
| box-open inline 100-loop to delete | `DegenerusGameLootboxModule.sol:1250-1260` |
| `_queueTickets` def + gate | `DegenerusGameStorage.sol:560` (liveness revert `:571`, far-future `:572`, RngLocked `:573`) |
| `_queueTicketRange` def ("optimized for whale pass claims") + gate | `DegenerusGameStorage.sol:647` (liveness revert `:655`, far-future `:660`, RngLocked `:661`) |
| `_applyWhalePassStats` def | `DegenerusGameStorage.sol:1111` |
| `_livenessTriggered` def | `DegenerusGameStorage.sol:1213` |
| `rngLockedFlag` | `DegenerusGameStorage.sol:279` |
| immediate-apply caller (bundle, UNTOUCHED, D-04) | `DegenerusGameWhaleModule.sol:1032` |
| immediate-apply caller (Decimator, UNTOUCHED, D-04) | `DegenerusGameDecimatorModule.sol:588` |

---

*Phase 334 SPEC artifact — WHALE-04 freeze proof (SC2). Verdict FREEZE-SAFE. Records the §1–§5 slot-by-slot argument established in 334-RESEARCH.md; does not re-derive or re-open it.*
