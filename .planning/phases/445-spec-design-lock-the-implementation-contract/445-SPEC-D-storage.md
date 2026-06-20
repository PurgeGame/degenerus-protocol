# 445 SPEC — Section D: Storage Layout (foilRecord + cap flag + foilMatchClaimed)

> Build-ready storage half of the v71.0 Foil Pack design-lock. Every layout choice below is the
> RESEARCH.md §D reconciled-and-corrected form (V3 PASS, the E.6 168-bit superset). An IMPL-446
> author declares the two new mappings, the five private-constant masks/shifts, and the two
> accessors with **zero** further layout decision (beyond confirming the two pins below). Consumed
> by Plan 04's consolidation.
>
> Scope: this section is paper-only. It appends three storage items — ONE packed `foilRecord`
> slot per player, the folded per-raw-level cap (no separate slot), and the sparse
> `foilMatchClaimed` marker — at the tail of `DegenerusGameStorage`. No existing slot moves
> (SEC-04). HARD CONSTRAINT: `contracts/*.sol` is read-only; nothing here edits a `.sol`.

---

## D.0 Grounded baseline facts (V3: all PASS)

| Fact | Source | Value |
| --- | --- | --- |
| Canonical game level type | `DegenerusGameStorage.sol:236` | `uint24 public level = 0` (≤ 16,777,215) |
| Whale-pass deferred grant (**already exists**) | `whalePassClaims:1122` | `mapping(address => uint256)` — do NOT re-declare |
| Century level-stamp idiom (the template) | `centuryBonusUsed:1857-1876` | `(level << 224) \| payload`; `_centuryUsedFor` returns the payload ONLY when `(packed >> 224) == level`, else `0` (auto-reset) |
| Retained daily RNG (claim re-derivation source) | `rngWordByDay:462` | `mapping(uint24 => uint256)` — claim re-derives from this, no draw-time scan |
| `TICKET_SCALE` | `:157, :663` | **100** (4 whole foil tickets = `quantityScaled = 400`) |
| **Append point (next free slot)** | `:2393` | `mapping(uint48 => address[]) internal boxPlayers;` is the LAST state var; closing `}` at `:2394`. New state appends **after `:2393`, before `:2394`**. |

A foil signature carries 4 quadrants × the full 6-bit `[CCC][SSS]` (color AND symbol — MATCH-03:
"color-only does NOT count"), packed into a `uint32` in the **identical `[QQ][CCC][SSS]`-per-byte
layout** as `packedTraitsFromSeed` / `packedTraitsFoil` (so the match predicate is a direct byte
compare).

---

## D.1 `foilRecord` — ONE packed slot per player (FOIL-01, MATCH-01, MATCH-02, SEC-03)

**LOCKED form: one packed `uint256` per player — `mapping(address => uint256) internal foilRecord`
appended after `DegenerusGameStorage.sol:2393`** (before the `:2394` closing brace), with an embedded
level stamp (the century idiom), NOT a `level => player` outer map. The record stores the **full
packed `uint32` per ticket PLUS the frozen 16-bit `multBps`** — the reconciled E.6 168-bit superset.

### D.1.1 The packed 168-bit superset (the LOCKED bit layout)

`foilRecord[player]` is **one `uint256`** holding the reconciled E.6 superset: **4 × 32-bit packed
ticket signatures + a 16-bit frozen `multBps` + a 24-bit raw-level stamp = 168 bits ≤ 256**. The
buy path writes this in **ONE SSTORE**; the claim path reads it in **ONE SLOAD**.

| field | width | bit range (LSB→MSB) | meaning |
| --- | --- | --- | --- |
| `sig0` | 32 bits | `[0-31]` | ticket-0 packed `uint32` signature |
| `sig1` | 32 bits | `[32-63]` | ticket-1 packed `uint32` signature |
| `sig2` | 32 bits | `[64-95]` | ticket-2 packed `uint32` signature |
| `sig3` | 32 bits | `[96-127]` | ticket-3 packed `uint32` signature |
| `multBps` | 16 bits | `[128-143]` | the frozen `foilBoostBps` output (range `20000..60000`); RARE-03 |
| `rawLevel` stamp | 24 bits | `[144-167]` | the raw `uint24 level` (`:236`) at buy; doubles as the cap flag |
| reserved | 88 bits | `[168-255]` | unused, always `0` |

**Bit budget:** `4 × 32 (sigs) + 16 (multBps) + 24 (stamp) = 168 bits ≤ 256`. One slot.

### D.1.2 E.6 superset adopted OVER the D.1 24-bit variant (V3 DEFECT D-α resolved)

