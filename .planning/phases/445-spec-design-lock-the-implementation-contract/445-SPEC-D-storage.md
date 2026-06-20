# 445 SPEC — Section D: Storage Layout (foilRecord + cap flag + foilMatchClaimed)

> Build-ready storage half of the v71.0 Foil Pack design-lock. Every layout choice below is the
> RESEARCH.md §D reconciled-and-corrected form (V3 PASS, the E.6 168-bit superset). An IMPL-446
> author declares the two new mappings, the five private-constant masks/shifts, and the two
> accessors with **zero** further layout decision (both pins below are RESOLVED by the 2026-06-19
> USER sign-off). Consumed by Plan 04's consolidation.
>
> Scope: this section is paper-only. It appends three storage items — ONE packed `foilRecord`
> slot per (level, player), the per-raw-level cap (the record's presence in that level's sub-map;
> no separate slot), and the sparse `foilMatchClaimed` marker — at the tail of `DegenerusGameStorage`.
> No existing slot moves (SEC-04). HARD CONSTRAINT: `contracts/*.sol` is read-only; nothing here edits a `.sol`.

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

## D.1 `foilRecord` — ONE packed slot per (level, player) (FOIL-01, MATCH-01, MATCH-02, SEC-03)

**CHOSEN form (USER sign-off 2026-06-19): one packed `uint256` per (level, player) —
`mapping(uint24 => mapping(address => uint256)) internal foilRecord`
appended after `DegenerusGameStorage.sol:2393`** (before the `:2394` closing brace), the level=>player
surviving-record form. The outer key is the raw `uint24 level` (`:236`, the same domain as
`rngWordByDay:462`); the inner key is the player. The record stores the **full packed `uint32` per ticket
PLUS the frozen 16-bit `multBps`** — the reconciled E.6 168-bit superset. The 24-bit level stamp in the
payload is RETAINED as a redundant cross-check (the outer level key already scopes the record per level).

### D.1.1 The packed 168-bit superset (the LOCKED bit layout)

`foilRecord[lvl][player]` is **one `uint256`** holding the reconciled E.6 superset: **4 × 32-bit packed
ticket signatures + a 16-bit frozen `multBps` + a 24-bit raw-level stamp = 168 bits ≤ 256**. The
buy path writes this in **ONE SSTORE** (`foilRecord[lvl][buyer]`); the claim path reads it in **ONE SLOAD**
(`foilRecord[recLevel][player]`).

| field | width | bit range (LSB→MSB) | meaning |
| --- | --- | --- | --- |
| `sig0` | 32 bits | `[0-31]` | ticket-0 packed `uint32` signature |
| `sig1` | 32 bits | `[32-63]` | ticket-1 packed `uint32` signature |
| `sig2` | 32 bits | `[64-95]` | ticket-2 packed `uint32` signature |
| `sig3` | 32 bits | `[96-127]` | ticket-3 packed `uint32` signature |
| `multBps` | 16 bits | `[128-143]` | the frozen `foilBoostBps` output (range `20000..60000`); RARE-03 |
| `rawLevel` stamp | 24 bits | `[144-167]` | the raw `uint24 level` (`:236`) at buy; a redundant cross-check (the outer level key is the cap) |
| reserved | 88 bits | `[168-255]` | unused, always `0` |

**Bit budget:** `4 × 32 (sigs) + 16 (multBps) + 24 (stamp) = 168 bits ≤ 256`. One slot. The PIN 2 bit
layout is UNCHANGED by the level=>player keying; the stamp simply changes role from cap to cross-check.

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

### D.1.4 The `_foilRecordFor(player, lvl)` accessor (one SLOAD)

A `view` accessor `_foilRecordFor(address player, uint256 lvl)` returns the live record
**`(present, multBps, sigs[4])`** for `player` at raw `lvl`. Semantics:

- Read `packed = foilRecord[uint24(lvl)][player]` (one SLOAD).
- `present = (packed != 0)` — a prior level's record lives at a DIFFERENT outer key, so it neither
  collides with nor masks the queried level. The nested level key replaces the century-style
  stamp-compare auto-reset; if a stamp-equality assertion is retained it is a redundant defensive
  check (always true, since the buy stamps `lvl` and the outer key is `lvl`).
- Unpack `sigs[i] = uint32((packed >> (32·i)) & _FOIL_SIG_MASK)` for `i ∈ {0,1,2,3}`,
  `multBps = uint16((packed >> _FOIL_MULT_SHIFT) & _FOIL_MULT_MASK)`.

**MATCH-01 (sigs frozen per `(player, level)`):** the four signatures and the `multBps` are written
once at buy into `foilRecord[lvl][player]`, and never mutated until the player's NEXT foil buy AT THE
SAME LEVEL. **MATCH-02 (whole-level window):** eligibility is read **from the outer level key, not a
live `level` compare** — every day within that level stays eligible. One cold slot per (level, player)
that ever bought.

---

## D.2 Per-raw-level one-pack cap — the record's presence in the level sub-map (FOIL-01; no separate slot)

