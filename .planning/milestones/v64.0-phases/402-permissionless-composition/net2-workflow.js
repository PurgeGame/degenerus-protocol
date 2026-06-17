export const meta = {
  name: 'v64-402-permissionless-composition-net2',
  description: 'NET-2 Claude adversarial permissionless-composition + indexer-event review (PERM-01..04) — verify permissionless access/composition, decimator offset-key isolation, redemption RNG gates, and the 3 indexer-parity events over the frozen tree',
  phases: [{ title: 'Verify' }, { title: 'Refute' }, { title: 'Critic' }],
}

const READONLY = `You are reviewing the frozen contracts/ tree (read-only, byte == 402855e1). DO NOT modify, write, or edit ANY file — analysis only. Read source with Read/Grep/Glob. Anchor every claim to file:line in contracts/. Use neutral correctness-review language.`
const PRIORS = `PRIOR CONTEXT (re-verify, don't re-litigate): the decimator DEC-ALIAS terminal-offset fix keyed terminal at lvl+1 (fixed d8778c3e); the REDEMPTION-ZERO-SEED grindable-zero-word was fixed by a burn-side gate BurnsBlockedBeforeDailyRng + local GameTimeLib day calc; the 3 indexer-parity events were added emission-only per reconstruction Task #8 (78eb3dd2, +18 lines/0 logic). Keeper-bounty exploitability uses REAL prevailing gas (5-50+ gwei) + flip-credit illiquidity, NOT the 0.5-gwei AUTO_GAS_PRICE_REF peg.`