The **E.6 168-bit form is adopted over** the D.1 24-bit/no-`multBps` variant. The frozen `multBps`
is **REQUIRED** in the record by **RARE-03 / MATCH-09**: the jackpot resolve path consumes the
frozen multiplier (the `/15360` ladder of §A.1.4) and the match re-derivation reads it back, so the
multiplier must live in the slot rather than being live-recomputed. Storing the full packed `uint32`
per ticket (not a narrower match-only signature) is the robust superset and matches the
`packedTraitsFoil` output byte layout, so the match predicate is a direct byte compare. (A 24-bit
match-only signature would be sufficient only if the boosted jackpot traits were resolved on a
separate path; the full packed value is the chosen superset.)

### D.1.3 The five private-constant masks/shifts (no storage footprint)

The IMPL declares these as `private constant` (inlined like `_CENTURY_USED_MASK:1864`; they consume
**no slots**), keyed to the §D.1.1 bit ranges:

| constant | value | role |
| --- | --- | --- |
| `_FOIL_SIG_MASK` | `(uint256(1) << 32) - 1` | extract any one 32-bit packed signature |
| `_FOIL_MULT_SHIFT` | `128` | shift to the `multBps` field |
| `_FOIL_MULT_MASK` | `(uint256(1) << 16) - 1` | mask the 16-bit `multBps` |
| `_FOIL_STAMP_SHIFT` | `144` | shift to the 24-bit raw-level stamp |
| `_FOIL_STAMP_MASK` | `(uint256(1) << 24) - 1` | mask the 24-bit stamp |

### D.1.4 The `_foilRecordFor(player, lvl)` accessor (per-level auto-reset)

A `view` accessor `_foilRecordFor(address player, uint256 lvl)` returns the live record
**`(present, multBps, sigs[4])`** for `player` at raw `lvl`, **or `(false, 0, [0,0,0,0])` when the
stored stamp ≠ the queried raw level** — the century auto-reset, identical in spirit to
`_centuryUsedFor` (`:1868-1871`). Semantics:

- Read `packed = foilRecord[player]` (one SLOAD).
- If `((packed >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK) != lvl` → return `(false, 0, sigs)` (a
  prior level's record reads **absent**; no global reset, exactly the `centuryBonusUsed` semantics).
- Otherwise unpack `sigs[i] = uint32((packed >> (32·i)) & _FOIL_SIG_MASK)` for `i ∈ {0,1,2,3}`,
  `multBps = uint16((packed >> _FOIL_MULT_SHIFT) & _FOIL_MULT_MASK)`, `present = true`.

**MATCH-01 (sigs frozen per `(player, level)`):** the four signatures and the `multBps` are written
once at buy, stamped to the buy level, and never mutated until the player's NEXT foil buy. **MATCH-02
(whole-level window):** eligibility is read **from the stamp, not a live `level` compare** — every
day within the stamped level stays eligible. One cold slot per player who ever bought, not one per
player-per-level.

---

## D.2 Per-raw-level one-pack cap — folded into the stamp (FOIL-01; no separate slot)

The one-foil-pack-**per-raw-level** cap (FOIL-01) needs **NO additional storage**: presence in
`foilRecord` at the current raw level **is** the cap.

`_foilBoughtThisLevel(player, lvl)` is a `view` predicate returning **true iff
`((foilRecord[player] >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK) == lvl`** — i.e. the stored stamp
equals the queried raw level. `buyFoilPack` reverts when `_foilBoughtThisLevel(msg.sender, level)`
is true, then the record write stamps the current `level`. A stale stamp reads "not bought" (a fresh
allowance at the new level), exactly the century-flag semantics.

**Keyed on raw `uint24 level` (`:236`), NEVER `_activeTicketLevel()`** (§1). Because the sigs (low
bits), `multBps` (mid bits), and the cap (stamp, high bits) share **one slot**, there is no
"bought-but-no-record" or "record-but-no-cap" desync — they are written and read atomically.

---

## D.3 Sparse double-claim marker — `foilMatchClaimed` (MATCH-05; collision-free)

**LOCKED: `mapping(bytes32 => bool) internal foilMatchClaimed`** appended at the tail (the unified
marker name — **`foilMatchClaimed`, NOT `foilClaimed`**; V3 DEFECT E-γ resolved). Each realized
winning tuple is claimable **at most once**.

### D.3.1 Key composition (five distinct positional `abi.encode` fields)

**Key = `keccak256(abi.encode(player, uint256(level), uint256(day), uint256(drawKind),
uint256(ticketIndex)))`** — five distinct positional `abi.encode` fields (each 32-byte padded; no
concatenation ambiguity, no field-boundary collision):

| field | type at encode | domain | role |
| --- | --- | --- | --- |
| `player` | `address` | the claimant | isolates callers — a forged tuple cannot replay another player's claim |
| `level` | `uint256(level)` | raw `uint24` | binds the marker to the record's stamp → no `L`/`L+1` replay |
| `day` | `uint256(day)` | the eligible day | spans the whole-level window (MATCH-02) |
| `drawKind` | `uint256(drawKind)` | `{0=main, 1=bonus}` | 2 draws/day; a ticket is claimed independently against each |
| `ticketIndex` | `uint256(ticketIndex)` | `{0..3}` | 4 independent tickets per pack (MATCH-04) |

So a single ticket is claimable independently against **main (drawKind 0)** and **bonus
(drawKind 1)** of each eligible day, but **never twice per draw**.

### D.3.2 Mark-before-payout (CEI)

`claimFoilMatch` **reverts if `foilMatchClaimed[key]` is already set**, then pays the tier, then sets
`foilMatchClaimed[key] = true` — **CEI: the marker is set BEFORE any external transfer**, so a
reentrant re-call sees the set marker and reverts. **Sparse** — only realized winning claims write a
slot; there is no draw-time scan, so `advanceGame` stays flat.

---

## D.4 MATCH-05 persist-per-level griefing-resistance (§5)

A record written at level *L* is **overwritten ONLY by the SAME player's next foil buy** (gated by
`level++`). It is **never touched by `advanceGame` or by another player**. A fast `level++` does
**NOT** strand an unclaimed match: the sigs + `multBps` + stamp `L` persist in the slot, and
`claimFoilMatch` re-derives eligibility from the stamp `L` and the retained `rngWordByDay[day]`
(`:462`), so matches for days within *L* stay claimable until the player's own NEXT foil buy. The
whole-level window (MATCH-02) is read from the stamp, not a live `level` compare. This is the §5
"records persist per-level so a fast `level++` can't grief an unclaimed match" property.

