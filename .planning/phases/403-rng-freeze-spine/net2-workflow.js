export const meta = {
  name: 'v64-403-rng-freeze-spine-net2',
  description: 'NET-2 Claude adversarial RNG-freeze-spine review (RNG-01..03) — backward-trace every new/changed RNG consumer to its commitment point, enumerate in-window SLOADs, and prove one-shot replay-safety over the frozen tree',
  phases: [{ title: 'Verify' }, { title: 'Refute' }, { title: 'Critic' }],
}

const READONLY = `You are reviewing the frozen contracts/ tree (read-only, byte == 402855e1). DO NOT modify, write, or edit ANY file — analysis only. Read source with Read/Grep/Glob. Anchor every claim to file:line in contracts/. Use neutral correctness-review language. RNG-freeze is the protocol's DOMINANT invariant — be maximally rigorous; trace each consumer backward from the VRF word to the player's input-commitment moment.`
const PRIORS = `PRIOR CONTEXT (re-verify, don't re-litigate): the v45 VRF-freeze invariant (every VRF-interacting variable frozen [request->unlock] vs players; advanceGame exempt); the Degenerette box-spin seeds derive purely from the frozen rngWord via hash1/hash2 with no live state (attested phase 399 RWD-02); the REDEMPTION-ZERO-SEED grindable-zero-word was fixed (burn-side gate BurnsBlockedBeforeDailyRng); the box-spin/decimator/redemption resolvers are guarded address(this) != GAME. Re-verify these hold across the repacked slots + the new consumers.`

