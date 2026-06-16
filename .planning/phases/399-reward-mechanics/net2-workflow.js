export const meta = {
  name: 'v64-399-reward-mechanics-net2',
  description: 'NET-2 Claude adversarial reward-mechanics correctness review (RWD-01..06) — verify the reward overhaul matches the stated design, conserves value, is freeze-safe + one-shot, and has no closed positive-EV loop',
  phases: [
    { title: 'Verify' },
    { title: 'Refute' },
    { title: 'Critic' },
  ],
}

// Frozen subject: contracts/ tree at this checkout (byte == 402855e1). READ-ONLY review.
// Design anchor: .planning/PAPER-REWARD-CHANGES-BRIEF.md (the stated claims) +
//                .planning/LOOTBOX-DEGENERETTE-SPINS-PLAN.md (spin design).
// Verify the code matches the claims; do not re-litigate intent.

const READONLY = `You are reviewing the frozen contracts/ tree (read-only). DO NOT modify, write, or edit ANY file — analysis only. Read the source with Read/Grep/Glob. Anchor every claim to file:line in contracts/. The stated design is in .planning/PAPER-REWARD-CHANGES-BRIEF.md and .planning/LOOTBOX-DEGENERETTE-SPINS-PLAN.md — VERIFY the code matches; do not re-litigate intent. Use neutral correctness-review language.`

const PRIORS = `PRIOR DISPOSITIONS (v63, carried — do NOT re-litigate, but FLAG if the new delta breaks them): the recycle money-pump and the quest streak-pump were REFUTED; survive-before-mint, BURNIE emission conservation, and the day-20 auto-rebuy latch monotonicity were attested; the WWXRP whale-half-pass (P(S=9)≈6.74e-8, one per bracket) is by-design. Flip-credit is illiquid (a BURNIE win must survive a 50/50 survival coinflip to mint); directly-opened boxes carry sub-100% EV; claimable winnings are paid first; there is a 10-ETH per (player,level) lootbox EV cap.`

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['dimension', 'summary', 'claims', 'leads'],
  properties: {
    dimension: { type: 'string' },
    summary: { type: 'string', description: 'one-paragraph verdict for this dimension' },
    claims: {
      type: 'array',
      description: 'each stated-design claim checked against code',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['claim', 'codeRef', 'matches', 'note'],
        properties: {
          claim: { type: 'string' },
          codeRef: { type: 'string', description: 'file:line(s) of the implementing code' },
          matches: { type: 'string', enum: ['yes', 'no', 'partial', 'cannot-determine'] },
          note: { type: 'string', description: 'the derivation / why it matches or diverges' },
        },
      },
    },
    leads: {
      type: 'array',
      description: 'any divergence, value leak, freeze violation, or positive-EV loop. Empty array is a valid clean result.',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'title', 'severity', 'file', 'line', 'claimVsCode', 'effect', 'confidence'],
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MED', 'LOW', 'INFO'] },
          file: { type: 'string' },
          line: { type: 'string' },
          claimVsCode: { type: 'string', description: 'the stated claim vs what the code actually does' },
          effect: { type: 'string', description: 'concrete economic / safety effect' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['lead_id', 'isReal', 'severity', 'reasoning', 'refutedBy'],
  properties: {
    lead_id: { type: 'string' },
    isReal: { type: 'boolean', description: 'true only if it survives refutation as a genuine divergence/leak/loop' },
    severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MED', 'LOW', 'INFO', 'REFUTED'] },
    reasoning: { type: 'string' },
    refutedBy: { type: 'string', description: 'the structural protection / EV-condition that kills it, or empty if it survives' },
  },
}

