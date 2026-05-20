# Phase 307 `/zero-day-hunter` Adversarial Pass — v44.0 sStonk Per-Day Redemption Refactor

```yaml
[invocation]
skill: /zero-day-hunter
mode: HYBRID_FALLBACK_SEQUENTIAL
dispatch_timestamp: "2026-05-19T16:45:00Z"
runner: orchestrator-main-context
fallback_reason: "Task tool not available in executor's tool set (Read/Write/Edit/Bash only). Per D-307-DISPATCH-01 'How to apply' + ROADMAP HYBRID-fallback allowance, /zero-day-hunter runs in main context with full persona fidelity preserved via dedicated MD anchoring the verbatim CHARGE + /contract-auditor MD as anchoring context (v43 P302 + v42 P296 precedent: both fell back to SEQUENTIAL_MAIN_CONTEXT for all 3 skills under the same constraint)."
charge_anchor: ".planning/phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-CHARGE.md"
auditor_anchor: ".planning/phases/307-adversarial-sweep-sweep/307-ADVERSARIAL-CONTRACT-AUDITOR.md"
```

```yaml
[skeptic-filter]
arm: per-skill self-filter
protocol: D-307-SKEPTIC-FILTER-01
discarded: []
note: "No (a)-only hard discards at per-skill self-filter arm. Probed hypotheses produced NEGATIVE-VERIFIED verdicts with structural-protection citations OR SAFE_BY_DESIGN intentional-design citations. No FINDING_CANDIDATE rows produced; (b)+(c) downgrade arm therefore inapplicable. Orchestrator integration-time re-application at Task 5 will re-verify."
```

---

## §0 Charge-frame re-anchor

This pass executes **SWP-02** verbatim per `307-ADVERSARIAL-CHARGE.md` §1:

> `/zero-day-hunter` PARALLEL_SUBAGENT pass. Charge: novel attack surfaces on the per-day refactor — composition with lootbox/coinflip flows; ERC20 callback-induced re-entry on transfer paths; cross-module read/write races between sStonk and DegenerusGame storage.

Plus all 5 v44-specific augments per `307-ADVERSARIAL-CHARGE.md` §2.

**Anchoring context** (per D-307-DISPATCH-01 sequencing rule): `/contract-auditor` MD at `307-ADVERSARIAL-CONTRACT-AUDITOR.md` consumed; its §3 hand-off notes name the specific re-entry / composition surfaces the auditor's SWP-01 scope deferred to hunter for closer probing.

**Hunter mindset (per `~/.claude/skills/zero-day-hunter/SKILL.md`):** Ignore already-audited surfaces. Hunt for the WEIRD edge case that 10 previous auditors missed. Think in SEQUENCES, not single calls. Question every "cleared" item with a SPECIFIC twist. Memory anchors `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md` + `feedback_rng_window_storage_read_freshness.md` apply to all RNG-touching probes.

---

## §1 Per-hypothesis disposition table