const FINDINGS_SCHEMA = { type: 'object', additionalProperties: false, required: ['dimension', 'summary', 'claims', 'leads'], properties: {
  dimension: { type: 'string' }, summary: { type: 'string' },
  claims: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['claim', 'codeRef', 'matches', 'note'], properties: { claim: { type: 'string' }, codeRef: { type: 'string' }, matches: { type: 'string', enum: ['yes', 'no', 'partial', 'cannot-determine'] }, note: { type: 'string' } } } },
  leads: { type: 'array', description: 'any privilege escalation, reentrancy/griefing, offset-key collision, grindable zero-word, or event-emission divergence. Empty array = valid clean result.', items: { type: 'object', additionalProperties: false, required: ['id', 'title', 'severity', 'file', 'line', 'invariantVsCode', 'effect', 'confidence'], properties: { id: { type: 'string' }, title: { type: 'string' }, severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MED', 'LOW', 'INFO'] }, file: { type: 'string' }, line: { type: 'string' }, invariantVsCode: { type: 'string' }, effect: { type: 'string' }, confidence: { type: 'string', enum: ['high', 'medium', 'low'] } } } },
} }
const VERDICT_SCHEMA = { type: 'object', additionalProperties: false, required: ['lead_id', 'isReal', 'severity', 'reasoning', 'refutedBy'], properties: { lead_id: { type: 'string' }, isReal: { type: 'boolean' }, severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MED', 'LOW', 'INFO', 'REFUTED'] }, reasoning: { type: 'string' }, refutedBy: { type: 'string' } } }

const DIMENSIONS = [
  { key: 'PERM-01-access-composition-offsetkey', prompt: `${READONLY}

DIMENSION PERM-01 — permissionless access-correctness + composition-safety + decimator offset-key isolation.
The permissionless decimator + redemption batch-claim entrypoints (4547b387, a6b3e2fd): (1) ACCESS — walk msg.sender vs the player/beneficiary in each entrypoint; confirm a permissionless caller can only advance public state, NEVER act AS another player, redirect a payout, mint to themselves, or claim another's value. (2) COMPOSITION — confirm no cross-call reentrancy / ordering break / griefing that bricks or double-processes another player's pending claim. (3) OFFSET-KEY ISOLATION — the terminal decimator is keyed at decBucketOffsetPacked[lvl+1]; re-derive and confirm a lagged-gameover decimator round can NEVER write the same bucket slot a live regular round reads/writes (the DEC-ALIAS class).
${PRIORS}
Report each entrypoint + the offset-key derivation with file:line; list any escalation, reentrancy/grief, or key collision as a lead.` },
  { key: 'PERM-02-keeper-bounty-faucet', prompt: `${READONLY}

DIMENSION PERM-02 — keeper box-bounty (decimator + redemption batch) is not a farmable faucet.
Compute the bounty reward vs REAL prevailing gas (5-50+ gwei) and account for flip-credit illiquidity (paid as BURNIE flip credit that must survive a ~50/50 flip). Trace the bounty arm → resolve → credit path for the decimator and redemption-batch keeper. Confirm the reward is net-negative-or-neutral at realistic gas and cannot be farmed (no compounding, no self-arming loop).
${PRIORS}
Report each bounty path with file:line + reward-vs-gas; list any faucet as a lead.` },
  { key: 'PERM-03-redemption-rng-gates', prompt: `${READONLY}

DIMENSION PERM-03 — redemption pre-draw RNG gate + mid-day RNG threshold gate hold against a grindable zero-word.
Verify: a redemption burn/claim CANNOT proceed while the relevant VRF word (rngWordForDay(day+1)) is still zero / not-yet-fulfilled — so a caller cannot read a zero word and grind a favorable outcome, nor act in the request→fulfillment window. Find the burn-side gate (BurnsBlockedBeforeDailyRng) + the mid-day RNG threshold gate, trace the day calc (local GameTimeLib), and confirm the gate fires before any RNG-dependent branch. Check the boundary: exactly when does the gate open, and is there any off-by-one that lets a zero-word read slip through?
${PRIORS}
Report each gate with file:line; list any grindable-zero-word path as a lead.` },
  { key: 'PERM-04-indexer-events', prompt: `${READONLY}

DIMENSION PERM-04 — the 3 indexer-parity events are correct + emission-only.
For each of AffiliateEarningsRecorded (reused in claim), MintStreakRecorded (new), AfkingDelivered (new): (1) confirm it emits at the CORRECT site with CORRECT args (the args reconstruct the off-chain state the indexer needs); (2) fires exactly ONCE per logical event — no double-emit, no missing emit, never on a reverting path; (3) is EMISSION-ONLY — adding the emit changed no state, control flow, or value (diff the emit site against the logic). Confirm the event signatures are stable for the indexer.
${PRIORS}
Report each event with file:line; list any wrong-site/args, double/missing emit, or non-emission-only change as a lead.` },
]

phase('Verify')
log(`NET-2 permissionless-composition review: ${DIMENSIONS.length} dimensions, each lead independently refuted`)
const results = await pipeline(DIMENSIONS,
  (d) => agent(d.prompt, { label: `verify:${d.key}`, phase: 'Verify', schema: FINDINGS_SCHEMA }),
  (review, d) => {
    if (!review || !review.leads || review.leads.length === 0) return { review, verdicts: [] }
    return parallel(review.leads.map((lead) => () =>
      agent(`${READONLY}

Independently RE-DERIVE and attempt to REFUTE this candidate. Default to REFUTED unless the escalation/reentrancy/collision/grindable-word/event-divergence genuinely survives end-to-end.

CANDIDATE [${lead.id}] (${lead.severity}): ${lead.title}
Location: ${lead.file}:${lead.line}
Invariant vs code: ${lead.invariantVsCode}
Asserted effect: ${lead.effect}

Skeptic gate before MED+: STRUCTURAL PROTECTION (access modifier / reentrancy guard / gate / key derivation that already neutralizes it?); REAL-GAS lens for bounties; DESIGN-INTENT (documented behavior?). Re-read the frozen source. isReal=true ONLY if it survives. ${PRIORS}`,
        { label: `refute:${lead.id}`, phase: 'Refute', schema: VERDICT_SCHEMA }).then((v) => ({ lead, verdict: v }))
    )).then((verdicts) => ({ review, verdicts: verdicts.filter(Boolean) }))
  })

phase('Critic')
const dimSummaries = results.filter(Boolean).map((r) => `- ${r.review?.dimension}: ${r.review?.summary} (${r.review?.leads?.length || 0} leads, ${r.verdicts.filter((v) => v.verdict?.isReal).length} survived)`).join('\n')
const critic = await agent(`${READONLY}

COMPLETENESS CRITIC for the permissionless-composition + indexer-event review. The 4 dimensions covered:
${dimSummaries}

Surface: permissionless decimator/redemption access+composition, decimator offset-key isolation, redemption RNG gates, the 3 indexer events. Ask: what permissionless/composition surface did the 4 dimensions NOT cover that a C4A warden could submit? Consider: a permissionless call interleaved with advanceGame; the redemption batch claim composed with the carry-escrow; the decimator offset-key under a multi-level gameover lag; an indexer event whose absence-on-a-branch breaks reconstruction; a keeper bounty armed across two entrypoints. Read the code to check any composition you raise. Return ONLY genuinely-uncovered, code-grounded leads (empty array if complete).`, { label: 'completeness-critic', phase: 'Critic', schema: FINDINGS_SCHEMA })
let criticVerdicts = []
if (critic && critic.leads && critic.leads.length > 0) {
  criticVerdicts = (await parallel(critic.leads.map((lead) => () =>
    agent(`${READONLY}

Independently RE-DERIVE and attempt to REFUTE this cross-composition candidate. Default to REFUTED unless it survives all skeptic-gate haircuts.
CANDIDATE [${lead.id}] (${lead.severity}): ${lead.title}
Location: ${lead.file}:${lead.line}
Invariant vs code: ${lead.invariantVsCode}
Effect: ${lead.effect}
${PRIORS}`, { label: `refute:${lead.id}`, phase: 'Refute', schema: VERDICT_SCHEMA }).then((v) => ({ lead, verdict: v }))
  ))).filter(Boolean)
}
return {
  dimensions: results.filter(Boolean).map((r) => ({ dimension: r.review?.dimension, summary: r.review?.summary, claims: r.review?.claims, leads: r.review?.leads, verdicts: r.verdicts.map((v) => ({ id: v.lead.id, title: v.lead.title, isReal: v.verdict?.isReal, severity: v.verdict?.severity, reasoning: v.verdict?.reasoning, refutedBy: v.verdict?.refutedBy })) })),
  critic: { summary: critic?.summary, leads: critic?.leads, verdicts: criticVerdicts.map((v) => ({ id: v.lead.id, title: v.lead.title, isReal: v.verdict?.isReal, severity: v.verdict?.severity, reasoning: v.verdict?.reasoning, refutedBy: v.verdict?.refutedBy })) },
}