const DIMENSIONS = [
  {
    key: 'RWD-01-ev-multiplier-split',
    prompt: `${READONLY}

DIMENSION RWD-01 — Lootbox EV-multiplier curve + reward-component split.
Verify against code (DegenerusGameLootboxModule.sol + MintStreakUtils activity-score):
1. EV multiplier: floor 90% at activity score 0, neutral 100% at score 6,000, ceiling 145%, ceiling reached at score 40,000, LINEAR between breakpoints. Find the constants + the interpolation; confirm each breakpoint and the linear formula. Check for off-by-one / wrong-denominator / saturation-clamp errors.
2. Reward split per roll: Tickets 40% · DGNRS 15% · WWXRP spin 15% · BURNIE flat 15% · BURNIE spins ×3 10% · ETH spin 5%. Find the split constants/thresholds (likely cumulative roll bands over an RNG byte). Confirm they SUM to exactly 100% (no gap, no overlap, no double-count of an RNG band) and each band maps to the claimed outcome.
3. Reconstruct the per-category EV and confirm the split is the claimed EV-neutral redistribution (only the EV-multiplier lift changes EV).
${PRIORS}
Report each claim with file:line + matches verdict; list any divergence as a lead.`,
  },
  {
    key: 'RWD-02-degenerette-spins',
    prompt: `${READONLY}

DIMENSION RWD-02 — the 3 Degenerette-spin lootbox outcomes (DegenerusGameDegeneretteModule.sol + LootboxModule call sites).
Verify:
1. WWXRP spin (15%): one WWXRP Degenerette spin staking the 1-WWXRP prize, scored by activity score, with the ROI bonus and the rare jackpot whale-half-pass (S=9). Confirm EV-equal to the flat 1-WWXRP it replaced.
2. BURNIE spins ×3 (10%): the would-be flat BURNIE split across 3 BURNIE spins, the summed payout then double-or-nothings on ONE survival coinflip (EV-neutral) before minting. Confirm: (a) the 3 spins are EV-neutral per category, (b) the survival flip is a true 50/50 double-or-nothing (no edge either way that breaks conservation), (c) mint happens only AFTER the survival gate (survive-before-mint).
3. ETH spin (5%, directly-opened boxes only): one ETH Degenerette spin; the win splits via the standard 3-tier rule into claimable ETH + a recirculated bonus box; recirc is depth 1 with allowEthSpin=false and awards tickets not ETH (no cascade).
FREEZE-SAFETY + ONE-SHOT (critical): for EACH spin, trace the RNG seed back to its commitment point — is the spin outcome NOT player-knowable when the box/bet is committed? Is each resolver one-shot / replay-safe (no re-entrancy or double-resolve)? Is the ETH-spin recirculation bounded (depth 1, no unbounded cascade / gas blowup)?
${PRIORS}
Report each claim with file:line; list any EV asymmetry, freeze violation, double-resolve, or unbounded recirc as a lead.`,
  },
  {
    key: 'RWD-03-ticket-budget-farfuture-variance',
    prompt: `${READONLY}

DIMENSION RWD-03 — ticket-roll budget + far-future distribution + variance tiers (value conservation; DegenerusGameLootboxModule.sol).
Verify the arithmetic in code:
1. Per-ticket-hit budget ×11/9 (~197%) so aggregate ticket ETH value is unchanged despite tickets dropping 55%→45%→40%. Find the ×11/9 factor; confirm it actually multiplies the per-hit budget and the product preserves aggregate value.
2. Far-future: 20% far / 80% near; far rolls 1.5× budget, near 0.875× → 0.8×0.875 + 0.2×1.5 = 1.0 (EV-neutral). Find the 20/80 split + the 1.5×/0.875× weights; confirm the weighted sum is exactly 1.0 (watch integer rounding/truncation: does fixed-point math drift the mean off 1.0?).
3. Variance tiers: probabilities 1/4/20/45/30%, each a symmetric range centered on the old fixed value (3.20–6.00 / 1.60–3.00 / 0.80–1.40 / 0.451–0.851 / 0.300–0.600), overall variance EV ≈0.786×. Confirm each range midpoint == the old fixed value and the probability-weighted midpoint sum ≈0.786. Check the RNG range-draw for bias (off-by-one bounds, modulo bias, asymmetric truncation).
${PRIORS}
Report each with file:line + the actual computed value; list any non-conserving drift (rounding that leaks or over-pays aggregate) as a lead.`,
  },
  {
    key: 'RWD-04-recycle-moneypump',
    prompt: `${READONLY}

DIMENSION RWD-04 — mint recycle bonus + closed positive-EV loop ("money pump") search (LootboxModule recycle + MintModule buy paths + affiliate + carry).
Verify:
1. Recycle bonus: 10% BURNIE flip-credit on recycled (claimable) value; NEW gate = any buy spending ≥3 whole tickets' worth of claimable (the old "spend essentially ALL claimable" drain-detection was removed). Find the gate; confirm it is exactly "≥3 whole tickets' worth of claimable spent" and the bonus is 10% of recycled value in flip-credit (illiquid BURNIE).
2. MONEY PUMP: search for ANY closed loop with net positive EV that a rational actor could repeat — across recycle (10% kicker) + spins/recirc + BURNIE carry + affiliate. For each candidate loop, account rigorously for: flip-credit illiquidity (a BURNIE win must survive a 50/50 flip → ~0.5× realizable, and even then it is peg-valued not market-liquid), sub-100% directly-opened-box EV (floor 90%), claimable-winnings-paid-first, and the 10-ETH per (player,level) EV cap. A loop is only real if EV>0 AFTER all four haircuts.
${PRIORS} The recycle money-pump was REFUTED in v63 — re-examine ONLY whether the relaxed gate (more buys qualify) opens a NEW loop the old gate closed.
Report the gate with file:line; list any candidate loop with the full EV accounting as a lead (mark REFUTED inline if a haircut kills it, but still surface the candidate).`,
  },
  {
    key: 'RWD-05-burnie-emission',
    prompt: `${READONLY}

DIMENSION RWD-05 — BURNIE emission conservation (BurnieCoin.sol + BurnieCoinflip.sol + LootboxModule/DegeneretteModule mint sites).
Verify:
1. Survive-before-mint: BURNIE is minted to a wallet ONLY after the survival coinflip gate (no path mints BURNIE before/around the survival flip).
2. Emission conservation: the coinflip-seeded stake (200k/day × 20d) replaces the old 2M+2M lumps; total emission stays conserved (≈8M staked / ~4M EV vs the removed 4M). Trace every BURNIE _mint / creditFlip site reachable from the reward path; confirm no path can mint more than the seeded/earned budget (no unbacked emission, no double-mint of the same win).
3. Day-20 sDGNRS rebuy latch: monotonic — once armed it only settles, seed wins mint to wallet pre-arming and settle-only post-arming. Confirm the latch cannot be toggled back / re-armed to double-pay.
4. Carry claim (claimCoinflipCarry / claimable carry): confirm a carried win is paid at most once and is backed.
${PRIORS}
Report each with file:line; list any unbacked/double mint, pre-gate mint, or non-monotonic latch as a lead.`,
  },
  {
    key: 'RWD-06-quest-streak-double-channel',
    prompt: `${READONLY}

DIMENSION RWD-06 — quest streak + unified activity score, double-channel + cap (DegenerusQuests.sol + MintStreakUtils.sol + GameAfkingModule.sol).
Verify:
1. Quest streak: halved + UNCAPPED (0.5% per completion), afking-secondary parity, unified into one activity score. Find the per-completion increment + confirm there is no cap on the quest-streak component (this is why the EV ceiling score moved 25,500→40,000).
2. DOUBLE-CHANNEL: can a single player accrue quest-streak / activity-score credit on BOTH the afking channel AND the manual channel for the SAME day/level/completion — i.e. double-counting one action? Trace the afking-secondary path vs the manual path; confirm the same completion is recorded once, not twice.
3. Activity-score composition: the score feeds the lootbox EV multiplier (ceiling 145% at 40,000). With quest-streak uncapped, confirm the OTHER components are still bounded and the total score is computed without overflow/wraparound, and that the 40,000 ceiling is a hard clamp on the multiplier even if score exceeds it.
${PRIORS} The streak-pump was REFUTED in v63 — re-examine ONLY whether the double-channel (afking + manual) or the uncapped quest streak opens a new way to inflate the multiplier beyond intended for a given real activity.
Report each with file:line; list any double-count, missing clamp, or overflow as a lead.`,
  },
]