The one-foil-pack-**per-raw-level** cap (FOIL-01) needs **NO additional storage**: presence in
`foilRecord[lvl][player]` **is** the cap.

`_foilBoughtThisLevel(player, lvl)` is a `view` predicate returning **true iff
`foilRecord[lvl][player] != 0`** — a real buy writes `multBps ≥ 20000` (and four sigs), making the
record non-zero. `buyFoilPack` reverts when `_foilBoughtThisLevel(msg.sender, level)` is true, then
writes `foilRecord[level][msg.sender]`. The nested level key inherently scopes the record per level,
so a buy at a new level reads "not bought" with no stamp-equality auto-reset needed.

**Keyed on raw `uint24 level` (`:236`), NEVER `_activeTicketLevel()`** (§1). Because the sigs (low
bits), `multBps` (mid bits), and the cross-check stamp (high bits) share **one slot**, there is no
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

A record written at level *L* lives at `foilRecord[L][player]` and is **never overwritten by a buy at
any OTHER level** — distinct levels are independent records. It is **never touched by `advanceGame` or
by another player**. A fast `level++` does **NOT** strand an unclaimed match: `foilRecord[L][player]`
(sigs + `multBps` + cross-check stamp `L`) persists, and `claimFoilMatch` re-derives eligibility from
the outer level key *L* and the retained `rngWordByDay[day]` (`:462`), so matches for days within *L*
stay claimable. The whole-level window (MATCH-02) is read from the outer level key, not a live `level`
compare. This is the §5 "records persist per-level so a fast `level++` can't grief an unclaimed match"
property.

