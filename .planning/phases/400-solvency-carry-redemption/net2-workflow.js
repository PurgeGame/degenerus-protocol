export const meta = {
  name: 'v64-400-solvency-carry-redemption-net2',
  description: 'NET-2 Claude adversarial solvency/carry/redemption correctness review (SOLV-01..05) — verify the claimablePool identity, carry-escrow + salvage conservation, payable/permissionless redemption CEI, and coinflip windows over the frozen tree',
  phases: [
    { title: 'Verify' },
    { title: 'Refute' },
    { title: 'Critic' },
  ],
}

const READONLY = `You are reviewing the frozen contracts/ tree (read-only, byte == 402855e1). DO NOT modify, write, or edit ANY file — analysis only. Read source with Read/Grep/Glob. Anchor every claim to file:line in contracts/. Use neutral correctness-review language. Solvency is the protocol's SPINE invariant — be rigorous and trace every credit/debit end-to-end.`

const PRIORS = `PRIOR DISPOSITIONS (carried — do NOT re-litigate, but FLAG if the new delta breaks them): SOLVENCY-01 (all free-ETH reservation sites reserve claimablePool inclusive of the keeper total) held through v63; V62-03 sDGNRS redemption reentrancy was FIXED via CEI reorder (53cd25cf yield-surplus class); BURNIE-04 carry-stranding was the one v63 CONFIRMED MED, fixed 98c4f049; the redemption-payable HIGH (every funded claim reverted with funded sDGNRS) was fixed 403afc62. These are RE-VERIFY targets, not open findings. Keeper-bounty exploitability must compare reward to REAL prevailing gas (5-50+ gwei) + flip-credit illiquidity, NOT the 0.5-gwei AUTO_GAS_PRICE_REF peg.`

const FINDINGS_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['dimension', 'summary', 'claims', 'leads'],
  properties: {
    dimension: { type: 'string' },
    summary: { type: 'string' },
    claims: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['claim', 'codeRef', 'matches', 'note'],
        properties: {
          claim: { type: 'string' },
          codeRef: { type: 'string' },
          matches: { type: 'string', enum: ['yes', 'no', 'partial', 'cannot-determine'] },
          note: { type: 'string' },
        },
      },
    },
    leads: {
      type: 'array',
      description: 'any solvency drift, double-pay, strand, CEI/reentrancy gap, unbounded drain, or keeper faucet. Empty array = valid clean result.',
      items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'title', 'severity', 'file', 'line', 'invariantVsCode', 'effect', 'confidence'],
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MED', 'LOW', 'INFO'] },
          file: { type: 'string' },
          line: { type: 'string' },
          invariantVsCode: { type: 'string' },
          effect: { type: 'string' },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['lead_id', 'isReal', 'severity', 'reasoning', 'refutedBy'],
  properties: {
    lead_id: { type: 'string' },
    isReal: { type: 'boolean' },
    severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MED', 'LOW', 'INFO', 'REFUTED'] },
    reasoning: { type: 'string' },
    refutedBy: { type: 'string' },
  },
}