phase('Verify')
log(`NET-2 reward-mechanics review: ${DIMENSIONS.length} dimensions, each lead independently refuted`)

const results = await pipeline(
  DIMENSIONS,
  // Stage 1: dimension finder
  (d) => agent(d.prompt, { label: `verify:${d.key}`, phase: 'Verify', schema: FINDINGS_SCHEMA }),
  // Stage 2: refute each lead independently (skeptic gate) — runs as soon as this dimension finishes
  (review, d) => {
    if (!review || !review.leads || review.leads.length === 0) return { review, verdicts: [] }
    return parallel(
      review.leads.map((lead) => () =>
        agent(
          `${READONLY}

Independently RE-DERIVE and attempt to REFUTE this candidate finding from the reward-mechanics review. Default to REFUTED unless the divergence/leak/loop genuinely survives.

CANDIDATE [${lead.id}] (${lead.severity}): ${lead.title}
Location: ${lead.file}:${lead.line}
Claim vs code: ${lead.claimVsCode}
Asserted effect: ${lead.effect}

Apply the skeptic gate before confirming anything as MED+:
- STRUCTURAL PROTECTION: is there a require/clamp/one-shot guard/CEI/access check that already neutralizes it? Read the actual code path end-to-end.
- EV LENS (for any economic claim): does it survive ALL of — flip-credit illiquidity (×~0.5 + peg-not-market), sub-100% box EV, claimable-paid-first, the 10-ETH/(player,level) cap?
- DESIGN-INTENT: is this a documented by-design choice in the PAPER brief / spins plan, not a defect?
Re-read the frozen source at the cited lines. Return your verdict: isReal=true ONLY if it survives. ${PRIORS}`,
          { label: `refute:${lead.id}`, phase: 'Refute', schema: VERDICT_SCHEMA }
        ).then((v) => ({ lead, verdict: v }))
      )
    ).then((verdicts) => ({ review, verdicts: verdicts.filter(Boolean) }))
  }
)

