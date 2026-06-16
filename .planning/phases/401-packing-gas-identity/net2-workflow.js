export const meta = {
  name: 'v64-401-packing-gas-identity-net2',
  description: 'NET-2 Claude adversarial storage-packing + gas-identity review (PACK-01..04) — verify narrowing widths, masked RMW + cross-module slot agreement, delegatecall/dispatch behavior-identity, and ABI getter preservation over the frozen tree',
  phases: [
    { title: 'Verify' },
    { title: 'Refute' },
    { title: 'Critic' },
  ],
}

const READONLY = `You are reviewing the frozen contracts/ tree (read-only, byte == 402855e1). DO NOT modify, write, or edit ANY file — analysis only. Read source with Read/Grep/Glob. You MAY run \`forge inspect <Contract> storageLayout\` (read-only) to get the AUTHORITATIVE storage layout — derive bounds against that, not against comments. Anchor every claim to file:line in contracts/. Use neutral correctness-review language.`

const GROUNDING = `DETERMINISTIC CHECK-SCRIPT RESULTS (grounding, already run): check-raw-selectors.sh = PASS (only 2 justified abi.encode sites in DegenerusAdmin); check-interface-coverage.sh = PASS (all typed module interfaces have matching impls); check-delegatecall-alignment.sh = FAIL with one mismatch — GAME_AFKING_MODULE has no IDegenerusGameAfkingModule in IDegenerusGameModules.sol (and the afking module is ALSO absent from the interface-coverage OK list). HYPOTHESIS to verify: the afking module is the raw \`delegatecall(msg.data)\` forwarding target (so it intentionally has NO typed interface, and the alignment checker's universe is stale) — confirm or refute against source.`

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
          claim: { type: 'string' }, codeRef: { type: 'string' },
          matches: { type: 'string', enum: ['yes', 'no', 'partial', 'cannot-determine'] },
          note: { type: 'string' },
        },
      },
    },
    leads: {
      type: 'array',
      description: 'any truncation, co-resident clobber, slot disagreement, dispatch divergence, or interface break. Empty array = valid clean result.',
      items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'title', 'severity', 'file', 'line', 'invariantVsCode', 'effect', 'confidence'],
        properties: {
          id: { type: 'string' }, title: { type: 'string' },
          severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MED', 'LOW', 'INFO'] },
          file: { type: 'string' }, line: { type: 'string' },
          invariantVsCode: { type: 'string' }, effect: { type: 'string' },
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
    lead_id: { type: 'string' }, isReal: { type: 'boolean' },
    severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MED', 'LOW', 'INFO', 'REFUTED'] },
    reasoning: { type: 'string' }, refutedBy: { type: 'string' },
  },
}

const DIMENSIONS = [
  {
    key: 'PACK-01-narrowing-widths',
    prompt: `${READONLY}

DIMENSION PACK-01 — narrowing safety: every narrowed packed field's declared width must be >= its real-world maximum value (no silent truncating cast can lose a high bit).
Run \`forge inspect\` on the changed contracts (DegenerusGame, StakedDegenerusStonk, BurnieCoinflip, DegenerusAdmin) to get the authoritative field widths. For EACH narrowed packed field (the Game 6-slot merge; StakedDegenerusStonk solvency scalars + poolBalances; BurnieCoinflip 8-bit 3-state day-result + lossless-wei stake; DegenerusAdmin vote-record), find the WIDEST writer and the protocol cap, derive the maximum reachable value, and confirm width >= max. Flag any field whose max can exceed its width (a real truncation) or any \`uintN(x)\` narrowing cast that can wrap. Pay special attention to: wei-precision stakes packed into narrow fields (does lossless-wei actually preserve every wei?), the 8-bit 3-state day-result encoding (does it cover all states?), and any value scaled by a level/day/count that grows unboundedly.
Report each field: type width | max value | bound source | width>=max verdict. List any truncation as a lead.`,
  },
  {
    key: 'PACK-02-masked-rmw-slot-agreement',
    prompt: `${READONLY}

DIMENSION PACK-02 — masked read-modify-write + cross-module slot agreement.
(1) For every masked RMW helper (sets one packed field, preserves co-residents), confirm it clears EXACTLY its own bits (correct mask) and preserves every co-resident field — find any setter that writes the full slot or a wrong mask and zeroes a co-resident.
(2) For every packed slot read/written across modules via delegatecall (shared Game storage context), confirm ALL readers and writers use IDENTICAL shift/mask/offset conventions — find any writer/reader pair that disagrees on a field's offset, width, or mask (a silent cross-module corruption). Cross-check the Game struct definitions in storage/DegenerusGameStorage.sol against every module that touches the same slot.
Report each RMW helper + each shared slot with file:line; list any clobber or shift/mask disagreement as a lead.`,
  },
  {
    key: 'PACK-03-dispatch-identity',
    prompt: `${READONLY}
${GROUNDING}

DIMENSION PACK-03 — dispatch + gas hot-path behavior-identity.
(1) The raw \`delegatecall(msg.data)\` dispatch: find it, confirm it resolves the same selector + ABI-decodes identically + bubbles revert + returns the same data as a typed call would. SPECIFICALLY verify the GAME_AFKING_MODULE hypothesis from the grounding: is the afking module dispatched via raw \`delegatecall(msg.data)\` (forwarding the original calldata), so it correctly has no typed interface and the alignment-checker FAIL is checker-universe staleness, NOT a contract defect? Trace the router → afking module path and confirm selector/decode/return/revert identity. If instead the afking module IS supposed to have a typed interface and it's genuinely missing, that's a real lead.
(2) The gas-round hot-path refactors: confirm they change NO externally-observable behavior — same return data, same revert behavior/selector, same emitted events, same selector routing. Spot-check the highest-churn gas refactors.
Report each with file:line; list any dispatch/output/revert/event divergence (or a genuinely-missing interface) as a lead.`,
  },
  {
    key: 'PACK-04-abi-getter-preservation',
    prompt: `${READONLY}

DIMENSION PACK-04 — ABI getter / interface preservation for off-chain consumers (especially the indexer).
For every field that was privatized or packed in the v64 delta, confirm an external ABI getter still exists with the same signature + return shape (or a documented equivalent), so no off-chain consumer breaks. Check the interfaces/ declarations against the implementations. Pay special attention to: getters the indexer consumes (the 3 new indexer-parity events + any view the indexer reads), packed structs that lost a field-level getter, and any return-type narrowing that changes the ABI-decoded value off-chain. Confirm the 3 indexer-parity events (AffiliateEarningsRecorded reuse, MintStreakRecorded, AfkingDelivered) are still emitted with stable signatures.
Report each privatized/packed field + its getter status with file:line; list any removed getter or silently-reshaped return as a lead.`,
  },
]