const DIMENSIONS = [
  {
    key: 'SOLV-01-claimablepool-identity',
    prompt: `${READONLY}

DIMENSION SOLV-01 — the claimablePool identity: \`claimablePool == Σ player claimable + Σ player afking\` must hold across EVERY changed credit/debit path.
Trace and re-derive the identity across the changed paths: (1) the sDGNRS salvage-swap legs (ETH/BURNIE pawn-shop payout in MintStreakUtils / salvage path), (2) the dust-drop forfeit self-credit, (3) the payable-delegatecall redemption ETH leg. For EACH credit to a player (claimable or afking), confirm a matching \`claimablePool\` increment; for each debit/payout, confirm a matching decrement. Find any path that credits a player without backing the pool, or pays from the pool without crediting/debiting a player — i.e. a solvency drift. Enumerate the free-ETH reservation sites and confirm each still reserves claimablePool inclusive of the keeper total (SOLVENCY-01).
${PRIORS}
Report each path with file:line + holds/diverges; list any drift as a lead.`,
  },
  {
    key: 'SOLV-02-burnie04-carry-escrow',
    prompt: `${READONLY}

DIMENSION SOLV-02 — the BURNIE-04 carry-escrow fix (98c4f049: submit-time carry escrow, flip-contingent D+1 payout, CoinflipClaimState event), in BurnieCoinflip.sol + StakedDegenerusStonk.sol.
Verify: (1) the escrowed sDGNRS auto-rebuy carry is REMOVED from redemption backing at submit (withdrawRedeemedBurnie); (2) it is paid OR forfeited exactly ONCE at claim, contingent on the D+1 survival flip; (3) it is never double-counted (counted in backing AND paid) or over-credited. Trace withdrawRedeemedBurnie → held → claimable → carry and the slot delete; confirm fail-closed on the day+1 read. Confirm the day+1 win-multiplier (the recent fix 891f7a8f) does not over-emit beyond flip mechanics. Confirm replay-safety (the carry slot cannot be claimed twice).
${PRIORS}
Report each with file:line; list any double-pay, strand, or over-credit as a lead.`,
  },
  {
    key: 'SOLV-03-salvage-carry-vault-fallback',
    prompt: `${READONLY}

DIMENSION SOLV-03 — the salvage carry-symmetric BURNIE sourcing + vault-owner buyer fallback (a8fa3afa).
Verify: (1) the far-future salvage BURNIE leg taps the buyer's auto-rebuy carry (symmetric with redemption — buyer-keyed sDGNRS + vault), value-conserving (no BURNIE minted from nothing, no double-source); (2) the vault-owner salvage-buyer fallback is bounded — gated by a toggle + an ETH floor, ETH sourced from vault claimable + afking with stage reserves via depositAfkingFunding, and CANNOT drain the vault below its obligations or underflow a balance; (3) the salvage swap arithmetic (distance discount, far-future quote) conserves value. Find any unbounded vault drain, negative-balance underflow, or value created/destroyed.
${PRIORS}
Report each with file:line; list any conservation break or unbounded drain as a lead.`,
  },
  {
    key: 'SOLV-04-payable-redemption-cei',
    prompt: `${READONLY}

DIMENSION SOLV-04 — permissionless/live-game redemption + dust forfeit + the payable-delegatecall ETH leg (403afc62, 4547b387, 78b858ed) + stETH-before-ETH CEI.
Verify: (1) every live (funded) redemption claim pays out, and reverts cleanly when unfunded — re-confirm the payable-chain fix (every funded claim used to revert; the 3 payable fns incl. nested boon dispatches preserve the callvalue guards); (2) the stETH-before-ETH CEI ordering holds in _payoutWithStethFallback — no ETH/stETH payout precedes the state update it depends on, so a reentrant advanceGame→yield-surplus / nested-boon path cannot observe stale backing (the V62-03 / 53cd25cf class); (3) the dust-drop forfeit self-credits correctly; (4) no path strands value or double-credits across the gameover drain snapshot. Trace the permissionless redemption entrypoints for access-correctness + composition-safety.
${PRIORS}
Report each with file:line; list any unfunded-revert, CEI gap, strand, or double-credit as a lead.`,
  },
  {
    key: 'SOLV-05-coinflip-window-keeper',
    prompt: `${READONLY}

DIMENSION SOLV-05 — coinflip claim-window changes (first-claim 30→180 days, c78ea3db) + calibrated keeper bounty.
Verify: (1) extending the first-claim window strands no seed/winning value — a claimant at day 180 (or anywhere in the window) is still paid the correct amount; the window boundary has no off-by-one that drops a valid claim; (2) the keeper/bounty calibration is net-negative-or-neutral vs REAL prevailing gas (5-50+ gwei) AND flip-credit illiquidity — arming/resolving the bounty must not pay a keeper more than the call costs (no faucet). Trace the bounty arm → resolve → credit path and compute the reward vs a realistic gas cost.
${PRIORS}
Report each with file:line; list any stranded value or keeper faucet as a lead.`,
  },
]

