# 389-01 — NET 1 (Cross-Model Council) Capture Record — PACKING-IDENTITY (STORAGE + GASID)

**Subject (byte-frozen):** `a8b702a7` (contracts tree `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Net:** NET 1 = the cross-model council (external `gemini` + `codex` CLIs via `council.sh`).
**Purpose:** per AUDIT-V63-PLAN §2, a no-finding verdict for any sweep slice requires BOTH nets on
record. This record puts NET 1 on record for the packing-identity surface so the Wave-2 Claude-net +
adjudication plan (389-02) can fold the council leads in BEFORE any per-item verdict. RAW capture only —
NOT adjudicated, refuted, or fixed here (adjudication is 389-02).

---

## NET 1 ON RECORD for STORAGE + GASID

Both slices fanned to both council models; **0 CLIs skipped on either slice**. Every FC-389-* lead and
every STORAGE-01..07 / GASID-01..05 thesis point received a traced response from BOTH models.

## Council manifests (available / skipped per slice)

| Slice | Label | council.json | Available models | Skipped models |
|-------|-------|--------------|------------------|----------------|
| STORAGE | `storage` | `council/storage.council.json` | `gemini`, `codex` | (none) |
| GASID | `gasid` | `council/gasid.council.json` | `gemini`, `codex` | (none) |

Council runner: `.planning/audit-v52/cross-model/bin/council.sh` (read-only `--approval-mode plan`
wrappers; the models may `git show a8b702a7:contracts/<File>.sol` but cannot mutate). No `--schema` was
passed → free-text `.txt` outputs. Both slices were run SERIALLY (STORAGE then GASID) per the pacing rule.

## Raw output file paths

| Slice | gemini | codex |
|-------|--------|-------|
| STORAGE | `council/storage.gemini.txt` (25 lines) | `council/storage.codex.txt` (39 lines) |
| GASID | `council/gasid.gemini.txt` (47 lines) | `council/gasid.codex.txt` (62 lines) |

(`council/storage.{gemini,codex}.err` + `council/gasid.{gemini,codex}.err` hold the per-model stderr;
both models exited 0 on both slices.)

---

## One-line characterization per model per slice (RAW — not adjudicated)

### STORAGE slice

- **storage.gemini:** All STORAGE-01..07 + FC-389-01..04 returned **VERIFIED SOUND/IDENTICAL**. Traces
  the EV two-window masks (`_EV_WINDOW_B_MASK`), confirms deferred opens draw from the live level so the
  live key set stays `{level, level+1}`, and asserts the active harnesses (`V55RevertFreeEvCap`@40/34,
  `AfKingConcurrency` subscribers@56) are correctly recalibrated aside from the known legacy
  `RedemptionInvariants` hole. **On FC-389-03 it claims the comment is CORRECT** (says `totalBurn` stores
  effective amounts) — i.e. it disagrees with the storage-map's "raw burns" framing.

- **storage.codex:** **No production packing bug** in STORAGE-01/02/03/04/05/07 — all VERIFIED SOUND with
  `file:line` anchors at `a8b702a7`. Surfaced **3 concrete STORAGE-06 stale-harness FINDINGS** (LOW /
  confirmatory, beyond the known `RedemptionInvariants` hole): (1) `Composition.inv.t.sol` /
  `CompositionHandler.sol` reads `keccak(player,10)` for `mintPacked_` but slot 10 is now `rngWordByDay`;
  (2) `SweepWorstCaseDrain.t.sol` + `RngLockDeterminism.t.sol` hardcode box-cursor/player slots 58/59 but
  the real `boxCursor`/`boxPlayers` moved to 59/60; (3) `HeroOverride*.test.js` seed
  `LOOTBOX_RNG_PACKED_SLOT = 35` but the real `lootboxRngPacked` is at 34 (35 is now
  `lootboxRngWordByIndex`'s root). **On FC-389-03 it agrees the comment is imprecise but locates it on
  `DecEntry.burn`** (says regular `DecClaimRound.totalBurn` stores EFFECTIVE burn, not raw) — also
  contradicting the storage-map's "raw burns" framing, but pointing at a different field than gemini.

### GASID slice

- **gasid.gemini:** All GASID-01..05 + FC-389-05..09 **VERIFIED IDENTICAL/SOUND**. Confirms the 30
  wrapper selectors match, the `hash2` 64-byte scratch == `abi.encode` preimage (incl. the
  `uint256(uint160(player))` address-padding equality), the PriceLookupLib nibble table over the cycle,
  the single-hero trait-roll consolidation, and the five FC leads (rngWord narrowing non-grindable;
  level-0 unreachable via `level+1` + 0.8 checked arithmetic; `newClaimed` bounded by pro-rata
  allocation; sDGNRS narrowings exceed physical supply; dynamic-array wrappers share the decoder).

- **gasid.codex:** **No findings.** All GASID-01..05 + FC-389-05..09 VERIFIED IDENTICAL/SOUND with
  `file:line` anchors. Provided the **full recomputed 30-row selector table** (every wrapper selector ==
  module selector, e.g. `advanceGame 0x75b5e924`, `claimBingo 0x039349d9`, `rawFulfillRandomWords
  0x1fe543e3`), recomputed the PriceLookupLib oracle over `level ∈ [0,99999]` = **0 mismatches**, and
  traced `DecClaimRound.rngWord` reads (winner selection uses the full word at `:242/:269`; only
  `uint32(rngWord)` stored at `:277`; sole read at `:410` → `resolveLootboxDirect`).

---

## Raw council leads routed to 389-02 Wave-2 adjudication (NOT adjudicated here)

The council net is on record. The following are the RAW leads/divergences for 389-02 to fold in against
the Claude net before any verdict:

1. **STORAGE-06 stale-harness leads (codex, 3 new + 1 known).** Codex named 3 additional slot-hardcoded
   harnesses that may poke a MOVED field (`Composition`/`CompositionHandler` slot-10; `SweepWorstCaseDrain`
   + `RngLockDeterminism` box-cursor slots 58/59; `HeroOverride*.test.js` lootboxRng slot 35). Gemini
   asserted the active harnesses are clean aside from the known `RedemptionInvariants` hole. **389-02 must
   verify each codex-named harness against `forge inspect` / the 388-01 LAYOUT-KEY** to confirm whether
   these are real stale-slot pokes (LOW / oracle-integrity, not contract defects) or false positives. NOTE
   the 388-01 LAYOUT-KEY §6 reconciliation ledger did NOT list these three harnesses — they are outside
   the four reshuffled contracts' explicitly-reconciled poke set, so they warrant a direct check.

2. **FC-389-03 model divergence on `DecClaimRound.totalBurn` framing.** The storage-map (FA-3) framed
   `totalBurn` as storing RAW burns with an imprecise "effective amounts" comment. BOTH council models
   instead assert the accumulator stores EFFECTIVE burns — gemini says the `DecClaimRound.totalBurn`
   comment is therefore correct and relocates the imprecision to `DecEntry.burn`; codex agrees the
   imprecision is on `DecEntry.burn` ("BURNIE burned" but stores effective). **389-02 must re-read the
   Decimator accumulator path (`_recordDecimatorBurn` / `_decEffectiveAmount` / `_decUpdateSubbucket`) at
   `a8b702a7`** to settle raw-vs-effective and pin which comment (if any) is imprecise. Either way the
   uint128 bound is agreed sound by all three lenses (raw < effective < BURNIE supply < 2^128) — this is
   an INFO comment-accuracy item, not an overflow risk.

3. **All other FC-389-* leads (01, 02, 04, 05, 06, 07, 08, 09) and all STORAGE/GASID thesis points** were
   returned **SOUND/IDENTICAL by both models** with source traces. 389-02 should confirm these against the
   Claude net; convergent council SOUND + Claude SOUND = both-nets-on-record for a no-finding verdict on
   those items.

---

## Byte-freeze attestation (after the council fan-out)

Both slices fanned; immediately verified the subject was not mutated:

- `git diff a8b702a7 -- contracts/` → **EMPTY** (subject byte-frozen; council writes only to its out-dir).
- `git status --porcelain contracts/` → **EMPTY** (no working-tree contract change).

The council ran in read-only `--approval-mode plan` and produced output only under
`.planning/phases/389-packing-identity/council/`. T-389-01 (tampering of the byte-frozen subject)
mitigation satisfied. T-389-02 (a slice silently treated as on-record with both CLIs unavailable) does
not apply — both CLIs were available on both slices (skipped[] empty for both).