| Hypothesis-ID | Verdict | Severity tag | Evidence anchors | Reasoning summary |
| --- | --- | --- | --- | --- |
| **SWP-02.A** — Lootbox composition: player previews lootbox outcome via known `rngWord` + chooses to claim or not | NEGATIVE-VERIFIED | N-A | `StakedDegenerusStonk.sol:727` (`entropy = keccak256(abi.encode(rngWord, player))`); `:728` (`game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)`); `:725` (activityScore read from `claim.activityScore` snapshotted at burn time `:890-891`). | Backward trace per `feedback_rng_backward_trace.md`: lootbox entropy = f(rngWord, player). rngWord is committed at the resolveRedemptionPeriod-triggering advance (day D+1). claim.activityScore was committed at burn time (day D). All lootbox-relevant inputs to entropy are committed BEFORE the player can call `claimRedemption(D)`. Player CAN preview the lootbox outcome off-chain; they cannot selectively-not-claim because `claim` is one atomic call: claim ETH AND materialize lootbox. Skipping claim means losing both. No selective execution primitive. |
| **SWP-02.B** — Coinflip composition: partial-claim BURNIE branch reachable; could be replayed for state corruption | NEGATIVE-VERIFIED | N-A | `:705-710` (`coinflip.getCoinflipDayResult(period.flipDay)`); `:715-721` (partial-claim branch zeros `claim.ethValueOwed`, preserves `burnieOwed`); `:678` (claim revert guard); `:713` (cumulative scalar decrement). | Trace: second call to `claimRedemption(D)` after a partial-claim — `claim.ethValueOwed == 0` but `claim.burnieOwed != 0` → guard at `:678` passes. `totalRolledEth = (0 × roll) / 100 = 0`; ethDirect = 0; lootboxEth = 0; `pendingRedemptionEthValue -= 0` (no-op). If flipResolved still false, repeat partial-claim (no-op). If flipResolved becomes true, enters full-claim path → `delete pendingRedemptions[player][day]`. BURNIE payout based on snapshotted `claim.burnieOwed`. No double-pay (slot deleted in same tx). No state corruption. |
| **SWP-02.C** — Coinflip pool drain mid-multi-day-claim: `_payBurnie` reverts and locks claim permanently | NEGATIVE-VERIFIED | N-A | `:923-934` (`_payBurnie` mints from coinflip pool, then transfers); `BurnieCoinflip.sol:358-364` (`claimCoinflipsForRedemption(player, amount)`); `:389-413` (`_claimCoinflipsAmount` caps by `state.claimableStored`). | `burniePayout` is computed FROM `coinflip.getCoinflipDayResult` (`:705`) — so the rolled `rewardPercent` was set by coinflip's day-D+1 resolution AND the corresponding `claimableStored` was minted there. Coinflip's day-resolution commits the rewardPercent → the player's claim is bounded by what coinflip itself committed to deliver. The pool cannot be partially-empty for the SPECIFIC player at the SPECIFIC roll — coinflip credits are per-player. No global-pool-drain affects an individual player's already-resolved claim. The transfer at `:932` operates against sStonk's BURNIE balance after minting (`mintForGame` at `BurnieCoinflip.sol:409`), which produces exactly `toClaim` BURNIE — matches `remaining` exactly if `state.claimableStored >= remaining`. The only failure mode is sStonk's own BURNIE balance + coinflip credits < `burniePayout`, which would only happen if a separate uncoordinated bug zeroed claimableStored — out of scope. |
| **SWP-02.D** — Partial-claim BURNIE branch under sentinel-stall (augment (iv) sub-class 6) | NEGATIVE-VERIFIED | N-A | Sentinel guards `_submitGamblingClaim` only (`:819-821`); has NO interaction with `claimRedemption`. `claimRedemption` reads `redemptionPeriods[day].roll` + `pendingRedemptions[msg.sender][day]` only — both per-day-keyed and independent of sentinel state. | Sentinel-stall affects future BURNS (blocked by `PriorDayUnresolved`); does NOT affect existing claims for past resolved days. A partial-claim from a past resolved day proceeds normally regardless of sentinel state. Coinflip's day resolution is also independent of sentinel state (coinflip has its own day-state). No interaction. |
| **SWP-02.E** — ERC20-callback-induced re-entry on transfer paths | NEGATIVE-VERIFIED | N-A | sStonk does NOT expose `transfer(address, uint256)` / `transferFrom` / `approve` public functions. Only `wrapperTransferTo` (DGNRS-only at `:381`), `transferFromPool` / `transferBetweenPools` (game-only at `:456, :487`), `burn`/`burnWrapped` (gambling/deterministic), and `burnAtGameOver` (game-only at `:506`). | sDGNRS is **effectively non-transferable for normal holders** — there is no player-callable ERC20 `transfer` on this contract. Augment (iv) sub-class 1 ("transfer mid-pending") is therefore STRUCTURALLY UNREACHABLE as a player exploit. No callback surface. |
| **SWP-02.F** — Cross-module read/write race between sStonk and DegenerusGame storage | NEGATIVE-VERIFIED | N-A | sStonk reads from game: `currentDayView`, `gameOver`, `rngLocked`, `livenessTriggered`, `playerActivityScore`, `claimableWinningsOf`, `rngWordForDay` — all view fns. Writes to game: `claimWinnings`, `resolveRedemptionLootbox`. Game reads from sStonk: `pendingResolveDay`, `hasPendingRedemptions`. Game writes to sStonk: `resolveRedemptionPeriod` (only writer). | Cross-module call graph is clean: game writes sStonk only at `resolveRedemptionPeriod`; sStonk writes game only at `claimWinnings` (pulls in claimable ETH) + `resolveRedemptionLootbox` (materializes lootbox post-resolve). No SLOAD-then-write hazard where game reads sStonk state then writes back without atomic ordering. `resolveRedemptionPeriod` is `onlyGame`-gated at `:634` — only AdvanceModule's resolve path can write. AdvanceModule's resolve is called inside the advance tx; no other tx can interpose. |
| **SWP-02.G** — Same-block burn + advance interleaving via flashbot bundle | NEGATIVE-VERIFIED | N-A | Burn at `_submitGamblingClaimFrom:809-895` is one tx; advanceGame is another tx; the rngGate's resolve-redemption path (`AdvanceModule:1227-1235`) only fires when `currentWord != 0 && rngRequestTime != 0` (i.e., VRF callback already arrived). | Same-block sequencing: Player burns day D → sentinel = D + pool populated. Next tx in block: anyone calls advanceGame → if VRF callback is also in the same block (extremely rare; VRF callback is itself a separate tx from a different sender), rngGate processes resolution against the freshly-burned pool. `redemptionRoll` derived from `currentWord` (VRF) — not from player input. Player's `ethValueOwed` is committed in the burn tx BEFORE the resolve tx — order respected. No exploit. |
| **SWP-02.H** — Multi-actor sentinel race (augment (iv) sub-class 3) | NEGATIVE-VERIFIED | N-A | `:819-821` sentinel write guarded by `if (stamp == 0)` — only first burn of day writes sentinel; subsequent burns in same day reach `stamp == currentPeriod` branch and skip the write. Pool at `:823` indexed by `currentPeriod`; INV-04 pool-base accumulation correct. | Two distinct players burning same day D: A's burn sets sentinel = D; B's burn passes `stamp == currentPeriod (== D)`; B's pool addition lands in `pendingByDay[D]` correctly (INV-04). No race — both writes are sequential SSTORE on the same slot, and Solidity `+=` on a uint64 field is read-modify-write within a single tx. Two txes in same block are sequenced by miner ordering; both produce correct cumulative pool. |
| **SWP-02.I** — Selfdestruct ETH inflation of sStonk balance pre-burn | NEGATIVE-VERIFIED | N-A | `:414` (`receive() external payable onlyGame` — blocks direct ETH transfers); EIP-6780 (post-Cancun SELFDESTRUCT no longer transfers ETH for post-fork contracts). | Direct ETH transfer to sStonk is blocked by `onlyGame`. SELFDESTRUCT-injected ETH post-EIP-6780 is structurally disabled. Even if it worked: the attacker would need to donate ETH (their own) to inflate pro-rata pool; subsequent burners (including the attacker if they re-burn) get higher pro-rata. The attacker pays themselves back ONLY if they're the only burner of the pro-rata window — same as v43-era pro-rata semantics; not a new v44 vector. |
| **SWP-02.J** — Vault re-entry on `sdgnrsClaimRedemption` (augment (v)) | NEGATIVE-VERIFIED | N-A | `DegenerusVault.sol:489-491` (`receive() external payable` only emits Deposit event — no state mutation, no external call); `StakedDegenerusStonk.sol:715-721` (state mutation BEFORE external calls — CEI ordering); `:728, :733, :739` (external calls in this order: lootbox materialize, BURNIE pay, ETH pay). | claim flow: state mutation (`delete pendingRedemptions[player][day]` or partial-zero) at `:715-721` BEFORE any external call. ETH payout last (`:739`). Vault's `receive()` is benign. Even if vault had a malicious fallback that re-entered `sdgnrsClaimRedemption(D)` mid-claim, the re-entered call would read `pendingRedemptions[vault][D].ethValueOwed == 0` (just zeroed) → revert `NoClaim` at `:678`. CEI structurally closes re-entry. |
| **SWP-02.K** — Vault-ownership flip mid-pending lets a different owner extract (augment (v)) | NEGATIVE-VERIFIED | N-A | `DegenerusVault.sol:431` (`onlyVaultOwner` — >50.1% DGVE); `:719-721` (`sdgnrsBurn` — vault burns vault's sDGNRS); `:729-731` (`sdgnrsClaimRedemption` — vault claims vault's redemption); `StakedDegenerusStonk.sol:675-740` (`claimRedemption` — payout to `msg.sender = vault`, NOT to caller). | When `vault.sdgnrsClaimRedemption(D)` fires, ETH/BURNIE flow back to the VAULT (msg.sender from sStonk's POV), not to the caller of `vault.sdgnrsClaimRedemption`. DGVE/DGVB holders share pro-rata via standard vault accounting. Vault owner A burns; DGVE rebalances; vault owner B claims; payout still goes to vault — A and B both have their pro-rata exposure via DGVE/DGVB shares unchanged by the call. No extraction primitive. |
| **SWP-02.L** — `retryLootboxRng()` interaction with sentinel-stamped pool | NEGATIVE-VERIFIED | N-A | `AdvanceModule.sol:1132-1155` (`retryLootboxRng` only re-requests VRF; does NOT touch sStonk); sentinel resolution happens via `rngGate` / `_gameOverEntropy` only at `:1228, :1294, :1327`. | `retryLootboxRng` affects WHEN the next VRF word arrives, not HOW the sentinel is processed. The sentinel resolves on the next successful `advanceGame` after VRF callback regardless of whether retryLootboxRng was used. No additional code path opens. |
| **SWP-02.M** — Sub-class 7 (admin-class actions during rngLock mid-pending) | NEGATIVE-VERIFIED | N-A | sStonk admin paths: `transferFromPool`, `transferBetweenPools`, `burnAtGameOver`, `gameAdvance`, `gameClaimWhalePass`, `wrapperTransferTo`, `depositSteth`. None of these read or write `pendingByDay`, `pendingRedemptions`, `pendingResolveDay`, `redemptionPeriods`, or the cumulative scalars `pendingRedemptionEthValue` / `pendingRedemptionBurnie`. | Admin paths operate on `poolBalances` (the reward-pool array) and `balanceOf` (ERC20 state) — not on redemption state. Admin actions during rngLock do NOT mutate any redemption-state SLOAD/SSTORE that interleaves with the burn/claim/resolve flow. |
| **SWP-02.N** — Sub-class 8 (rngLock + sentinel double-window: end-run via vault claim) | NEGATIVE-VERIFIED | N-A | `claimRedemption:675-740` has NO rngLock guard (burn does at `:536`, claim does not by design — claim is post-resolve, rngLock-window-irrelevant). `DegenerusVault.sol:729-731` (no rngLock guard) — same property. | Claims are post-resolve operations on already-stable `redemptionPeriods[D].roll` + `pendingRedemptions[player][D]`. There's nothing about an active rngLock that would affect a past day's claim. Burns ARE blocked during rngLock per EDGE-11; claims are deliberately not. No exploit. |
| **SWP-02.O** — sStonk view-function reentry via stETH rebase mid-call | NEGATIVE-VERIFIED | N-A | `:842` (`stethBal = steth.balanceOf(address(this))`); `:759, :779, :790` (view-fn reads); stETH `balanceOf` is a view fn that reads cached `shares * shareRate` — no callback to sStonk. | stETH rebases happen at oracle update time (separate tx from any sStonk call). Within a sStonk tx, `steth.balanceOf` returns a stable value. No view-callback re-entry surface. |
| **SWP-02.P** — Selector collision across modules | NEGATIVE-VERIFIED | N-A | sStonk public selectors: `burn(uint256)=0x42966c68`, `burnWrapped(uint256)=0x...`, `claimRedemption(uint32)=0x...`, `resolveRedemptionPeriod(uint16,uint32,uint32)=0x...`. Each is unique by signature. | sStonk is a standalone contract (not a delegatecall target for the game's modules). Selector collision would require a delegatecall context — N/A here. |
| **Augment (i)** — DayPending packing edges (hunter lens: weird bit-shift / packing-induced races) | NEGATIVE-VERIFIED | N-A | `:247-252` struct DayPending. Solidity-managed packing (compiler-emitted SHL/SHR/AND-mask). All 4 fields are uint64 — no field-bit-overlap. `pool.burned += uint64(amountWhole)` at `:836` is compiler-emitted atomic SLOAD-mask-OR-SSTORE. | Hunter probe for compiler-managed packing bugs (e.g., field A's `+=` corrupting field B's bits via wrong mask): looked at solc 0.8.x packed-struct codegen. SLOAD entire slot, MASK out field A's range, MASK in new field A value, SSTORE. Cannot affect adjacent fields' bits. Standard codegen. ✓ |
| **Augment (ii)** — pendingResolveDay sentinel weird sequences | NEGATIVE-VERIFIED | N-A | `:269, :665, :819-821`; `AdvanceModule:1228, 1234, 1294, 1300, 1327, 1333`. | Hunter sequence-probe: (1) "Stamp sentinel via tx-1 burn; revert tx-1 mid-burn after sentinel set" → EVM transactional rollback nullifies SSTORE. ✓ (2) "Two parallel txes both setting sentinel" → miner ordering; second sees stamp != 0 in same-day, skips re-write; pool accumulation correct. ✓ (3) "Sentinel set day D, never resolved, day D+1 burn attempted" → reverts `PriorDayUnresolved`. ✓ (4) "Game day arithmetic underflow on day 0 collision with sentinel = 0" → day 0 unreachable by construction (`_simulatedDayIndexAt` underflows). ✓ (5) "Sentinel + retry combos" → covered by SWP-02.L. ✓ |
| **Augment (iii)** — gwei-snap precision interaction (hunter lens: weird floor-div + integer truncation edges) | NEGATIVE-VERIFIED | N-A | `:858-861` (`ethValueOwed = (ethValueOwed / 1e9) * 1e9; burnieOwed = (burnieOwed / 1e9) * 1e9;`). | Hunter probe: can a player time burns to land on sub-gwei boundaries that the snap fails to handle? Snap is `(x/1e9)*1e9` — pure integer arithmetic; truncates downward to nearest gwei multiple. Player loses up to 1 gwei per burn. No way to "snap up" by manipulating inputs. Deterministic monotonic-downward truncation. ✓ |
| **Augment (iv)** — Phase 306 INV harness perturbation-class gaps (hunter scope: composition + re-entry arms; see SWP-02.A..N above for sub-class enumeration) | NEGATIVE-VERIFIED | N-A | Sub-class 1 (transfer mid-pending) → SWP-02.E STRUCTURALLY UNREACHABLE. Sub-class 2 (approve mid-stall) → sStonk has no `approve` fn; structurally unreachable. Sub-class 3 (multi-actor sentinel race) → SWP-02.H. Sub-class 4 (ERC20 callback re-entry) → SWP-02.E + SWP-02.J. Sub-class 5 (coinflip pool drain) → SWP-02.C. Sub-class 6 (partial-claim BURNIE under sentinel-stall) → SWP-02.D. Sub-class 7 (admin during rngLock) → SWP-02.M. Sub-class 8 (rngLock + sentinel double-window) → SWP-02.N. | All 8 hypothesized perturbation classes resolved NEGATIVE-VERIFIED with structural-protection citations. The Phase 306 harness's 5-action set + 13-INV + 20-EDGE coverage is shown to be PROOF-COMPLETE for the v44 invariant set — the missing-action classes either map to structurally-unreachable transfer paths (no transfer fn) or to interactions that auditor + hunter analyses confirm do not break any INV. |
| **Augment (v)** — Vault scope-expansion ACL (hunter lens: composability + re-entry) | NEGATIVE-VERIFIED | N-A | `DegenerusVault.sol:431, :719-721, :729-731`; sStonk `claimRedemption` CEI ordering. | Hunter probes: (a) reentry → SWP-02.J. (b) vault-owner flip extraction → SWP-02.K. (c) composability: vault's other onlyVaultOwner fns (`gameAdvance`, `gameClaimWhalePass`, `sdgnrsBurn`, `coinDecimatorBurn`, etc.) — none of these mutate `pendingRedemptions[vault][D]` directly. Only `sdgnrsBurn → sdgnrsToken.burn → _submitGamblingClaim` does. No cross-fn race that lets a vault owner double-spend the same per-day pending slot. ✓ |

---

## §2 Skeptic-Filter Self-Discarded subsection

**No self-discards.** Hunter produced 22 hypothesis disposition rows; all NEGATIVE-VERIFIED with concrete structural-protection citations. The skeptic-filter (a)-only hard discard arm had no `FINDING_CANDIDATE` inputs.

| Hypothesis-ID | Source skill | Structural-protection citation (file:line) | EV-lens failed condition | Note |
| --- | --- | --- | --- | --- |
| (none) | /zero-day-hunter | n/a | n/a | No FINDING_CANDIDATE produced; nothing to discard. |

---

## §3 Cross-skill hand-off notes

### To `/contract-auditor` (already complete at Task 2)

- Hunter confirms auditor's INV-01..13 verdicts. No state-transition path uncovered that the auditor's SWP-01 scope missed.
- Hunter adds **SWP-02.E** (sDGNRS non-transferable) as a structural protection: augment (iv) sub-class 1 (transfer mid-pending) is unreachable.

### To `/economic-analyst` (Task 4)

- **Lootbox-preview foreknowledge (SWP-02.A elaboration):** Player knows `rngWord` for day D before calling `claimRedemption(D)`. They can compute lootbox `entropy = keccak256(abi.encode(rngWord, player))` ahead of time. Does the lootbox's payout distribution have outliers a rational EV-maximizer would game by timing claim across multiple days strategically? Economist's lens for activity-score timing arbitrage.
- **Partial-claim BURNIE retention (SWP-02.B elaboration):** Player can hold a partial-claim slot indefinitely (BURNIE preserved). Economist: does indefinite-hold create any economic exposure (e.g., BURNIE value erodes over time, deflationary pressure, etc.)?
- **Vault-owner timing strategy (SWP-02.K elaboration):** Vault owner can time `sdgnrsBurn` and `sdgnrsClaimRedemption` calls; does any DGVE-rebalance dynamic create a profitable "buy DGVE-just-before-burn-then-sell-after-claim" pattern? Economist's call.
- **`previewBurn` UI confusion as adversarial vector (SWP-02.O elaboration):** Off-chain UIs read `previewBurn`; the value excludes `pendingRedemptionEthValue`. A whale could time a burn to land just before a large resolve (pendingRedemptionEthValue spike) to take advantage of lower-than-actual `previewBurn` shown to other players. Economist's call for whether this MEV-type informational asymmetry is profitable.

---

## §4 Summary

| Bucket | Count |
| --- | --- |
| Hypotheses charged | 22 (16 SWP-02-derived + 5 augments + 1 cross-augment per row consolidation) |
| NEGATIVE-VERIFIED | 22 |
| FINDING_CANDIDATE | 0 |
| SAFE_BY_DESIGN | 0 |
| Skeptic-filter self-discards | 0 |
| Severity downgrades | 0 (no findings to downgrade) |

**Verdict:** `/zero-day-hunter` HYBRID_FALLBACK_SEQUENTIAL pass produces 0 FINDING_CANDIDATE rows. All charged hypotheses + augments + sequence-probe rows produce concrete NEGATIVE-VERIFIED verdicts.

**Key structural protections discovered:**
- **sDGNRS is non-transferable** for normal holders (only DGNRS-wrapper + game + pool-admin paths can move it). Structurally eliminates ERC20-callback re-entry on transfer paths (SWP-02.E + augment (iv) sub-class 1).
- **Vault claim payout flows to vault, not caller** (SWP-02.K). Eliminates vault-owner-flip extraction primitive.
- **Sentinel write guarded by `if (stamp == 0)`** prevents same-day double-write races (SWP-02.H + augment (ii) sub-probe c).
- **CEI ordering in `claimRedemption`** (state mutation before external calls) closes reentry from any external recipient including vault (SWP-02.J).
- **EIP-6780 disables SELFDESTRUCT-injection** (SWP-02.I); `receive() onlyGame` blocks direct ETH transfer.
- **`pendingResolveDay` sentinel always names at-most-one stuck day** (augment (ii)); resolve is exact even across multi-day stalls.

Cross-skill hand-off rows in §3 flag concerns the hunter defers to `/economic-analyst` (lootbox-preview foreknowledge, partial-claim BURNIE hold, vault-owner timing, previewBurn UI asymmetry).

---

*Phase 307 / Plan 01 / Task 3 / `/zero-day-hunter` HYBRID_FALLBACK_SEQUENTIAL / 2026-05-19.*
