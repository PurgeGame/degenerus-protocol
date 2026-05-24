# Phase 320 Adversarial-Pass Charge — v46.0 Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal (TERMINAL)

**Phase:** 320-audit-adversarial-sweep-add-remove-delta-audit-closure-termi
**Plan:** 01
**Authored:** 2026-05-24
**Audit baseline:** v45.0 closure HEAD `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`
**Subject under probe:** v46.0 audit-subject HEAD — the batched Phase 317 ADD+REMOVE diff (`df4ef365`) + the keeper-reconciliation / slot gap-closure (317-08 family) + the Phase 319.1 OPEN-E diff (`42140ceb` + WR-01 event `e1baa978`) + the Phase 319 GAS pegs (`e4014f91` + CR-01 fix `795e679d`) + the JGAS jackpot-split removal across `DegenerusGameAdvanceModule` + `DegenerusGameJackpotModule`. SOURCE-TREE FROZEN reference: phase-start HEAD `30b5c89c` (contracts/+test/ byte-frozen since).
**Composition:** `/contract-auditor` FIRST (anchor) + `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT (D-05 ADAPTIVE PARALLEL→HYBRID; HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT allowed if the executor lacks the Task tool).
**Out-of-scope skills:** `/degen-skeptic` (D-271-ADVERSARIAL-02 carry).
**In-scope skills:** `/economic-analyst` (D-271-ADVERSARIAL-03 carry).

---

## §0 Charge-Frame

### Master charge — verbatim ROADMAP §"Phase 320" Goal surface list (the non-negotiable instruction set)

> SOURCE-TREE FROZEN — zero `contracts/` + zero `test/` mutations during Phase 320 (unless a Tier-1 user-approved or Tier-2 auto-elevated FINDING_CANDIDATE triggers a RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01`). **Adversarial sweep** — `/economic-analyst` + `/zero-day-hunter` (and `/contract-auditor` per the established 3-skill HYBRID pattern; `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02`) charged with: composition + subscription-trigger griefing + coinflip-credit recycle + BURNIE-supply interaction + the `burnForKeeper`/`creditFlip`/`batchPurchase` authority surface + the two-tier skip-kill identity (can a NORMAL sub spoof the Vault/sDGNRS exemption? can a funding-margin griefer force-cancel a fragile claimable-only sub?) + the OPEN-E shared-funding-source surface from Phase 319.1 (can subscriber M point `fundingSource` at a non-consenting S — without `isOperatorApproved(S, M)` — to drain S's `_poolOf` ETH or burn S's general wallet BURNIE + pending coinflip? is a cross-account draw impossible without `isOperatorApproved(S, M)` at `subscribe()` (subscribe-only auth — revocation intentionally does NOT retroactively stop an active sub; an active funding sub's drain is bounded only by sub lifetime + S-defunding, the by-design trust-the-sub posture)? can the `fundingSource` redirect spoof the Vault/sDGNRS subscriber-identity skip-kill exemption? does the default-self `fundingSource == 0` path stay behavior-identical?) + faucet round-trip + the REMOVE surface (can removing the ETH auto-rebuy branch strand winnings? can the BURNIE 75bps collapse under/over-credit? can removing the two-call jackpot split strand a payout via the dropped `resumeEthPool` carry, or under/over-pay a bucket at the 305-winner single-call ceiling?). Skeptic-reviewer filter per `feedback_skeptic_pass_before_catastrophe.md` (structural-protection check + 3-condition EV lens) BEFORE any user-pause; two-tier consensus (Tier-1 any-skill FINDING_CANDIDATE → AskUserQuestion PAUSE; Tier-2 3-of-3 → auto-elevation + RE-PASS).

This charge decomposes the verbatim surface list into the seven SWP charge IDs below (SWP-AUTH, SWP-SKIP, SWP-OPENE, SWP-GRIEF, SWP-ECON, SWP-REMOVE, SWP-COMPOSE) covering all nine named surfaces: composition (SWP-COMPOSE), subscription-trigger griefing (SWP-GRIEF), coinflip-credit recycle (SWP-ECON), BURNIE-supply interaction (SWP-ECON), the `burnForKeeper`/`creditFlip`/`batchPurchase` authority surface (SWP-AUTH), the two-tier skip-kill identity (SWP-SKIP), the OPEN-E shared-funding-source surface (SWP-OPENE), faucet round-trip (SWP-GRIEF), and the REMOVE surface (SWP-REMOVE).

### Composition and sequencing (D-05 ADAPTIVE PARALLEL→HYBRID)

- **`/contract-auditor`** — runs FIRST (anchor). Owns the structural / authority surface (SWP-AUTH, the SWP-OPENE four D-03 residual structural charges, the SWP-REMOVE grep-clean kill sets + JGAS single-call payout structure). Its disposition MD anchors the parallel hunter + economist pair so they diverge rather than rediscover.
- **`/zero-day-hunter` + `/economic-analyst`** — PARALLEL_SUBAGENT, dispatched in a single multi-Task message, both receiving the auditor MD as anchoring context. `/zero-day-hunter` owns novel / composition vectors (SWP-GRIEF subscription-trigger griefing + faucet round-trip, SWP-SKIP spoofing, SWP-OPENE fundingSource redirect-to-different-address escalation, SWP-REMOVE dropped-`resumeEthPool`-carry stranding, SWP-COMPOSE cross-surface ADD×REMOVE×OPEN-E). `/economic-analyst` owns incentive vectors (SWP-ECON coinflip-credit recycle EV + BURNIE-supply interaction, SWP-SKIP funding-margin griefer force-cancel, SWP-OPENE trust-the-sub temporal-bound EV + the D-02 overload cost/benefit, SWP-REMOVE 75bps collapse cost/benefit, beyond-charge rows).
- **D-05 mechanics:** parallel dispatch is attempted ONLY if the runner genuinely holds the Task tool. The Phase 320 sweep runs in the main orchestrator context, which DOES hold the Task tool, so PARALLEL_SUBAGENT is the planned mode (mirroring v45 Phase 314 — the genuine-parallel precedent). If parallel dispatch fails (subagent crash, malformed output, timeout, persona drift) for either parallel skill, HYBRID-fallback to SEQUENTIAL_MAIN_CONTEXT for that skill and document `mode: HYBRID_FALLBACK_SEQUENTIAL` + `fallback_reason` in the per-skill MD `[invocation]` frontmatter. Persona fidelity is preserved via the dedicated per-skill MD carrying the verbatim CHARGE regardless of mode.

### Two-tier consensus rule (D-302-CONSENSUS-01 carry)

- **Tier-1** — Any single skill's `FINDING_CANDIDATE` that survives the dual-gate skeptic filter → AskUserQuestion user-pause at integration time. User adjudicates (elevate / SAFE_BY_DESIGN / NEGATIVE-VERIFIED-on-reconsideration). This is the sensitive-contract boundary per `feedback_pause_at_contract_phase_boundaries.md`.
- **Tier-2** — 3-of-3 cross-skill consensus `FINDING_CANDIDATE` on the same hypothesis → automatic elevation + RE-PASS per `D-284-ADVERSARIAL-RE-PASS-01` (no user-pause for the elevation itself; user diff review still required for any `contracts/*.sol` change per `feedback_manual_review_before_push.md`).
- **unanimous-NEGATIVE** — No surviving `FINDING_CANDIDATE` from any skill → no elevation, no user-pause. The RE-PASS precondition gate fails; the phase proceeds directly to the integrated LOG verdict. **This is the EXPECTED outcome** per the lean-verification-formality posture (cf. v42 P296 / v43 P302 / v44 P307 / v45 P314 — all unanimous-NEGATIVE).

### 3-classification disposition rubric

Per-hypothesis verdict ∈ {`NEGATIVE-VERIFIED`, `FINDING_CANDIDATE`, `SAFE_BY_DESIGN`} crossed with per-skill source ∈ {`/contract-auditor`, `/zero-day-hunter`, `/economic-analyst`}. Each row is recorded in §1 of the per-skill MD and aggregated into `320-01-ADVERSARIAL-LOG.md`.

- **NEGATIVE-VERIFIED** — Hypothesis was probed concretely (file:line trace through current source) and found unreachable / non-exploitable / structurally closed. Cite the structural protection.
- **FINDING_CANDIDATE** — Hypothesis surfaces a reachable-by-attacker exposure with a concrete attack narrative + (b)/(c) EV-lens signal. Must carry a severity tag from {CATASTROPHE, HIGH, MEDIUM, LOW, N-A}.
- **SAFE_BY_DESIGN** — Hypothesis points at a design choice the protocol intentionally made (e.g., the operator-approval trust boundary per D-01, the BURNIE-funding overload per D-02, the trust-the-sub temporal bound per D-03.4). Cite the decision / design rationale.

> **Posture:** lean **verification-formality** with FULL disposition enumeration, expecting unanimous-NEGATIVE. The genuinely-new contract surface is `AfKing.sol` (a brand-new in-tree keeper) + the OPEN-E `fundingSource` routing; everything else (the crank/subscription ADD, the legacy-AFKing/ETH-auto-rebuy REMOVE, the JGAS split removal, the GAS pegs) is delta-audited at 320-02 + 320-03 and re-attested here. The bar is rigorous full enumeration, NOT adversarial over-reach.

---

## SWP-AUTH — the burnForKeeper / creditFlip / batchPurchase authority surface (§1; primary `/contract-auditor`)

### Charge

Prove the three authority primitives cannot be driven by an unauthorized caller or be made to over/under-pay. **`burnForKeeper`** is all-or-nothing and `onlyAfKing`-gated on the BURNIE side; the keeper consumes it on the subscribe-time SUB-01 pass-or-pay charge and the day-31 auto-extract. **`creditFlip`** is `onlyFlipCreditors`-gated (extended to include the keeper) and pays the do-work bounty as ONE gas-pegged credit per tx (never per-item). **`batchPurchase`** is keeper-gated with a per-player try/catch + slice-refund. Red-team: can a non-keeper reach `burnForKeeper`/`creditFlip`? can the all-or-nothing semantics be partially-applied to double-spend a charge? can `batchPurchase`'s per-player try/catch swallow a failure that strands or double-credits a winning?

### Evidence anchors (re-grep vs HEAD before citing)

- `contracts/AfKing.sol:50` — `IBurnie.burnForKeeper(address user, uint256 amount) external returns (uint256 burned)` interface decl; `:47` NatSpec `onlyAfKing` gate note.
- `contracts/AfKing.sol:63` — `ICoinflip.creditFlip(address player, uint256 amount)` interface decl; `:60` NatSpec `onlyFlipCreditors` gate note (extended to include the keeper).
- `contracts/AfKing.sol:438` — subscribe-time `burnForKeeper(` charge (window-1 SUB-01 pass-or-pay; reads the `fundingSource` set earlier in the SAME call at `:426`); `:634` — day-31 sweep auto-extract `burnForKeeper(`.
- `contracts/AfKing.sol:802` — `ICoinflip(ContractAddresses.COINFLIP).creditFlip(msg.sender, bountyEarned)` — ONE gas-pegged bounty credit per tx; `:796` NatSpec "never per-item".
- `contracts/BurnieCoin.sol` — re-grep the `onlyAfKing` modifier + `burnForKeeper` body for the all-or-nothing semantics; `contracts/BurnieCoinflip.sol` — re-grep `onlyFlipCreditors` + `creditFlip`.
- `batchPurchase` — re-grep the keeper-gate + per-player try/catch + slice-refund across the game module that owns it (resolve the owning module via grep; the keeper-gate is the structural protection).

---

## SWP-SKIP — the two-tier subscriber-identity skip-kill (§1; `/zero-day-hunter` spoofing + `/economic-analyst` griefer)

### Charge

The day-31 sweep applies a two-tier skip-kill: protocol subscribers (Vault/sDGNRS, SUB-09 permanent-deity) are EXEMPT from the funding-skip kill; a NORMAL sub that cannot fund is auto-paused/killed. Red-team the IDENTITY of the exemption. **(a)** Can a NORMAL sub spoof the Vault/sDGNRS exemption? The exemption MUST be keyed on the un-spoofable SUBSCRIBER identity (the `address(this)` self-subscribe of the Vault/sDGNRS), NEVER on the `fundingSource` (which a NORMAL sub controls). **(b)** Can a funding-margin griefer force-cancel a fragile claimable-only sub — i.e., push a victim sub just under its funding margin at the skip-kill boundary to trigger the auto-pause? Disposition the kill trigger's caller-independence (does any third-party crank action change WHO gets killed, or only WHETHER the victim's own funding covers the charge?).

### Evidence anchors (re-grep vs HEAD before citing)

- `contracts/AfKing.sol:721` — comment "(6) InsufficientPool funding skip → two-tier skip-kill. A NORMAL sub…"; `:728` — `if (_poolOf[src] < msgValue)` (the funding-skip branch); the skip-kill / auto-pause emission (re-grep `AutoPause` / the day-31 kill site).
- `contracts/AfKing.sol:660` — `isOperatorApproved(player, address(this))` (a sweep-side gate distinct from the subscribe-time gate — enumerate which identity it keys on).
- `contracts/DegenerusVault.sol:474` — `afKing.subscribe(address(this), true, false, 1, 0, address(0))` (SUB-09 self-subscribe, `fundingSource = address(0) = self`); `contracts/StakedDegenerusStonk.sol:380` — `afKing.subscribe(address(this), true, false, 1, 2, address(0))`. The exemption MUST key on this `address(this)` subscriber identity.
- The two-tier exemption read site in `sweep()` — re-grep where the kill decision branches on subscriber identity; prove it cannot read `fundingSource` for the exemption.

---

## SWP-OPENE — the OPEN-E shared-funding-source surface (§1; `/contract-auditor` structural + `/zero-day-hunter` escalation + `/economic-analyst` EV)

### Charge framing per the LOCKED CONTEXT decisions D-01 / D-02 / D-02a

- **D-01 — Operator-approval IS the trust boundary (load-bearing threat-model assumption).** Any `M` holding `setOperatorApproval(S, M) = true` is, by assumption, **either the same person as `S` (multi-wallet) or a fixed/known contract `S` deliberately integrated with.** There is NO "tricked into granting" actor in the threat model — *"approve the wrong guy and you prob getting rekt so just dont do that."* The protocol's only job is to enforce the gate exists; the consent *scope* is the grantor's responsibility (caveat emptor on the grant). **Do NOT model a tricked-into-approving actor.**
- **D-02 — The BURNIE-funding overload is ACCEPTED-BY-DESIGN / SAFE_BY_DESIGN.** OPENE-04's caveat — that the operator-approval also authorizes `M`'s subscription to burn `S`'s general-wallet BURNIE + pending coinflip (sharper than the pre-funded ETH escrow `_poolOf[S]` the gate was originally chosen for) — is consensual by construction under D-01. The sweep documents it as accepted with rationale; it is **NOT a FINDING_CANDIDATE to be elevated.** Record it as an explicit SAFE_BY_DESIGN row with the D-01 rationale.
- **D-02a — The `allowBurnieFunding[S][M]` opt-in flag is DROPPED, not deferred.** Under D-01 it adds nothing (S already chose to trust M with the whole grant). **Do NOT charge a "missing opt-in flag" finding.**

### The four D-03 residual STRUCTURAL must-pass charges (NOT waived by D-01/D-02 — FAILURE of any = a genuine FINDING_CANDIDATE)

These are the gate that makes the trust assumption hold, so the sweep MUST still prove each. Each is a distinct must-prove sub-charge with the verdict bar that failure = a genuine FINDING_CANDIDATE → Tier-1 PAUSE → potential RE-PASS contract fix (the one path that could break SOURCE-TREE FROZEN).

- **SWP-OPENE.1 — No cross-account draw without consent.** A non-approved `M` pointing `fundingSource = S` MUST revert (`NotApproved`); `isOperatorApproved(S, M)` is genuinely enforced **at `subscribe()`** (subscribe-only auth — never per-draw, never at day-31 renewal). Verdict bar: a non-zero, non-self `fundingSource` whose owner has NOT approved the subscriber reaches the ETH `_poolOf` draw or a `burnForKeeper` charge = a CATASTROPHE FINDING_CANDIDATE.
- **SWP-OPENE.2 — Default-self identity byte-identical.** `fundingSource == 0` (self) stays behavior-identical to pre-OPEN-E — short-circuits the approval read, SLOADs the same single `_poolOf` slot, per-draw gas unchanged. Verdict bar: any per-draw behavioral or gas divergence on the default path = a FINDING_CANDIDATE.
- **SWP-OPENE.3 — No escalation beyond the grant.** `M` cannot redirect to drain a *different*, non-approving address, and the `fundingSource` redirect cannot spoof the Vault/sDGNRS subscriber-identity skip-kill exemption (the exemption is keyed on the un-spoofable SUBSCRIBER identity, never the source — cross-ref SWP-SKIP). Verdict bar: any redirect that reaches a non-approving address's funds, or any source-keyed exemption spoof, = a FINDING_CANDIDATE.
- **SWP-OPENE.4 — Trust-the-sub temporal bound (documented, accepted).** A later `setOperatorApproval(M, false)` revoke does NOT retroactively stop an active sub; an active funding sub's drain is bounded only by sub lifetime + `S`-defunding (`_poolOf[S]` ETH / spending down BURNIE) or `M` cancelling. This by-design posture is the accepted bound, **NOT a defect** — record SAFE_BY_DESIGN. Verdict bar: this is a SAFE_BY_DESIGN row; only an UNBOUNDED drain (one not bounded by sub lifetime + S-defunding) would be a FINDING_CANDIDATE.

### Evidence anchors (re-grep vs HEAD before citing — these are STARTING anchors, not authoritative)

- `contracts/AfKing.sol:79` — `struct Sub`; `:85` — `address fundingSource;` (offset-11; `address(0)` = self).
- `contracts/AfKing.sol:375` — `function subscribe(`; `:381` — `address fundingSource` param (the SOLE set point feeds `:426 s.fundingSource = fundingSource`).
- `contracts/AfKing.sol:389-390` — third-party-subscribe operator gate `isOperatorApproved(subscriber, msg.sender)` → `revert NotApproved()`; `:400-402` — cross-account fundingSource gate `!isOperatorApproved(fundingSource, subscriber)` → `revert NotApproved()` (SWP-OPENE.1 — the live gate, subscribe-only).
- `contracts/AfKing.sol:130` — `error NotApproved();`.
- `contracts/AfKing.sol:439` — subscribe-time resolve `s.fundingSource == address(0) ? subscriber : s.fundingSource` (SWP-OPENE.2 short-circuit); `:635` — day-31 resolve `sub.fundingSource == address(0) ? player : sub.fundingSource`; `:697` — ETH-draw resolve `address src = sub.fundingSource == address(0) ? player : sub.fundingSource`.
- `contracts/AfKing.sol:728` — `if (_poolOf[src] < msgValue)` (the resolved-src ETH draw); `:750` — `_poolOf[src] -= msgValue` (SWP-OPENE.2 same-single-slot SLOAD).
- `contracts/AfKing.sol:160` — `event SubscriptionUpdated(` with indexed `fundingSource` (WR-01 `e1baa978`); emitted at `:429` (subscribe) + the cancel/update sites.
- `.planning/phases/319.1-impl-open-e-shared-funding-source-burnie-and-eth-pool/319.1-VERIFICATION.md` — the 13/13 OPENE-01..04 verification (RE-ATTEST, do NOT re-derive).
- `.planning/REQUIREMENTS.md` §OPENE (`:96-99`) — OPENE-01..04 (the funding-source contract being re-attested). **NOTE: the REQUIREMENTS / CONTEXT cites `AfKing.sol:396` / `:587` for the burnForKeeper sites — these are STALE; the live sites are `:438` (subscribe-time) + `:634` (day-31).**

---

## SWP-GRIEF — subscription-trigger griefing + faucet round-trip (§1; primary `/zero-day-hunter`)

### Charge

**Subscription-trigger griefing:** the do-work crank is permissionless (third parties crank others' subs/boxes for a bounty). Can a griefer trigger a victim's subscription charge / sweep at an adversarial time, force an unwanted auto-rebuy, or burn a victim's funding when the victim did not want a crank this cycle? Disposition the caller-independence of the OUTCOME (the cranker chooses WHEN to crank, but can they change WHAT happens to the victim beyond what the victim's own sub config + funding already authorize?). **Faucet round-trip:** the "free BURNIE" crank bounty pays a `creditFlip` reward. Prove the self-crank / Sybil round-trip is ≤ 0 (a cranker cannot profitably crank their own work), WWXRP (currency==3) earns zero, one-reward-per-item, and no pre-RNG-word resolution leaks entropy.

### Evidence anchors (re-grep vs HEAD before citing)

- `contracts/AfKing.sol:569` — `function sweep(uint256 maxCount) external returns (uint256 bountyEarned)` (the permissionless crank entrypoint); `:802` — the ONE `creditFlip` bounty payout per tx; `:796` NatSpec "never per-item".
- The gas-peg constants (`e4014f91` + CR-01 `795e679d`) — the per-box marginal peg (71_203) + the resolve peg (66_528) that make the round-trip ≤ 0 (cross-ref 320-03 SAFE-01 faucet-bounded + the WR-01 round-trip guard).
- The 318 SAFE-01 faucet-resistance proof (`CrankFaucetResistance.t.sol`) — re-attest: self-crank/Sybil round-trip ≤ 0, WWXRP currency==3 zero reward, one-reward-per-item, no pre-RNG-word resolution.

---

## SWP-ECON — coinflip-credit recycle + BURNIE-supply interaction (§1; primary `/economic-analyst`)

### Charge

**Coinflip-credit recycle:** can a player recycle coinflip credit / claimable through the BURNIE flip + the crank bounty to extract positive EV (a perpetual-motion credit loop)? Model the 75bps flat unconditional recycle EV (cross-ref SWP-REMOVE). **BURNIE-supply interaction:** BURNIE is uncapped-mintable for game rewards but the crank bounty is funded from a FINITE pool (transfer, mirror `_awardDegeneretteDgnrs`), NOT `mintForGame`. Disposition whether the subscription/crank emission can inflate BURNIE supply beyond the intended faucet ceiling, or interact with the flip economy to mint-and-recycle.

### Evidence anchors (re-grep vs HEAD before citing)

- `contracts/AfKing.sol` — the bounty-pool funding mechanism (finite-pool transfer, NOT `mintForGame`); the 75bps flat recycle.
- `contracts/BurnieCoin.sol` / `contracts/BurnieCoinflip.sol` — the BURNIE supply + flip-credit economy the recycle would have to round-trip through.
- The 75bps flip-autorebuy KEPT semantics (REW/SUB scope) — flat, unconditional, no deity scaling.

---

## SWP-REMOVE — the REMOVE surface (§1; `/contract-auditor` grep-clean + `/zero-day-hunter` stranding)

### Charge

The v46.0 REMOVE half: legacy AFKing mode + free ETH auto-rebuy DELETED (RM-01..06), the BURNIE flip-autorebuy KEPT @75bps, and the JGAS two-call jackpot ETH split REMOVED. Red-team three stranding/credit hazards.

- **SWP-REMOVE.A — ETH-auto-rebuy strand (RM-02).** Removing the ETH auto-rebuy interception path: do ETH jackpot winnings now ALWAYS credit to `claimable` (no ticket-conversion interception left behind)? Prove no orphaned winning. Grep-clean attestation: the full RM kill-set regex (`afKing|AFKING_|setAutoRebuy|autoRebuyState|AutoRebuyState|_processAutoRebuy|_calcAutoRebuy|settleFlipModeChange|_afKingRecyclingBonus|deactivateAfKingFromCoin|syncAfKingLazyPassFromCoin`), filtered to exclude `contracts/test`+`mocks`+the KEPT canonical keeper `contracts/AfKing.sol`, MUST return ZERO matches; the lone surviving afKing-named symbol is the kept `_hasAnyLazyPass`/`hasAnyLazyPass` (PROTO-01/RM-04 keeper gate).
- **SWP-REMOVE.B — BURNIE 75bps collapse under/over-credit.** The flip-autorebuy collapses to a flat 75bps unconditional credit (no deity/activity scaling). Prove it cannot under- or over-credit (no rounding leak, no scaling residue).
- **SWP-REMOVE.C — JGAS jackpot two-call-split removal (JGAS-01/02).** Removing the two-call ETH-jackpot split: prove the daily ETH jackpot completes in ONE `advanceGame` stage at the 305-winner ceiling (buckets 159/95/50/1) with NO resume stage entered and NOTHING stranded by the dropped `resumeEthPool` carry. Grep-clean attestation: `SPLIT_CALL1|SPLIT_CALL2|resumeEthPool|_resumeDailyEth|STAGE_JACKPOT_ETH_RESUME|call1Bucket`, excluding `contracts/test`+`mocks`, MUST return ZERO. Conservation: `sum(claimable) + whale-pass == paidWei ≤ pool`; no under/over-pay of a bucket at the single-call ceiling.

### Evidence anchors (re-grep vs HEAD before citing)

- `contracts/modules/DegenerusGameJackpotModule.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol` — the single-call daily-ETH path + the 305-winner buckets; the absence of any resume stage.
- The 318-06 `JackpotSingleCallCorrectness` proof + the 318-05 `RngFreezeAndRemovalProofs` (RE-ATTEST, do NOT re-derive).
- The RM-02 deletion footprint per 316-SPEC + the SAFE-04 deterministic-no-VRF-word-credit proof.

---

## SWP-COMPOSE — cross-surface ADD×REMOVE×OPEN-E composition (§1; primary `/zero-day-hunter`)

### Charge

The integrated composition pass: do the ADD surfaces (PROTO/CRANK/REW/SUB + the OPEN-E funding-source routing) and the REMOVE surfaces (RM + JGAS) compose cleanly under adversarial interleaving? Probe for a cross-surface differential: e.g., a subscription crank + a removed-auto-rebuy path + an OPEN-E redirect that together strand or double-credit a winning; a JGAS single-call + a crank reward landing in the same `advanceGame` stage that races a claimable write; an OPEN-E fundingSource redirect that interacts with the two-tier skip-kill + the crank bounty to extract value. The expected outcome is NEGATIVE-VERIFIED — the surfaces are storage-disjoint and the writes are ordered — but the hypothesis MUST be probed concretely, not assumed.

### Evidence anchors (re-grep vs HEAD before citing)

- The 320-02 delta-audit composition attestations (ADD×REMOVE clean, JGAS single-call clean, OPEN-E default-self identical) — cross-ref, do NOT re-derive.
- The 316-SPEC locked add+remove+JGAS footprint (the storage-disjointness + write-ordering the composition rests on).

---

## §4 Dual-gate skeptic-reviewer filter protocol (operationalizing `feedback_skeptic_pass_before_catastrophe.md`)

### Filter location: dual gate

1. **Per-skill self-filter** — Each skill applies the filter to its own `FINDING_CANDIDATE` set BEFORE writing its per-skill MD. Discards documented in a "Skeptic-Filter Self-Discarded" subsection within the MD AND in the `[skeptic-filter]` frontmatter `discarded: []` array.
2. **Orchestrator integration-time re-application** — At integration, the orchestrator re-applies the filter against the aggregated `FINDING_CANDIDATE` set across all 3 skill MDs (the UNION). Integration-time discards are documented inline in `320-01-ADVERSARIAL-LOG.md`'s Skeptic-Filter Discarded table. **This re-application happens BEFORE any AskUserQuestion user-pause.**

### Structural-protection arm: STRICT

A finding is discarded under the structural-protection arm **only** if the code path makes the attack **literally physically unreachable** — e.g.:
- The `:389-390` / `:400-402` `isOperatorApproved` + `revert NotApproved()` gates make a non-approved cross-account `fundingSource` literally revert at `subscribe()`.
- The `onlyAfKing` / `onlyFlipCreditors` modifiers make `burnForKeeper` / `creditFlip` unreachable by any non-keeper caller.
- The `address(this)` self-subscribe identity makes the Vault/sDGNRS exemption un-spoofable by a source-controlled value.
- The type system forbids the input.

**Defense-in-depth alone (ACL gate + downstream secondary check) does NOT pass the strict structural arm** — those findings surface to user-pause.

### 3-condition EV lens

- **(a)** attacker controls the necessary state;
- **(b)** the manipulation produces a measurable economic gain;
- **(c)** the gain exceeds gas cost + opportunity cost + risk cost.

**(a) is the ONLY hard discard condition.** If the attacker does NOT control the necessary state, the filter discards the finding (no exploitable scenario can be constructed). **(b) measurability + (c) gain-vs-cost** are **severity-downgrade** signals — they DOWNGRADE the severity tag (CATASTROPHE → HIGH → MEDIUM → LOW) and document the downgrade rationale. They do NOT discard.

### `[skeptic-filter]` frontmatter shape (per-skill MD MUST include)

```yaml
[skeptic-filter]
discarded:
  - hypothesis-id: "<SWP-NN-sub-id>"
    structural-protection-citation: "<contracts/Foo.sol:LINE>"
    ev-lens-failed-condition: "a"   # always "a" for discards
    note: "<one-line explanation>"
```

Empty array (`discarded: []`) is valid if the skill found no discards (the expected case).

---

## §5 Disposition-table column schema + consensus routing + elevation routing

### Skeptic-Filter Discarded inline table (integration LOG)

| Hypothesis-ID | Source skill | Structural-protection citation (file:line) | EV-lens failed condition | Note |
| ------------- | ------------ | ------------------------------------------ | ------------------------ | ---- |

Populated from (a) the union of all 3 per-skill `[skeptic-filter]` `discarded` arrays AND (b) any additional orchestrator integration-time discards.

### Integrated Disposition table (integration LOG; survivors only)

| Hypothesis-ID | Source skill | Verdict (NEGATIVE-VERIFIED / FINDING_CANDIDATE / SAFE_BY_DESIGN) | Severity tag (CATASTROPHE / HIGH / MEDIUM / LOW / N-A) | (b)+(c) downgrade rationale | Cross-skill consensus state (Tier-1 / Tier-2 / unanimous-NEGATIVE) |
| ------------- | ------------ | --------------------------------------------------------------- | ------------------------------------------------------ | --------------------------- | ------------------------------------------------------------------ |

A separate SAFE_BY_DESIGN informational table MUST include the D-02 OPEN-E BURNIE-funding overload accepted row (with its D-01 operator-approval-trust-boundary rationale) and the SWP-OPENE.4 trust-the-sub temporal-bound accepted row.

### Severity-Downgrade Rationale table (integration LOG)

For every surviving FINDING_CANDIDATE whose severity was downgraded under (b) or (c) arms, document original-vs-downgraded severity + the driving (b)/(c) signal (may be a "no downgrades" attestation).

### Per-skill MD §1 disposition table

Columns: Hypothesis-ID, Verdict, Severity tag, Evidence anchors (file:line + SWP/OPENE/RM/JGAS/OPENE-req IDs), Reasoning summary.

### Two-tier consensus routing (D-302-CONSENSUS-01)

- **Tier-2 (3-of-3 consensus FINDING_CANDIDATE on same hypothesis)** → automatic elevation + RE-PASS per D-284-ADVERSARIAL-RE-PASS-01 (no user-pause for elevation).
- **Tier-1 (any-skill FINDING_CANDIDATE surviving dual-gate filter)** → AskUserQuestion user-pause at integration.
- **unanimous-NEGATIVE** → no elevation; RE-PASS gate fails; proceed to the LOG verdict.

### Elevation-routing protocol (conditional — the RE-PASS envelope)

Any Tier-1 user-approved or Tier-2 auto-elevated `FINDING_CANDIDATE` routes to:

1. **Author `320-FIXREC-AUGMENT.md`** (AGENT-COMMITTED): VIOLATION class; recommended structural close (preferred — eliminates the attack primitive) OR defense-in-depth mitigation (fallback); per-hypothesis evidence anchors (file:line + SWP/OPENE/RM/JGAS IDs + cross-ref to the surviving Disposition row); v46 handoff anchor.
2. **If the close requires a `contracts/*.sol` diff:** batch per `feedback_batch_contract_approval.md` (ONE consolidated diff); present the actual `git diff -- contracts/` to the USER for explicit review per `feedback_manual_review_before_push.md` + `feedback_never_preapprove_contracts.md` (the orchestrator MUST NOT pre-approve for sub-agents); land the diff as a SEPARATE USER-APPROVED commit. This is the sensitive-contract boundary per `feedback_pause_at_contract_phase_boundaries.md`.
3. **If the close requires `test/*.sol` augmentation:** bundle with the FIXREC-augment commit (test/ autonomy within the envelope per `feedback_no_contract_commits.md`).
4. **Trigger RE-PASS per D-284-ADVERSARIAL-RE-PASS-01:** dispatch the 3 skills against (augment diff + affected hypothesis subset ONLY); produce the RE-PASS per-skill MDs; integrate into a `## Second-Pass (RE-PASS) Disposition` section appended to `320-01-ADVERSARIAL-LOG.md`.

Deletion proposals MUST trace original design intent + actor game-theory first (`feedback_design_intent_before_deletion.md`); MUST NOT propose future-extensibility scaffolding (`feedback_frozen_contracts_no_future_proofing.md`).

---

## §6 Boilerplate

### Out-of-scope / in-scope skills

- **D-271-ADVERSARIAL-02 (carry):** `/degen-skeptic` OUT OF SCOPE for Phase 320.
- **D-271-ADVERSARIAL-03 (carry):** `/economic-analyst` IN SCOPE for Phase 320.

### Consensus rule

- **D-302-CONSENSUS-01 (carry):** Two-tier consensus — Tier-1 user-pause + Tier-2 auto-elevate + RE-PASS.

### Invocation / HYBRID-fallback allowance (D-05)

`/contract-auditor` runs FIRST (anchor). `/zero-day-hunter` + `/economic-analyst` PARALLEL_SUBAGENT if the runner has the Task tool, else HYBRID_FALLBACK_SEQUENTIAL. The Phase 320 sweep runs in the main orchestrator context (Task tool present) → PARALLEL_SUBAGENT is the planned mode. Document the chosen mode in each per-skill MD `[invocation]` frontmatter:

```yaml
[invocation]
skill: /<skill>
mode: <SEQUENTIAL_MAIN_CONTEXT | PARALLEL_SUBAGENT | HYBRID_FALLBACK_SEQUENTIAL>
dispatch_timestamp: "<ISO>"
runner: <orchestrator-main-context | task-subagent>
fallback_reason: <null | "...">
charge_anchor: ".planning/phases/320-audit-adversarial-sweep-add-remove-delta-audit-closure-termi/320-ADVERSARIAL-CHARGE.md"
```

### Re-grep mandate (MANDATORY per `feedback_verify_call_graph_against_source.md`)

Every cited `AfKing.sol` / `DegenerusVault.sol` / `StakedDegenerusStonk.sol` / `BurnieCoin.sol` / `BurnieCoinflip.sol` / module file:line MUST be re-grep-verified against HEAD before any disposition claim is written. **Worked example of why this is mandatory:** the CONTEXT and `.planning/REQUIREMENTS.md:98` cite the burnForKeeper sites as `AfKing.sol:396` (subscribe-time) and `:587` (day-31) — **both are STALE.** The LIVE sites are `:438` (subscribe-time SUB-01 pass-or-pay) and `:634` (day-31 auto-extract). The fundingSource resolve short-circuit cited `~:396` is live at `:439`. AfKing.sol is a brand-new keeper whose lines drift between planning and HEAD — treat EVERY anchor in this charge as a STARTING point, not authoritative, and re-grep before citing. "By construction" / "single fn reaches all paths" claims are exactly what gets attacked (the DegenerusGameJackpotModule inline-duplication precedent).

### Mutations policy

- **Zero `contracts/*.sol`** and **zero `test/*.sol`** mutations during the pass EXCEPT via the §5 elevation envelope (the RE-PASS escape hatch).
- Any `contracts/*.sol` diff at elevation lands as a SEPARATE USER-APPROVED commit per `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`.
- Any `test/*.sol` augmentation at elevation bundles with the FIXREC-augment commit per `feedback_no_contract_commits.md`.
- This is an AUDIT-ONLY phase: it READS `contracts/` + git history and WRITES only `.planning/phases/320-*/`.

### Lean verification-formality posture

The bar is rigorous FULL disposition enumeration expecting unanimous-NEGATIVE like v42 P296 / v43 P302 / v44 P307 / v45 P314. Document structural protections as SAFE_BY_DESIGN rather than hunt them exhaustively; accept the OPEN-E operator-approval trust boundary (D-01) and the BURNIE-funding overload (D-02) as design choices rather than escalate them; prove the four D-03 residual structural charges concretely. NOT adversarial over-reach.

### Memory anchors (load-bearing)

- `feedback_skeptic_pass_before_catastrophe.md` — operationalized via §4 (structural-protection arm + 3-condition EV lens BEFORE any user-pause).
- `feedback_verify_call_graph_against_source.md` — every file:line anchor re-grep-verified pre-write; the stale `:396/:587` cites named as the worked example.
- `open-e-operator-approval-trust-boundary.md` — operator-approval IS the trust boundary; BURNIE-funding overload ACCEPTED-BY-DESIGN; `allowBurnieFunding` DROPPED; the four D-03 structural protections still proven; no "tricked into approving" actor.
- `feedback_security_over_gas.md` — security / RNG-non-manipulability is the hard floor.
- `feedback_design_intent_before_deletion.md` — any RE-PASS deletion proposal traces original design intent + actor game-theory first.
- `feedback_frozen_contracts_no_future_proofing.md` — no future-extensibility scaffolding in any RE-PASS close.
- `feedback_no_history_in_comments.md` — artifacts describe what IS.

---

## §7 Required output per skill

Each per-skill MD (`320-ADVERSARIAL-CONTRACT-AUDITOR.md`, `320-ADVERSARIAL-ZERO-DAY-HUNTER.md`, `320-ADVERSARIAL-ECONOMIC-ANALYST.md`) MUST include:

1. **`[invocation]` frontmatter** — mode + dispatch timestamp + runner + (if fallback) reason + `charge_anchor` pointing at this CHARGE.
2. **`[skeptic-filter]` frontmatter** — `discarded: []` array per the per-skill self-filter arm.
3. **§0 Charge-frame re-anchor** — verbatim quote of the skill's charged SWP-NN sub-charges.
4. **§1 Per-hypothesis disposition table** — one row per charged hypothesis; `/contract-auditor` owns SWP-AUTH + the SWP-OPENE four D-03 structural rows + SWP-REMOVE grep-clean + JGAS single-call; `/zero-day-hunter` owns SWP-GRIEF + SWP-SKIP spoofing + SWP-OPENE.3 redirect + SWP-COMPOSE; `/economic-analyst` owns SWP-ECON + SWP-SKIP griefer + SWP-OPENE.4 EV + beyond-charge rows.
5. **§2 Skeptic-Filter Self-Discarded subsection** — table or "no self-discards" attestation.
6. **§3 Cross-skill hand-off notes** — observations anchoring the other skills' hypotheses; keeps coverage divergent.

---

## §8 Reference files (load-bearing)

### Phase 320 anchors
- `.planning/ROADMAP.md` §"Phase 320" — Goal (the verbatim charged-surface list, quoted in §0 above) + 5 success criteria.
- `.planning/phases/320-audit-adversarial-sweep-add-remove-delta-audit-closure-termi/320-CONTEXT.md` — D-01..D-06 verbatim (the OPEN-E disposition framing + the four D-03 residual structural charges).
- `.planning/REQUIREMENTS.md` §OPENE (`:96-99`) — OPENE-01..04 (the funding-source contract being re-attested) + the Traceability table.

### Locked design + prior-phase context
- `.planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md` — the locked v46.0 add+remove+JGAS design (the "intended" reference the dispositions confirm the diff matches).
- `.planning/phases/319.1-impl-open-e-shared-funding-source-burnie-and-eth-pool/319.1-RESEARCH.md` — the fundingSource design substrate (offsets, routing, gate placement).
- `.planning/phases/319.1-.../319.1-VERIFICATION.md` — 13/13 verification (what OPENE-01..04 already prove; RE-ATTEST, do NOT re-derive).

### Contracts under adversarial probe (v46.0 audit-subject HEAD)
- `contracts/AfKing.sol` — the new keeper (SWP-AUTH, SWP-SKIP, SWP-OPENE, SWP-GRIEF, SWP-ECON).
- `contracts/DegenerusVault.sol` + `contracts/StakedDegenerusStonk.sol` — the SUB-09 protocol self-subscribe callers (SWP-SKIP exemption identity).
- `contracts/BurnieCoin.sol` + `contracts/BurnieCoinflip.sol` — the BURNIE supply + flip economy (SWP-AUTH authority, SWP-ECON recycle).
- `contracts/modules/DegenerusGameJackpotModule.sol` + `contracts/modules/DegenerusGameAdvanceModule.sol` — the JGAS split removal + the single-call daily-ETH path (SWP-REMOVE.C).

### Adversarial-sweep precedent (structure mirrored — D-05)
- `.planning/milestones/v45.0-phases/314-sweep-3-skill-adversarial-degenerette-audit-sweep/314-ADVERSARIAL-CHARGE.md` + `314-01-ADVERSARIAL-LOG.md` + the 3 per-skill MDs (the artifact bundle shape; v45 unanimous-NEGATIVE 33 rows / 0 FINDING_CANDIDATE).

### Skill source definitions
- `~/.claude/skills/contract-auditor/SKILL.md` / `~/.claude/skills/zero-day-hunter/SKILL.md` / `~/.claude/skills/economic-analyst/SKILL.md`.

---

*Phase: 320-audit-adversarial-sweep-add-remove-delta-audit-closure-termi / Plan: 01 / Charge document authored 2026-05-24. All cited file:line anchors are STARTING points re-grep-verified against HEAD at authoring; each skill MUST independently re-grep before writing any disposition claim per feedback_verify_call_graph_against_source.md.*