phase('Verify')
log(`NET-2 solvency/carry/redemption review: ${DIMENSIONS.length} dimensions, each lead independently refuted`)

const results = await pipeline(
  DIMENSIONS,
  (d) => agent(d.prompt, { label: `verify:${d.key}`, phase: 'Verify', schema: FINDINGS_SCHEMA }),
  (review, d) => {
    if (!review || !review.leads || review.leads.length === 0) return { review, verdicts: [] }
    return parallel(
      review.leads.map((lead) => () =>
        agent(
          `${READONLY}

Independently RE-DERIVE and attempt to REFUTE this candidate solvency finding. Default to REFUTED unless the drift/double-pay/strand/CEI-gap/faucet genuinely survives end-to-end tracing.

CANDIDATE [${lead.id}] (${lead.severity}): ${lead.title}
Location: ${lead.file}:${lead.line}
Invariant vs code: ${lead.invariantVsCode}
Asserted effect: ${lead.effect}

Skeptic gate before confirming MED+:
- STRUCTURAL PROTECTION: is there a require/reserve/CEI-ordering/one-shot guard/access check that already neutralizes it? Read the path end-to-end.
- SOLVENCY LENS: re-derive the claimablePool identity on this exact path. Does the credit/debit actually balance?
- REAL-GAS LENS (keeper claims): reward vs 5-50+ gwei + flip illiquidity, not the 0.5-gwei peg.
- DESIGN-INTENT: documented by-design behavior, not a defect?
Re-read the frozen source at the cited lines. isReal=true ONLY if it survives. ${PRIORS}`,
          { label: `refute:${lead.id}`, phase: 'Refute', schema: VERDICT_SCHEMA }
        ).then((v) => ({ lead, verdict: v }))
      )
    ).then((verdicts) => ({ review, verdicts: verdicts.filter(Boolean) }))
  }
)

phase('Critic')
const dimSummaries = results.filter(Boolean)
  .map((r) => `- ${r.review?.dimension}: ${r.review?.summary} (${r.review?.leads?.length || 0} leads, ${r.verdicts.filter((v) => v.verdict?.isReal).length} survived)`)
  .join('\n')

const critic = await agent(
  `${READONLY}

COMPLETENESS CRITIC for the solvency/carry/redemption review. The 5 dimensions covered:
${dimSummaries}

The full surface: claimablePool identity, BURNIE-04 carry-escrow, salvage carry + vault fallback, payable/permissionless redemption + stETH-before-ETH CEI, coinflip window + keeper bounty.
Ask: what solvency-bearing path or CROSS-PATH composition did the 5 dimensions NOT cover that a C4A warden could submit? Consider compositions: a salvage carry interacting with the redemption carry-escrow on the same buyer; the vault-owner fallback ETH leg interacting with the yield-surplus reservation; the dust-forfeit self-credit interacting with the gameover drain snapshot; a reentrant path across two of the changed payable entrypoints; the coinflip window interacting with the day-20 rebuy latch. Read the code to check any composition you raise. Return ONLY genuinely-uncovered, code-grounded leads (empty array if coverage is complete).`,
  { label: 'completeness-critic', phase: 'Critic', schema: FINDINGS_SCHEMA }
)

let criticVerdicts = []
if (critic && critic.leads && critic.leads.length > 0) {
  criticVerdicts = (await parallel(
    critic.leads.map((lead) => () =>
      agent(
        `${READONLY}

Independently RE-DERIVE and attempt to REFUTE this cross-composition solvency candidate. Default to REFUTED unless it survives all skeptic-gate haircuts (structural guard, solvency identity re-derivation, real-gas lens, design-intent).

CANDIDATE [${lead.id}] (${lead.severity}): ${lead.title}
Location: ${lead.file}:${lead.line}
Invariant vs code: ${lead.invariantVsCode}
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
