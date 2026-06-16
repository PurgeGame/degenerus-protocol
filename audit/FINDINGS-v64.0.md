# Degenerus Protocol — v64.0 Audit Findings (Recent-Changes Re-Audit + Level-Semantics Sweep)

**Milestone:** v64.0 · **Baseline:** v62.0 closure subject `77580320` · **Audit subject (byte-frozen):** contracts tree `402855e171168ff4f653eb1434de4ff045a4e28f` (the 398 fixes' freeze; commit `891f7a8f`).
**Surface:** the full post-v62 contract delta (`77580320..HEAD`, 41 files / +4902/−3697 / 33 commits — gas rounds, storage packing, the reward overhaul, BURNIE emission rework, permissionless decimator/redemption, payable-chain fixes, the 5 post-v63 commits) **plus** a whole-codebase `lvl` vs `lvl+1` correctness sweep.
**Method:** per-sweep **dual-net** — the Gemini+Codex cross-model council (NET-1) + a deep adversarial Claude Workflow (NET-2), every lead adjudicated against frozen source and skeptic-gated; v63 dispositions carried as priors.
**Posture:** audit-only; the subject is byte-frozen. The only contract changes in v64 are the two 398 fixes (committed before the freeze).

---

## Verdict

**0 CATASTROPHE · 0 HIGH · 0 MEDIUM.**
**1 LOW — found and FIXED in-milestone** (LVL-A, `891f7a8f`).
Everything else is **INFO / by-design / refuted**, the majority USER-adjudicated by-design.

The post-v62 delta holds up: the one genuine off-by-one (an afking lootbox streak-basis) was caught and fixed in the level-semantics sweep; the solvency spine, the RNG-freeze spine, the storage packing, the permissionless surface, and the reward overhaul are all attested clean. The cross-model council's distinctive value was catching *framing/arithmetic* nuances (the BURNIE seed-emission magnitude) rather than exploitable defects.

| Severity | Count | Status |
|---|---|---|
| CATASTROPHE | 0 | — |
| HIGH | 0 | — |
| MEDIUM | 0 | — |
| LOW | 1 | **FIXED** in-milestone (`891f7a8f`) |
| INFO / by-design / refuted | 14 | documented below; none require a contract change |

---

## Phase ledger (397–404)

### 398 — LEVEL-SEMANTICS (`lvl` vs `lvl+1`, ~200 sites; dual-net)
- **LVL-A — CONFIRMED LOW → FIXED `891f7a8f`.** Afking lootbox-mode `_playerActivityScore` passed `currentLevel+1` as the streak-base instead of `_activeTicketLevel()` (`==ticketTargetLevel`); in jackpot phase these differ → silently zeroed an afker's manual streak → up to ~6–8% lower-EV capped box vs an equal manual buyer. Player-disadvantaging, no attacker gain. Fix = pass `ticketTargetLevel`.
- **USER-raised (FIXED `891f7a8f`):** redemption BURNIE day+1 win-multiplier on redeemed BURNIE.
- By-design / refuted: affiliate freshest-bucket exclusion (USER by-design — "no inter-level bullshit"); `DegenerusQuests._isLevelQuestEligible` `unitsLvl==lvl+1` (REFUTED, correct-by-design); `getPlayerPurchases` stale read (INFO, no on-chain consumers); whale/pass `level+1` (by-design future product).

### 399 — REWARD-MECHANICS (dual-net + corroborating Claude net)
- **RWD-A — INFO (USER-confirmed by-design).** *Codex-unique catch* (gemini, NET-2, NET-2b all accepted the priors' "~4M EV"). The BURNIE seed = **8M** staked (200k/day × 20d to VAULT **and** sDGNRS) at a deliberately near-fair coinflip (win pays `stake + ~96.85%` ≈ 1.9685×, 50/50) → EV ≈ 0.984× → **~7.87M expected emission, not ~4M**. The `:879-880` RTP comment confirms the near-fair design intent; bounded + survive-before-mint + accrues to protocol backing. **USER 2026-06-16: the magnitude is intended.** Corrects the v63 "conservation ≈ 4M" attestation (slipped arithmetic).
- **RWD-B — by-design (codex + NET-2b convergent).** Lootbox spins realize the standard activity-score-weighted Degenerette house edge (90–99.9% ROI; WWXRP up to 109.9%) — the documented "real Degenerette spin," not realized-100%. "EV-neutral" = conserved stake/split. No leak.
- **RWD-C/D/E — INFO:** stale EV-range comments (`Lootbox:472,563`, `Game:2210`); a correct-by-design redemption-parity comment; ≤2-wei BURNIE-spin integer-split dust.
- Attested by ≥2 nets: split=100%, ×11/9 ticket budget, far/near=1.0, variance≈0.786, recycle gate, no money-pump, freeze-safety, one-shot, quest no-double-channel, activity cap.

### 400 — SOLVENCY · CARRY · REDEMPTION (the SPINE; dual-net)
- **SOLV-01..04 — convergent CLEAN (all 3 nets).** claimablePool identity holds across the salvage relabel (pool-neutral), dust-forfeit, and payable redemption (all tandem-backed); BURNIE-04 carry-escrow paid/forfeit exactly once + slot-delete-before-credit; salvage vault fallback bounded by toggle + ETH floor; **stETH-before-ETH CEI intact** (V62-03 class); 5 cross-path compositions verified.
- **SOLV-05-A — INFO (by-design).** The first-claim window (30→180d, *improved*) strands no value as solvency: a forgone out-of-window coinflip win is a **deflationary un-mint** (BURNIE burned-at-deposit / minted-at-claim), not stranded value; sDGNRS auto-settles every resolution so its backing never strands. Operational note: claim VAULT seed wins within 180d.

### 401 — PACKING & GAS-IDENTITY (gemini + NET-2 + deterministic scripts; codex backfill)
- **PACK-01..04 — attested CLEAN.** Every narrowing ≥ its real max via `forge inspect` (Admin `uint40` vote safe under fixed 1T supply; `activityScore uint16(score)+1` lands exactly at 65535 by deliberate cap-tuning; lossless-wei stake bound by `uint128` supply cap; 8-bit 3-state day-result covers 0/1/50–156); masked RMW preserves co-residents; `delegatecall(msg.data)` + gas refactors behavior-identical.
- **2 PACK-04 leads REFUTED:** `hasAnyLazyPass`/`lazyPassHorizon` removal (never in the vendored ABI — no consumer); `sampleTraitTickets`→`sampleTraitTicketsAtLevel` (dead-code rename, indexer already migrated).
- INFO: 2 stale comments (`SUBSCRIBER_CAP 500→1000`, `ethValueOwed 79B→160ETH`); a stale delegatecall-alignment checker (afking is correctly raw-dispatched + has `IGameAfkingModule`); a local `degenerus-sim` dev-script note.

### 402 — PERMISSIONLESS-COMPOSITION (dual-net; codex backfill)
- **PERM-01..04 — attested.** Permissionless claims credit the named beneficiary never `msg.sender`; CEI holds; decimator offset-key `lvl`/`lvl+1` isolation holds (DEC-ALIAS class); keeper bounties net-negative vs real gas; indexer events emission-only.
- **3 INFO (USER-adjudicated by-design):** (PERM-04) `MintStreakRecorded` scopes to manual-mint — pass front-load is **event-derivable** from `DeityPassPurchased`/`WhalePassClaimed` + the deterministic rule (no gap; indexer is snapshot-based regardless); (PERM-CRIT-01) the rare freeze-window ETH-spin deep-revert is the **correct trade-off** (an upfront guard would over-block the 95%+ non-ETH-spin claims; decimator is immune via value-sealed-at-bucketing; transient/self-resolving/no fund loss); (PERM-03-L1) `resolveRedemptionLootbox` missing in-leg `rngWord==0` revert = unreachable defense-in-depth.

### 403 — RNG-FREEZE SPINE (the DOMINANT invariant; full gemini+codex+NET-2)
- **RNG-01..03 — attested CLEAN.** Every new/changed consumer (Degenerette bets, the 3 box-spins, decimator claim-seed, redemption lootbox seed) is **frozen-at-commit**; the **activity score that scales the spins is snapshotted at deposit and frozen** ("the anti-gaming knob", `LootboxModule:552`) so no in-window score-bump can bias a payout; resolvers are one-shot + replay-safe (record-clear-before-effect + guards).
- **1 INFO (by-design):** resolver guard-shape variance (`address(this)==GAME` vs `msg.sender==SDGNRS` vs module-storage isolation) — equally effective, no double-resolve path.

### 404 — MUTATION (resume the v63 CI-resumable tail; bounded)
- v63 SPINE targets (BitPackingLib, DegenerusGameStorage, StakedDegenerusStonk) already scored + triaged, **0 contract defects**, all GENUINE survivors killed by regression tests — carries forward (primitives byte-identical at the v64 subject).
- v64 subject: **BurnieCoinflip** mutation launched on the re-pinned `run-campaign-v64.sh` (CI-resumable); Lootbox + Decimator CI-resumable (via_ir overnight). The v64-changed functions in all three are primarily covered by the 399–403 dual-net sweeps (all clean). Triage on completion; 0 contract defects expected. *(Result folded in on completion; see `404-MUTATION-STATUS.md`.)*

---

## Routed / open items (none block the audit verdict)

- **Fixed in-milestone:** LVL-A + the redemption day+1 multiplier (`891f7a8f`).
- **USER-confirmed by-design (no change):** RWD-A emission magnitude; PERM-04 pass-streak event-derivability; PERM-CRIT-01 freeze-window revert; the affiliate / whale-pass / quest level dispositions.
- **Optional post-audit polish (not defects):** unify resolver guard-shape; add the symmetric in-leg `rngWord==0` revert to `resolveRedemptionLootbox`; the stale comments; emit `MintStreakRecorded` on front-load paths *if* event-driven streak reconstruction is ever adopted; update the `degenerus-sim` dev scripts for the removed lazy-pass getters; register the afking `NAMING_EXCEPTION` in the delegatecall checker.
- **Captured forward:** SEED-001 (century quest-streak shield, post-audit feature).
- **CI-resumable:** the Lootbox + Decimator mutation tail.

## Method note

Every no-finding verdict has both nets on record (council + Claude Workflow). Codex hit a usage cap mid-run (phases 401/402 ran gemini + NET-2 + deterministic scripts/orchestrator cross-check; codex backfilled after the cap reset — 403 onward had the full council in-phase). The cross-model council earned its keep on RWD-A (the seed-emission EV arithmetic the other nets glossed). No Write-capable subagent mutated the frozen contract source (git-verified after every fan-out).
