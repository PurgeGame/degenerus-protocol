# 339 — `traitBurnTicket` Write-Site Soundness Attestation (+ Whale-Race Non-Finding)

**Phase:** 339 — SPEC design-lock (claimBingo / v51.0)
**Decisions:** **D-02** (full write-site attestation — NOT a precedent-based hand-wave) + **D-03** (the whale-race ACCEPTED-BY-DESIGN non-finding).
**Purpose:** This is the heart of whether `claimBingo` can be **spoofed**. `claimBingo` admits a claim iff the caller can name slots `slots[c]` such that `traitBurnTicket[level][traitId][slots[c]] == msg.sender` for all 8 colors `c` of the requested symbol. This attestation PROVES the ownership semantics of that map. It is the companion to `339-BINGO06-FREEZE-PROOF.md`.
**Tree:** Anchors grep-attested against the live tree at HEAD `743c20ae`; `git diff 812abeee HEAD -- contracts/` is EMPTY → HEAD ≡ `812abeee` for `contracts/` (D-13).
**"PROVEN not assumed":** the governing directive — the precedent is the `DegenerusGame` mint/jackpot inline-duplication caught in prior milestones; no "single fn reaches all paths" / "by construction" claim survives un-checked. Accordingly this doc TRACES the actual source and **corrects the anchor-classification drift it found** rather than transcribing the cited anchors uncritically.

---

## SOUNDNESS THEOREM

> An address `A` appears at `traitBurnTicket[level][traitId][slot]` **iff** `A` owned a post-RNG-resolved entry on `level` carrying that exact trait byte `traitId == [QQ][CCC][SSS]`.

