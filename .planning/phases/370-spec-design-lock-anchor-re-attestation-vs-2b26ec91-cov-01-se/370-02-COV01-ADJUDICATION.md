# 370-02 — COV-01 Second-Model `area-solvency` Re-Run + Adjudication (vs frozen `2b26ec91`)

**Requirement:** COV-01 (close the v58.0 `area-solvency` cross-model coverage gap).
**Frozen subject:** `2b26ec91` (`2b26ec91810a733e15666a4c23e8f365a4f04f51`) — the last `contracts/*.sol`
commit at v57.0 closure; the v59.0 baseline. All cites below are `<path>:<line>` per
`git show 2b26ec91:<path>`.
**Posture:** harness + paper only — ZERO `contracts/*.sol` touched. Frozen source read via
`git show 2b26ec91:<path>` / the materialized solvency pack. The external model ran read-only
(Plan Mode), prompt in a FILE.

---

## Task 1 — The run record

### Why this leg exists (the v58 coverage gap)

In v58.0 the `area-solvency` cross-model leg ran TWO models against frozen `2b26ec91`:
- **Codex** ran and produced a real result → it raised **F-03** (BAF whale-pass remainder).
  (See `.planning/audit-v52/runs/v58/xmodel/results/area-solvency.codex.txt`.)
- **Gemini REFUSED** via Plan Mode — it never read the frozen tree. The refusal text
  (`.../v58/.../area-solvency.gemini.txt`) reads: *"I am currently operating in Plan Mode … the
  execution of shell commands (including `git show` and `git grep`) is disabled by system policy
  … Because your instructions explicitly prohibit reading the working tree … I cannot perform the
  audit."* — i.e. `ask-gemini.sh` runs `gemini --approval-mode plan`, Plan Mode disables the
  `git` shell, and the prompt forbade the working tree → a refusal, not a result.

So the v58 spine got Codex + composition + Claude, but **not a second independent model that
actually read frozen source on the solvency identity**. COV-01 closes exactly that gap *before*
the milestone relies on the F-03/F-04 corrections (which fold into the Phase-371 IMPL diff).

### Smoke-test

PONG smoke-test of the council (per LAUNCH.md §0) — **both models answered PONG**
(gemini + codex, 2026-06-04). Recorded in the run manifest
`.planning/audit-v52/runs/v59/xmodel/results/area-solvency.council.json`
(`"smoke_test": "PONG OK (gemini + codex both answered PONG, 2026-06-04)"`).

### Second model + mechanism (and why)

- **Second independent model: Gemini** (`gemini-3-pro-preview`). This is a model OTHER than the
  v58 Codex leg, so it satisfies "a SECOND independent model on the spine" (Codex was the v58
  leg → excluded; `"excluded": ["codex"]` in the manifest).
- **Mechanism: frozen source MATERIALIZED into a context FILE, read in Plan Mode.** Because the
  v58 refusal cause was *Plan Mode cannot run `git`*, the robust fix is to remove the need for a
  `git` shell entirely: every in-scope solvency module at frozen `2b26ec91` was extracted via
  `git show 2b26ec91:<path>` into a single pack
  `.planning/audit-v52/runs/v59/xmodel/context/frozen-solvency-source.txt` (8,125 lines, each
  section headed `### FILE: <path> (frozen 2b26ec91)`, line numbers 1-based per file matching
  `git show` exactly). The v59 prompt (`prompts/area-solvency.v59.txt`) instructs the model to
  read THAT FILE with its file-reading tool and cite `<path>:<line>` from it — no `git` shell, no
  working-tree read. Pack contents: `DegenerusGamePayoutUtils.sol`, `DegenerusGameAdvanceModule.sol`,
  `DegenerusGameDecimatorModule.sol`, `DegenerusGameWhaleModule.sol`, `DegenerusGameJackpotModule.sol`,
  `GameAfkingModule.sol`, the `DegenerusGame.sol` ETH-ledger entrypoints (claimWinnings /
  withdrawAfkingFunding / sellFarFutureTickets / pullRedemptionReserve), and the Degenerette
  `_addClaimableEth`.