The single-slot player-loss edge (a player's OWN re-buy at *L+1* overwrites their unclaimed *L*
signatures) is the one residual surface — it is **NOT** a griefing vector (no third party can trigger
it) and is surfaced for explicit USER sign-off in **PIN 1** (§D.6).

---

## D.5 No-collision / no-reorder attestation (SEC-04, SEC-03)

- **Append-only at the tail.** Both new mappings (`foilRecord`, `foilMatchClaimed`) go **after
  `boxPlayers` (`:2393`), before the `:2394` closing brace**. No existing declaration is
  moved, retyped, reordered, or removed.
- **Constants consume no slots.** The five `_FOIL_*` masks/shifts are `private constant` (inlined,
  like `_CENTURY_USED_MASK:1864`); `_foilRecordFor` / `_foilBoughtThisLevel` are `internal` view
  helpers with no storage footprint.
- **Two new base mapping slots ONLY** (`foilRecord`, `foilMatchClaimed`) take the next two slots
  after `boxPlayers`'s. **All prior slot indices are unchanged** → the layout goldens are
  byte-preserved (SEC-04, re-attested by the layout-golden re-pass at 448).
- **Storage lives ONLY in `DegenerusGameStorage`** (the delegatecall-shared base; SEC-03), never in
  the foil module or the facade.
- **`whalePassClaims` already exists at `:1122`** (`mapping(address => uint256)`) — do **NOT**
  re-declare it; the 4-of-4 tier does `whalePassClaims[player] += 1` against the existing slot.
- **Net storage cost:** 2 new base mapping slots. `foilRecord` = 1 packed slot per player who ever
  bought (cap + sigs + `multBps` co-resident — no separate cap slot). `foilMatchClaimed` = 1 slot
  per realized winning claim (sparse).

---

## D.6 Pinned Layout Decisions (LOCKED)

> Mirroring the house SPEC-V61 "Locked Knobs" form: each pin states the **LOCKED value + rationale +
> documented alternative + affected REQ-IDs**. Two genuine SPEC decisions are pinned here; the rest
> of §D is mechanically determined. PIN 1 carries a **USER-SIGN-OFF FLAG** that Plan 04's
> consolidation must surface in the SPEC's "USER decisions to confirm" callout.

### PIN 1 — `foilRecord` level-keying (LOCKED: single-slot `mapping(address => uint256)`)

**LOCKED choice:** the **single-slot** `mapping(address => uint256) foilRecord` form (the
§5-compliant minimum), with the level stamp embedded in bits `[144-167]` (the century idiom). One
cold slot per player, auto-reset per level via the stamp.

**Rationale:** one packed slot per player gives the per-level auto-reset for free (a prior level's
record reads absent), keeps the cap + sigs + `multBps` co-resident (no desync), and is the minimal
storage that satisfies §5's "records persist per-level". A `level++` alone never strands a match
(§D.4).