(Read "iff" as the biconditional: forward — every appended address is the resolving entry's owner under the exact resolved trait byte; reverse — the only way an address lands in that bucket is by owning such a resolved entry. `claimBingo` cannot be spoofed because passing the check `traitBurnTicket[level][traitId][slots[c]] == msg.sender` requires `msg.sender` to BE such an owner.)

**VERDICT: SOUND.** The IFF holds across the sole write-site; no read-side or migration path lets a non-owner land at a slot. `claimBingo` cannot be spoofed.

---

## ⚠ Anchor-classification correction (D-13 grep-attestation; D-02 "PROVEN not assumed")

D-02 and CONTEXT cite the `traitBurnTicket` "write-sites" as `DegenerusGame.sol:2701 / 2730 / 2813` and `DegenerusGameJackpotModule.sol:654`. **Grep-attestation against HEAD shows all four are READ-side, not write-side:**

| Cited anchor | Actual role at HEAD | Evidence |
|---|---|---|
| `DegenerusGame.sol:2701` `traitBurnTicket[lvlSel][traitSel]` | **READ** | inside `sampleTraitTickets(uint256 entropy) external view` — samples up to 4 holders for BAF scatter (`view`, no append). |
| `DegenerusGame.sol:2730` `traitBurnTicket[targetLvl][traitSel]` | **READ** | inside `sampleTraitTicketsAtLevel(uint24,uint256) external view` — targeted-level sample (`view`, no append). |
| `DegenerusGame.sol:2813` `traitBurnTicket[lvl][trait]` | **READ** | inside `getTickets(uint8,uint24,uint32,uint32,address) external view` — paginated count query (`view`, no append). |
| `DegenerusGameJackpotModule.sol:654` `address[][256] storage bucket = traitBurnTicket[lvl]` | **READ (bucket reader)** | passes `bucket` to `_randTraitTicket(...) private view` (`:1543-1554`) for jackpot winner selection; the loop body calls `_queueTickets` (a SEPARATE tickets-owed path), never appends to `traitBurnTicket`. |

**The SOLE population / append (write) site of `traitBurnTicket` is `contracts/modules/DegenerusGameMintModule.sol:603-643`.** This was found by enumerating every `traitBurnTicket` reference in `contracts/` (the complete set: `Storage.sol:105/407/416` [decl+comments], `MintModule.sol:603-611` [the writer], `DegenerusGame.sol:2701/2730/2813` [reads], `JackpotModule.sol:654/886/936/1173/1257/1544/1554/1696` [reads]). No `.push` and no other `sstore` to the `traitBurnTicket` slot exists anywhere else.

Because D-02 demands the actual population sites be read and proven, **this attestation proves the IFF at the corrected writer `MintModule.sol:603-643`** and treats the cited `:2701/:2730/:2813/:654` anchors as the **read-side consumers** the soundness theorem protects (they, like `claimBingo`, only ever read the post-resolution bucket). This is exactly the class of un-checked-anchor error the "PROVEN not assumed" directive exists to catch.

---

## The sole write-site: `DegenerusGameMintModule.sol:603-643`

The append is an inline-assembly batch write inside ticket processing. The load-bearing facts (verified at HEAD):

1. **The trait byte is RNG-derived.** Inside the trait-generation loop, each trait is `uint8 traitId = DegenerusTraitUtils.traitFromWord(s) + (uint8(i & 3) << 6)` (`MintModule.sol:586-587`), where `s` is an LCG stream seeded from `keccak256(abi.encode(baseKey, entropyWord, groupIdx))` (`MintModule.sol:572-575`) — `entropyWord` being the resolved VRF entropy for the batch. The trait byte does not exist until the entropy is consumed → **the append is necessarily post-RNG-resolution.**
2. **The level key.** `uint24 lvl = uint24(baseKey >> 224)` (`MintModule.sol:600`) → the level slot `keccak256(lvl . traitBurnTicket.slot)` (`MintModule.sol:608-613`).
3. **The append is keyed by `[level][traitId]` and stores `player`.** For each touched trait, the assembly computes `elem := add(levelSlot, traitId)` (the inner fixed-array slot for that traitId), extends the array length by `occurrences`, and writes `player` into the new tail slots `occurrences` times (`MintModule.sol:620-639`). The appended address is `player` — the owner of the resolving entry.

This single writer is the entire ground truth of the IFF. The three D-02 sub-claims are proven against it.

---

## Sub-claim (a) — KEYED BY THE RESOLVED TRAIT BYTE (no cross-trait contamination)

**Claim:** the append indexes `[level][traitId]` where `traitId` is the *resolved* trait of the entry, so an entry of trait `X` is never appended under trait `Y`.

**Proof:** at `MintModule.sol:622` the destination inner array is `elem := add(levelSlot, traitId)`, where `levelSlot = keccak256(lvl . traitBurnTicket.slot)` (`:608-613`) and `traitId` is the exact byte produced for *that* entry at `:586-587` (`traitFromWord(s) + (uint8(i & 3) << 6)`). The `+ (uint8(i & 3) << 6)` term sets bits 7-6 (the quadrant `QQ`) from the entry's own quadrant index; `traitFromWord(s)` sets the color/symbol bits (`CCC`/`SSS`). The trait-byte layout `[QQ][CCC][SSS]` (Q bits 7-6, C bits 5-3, S bits 2-0) is confirmed at `contracts/DegenerusTraitUtils.sol:17-39`, and `claimBingo` reconstructs the identical key `traitId = (quadrant<<6) | (c<<3) | symInQ` (plan doc :103) with `quadrant = symbol>>3`, `symInQ = symbol & 7` (D-09). Since the write key and the `claimBingo` read key are computed from the same `[QQ][CCC][SSS]` packing, **the address an entry contributes lands under exactly its own resolved trait byte and nowhere else** — no cross-trait contamination. An address appearing under `traitId` therefore owned an entry whose resolved trait byte equals `traitId`. ∎ (forward direction of the IFF.)

---

## Sub-claim (b) — DUPLICATE-APPEND behavior (N entries → N appearances; griefing impossible)

**Claim:** a player who resolved `N` entries of the same trait appears `N` times in that bucket — and this is fine; duplicate-slot griefing is impossible.

**Proof:**
- **N → N.** The writer aggregates per-batch occurrences in `counts[traitId]` (`MintModule.sol:590`) and writes `player` exactly `occurrences` times into consecutive tail slots (`MintModule.sol:631-638` loop `for k < occurrences { sstore(dst, player); dst++ }`). Across batches the same player simply appends again. So `N` resolved same-trait entries ⇒ `N` appearances. This is benign: `claimBingo` only requires the caller to **name one slot they occupy** per color (`traitBurnTicket[level][traitId][slots[c]] == msg.sender`) — having multiple slots only gives the caller more valid `slots[c]` choices for that one color; it confers no extra reward and no extra claim (the per-player dedup is `(level, quadrant)` via `bingoClaimed`, D-07).
- **Duplicate-slot griefing impossible.** Each trait byte `[QQ][CCC][SSS]` encodes **exactly one** `(quadrant, color, symbol)` triple (D-09; `DegenerusTraitUtils.sol:17-39`). For a fixed `(quadrant, symbol)` the 8 colors `c ∈ [0,7]` produce 8 **distinct** traitIds (`(quadrant<<6)|(c<<3)|symInQ`), so two different color-loop indices `c₁ ≠ c₂` necessarily index two **different** inner arrays `traitBurnTicket[level][traitId₁]` vs `[...][traitId₂]`. There is no way for two colors to collide on the same `(traitId, slot)` entry — the 8 ownership checks are over 8 disjoint buckets. A caller cannot reuse a single owned entry to satisfy two colors, and cannot "grief" the slot space because each color's bucket is independent. ∎

---

## Sub-claim (c) — TRANSFER / BURN RE-POPULATION (no NON-owner can land at a slot)

**Claim:** examine whether any path (resale, burn-and-reappend, bucket compaction, level migration, virtual entries) lets a NON-owner land at a `traitBurnTicket[level][traitId][slot]` and thereby spoof a claim. Attest the result.

**Proof — by exhaustion over every `traitBurnTicket` touch:**

1. **No resale / transfer path writes the bucket.** The bucket stores the burner/owner address at append time and is never rewritten per-element. There is **no setter, no swap, no re-key** of `traitBurnTicket[level][traitId][i]` anywhere in `contracts/` — the only mutation is the append at `MintModule.sol:603-643` (extend length + write `player`). A later token transfer of the underlying NFT does NOT touch `traitBurnTicket` (it is a burn-ticket ledger keyed by historical resolution, not by current ownership). So a non-owner cannot acquire an existing slot by buying/transferring anything.
2. **No burn-and-reappend re-points an existing slot to a non-owner.** Burns only ever *append* (the writer is the burn-processing path itself); they never overwrite a prior slot. Length is monotone-increasing; existing indices are immutable once written.
3. **No bucket compaction / deletion.** There is no `delete traitBurnTicket[...]`, no length-truncation, and no `pop` in `contracts/`. Indices are stable for the life of the contract (pre-launch redeploy-fresh; no migration). A `slot` index named today refers to the same entry forever.
4. **Level-migration reads do not re-populate.** `JackpotModule.sol:886` (`traitBurnTicket[sourceLvl]`), `:1173`, `:1257` and the `_randTraitTicket(address[][256] storage, ...) private view` (`:1543-1554`) read *other* levels' buckets for jackpot scatter; being `view`, they cannot write. They never copy an address from one bucket into another.
5. **Virtual deity entries are read-time-only, never persisted.** `_randTraitTicket` synthesizes "virtual" deity entries in memory (`JackpotModule.sol:1557-1569`, `deity = deityBySymbol[fullSymId]`, `virtualCount`) to bias jackpot odds — but these are computed transiently for the winner draw and are **never written back** into `traitBurnTicket`. So the deity (a non-burner for those slots) does NOT occupy any real `traitBurnTicket[level][traitId][slot]` that `claimBingo` could index. `claimBingo` reads only real, persisted entries.

**Result:** no path lets a NON-owner land at a `traitBurnTicket` slot. The reverse direction of the IFF holds: the *only* way an address occupies `traitBurnTicket[level][traitId][slot]` is to have owned a post-RNG-resolved entry under that exact trait byte. ∎

---

## SOUND verdict

Combining (a) forward (every appended address owned a resolved entry under exactly that trait byte), (b) (duplicate appearances are benign; the 8 colors are disjoint buckets so duplicate-slot griefing is impossible), and (c) reverse (no non-owner re-population path exists):

> An address appears at `traitBurnTicket[level][traitId][slot]` **iff** it owned a post-RNG-resolved entry carrying that exact trait byte.

Therefore `claimBingo`'s ownership check `traitBurnTicket[level][traitId][slots[c]] == msg.sender` passes **iff** `msg.sender` genuinely owned a resolved entry of each of the 8 colors of the requested symbol on that level. **`claimBingo` cannot be spoofed. VERDICT: SOUND.**

---

## Whale-Race — ACCEPTED-BY-DESIGN NON-FINDING (D-03)

> **Whale frontrunning on the per-VRF trait-resolution batch is accepted by design — the race window is the per-VRF reveal, not per-block; two simultaneous first-claimants for the same `(level, quadrant)` or `(level, symbol)` require both to land their last needed color in the same VRF resolution, which is rare.**

**Framing.** The contended prizes are the systemwide-first tiers (4 quadrant-firsts + 32 symbol-firsts per level, keyed by `firstQuadrant[level]` / `firstSymbol[level]`, D-07). "First" is decided by transaction ordering after a `(level, symbol)` becomes claimable. A claim only becomes possible once the relevant 8 colors are RNG-resolved (race-start = the moment level-`N` traits are RNG-resolved as the level counter advances; `339-BINGO06-FREEZE-PROOF.md` §"Race-start semantics"). Therefore the race window is the **per-VRF reveal** (the trait-resolution batch), **not per-block** ordinary mempool ordering. For two players to genuinely contend for the same systemwide-first, BOTH must complete their full 8-color set such that the *final* needed color resolves in the **same** VRF resolution — a narrow coincidence given the heavy-tail gold-tier bottleneck (Monte-Carlo mean ~182 tickets to a first bingo, plan doc :184-186). The trait byte each player can claim is itself RNG-determined and frozen pre-reveal (the freeze proof), so no player can manipulate *which* colors they hold to engineer the tie; they can only race to submit once resolution lands.

**Disposition.** Per the USER-LOCKED audit weighting (`threat-model-reentrancy-mev-nonissues`: MEV is LOW / confirmatory-only, timing-independent, gated), this is **ACCEPTED-BY-DESIGN**, not a vulnerability. It is enshrined here as a **written non-finding** so the **deferred v52 adversarial sweep treats it as already-dispositioned / known, not a fresh finding.** No mitigation (no commit-reveal, no anti-MEV ordering) is in scope (explicit non-goal, plan doc :230). The systemwide-first bits are monotone one-way latches (`|=` only), so the worst case of the race is simply *which* eligible winner books the first-prize — value is never double-paid (quadrant-first marks AND suppresses the symbol-first bonus, D-06) and never paid to a non-owner (the SOUND verdict above).

---

## Anchor summary (grep-attested vs HEAD `743c20ae` ≡ `812abeee` for `contracts/`)

| Anchor | Role | Used for |
|---|---|---|
| `DegenerusGameMintModule.sol:603-643` | **sole WRITE-site** (corrected) | the IFF proof — keyed-by-resolved-trait append of `player` |
| `DegenerusGameMintModule.sol:586-587` | RNG-derived `traitId` | sub-claim (a) — append keyed by resolved trait byte |
| `DegenerusTraitUtils.sol:17-39` | `[QQ][CCC][SSS]` layout | sub-claims (a)/(b) — one byte ⇒ one (q,c,s) |
| `DegenerusGame.sol:2701 / 2730 / 2813` | READ-side (cited as "write" — corrected) | the read-only consumers the theorem protects |
| `DegenerusGameJackpotModule.sol:654` | READ (bucket reader) | sub-claim (c) — reads, never re-populates |
| `DegenerusGameJackpotModule.sol:886 / 1173 / 1257 / 1554 / 1696` | READ (jackpot scatter) | sub-claim (c) — level-migration reads do not write |
| `DegenerusGameJackpotModule.sol:1557-1569` | virtual deity (read-time-only) | sub-claim (c) — never persisted into the bucket |