// Completeness critic — what surface did the 6 dimensions miss?
phase('Critic')
const dimSummaries = results
  .filter(Boolean)
  .map((r) => `- ${r.review?.dimension}: ${r.review?.summary} (${r.review?.leads?.length || 0} leads, ${r.verdicts.filter((v) => v.verdict?.isReal).length} survived)`)
  .join('\n')

const critic = await agent(
  `${READONLY}

COMPLETENESS CRITIC for the reward-mechanics correctness review. The 6 dimensions covered:
${dimSummaries}

The full reward overhaul surface (PAPER brief): EV-multiplier curve, 6-way reward split, the 3 Degenerette spins (WWXRP/BURNIE×3+survival/ETH+recirc), ×11/9 ticket budget, 20/80 far-future + 1.5×/0.875× weights, variance tiers, recycle 10% bonus, BURNIE emission rework, quest-streak uncap + double-channel.

Ask: what reward-mechanics surface or interaction did the 6 dimensions NOT cover that a C4A warden could submit? Specifically consider CROSS-DIMENSION compositions: e.g. a spin's recirc box feeding the recycle bonus; the activity score feeding both the EV multiplier AND a spin's ROI bonus; far-future budget interacting with the variance tier draw; a BURNIE spin's survival flip interacting with the day-20 rebuy latch; the EV-multiplier applied to spin outcomes vs flat outcomes. Read the code to check any composition you raise. Return ONLY genuinely-uncovered, code-grounded leads (empty array if the coverage is complete).`,
  { label: 'completeness-critic', phase: 'Critic', schema: FINDINGS_SCHEMA }
)

// Refute any critic leads too
let criticVerdicts = []
if (critic && critic.leads && critic.leads.length > 0) {
  criticVerdicts = (await parallel(
    critic.leads.map((lead) => () =>
      agent(
        `${READONLY}

Independently RE-DERIVE and attempt to REFUTE this cross-composition candidate. Default to REFUTED unless it genuinely survives all skeptic-gate haircuts (structural guard, EV lens, design-intent).

CANDIDATE [${lead.id}] (${lead.severity}): ${lead.title}
Location: ${lead.file}:${lead.line}
Claim vs code: ${lead.claimVsCode}
Effect: ${lead.effect}
${PRIORS}`,
        { label: `refute:${lead.id}`, phase: 'Refute', schema: VERDICT_SCHEMA }
      ).then((v) => ({ lead, verdict: v }))
    )
  )).filter(Boolean)
}

return {
  dimensions: results.filter(Boolean).map((r) => ({
    dimension: r.review?.dimension,
    summary: r.review?.summary,
    claims: r.review?.claims,
    leads: r.review?.leads,
    verdicts: r.verdicts.map((v) => ({ id: v.lead.id, title: v.lead.title, isReal: v.verdict?.isReal, severity: v.verdict?.severity, reasoning: v.verdict?.reasoning, refutedBy: v.verdict?.refutedBy })),
  })),
  critic: { summary: critic?.summary, leads: critic?.leads, verdicts: criticVerdicts.map((v) => ({ id: v.lead.id, title: v.lead.title, isReal: v.verdict?.isReal, severity: v.verdict?.severity, reasoning: v.verdict?.reasoning, refutedBy: v.verdict?.refutedBy })) },
}