**The precise edge (LOCKED form's only loss surface):** a player's **OWN re-buy at level *L+1*
overwrites their unclaimed level-*L* signatures**. A level advance **ALONE** never strands a match —
**only the player's own next foil buy does**. No third party (`advanceGame`, another player) can
trigger this; it is not a griefing vector. The `foilMatchClaimed` key includes `level` (§D.3.1), so
*L* and *L+1* markers never collide even across the overwrite.

**Documented alternative (NOT chosen):** `mapping(uint24 level => mapping(address => uint256))` —
keys the record by level **then** player, so *L*'s unclaimed signatures **survive** an *L+1* re-buy.
This is an **additive widening, no reorder** (still appendable at the tail, no existing slot moved),
at the cost of **+1 storage slot per (level, player) that ever buys** — i.e. one slot per level per
buyer rather than one slot per buyer. The single-slot form is the §5-compliant minimum and is chosen.

**>>> USER-SIGN-OFF FLAG — USER REVIEW BEFORE THE 446 IMPL GATE <<<**
The single-slot lock means **a player who re-buys at *L+1* before claiming *L*'s matches loses *L*'s
unclaimed signatures**. Confirm this is acceptable, **or switch to the
`mapping(level => mapping(address => uint256))` variant** (one extra slot per level per buyer) to let
*L*'s unclaimed matches survive an *L+1* re-buy. This is the single open USER decision in §D.

**Affected REQ-IDs:** FOIL-01 (per-level cap), MATCH-01 (sigs frozen per `(player, level)`), MATCH-05
(double-claim guard + persist-per-level griefing-resistance).

### PIN 2 — exact packed bit-offset (LOCKED: stamp at `[144-167]`, payload at `[0-143]`)

**LOCKED choice:** the **stamp at bits `[144-167]` with the payload at bits `[0-143]`** —
`sig0..sig3` at `[0-127]` (each 32 bits), `multBps` at `[128-143]` (16 bits), `rawLevel` stamp at
`[144-167]` (24 bits), `[168-255]` reserved `0`. This is the §D.1.1 table, asserted exactly:

> **The locked offsets are: `sig0 = [0-31]`, `sig1 = [32-63]`, `sig2 = [64-95]`, `sig3 = [96-127]`,
> `multBps = [128-143]`, `rawLevel stamp = [144-167]`** — with `_FOIL_STAMP_SHIFT = 144`,
> `_FOIL_MULT_SHIFT = 128`. The self-stamp cap read is
> `(packed >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK == lvl`.

**Rationale:** the four 32-bit sigs and the 16-bit `multBps` stay **contiguous in the low 144 bits**
(a clean unpack loop), and the stamp is a high-field self-stamp read identical in spirit to
`centuryBonusUsed`'s `(packed >> 224) == level`. Total 168 bits ≤ 256, one slot, one SSTORE / one
SLOAD.

**Documented alternative (NOT chosen):** the `centuryBonusUsed`-mirroring form with the **stamp at
bit 224** (mirroring `:1875` exactly), `multBps` at `[128-143]`, sigs at `[0-127]`. Also one slot,
≤ 256 bits; the only difference is the stamp offset (224 vs 144). The `[144-167]` form is chosen so
the payload is contiguous in the low 144 bits; the bit-224 mirror is the documented-but-not-chosen
alternative.

**Affected REQ-IDs:** SEC-03 (storage in `DegenerusGameStorage`), SEC-04 (no-slot-move / layout
goldens preserved).

---

## D.7 Acceptance — IMPL can declare with zero further layout decision

An IMPL-446 author can declare `foilRecord` (the packed `mapping(address => uint256)` with the
§D.1.1 168-bit layout), `foilMatchClaimed` (the sparse `mapping(bytes32 => bool)` with the §D.3.1
keccak key), the five `_FOIL_*` masks/shifts, and the `_foilRecordFor` / `_foilBoughtThisLevel`
accessors — appended after `:2393`, no existing slot moved — with **ZERO further layout decision**,
beyond confirming the two pins of §D.6 (PIN 2 is locked outright; PIN 1 carries the one USER
sign-off on the single-slot loss edge before the 446 IMPL gate).

**REQ coverage:** FOIL-01 (folded per-raw-level cap, §D.2), MATCH-01 (sigs frozen per
`(player, level)`, §D.1.4), MATCH-02 (whole-level window read from the stamp, §D.1.4), MATCH-05
(double-claim guard + persist-per-level griefing-resistance, §D.3/§D.4), SEC-03 (storage only in
`DegenerusGameStorage`, §D.5), SEC-04 (append-only / no-slot-move attestation, §D.5).