phase('Verify')
log(`NET-2 packing/gas-identity review: ${DIMENSIONS.length} dimensions, each lead independently refuted`)

const results = await pipeline(
  DIMENSIONS,
  (d) => agent(d.prompt, { label: `verify:${d.key}`, phase: 'Verify', schema: FINDINGS_SCHEMA }),
  (review, d) => {
    if (!review || !review.leads || review.leads.length === 0) return { review, verdicts: [] }
    return parallel(
      review.leads.map((lead) => () =>
        agent(
          `${READONLY}

Independently RE-DERIVE and attempt to REFUTE this candidate packing/gas-identity finding. Default to REFUTED unless the truncation/clobber/disagreement/divergence/interface-break genuinely survives.

CANDIDATE [${lead.id}] (${lead.severity}): ${lead.title}
Location: ${lead.file}:${lead.line}
Invariant vs code: ${lead.invariantVsCode}
Asserted effect: ${lead.effect}

Skeptic gate before confirming MED+:
- For a truncation: re-derive the field's MAX reachable value from the widest writer + the protocol cap; does it actually exceed the width? Use \`forge inspect\` for the authoritative width.
- For a clobber/slot disagreement: read the exact mask/shift in BOTH the writer and reader; do they actually disagree?
- For a dispatch/getter divergence: is the behavior actually externally-observable and different, or a checker-universe / by-design forwarding artifact?
Re-read the frozen source at the cited lines. isReal=true ONLY if it survives.`,
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

COMPLETENESS CRITIC for the storage-packing + gas-identity review. The 4 dimensions covered:
${dimSummaries}

The full surface: narrowing widths (PACK-01), masked RMW + cross-module slot agreement (PACK-02), raw delegatecall(msg.data) + gas hot-path identity (PACK-03), ABI getter preservation (PACK-04).
Ask: what packing/identity surface did the 4 dimensions NOT cover that a C4A warden could submit? Consider: a packed field that is co-resident with a field written by a DIFFERENT module than the one that reads it; a narrowing that is safe today but whose cap was raised in the same delta; an RMW under delegatecall where msg.value or a transient is co-resident; a getter whose return changed only for a gameover/edge state; an event whose indexed topic shape shifted. Read the code to check any composition you raise. Return ONLY genuinely-uncovered, code-grounded leads (empty array if coverage is complete).`,
  { label: 'completeness-critic', phase: 'Critic', schema: FINDINGS_SCHEMA }
)

let criticVerdicts = []
if (critic && critic.leads && critic.leads.length > 0) {
  criticVerdicts = (await parallel(
    critic.leads.map((lead) => () =>
      agent(
        `${READONLY}

Independently RE-DERIVE and attempt to REFUTE this cross-composition packing candidate. Default to REFUTED unless it survives all skeptic-gate haircuts (authoritative width via forge inspect, exact mask/shift comparison, externally-observable behavior, by-design forwarding).

CANDIDATE [${lead.id}] (${lead.severity}): ${lead.title}
Location: ${lead.file}:${lead.line}
Invariant vs code: ${lead.invariantVsCode}
Effect: ${lead.effect}`,
        { label: `refute:${lead.id}`, phase: 'Refute', schema: VERDICT_SCHEMA }
      ).then((v) => ({ lead, verdict: v }))
    )
  )).filter(Boolean)
}

return {
  dimensions: results.filter(Boolean).map((r) => ({
    dimension: r.review?.dimension, summary: r.review?.summary, claims: r.review?.claims, leads: r.review?.leads,
    verdicts: r.verdicts.map((v) => ({ id: v.lead.id, title: v.lead.title, isReal: v.verdict?.isReal, severity: v.verdict?.severity, reasoning: v.verdict?.reasoning, refutedBy: v.verdict?.refutedBy })),
  })),
  critic: { summary: critic?.summary, leads: critic?.leads, verdicts: criticVerdicts.map((v) => ({ id: v.lead.id, title: v.lead.title, isReal: v.verdict?.isReal, severity: v.verdict?.severity, reasoning: v.verdict?.reasoning, refutedBy: v.verdict?.refutedBy })) },
}