**The single-slot player-loss edge is ELIMINATED by the chosen level=>player keying.** A re-buy at
*L+1* writes `foilRecord[L+1][player]` and does **NOT** touch `foilRecord[L][player]`; *L*'s unclaimed
signatures survive until claimed. Grief-resistance is now **STRUCTURAL** — distinct levels are
independent records — not merely "self-inflicted only". The single-slot self-overwrite surface (a
player's own *L+1* re-buy clobbering their unclaimed *L* signatures) was the rejected single-slot
form's only loss edge; under the CHOSEN keying it cannot occur (USER sign-off, §D.6).

---

## D.5 No-collision / no-reorder attestation (SEC-04, SEC-03)

- **Append-only at the tail.** Both new mappings (`foilRecord`, `foilMatchClaimed`) go **after
  `boxPlayers` (`:2393`), before the `:2394` closing brace**. No existing declaration is
  moved, retyped, reordered, or removed.
- **Constants consume no slots.** The five `_FOIL_*` masks/shifts are `private constant` (inlined,
  like `_CENTURY_USED_MASK:1864`); `_foilRecordFor` / `_foilBoughtThisLevel` are `internal` view
  helpers with no storage footprint.
- **Two new base mapping slots ONLY** (`foilRecord`, `foilMatchClaimed`) take the next two slots
  after `boxPlayers`'s. A **nested** mapping (`mapping(uint24 => mapping(address => uint256))`) still
  occupies exactly **ONE declared base mapping slot** — its per-(level, player) entries live at
  keccak-derived addresses, not at additional declared slots. **All prior slot indices are
  unchanged** → the layout goldens are byte-preserved (SEC-04, re-attested by the layout-golden
  re-pass at 448).
- **Storage lives ONLY in `DegenerusGameStorage`** (the delegatecall-shared base; SEC-03), never in
  the foil module or the facade.
- **`whalePassClaims` already exists at `:1122`** (`mapping(address => uint256)`) — do **NOT**
  re-declare it; the 4-of-4 tier does `whalePassClaims[player] += 1` against the existing slot.
- **Net runtime storage cost:** `foilRecord` = 1 packed slot per (level, player) that ever bought
  (the surviving-record cost of the chosen level=>player keying; cap + sigs + `multBps` co-resident —
  no separate cap slot). `foilMatchClaimed` = 1 slot per realized winning claim (sparse). The DECLARED
  base-slot count is two (one per nested mapping), unchanged from the rejected single-slot form.

---

## D.6 Pinned Layout Decisions (RESOLVED — USER sign-off 2026-06-19)

> Mirroring the house SPEC-V61 "Locked Knobs" form: each pin states the **CHOSEN value + rationale +
> rejected alternative + affected REQ-IDs**. Two genuine SPEC decisions were pinned here; both are now
> RESOLVED by the 2026-06-19 USER sign-off. The rest of §D is mechanically determined.

### PIN 1 — `foilRecord` level-keying (CHOSEN: `mapping(uint24 => mapping(address => uint256))`, level=>player)

**CHOSEN choice (USER sign-off 2026-06-19):** the **level=>player surviving-record** form
`mapping(uint24 => mapping(address => uint256)) foilRecord`. The outer key is the raw `uint24 level`
(`:236`), the inner key is the player; one packed slot per (level, player).

**Rationale:** *L*'s unclaimed signatures **survive** an *L+1* re-buy because distinct levels are
independent records, so the single-slot self-overwrite loss edge is **ELIMINATED** and
grief-resistance is STRUCTURAL (§D.4). The cap + sigs + `multBps` stay co-resident in one packed slot
per (level, player) (no desync). The additive widening is still appendable at the tail with no
existing slot moved (one DECLARED base mapping slot, nested), at the documented runtime cost of one
slot per (level, player) that ever buys. The 24-bit stamp is RETAINED as a redundant cross-check (the
outer level key already scopes the record).

**Rejected alternative (single-slot, NOT chosen):** the single-slot
`mapping(address => uint256) foilRecord` form (the §5-compliant storage minimum) with the level stamp
embedded in bits `[144-167]` as the cap (the century idiom). One cold slot per player, auto-reset per
level via the stamp — but with one residual loss surface: a player's **OWN re-buy at level *L+1*
overwrites their unclaimed level-*L* signatures** (self-inflicted only — no third party, not a
griefing vector). The USER chose the surviving-record form, so this self-overwrite cannot occur. The
`foilMatchClaimed` key includes `level` (§D.3.1), so *L* and *L+1* markers never collide.

**USER sign-off 2026-06-19:** the level=>player surviving-record variant is CHOSEN; the single-slot
self-overwrite player-loss edge is therefore eliminated. (Resolved — no longer an open §D decision.)

**Affected REQ-IDs:** FOIL-01 (per-level cap), MATCH-01 (sigs frozen per `(player, level)`), MATCH-05
(double-claim guard + persist-per-level griefing-resistance).

### PIN 2 — exact packed bit-offset (ACCEPTED — USER sign-off 2026-06-19: stamp at `[144-167]`, payload at `[0-143]`)

**ACCEPTED choice (USER sign-off 2026-06-19 — "bit-offset OK"):** the **stamp at bits `[144-167]`
with the payload at bits `[0-143]`** — `sig0..sig3` at `[0-127]` (each 32 bits), `multBps` at
`[128-143]` (16 bits), `rawLevel` stamp at `[144-167]` (24 bits), `[168-255]` reserved `0`. This is
the §D.1.1 table, asserted exactly:

> **The locked offsets are: `sig0 = [0-31]`, `sig1 = [32-63]`, `sig2 = [64-95]`, `sig3 = [96-127]`,
> `multBps = [128-143]`, `rawLevel stamp = [144-167]`** — with `_FOIL_STAMP_SHIFT = 144`,
> `_FOIL_MULT_SHIFT = 128`. The self-stamp cross-check read is
> `(packed >> _FOIL_STAMP_SHIFT) & _FOIL_STAMP_MASK == lvl`.

**Rationale:** the four 32-bit sigs and the 16-bit `multBps` stay **contiguous in the low 144 bits**
(a clean unpack loop), and the stamp is a high-field self-stamp read identical in spirit to
`centuryBonusUsed`'s `(packed >> 224) == level`. Total 168 bits ≤ 256, one slot, one SSTORE / one
SLOAD. Under the level=>player keying (PIN 1) this stamp is a redundant cross-check rather than the
cap, but the bit layout is UNCHANGED and accepted as-is.

**Documented alternative (NOT chosen):** the `centuryBonusUsed`-mirroring form with the **stamp at
bit 224** (mirroring `:1875` exactly), `multBps` at `[128-143]`, sigs at `[0-127]`. Also one slot,
≤ 256 bits; the only difference is the stamp offset (224 vs 144). The `[144-167]` form is chosen so
the payload is contiguous in the low 144 bits; the bit-224 mirror is the documented-but-not-chosen
alternative.

**Affected REQ-IDs:** SEC-03 (storage in `DegenerusGameStorage`), SEC-04 (no-slot-move / layout
goldens preserved).

---

## D.7 Acceptance — IMPL can declare with zero further layout decision

An IMPL-446 author can declare `foilRecord` (the packed `mapping(uint24 => mapping(address => uint256))`
with the §D.1.1 168-bit per-entry layout), `foilMatchClaimed` (the sparse `mapping(bytes32 => bool)`
with the §D.3.1 keccak key), the five `_FOIL_*` masks/shifts, and the `_foilRecordFor` /
`_foilBoughtThisLevel` accessors — appended after `:2393`, no existing slot moved — with **ZERO
further layout decision**. Both pins of §D.6 are RESOLVED by the 2026-06-19 USER sign-off (PIN 1 =
level=>player surviving-record; PIN 2 = the `[144-167]`/`[0-143]` bit layout accepted), so 446 reads
them as final.

**REQ coverage:** FOIL-01 (per-raw-level cap = record presence in the level sub-map, §D.2), MATCH-01
(sigs frozen per `(player, level)`, §D.1.4), MATCH-02 (whole-level window read from the outer level
key, §D.1.4), MATCH-05 (double-claim guard + persist-per-level griefing-resistance, §D.3/§D.4), SEC-03
(storage only in `DegenerusGameStorage`, §D.5), SEC-04 (append-only / no-slot-move attestation, §D.5).