- **Prompt in a FILE, never inline** (avoids the repo's contract-commit guard hook). Pacing:
  concurrency 1, read-only/plan mode.

### Result — a genuine frozen-source read (NOT a Plan-Mode refusal)

Raw output persisted at
**`.planning/audit-v52/runs/v59/xmodel/results/area-solvency.gemini.txt`** (non-empty; `.err` empty).
It opens `FROZEN SUBJECT — commit 2b26ec91.` and returns four blocks with concrete
`file:line` cites into the frozen tree — a real read, not a refusal. Manifest:
`.../results/area-solvency.council.json`. The raw output is on disk → the pacing checkpoint is
satisfied (Task 2 adjudication below verifies it against frozen source; nothing is lost if a
usage-cap stop lands here).

**Run artifacts (under `.planning/audit-v52/runs/v59/xmodel/`):**
- `prompts/_preamble.txt`, `prompts/solvency-focus.txt`, `prompts/area-solvency.v59.txt` (self-contained)
- `context/frozen-solvency-source.txt` (the materialized frozen pack)
- `results/area-solvency.gemini.txt` (the raw second-model result), `results/area-solvency.gemini.err` (empty)
- `results/area-solvency.council.json` (the run manifest: model, mechanism, smoke-test, exclusions)

---

## Task 2 — Per-claim adjudication (Claude owns the verdict)

The second model (Gemini) returned **3 concerns + 1 attestation**. Each is parallel-verified
below against the AS-FOUND frozen `2b26ec91` source (read via `git show 2b26ec91:<path>`). Claude
owns every verdict. Dedup baselines: `audit/FINDINGS-v58.0.md` (F-03/F-04 already adjudicated)
and `.../runs/v58/xmodel/results/area-solvency.codex.txt` (the v58 Codex solvency claim).

### Claim 1 — "[High] BAF Whale-Pass Remainder Asset Deficiency"

**Model cite:** `DegenerusGameJackpotModule.sol:1949, 2001` · `DegenerusGamePayoutUtils.sol:58` ·
`DegenerusGameAdvanceModule.sol:902`.
**Claim:** the BAF large-lootbox leg routes `lootboxPortion` to `_queueWhalePassClaimCore`, whose
sub-half-pass `remainder` bumps `claimablePool` inline (PayoutUtils:58) but is NOT in
`runBafJackpot`'s returned `claimableDelta`, so `AdvanceModule:902 memFuture -= claimed` never
debits it from `futurePrizePool` → the same wei is counted in both `claimablePool` (liability) and
`futurePrizePool` (asset) → cumulative solvency leak.

**AS-FOUND frozen code:**
- `DegenerusGamePayoutUtils.sol:51-59` — `_queueWhalePassClaimCore(address winner, uint256 amount)`
  is `internal` with **no return type**; on `remainder != 0` it does
  `claimableWinnings[winner] += remainder;` (`:56`) **and** `claimablePool += uint128(remainder);`
  (`:58`). It returns nothing.
- `DegenerusGameJackpotModule.sol:1949` — `_queueWhalePassClaimCore(winner, lootboxPortion);`
  (large-lootbox branch); `:2001` — `_queueWhalePassClaimCore(winner, amount);` (the
  `_awardJackpotTickets` large-amount branch). Neither folds a return into `claimableDelta`.
- `runBafJackpot` (`JackpotModule.sol:1901`) accumulates `claimableDelta` ONLY from
  `_addClaimableEth(...)` (the ETH-leg, e.g. `:1932`, `:1960`) — the trailing comment
  (`~:1976-1977`) states *"lootbox + whale pass ETH stays in futurePool implicitly: caller only
  deducts claimableDelta from memFuture."*
- `DegenerusGameAdvanceModule.sol:902` — `memFuture -= claimed;` (`:903` `claimableDelta += claimed`)
  where `claimed` = `runBafJackpot`'s return → ETH-leg only, NOT the remainder.

**Claude verdict: CONFIRMED — corroborates v58 F-03.** The frozen code matches the claim exactly.
`_addClaimableEth` is the correct return-and-fold pattern (credits `claimableWinnings`, returns
the delta, caller debits `memFuture`); `_queueWhalePassClaimCore` is the broken pattern (bumps
`claimablePool` inline, returns nothing) → its `remainder` is invisible to `memFuture -= claimed`
→ `claimablePool` grows without a matching `futurePrizePool` debit → the same ETH is double-counted.
This is **F-03** from `audit/FINDINGS-v58.0.md` (v58 council: MEDIUM; the v58 Codex solvency leg
also rated it HIGH; Gemini here independently rates it High). Severity divergence (High vs the v58
MEDIUM settlement) is noted but immaterial — the v58 council MEDIUM stands (sub-2.25-ETH dust per
event, cumulative, pre-launch no live funds). Independent corroboration: two adversarial Claude
agents tasked to REFUTE F-03 against frozen `2b26ec91` both came back REAL / could-not-refute.

**Disposition: ALREADY IN SCOPE — corroborates F-03.** No new IMPL work. Strengthens the close.
The fix is already locked in `370-01-SPEC.md` Section 2 as **SOLV-01 variant (a)**: make
`_queueWhalePassClaimCore` return `remainder` and drop the inline `claimablePool += remainder` at
PayoutUtils:58, then fold the returned remainder into `claimableDelta` at both BAF caller sites
(`JackpotModule.sol:1949` and `:2001`) so `memFuture -= claimed` debits it. Routed to Phase-371.

### Claim 2 — "[High] Decimator Lootbox Remainder Missing Liability"

**Model cite:** `DegenerusGameDecimatorModule.sol:596` · `:390` (the debit; the exact frozen line
is `:398`).
**Claim:** `_creditDecJackpotClaimCore` debits the FULL `lootboxPortion` from `claimablePool`;
if the payout triggers whale passes, `_awardDecimatorLootbox` credits the dust `remainder` back to
the player via `_creditClaimable` (`:596`) — which updates `claimableWinnings` only and does NOT
re-increment `claimablePool`. Net: `Σ claimableWinnings > claimablePool` → the identity
`claimablePool == Σ claimableWinnings + Σ afkingFunding` breaks (under-reports liability).

**AS-FOUND frozen code:**
- `DegenerusGameDecimatorModule.sol:398` — `claimablePool -= uint128(lootboxPortion);` (the FULL
  lootbox portion removed from the aggregate, inside `_creditDecJackpotClaimCore`).
- `DegenerusGameDecimatorModule.sol:580-596` — `_awardDecimatorLootbox(...)`: for
  `amount > LOOTBOX_CLAIM_THRESHOLD` it awards `fullHalfPasses` via `_queueTicketRange` and, on
  `remainder != 0`, calls `_creditClaimable(winner, remainder);` (`:596`).
- `DegenerusGamePayoutUtils.sol:21-28` — `_creditClaimable(address, uint256)` does ONLY
  `claimableWinnings[beneficiary] += weiAmount;` (`:25`) + an event. It does **not** touch
  `claimablePool`.

**Claude verdict: CONFIRMED — corroborates v58 F-04.** The frozen code matches exactly: the full
`lootboxPortion` is debited from `claimablePool` (`:398`), then the `remainder` is added back to
`Σ claimableWinnings` (`:596` → `_creditClaimable`) WITHOUT re-crediting `claimablePool`. The
correct paired analogue is `_queueWhalePassClaimCore` at PayoutUtils:58 (`claimablePool +=
uint128(remainder)`), which the decimator path is missing. Result: `Σ claimableWinnings` exceeds
`claimablePool` by `remainder` → the identity is broken in the under-report direction; the tail
claimant(s) summing past `claimablePool` revert on the checked `claimablePool -=` debit. This is
**F-04** from `audit/FINDINGS-v58.0.md` (v58: MEDIUM; surfaced by the v58 Codex composition leg).
Independent corroboration: two adversarial Claude agents tasked to REFUTE F-04 against frozen
`2b26ec91` both came back REAL / could-not-refute.

**Disposition: ALREADY IN SCOPE — corroborates F-04.** No new IMPL work. The fix is locked in
`370-01-SPEC.md` Section 2 as **SOLV-02 (F-04, no variant — confirm-only)**: add
`claimablePool += uint128(remainder);` alongside `_creditClaimable(winner, remainder)` at
`DecimatorModule.sol:596`. Routed to Phase-371.

### Claim 3 — "[Medium] Yield Over-distribution via Under-reported Liability"

**Model cite:** `DegenerusGameJackpotModule.sol:718, 693` (the actual frozen anchors:
`:693` `claimablePool +` inside `obligations`, `:707` `yieldPool = totalBal - obligations`,
`:715` `claimablePool += uint128(claimableDelta)`).
**Claim:** `distributeYieldSurplus` computes `obligations` INCLUDING `claimablePool` (`:693`), then
distributes `totalBal - obligations` as yield. Because the F-04 decimator omission makes
`claimablePool` UNDER-report the true liability, `obligations` is understated → `yieldPool`
overstated → it mints NEW claimable liability (`:715`) not backed by real stETH appreciation,
compounding the solvency error.

**AS-FOUND frozen code:**
- `DegenerusGameJackpotModule.sol:691-695` — `obligations = _getCurrentPrizePool() +
  _getNextPrizePool() + claimablePool + _getFuturePrizePool() + yieldAccumulator;` (plus the
  pending-buffer add at `:703`).
- `:705` `if (totalBal <= obligations) return;` · `:707` `yieldPool = totalBal - obligations;` ·
  `:709-715` distributes `23%` shares via `_addClaimableEth` and `claimablePool += claimableDelta`.

**Claude verdict: CONFIRMED — but DOWNSTREAM of F-04, not an independent new finding.** The
mechanism is real and correctly reasoned: `distributeYieldSurplus` reads `claimablePool` as the
liability anchor, so any F-04 under-report of `claimablePool` propagates into an over-estimate of
`yieldPool` and an over-distribution. HOWEVER this is a *consequence* of the F-04 break, not a
separate defect in `distributeYieldSurplus` itself — the obligations math at `:691-703` is correct
(it even adds the pending freeze-buffer at `:703` to avoid double-reading frozen-window revenue).
Once F-04 restores the `claimablePool == Σ claimableWinnings + Σ afkingFunding` identity (the
SOLV-02 fix already in scope), `claimablePool` reports the true liability and this over-distribution
vanishes with no separate change. Note the F-03 leak inflates `claimablePool` (the opposite
direction), so the two partially offset in aggregate — but neither is acceptable individually.

**Disposition: ALREADY IN SCOPE — downstream consequence of F-04, resolved by the SOLV-02 fix.**
No separate IMPL work and no `distributeYieldSurplus` change. Recorded so the TERMINAL can note
that the F-04 fix also closes the yield-surplus over-distribution it feeds.

### Attestation — "NO CONCERNS: sDGNRS Salvage Relabel & Redemption"

**Model cite:** `DegenerusGame.sol:2061` · `DegenerusGameMintModule.sol:1026`.
**Claim:** the sDGNRS salvage relabel debits `claimableWinnings[SDGNRS]` and credits
`claimableWinnings[player]` with `claimablePool` unchanged (identity-preserving); and
`pullRedemptionReserve` debits `claimablePool` in tandem when moving at-risk ETH to sDGNRS.

**AS-FOUND frozen code:**
- `DegenerusGameMintModule.sol:1026-1027` — `claimableWinnings[ContractAddresses.SDGNRS] -=
  ethRelabel; claimableWinnings[player] += ethRelabel;` — a tandem relabel, `claimablePool`
  UNCHANGED (the BURNIE leg is a `creditFlip`, not ETH). Solvency-identity-preserving.
- `DegenerusGame.sol:2057-2061` — `pullRedemptionReserve` debits both
  `claimableWinnings[ContractAddresses.SDGNRS] -= amount;` (`:2060`) AND
  `claimablePool -= uint128(amount);` (`:2061`) in tandem. Identity-preserving.

**Claude verdict: CONFIRMED CORRECT (attestation upheld).** Both paths preserve the solvency
identity exactly as the model states. (For the record: the separate v58 **F-01 CRITICAL** is an
ENTRIES-quantity truncation in `sellFarFutureTickets` — `uint32(quantity)*4` debit vs full-uint256
quote — NOT a `claimablePool`/`claimableWinnings` identity break, so it correctly does not surface
under this solvency-identity-scoped area. F-01 is tracked separately and folds into Phase-371.)

---

## Disposition summary

| # | Model concern | Severity (model / v58) | Claude verdict | Disposition |
|---|---------------|------------------------|----------------|-------------|
| 1 | BAF whale-pass remainder | High / MEDIUM (F-03) | CONFIRMED | ALREADY IN SCOPE — corroborates F-03 (SOLV-01 variant (a) → Phase-371) |
| 2 | Decimator whale-pass remainder | High / MEDIUM (F-04) | CONFIRMED | ALREADY IN SCOPE — corroborates F-04 (SOLV-02 confirm-only → Phase-371) |
| 3 | Yield over-distribution | Medium / — | CONFIRMED (downstream of F-04) | ALREADY IN SCOPE — resolved by the SOLV-02 fix; no separate change |
| — | Salvage relabel + redemption | NO CONCERNS | CONFIRMED CORRECT | Attestation upheld — both paths identity-preserving |

- **Total claims:** 3 concerns + 1 attestation.
- **CONFIRMED-new (routed to 371 as NEW IMPL work):** 0.
- **CONFIRMED-known (corroborations of in-scope F-03/F-04):** 2 (claims 1 & 2); claim 3 is a
  confirmed downstream consequence of F-04 (no separate work).
- **REFUTED:** 0.
- **Attestations upheld:** 1 (salvage relabel + redemption).

**Net new solvency findings for IMPL: K = 0.** No claim required absorbing into the 370-01
design-lock edit order — the only solvency-identity breaks the second model found are exactly the
already-locked F-03 (SOLV-01 variant (a)) and F-04 (SOLV-02 confirm-only); claim 3 is closed by the
F-04 fix; the salvage/redemption attestation is upheld. **No cross-dependency on 370-01 beyond the
already-mapped SOLV-01/SOLV-02 edits** (because K = 0, the 370-01 edit order absorbs nothing new).

### Verdict line

**COV-01 area-solvency coverage gap CLOSED** — a second independent model (Gemini, NOT the v58
Codex leg) genuinely read frozen `2b26ec91` (via the materialized solvency pack, defeating the v58
Gemini Plan-Mode refusal) and independently re-produced exactly the in-scope F-03 and F-04
solvency-identity breaks, plus a confirmed downstream yield-over-distribution consequence of F-04,
and upheld the salvage-relabel / redemption attestation. **Net new solvency findings for IMPL = 0.**
The F-03/F-04 corrections the milestone relies on are now backed by an independent second-model read
on the spine.

### TERMINAL carry-forward note (for 374 `audit/FINDINGS-v59.0.md`, AUDIT-01)

> **COV-01 — second-model `area-solvency` re-run (closes the v58.0 coverage gap).** The v58.0
> Gemini solvency leg refused via Plan Mode (never read frozen source). At v59.0 SPEC the
> `area-solvency` leg was re-run against frozen `2b26ec91` with a SECOND independent model
> (Gemini `gemini-3-pro-preview`, distinct from the v58 Codex leg) by materializing the in-scope
> frozen solvency modules into a context FILE the model reads in Plan Mode — a genuine frozen-source
> read. The model independently re-produced the two in-scope solvency-identity breaks **F-03**
> (BAF whale-pass remainder, `PayoutUtils:58` `claimablePool +=` not folded into the BAF
> `memFuture -= claimed` debit at `AdvanceModule:902`) and **F-04** (decimator whale-pass remainder,
> `_creditClaimable(winner, remainder)` at `DecimatorModule:596` with no paired `claimablePool +=`
> after the full-portion debit at `:398`), plus a confirmed downstream consequence (the F-04
> under-report inflates `distributeYieldSurplus`'s distributable yield), and upheld the
> salvage-relabel / `pullRedemptionReserve` identity-preservation attestation. **Zero net-new
> solvency findings** — all CONFIRMED concerns are corroborations of the already-in-scope
> F-03/F-04 fixes (SOLV-01 variant (a) + SOLV-02), which fold into the Phase-371 IMPL diff. Raw run:
> `.planning/audit-v52/runs/v59/xmodel/results/area-solvency.gemini.txt`; adjudication:
> `370-02-COV01-ADJUDICATION.md`. The v58 area-solvency coverage gap is CLOSED.