const FINDINGS_SCHEMA = { type: 'object', additionalProperties: false, required: ['dimension', 'summary', 'claims', 'leads'], properties: {
  dimension: { type: 'string' }, summary: { type: 'string' },
  claims: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['claim', 'codeRef', 'matches', 'note'], properties: { claim: { type: 'string' }, codeRef: { type: 'string' }, matches: { type: 'string', enum: ['yes', 'no', 'partial', 'cannot-determine'] }, note: { type: 'string' } } } },
  leads: { type: 'array', description: 'any RNG-freeze violation (manipulable in-window input/SLOAD), grindable zero/stale word, or double-resolve/replay. Empty array = valid clean result.', items: { type: 'object', additionalProperties: false, required: ['id', 'title', 'severity', 'file', 'line', 'invariantVsCode', 'effect', 'confidence'], properties: { id: { type: 'string' }, title: { type: 'string' }, severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MED', 'LOW', 'INFO'] }, file: { type: 'string' }, line: { type: 'string' }, invariantVsCode: { type: 'string' }, effect: { type: 'string' }, confidence: { type: 'string', enum: ['high', 'medium', 'low'] } } } },
} }
const VERDICT_SCHEMA = { type: 'object', additionalProperties: false, required: ['lead_id', 'isReal', 'severity', 'reasoning', 'refutedBy'], properties: { lead_id: { type: 'string' }, isReal: { type: 'boolean' }, severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MED', 'LOW', 'INFO', 'REFUTED'] }, reasoning: { type: 'string' }, refutedBy: { type: 'string' } } }

const DIMENSIONS = [
  { key: 'RNG-01-backward-trace', prompt: `${READONLY}

DIMENSION RNG-01 — backward-trace each new/changed RNG consumer to its commitment point.
For EACH consumer — the Degenerette box-spin seeds (WWXRP, BURNIE×3+survival, ETH), the decimator claim-seed, the redemption lootbox seed — trace BACKWARD from where the seed is consumed to the moment the player committed the input that the VRF word scores. Walk the request → commit → fulfill → resolve timeline. Confirm the word was UNKNOWN (and unpredictable) when the player's scored input was locked, so the outcome is fixed at VRF fulfillment and cannot be influenced after the word is knowable. For each, state: what the word scores, the latest player-controllable commit moment, and whether it is strictly before the word is knowable.
${PRIORS}
Report each consumer with file:line + frozen/manipulable verdict; list any consumer where a player can influence a scored input after the word is knowable as a lead.` },
  { key: 'RNG-02-inwindow-sloads', prompt: `${READONLY}

DIMENSION RNG-02 — enumerate ALL in-window SLOADs (not just VRF seeds) over the repacked slots.
For each changed RNG consumer, enumerate every storage read consumed inside the rng-window (between VRF request and fulfillment/unlock) — including non-VRF reads: balances, levels, packed flags, activity score, streak, day, pool sizes. For EACH, determine whether a player can mutate that storage value in the request→fulfillment window to bias the scored outcome. A player-controllable non-VRF SLOAD consumed alongside the word is a distinct freeze-violation class. Pay special attention to the repacked slots (v64 packing moved field offsets) — confirm a resolver reads the field it intends and that field is frozen in-window.
${PRIORS}
Report the in-window SLOAD set per consumer with file:line; list any player-mutable in-window read as a lead.` },
  { key: 'RNG-03-oneshot-replay', prompt: `${READONLY}

DIMENSION RNG-03 — one-shot + replay-safe resolvers.
For the box-spin / decimator / redemption resolvers: (1) confirm the seed/claim RECORD is cleared (deleted/zeroed) BEFORE the value/external effect, so a reentrant or repeated call cannot resolve the same seed twice (record-clear-before-resolution); (2) confirm each delegatecall resolver is guarded 'address(this) != GAME reverts', so it is reachable ONLY via the Game's delegatecall and never callable on the deployed module instance directly; (3) check the redemption pre-draw + mid-day RNG gate blocks a consuming action until the relevant word exists (no zero/stale-word grind). Find any double-resolve, missing clear-before-effect, missing guard, or grindable-word path.
${PRIORS}
Report each resolver with file:line + clear-order/guard status; list any double-resolve or missing guard as a lead.` },
]

phase('Verify')
log(`NET-2 RNG-freeze-spine review: ${DIMENSIONS.length} dimensions, each lead independently refuted`)
const results = await pipeline(DIMENSIONS,
  (d) => agent(d.prompt, { label: `verify:${d.key}`, phase: 'Verify', schema: FINDINGS_SCHEMA }),
  (review, d) => {
    if (!review || !review.leads || review.leads.length === 0) return { review, verdicts: [] }
    return parallel(review.leads.map((lead) => () =>
      agent(`${READONLY}

Independently RE-DERIVE and attempt to REFUTE this candidate RNG-freeze finding. Default to REFUTED unless the freeze violation / grindable word / double-resolve genuinely survives a full backward trace.

CANDIDATE [${lead.id}] (${lead.severity}): ${lead.title}
Location: ${lead.file}:${lead.line}
Invariant vs code: ${lead.invariantVsCode}
Asserted effect: ${lead.effect}

Skeptic gate before MED+: (1) re-walk the request→commit→fulfill→resolve timeline — is the scored input ACTUALLY mutable after the word is knowable? (2) is the in-window SLOAD ACTUALLY player-controllable in-window, or frozen by a gate/guard? (3) is the resolver ACTUALLY double-resolvable, or cleared-before-effect + guarded? Re-read the frozen source. isReal=true ONLY if it survives. ${PRIORS}`,
        { label: `refute:${lead.id}`, phase: 'Refute', schema: VERDICT_SCHEMA }).then((v) => ({ lead, verdict: v }))
    )).then((verdicts) => ({ review, verdicts: verdicts.filter(Boolean) }))
  })

phase('Critic')
const dimSummaries = results.filter(Boolean).map((r) => `- ${r.review?.dimension}: ${r.review?.summary} (${r.review?.leads?.length || 0} leads, ${r.verdicts.filter((v) => v.verdict?.isReal).length} survived)`).join('\n')
const critic = await agent(`${READONLY}

COMPLETENESS CRITIC for the RNG-freeze-spine review. The 3 dimensions covered:
${dimSummaries}

Surface: backward-trace of every new/changed RNG consumer, in-window SLOAD enumeration over repacked slots, one-shot/replay/guard. Ask: what RNG-freeze surface did the 3 dimensions NOT cover that a C4A warden could submit? Consider: a consumer that reads an activity score or streak a player can bump in-window (the spins are activity-scored!); a cross-day word reuse; a packed flag whose offset shifted under v64 packing and is now read in-window; a recirc box that re-derives a seed; the survival flip's entropy source; a decimator claim that scores a player-set bucket. Read the code to check any composition you raise. Return ONLY genuinely-uncovered, code-grounded leads (empty array if complete).`, { label: 'completeness-critic', phase: 'Critic', schema: FINDINGS_SCHEMA })
let criticVerdicts = []
if (critic && critic.leads && critic.leads.length > 0) {
  criticVerdicts = (await parallel(critic.leads.map((lead) => () =>
    agent(`${READONLY}

Independently RE-DERIVE and attempt to REFUTE this cross-composition RNG candidate. Default to REFUTED unless it survives a full backward trace + the skeptic-gate haircuts.
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
