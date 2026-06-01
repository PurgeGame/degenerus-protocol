# XMODEL Design Review — Concern C3: Ticket-Mode Primitive Parity

You are an adversarial smart-contract auditor reviewing a **design** (pre-launch, frozen contracts). Your single job: determine whether the v56 ticket-mode minimal-write primitive — which KEEPS the century/x00 quantity bonus at parity while DEFERRING affiliate/quest to the settle — creates any **exploit or resolution mismatch vs the manual ticket-buy leg**.

## The mechanism

Today, an afking **ticket** sub buys via a heavyweight `purchaseWith` delegatecall (`GameAfkingModule.sol:713-731`, ~262k gas), which runs the full per-buy affiliate + quest storm. v56 replaces this with a custom **minimal-write primitive** (a `_queueTicketsScaled`-equivalent) that:
- Writes only the resolution-equivalent placement/trait/quantity (mirroring the lootbox box-stamp) — NO per-buy `payAffiliate` / `handlePurchase` / `creditFlip`.
- Defers affiliate + quest to the once-per-window aggregator settle (same as the lootbox-mode accrual; the accumulator is mode-agnostic).

**Century/x00 parity — KEPT (design decision D-10):** the afking-ticket primitive replicates the `targetLevel % 100 == 0` quantity bonus (`DegenerusGameMintModule.sol:1243-1259`) **before queuing**, so afking-ticket buyers GET the century bonus **at parity** with manual ticket buyers. It does this by:
- REUSING the EXISTING `centuryBonusLevel` (uint24, `DegenerusGameStorage.sol:1563`) + `centuryBonusUsed` (mapping, `:1567`) storage — **NO new slot**.
- REUSING the per-buy activity score already computed for the AFF-02 affiliate taper — **NO extra `_playerActivityScore` call**.
- The bonus is gated by the every-100th-level check (`targetLevel % 100 == 0`), so it fires only on the rare century-level buy; the only real cost (~7–31k, the `centuryBonusUsed[buyer]` zero→nonzero write) lands on that rare buy.

## The asserted invariants (try to break these)

1. **Resolution parity:** the minimal-write primitive must produce a ticket-queue placement/trait/quantity that resolves **identically** to the manual `purchaseWith` ticket leg (modulo the deferred affiliate/quest, which are BURNIE-off-the-ETH-path side effects).
2. **Century-bonus parity (no double-claim, no skip):** the afking primitive reuses the SAME `centuryBonusUsed[buyer]` dedup map the manual leg uses. A century bonus must be claimable **exactly once per buyer** across BOTH the manual and the afking paths — no double-claim by alternating paths, no silent skip.
3. **Deferred-settle equivalence:** moving affiliate/quest to the settle must not change the eventual affiliate/quest credit vs the per-buy storm (modulo the accepted settle-timing/option-A simplifications) — i.e. v56 must not re-introduce the v55 "349.2" regression (where the afking lootbox sub silently dropped quest-credit + affiliate) in a new form for the ticket path.

## Your task

Find any **exploit or mismatch** introduced by (a) keeping the century bonus at parity via the shared `centuryBonusUsed` map, or (b) deferring affiliate/quest to the settle for the ticket path. Consider:
- Can a player **double-claim** the century bonus by interleaving a manual century-level buy and an afking century-level buy (both reading/writing the same `centuryBonusUsed[buyer]`)? Is the dedup atomic across paths?
- Can a player **skip the taper or the affiliate accrual** on the ticket path (since the per-buy storm is gone) and still get the century bonus, gaining an asymmetric advantage vs the manual leg?
- Does the minimal-write primitive's ticket-queue placement diverge from the manual leg in any field that affects RESOLUTION (trait, level, quantity, placement index)?
- Does deferring quest to the settle let a ticket buyer dodge a quest streak penalty or double-credit a quest reward the manual leg would credit once?

## Required structured answer

End your response with EXACTLY this block:

```
VERDICT: [EXPLOITABLE | NOT-EXPLOITABLE | NEEDS-DESIGN-CHANGE]
RATIONALE: <one paragraph>
MISMATCH-OR-EXPLOIT: <the concrete parity break / double-claim / resolution mismatch, OR "none — the primitive resolves identically and shares the century dedup map atomically">
```
