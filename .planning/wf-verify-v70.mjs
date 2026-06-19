export const meta = {
  name: 'verify-v70-reshape',
  description: 'Adversarially verify the v70 activity-curve reshape working tree against the locked design (read-only)',
  phases: [
    { title: 'Review', detail: 'one independent verifier per curve / ladder+inverse+delegation / migration-sweep / bounds' },
    { title: 'Completeness', detail: 'critic sweeps for any missed read-site, stale constant, un-migrated consumer, unchecked waypoint' },
    { title: 'Verify findings', detail: 'adversarially confirm every flagged gap is a real defect' },
  ],
}

// Empirical ground truth (build/tests/sizes) passed in from the main loop.
const EMPIRICAL = (args && args.empirical) ? String(args.empirical) : '(empirical results not supplied)';

const PREAMBLE = `
You are an ADVERSARIAL VERIFIER on a real-money smart-contract audit (Degenerus Protocol).
Working dir: /home/zak/Dev/PurgeGame/degenerus-audit

CONTEXT: The v70 "activity-curve reshape" is ALREADY WRITTEN in the working tree, UNCOMMITTED. Your job is to
confirm it is correct against the LOCKED DESIGN — not to re-implement. **DO NOT EDIT ANY FILE.** Read and report only.

AUTHORITATIVE SPEC: .planning/PLAN-ACTIVITY-CURVE-RESHAPE.md (read your relevant section in full) PLUS the exact
numbers embedded in your task below. If the doc and the embedded numbers ever disagree, FLAG it as a finding.

METHOD (be rigorous, assume nothing):
- Run \`git diff -- <file>\` and \`git status\` to see exactly old→new. Read the ACTUAL current function body (line
  numbers in the design doc are PRE-edit and may be stale — locate functions by name, not by line).
- For every curve, COMPUTE the code's result with Solidity integer arithmetic (division TRUNCATES toward zero) at
  each waypoint and compare to the expected value. Verify: endpoint values, monotonic non-decreasing, continuity at
  each knee (segment boundary value from the left == from the right), and any special no-op branch.
- For "byte-identical to the prior MAX/anchor" claims, use \`git diff\` to find the OLD constant/output and confirm
  the new endpoint equals it (the reshape must not change payouts at the extremes — only the ramp shape).
- Prefer concrete evidence (exact code lines, computed numbers, grep output) over assertion.

EMPIRICAL GROUND TRUTH (build + targeted tests + sizes, already run by the orchestrator):
${EMPIRICAL}

Return STRICTLY the structured schema. verdict=MATCHES only if every check passed; MISMATCH if any real defect;
UNCERTAIN if you could not resolve something. Put every concrete check in \`checks\` (with expected vs actual), and
any defect/concern in \`gaps\` with a severity.
`;

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['dimension', 'verdict', 'checks', 'gaps', 'notes'],
  properties: {
    dimension: { type: 'string' },
    verdict: { type: 'string', enum: ['MATCHES', 'MISMATCH', 'UNCERTAIN'] },
    checks: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['what', 'expected', 'actual', 'ok'],
        properties: {
          what: { type: 'string' }, expected: { type: 'string' },
          actual: { type: 'string' }, ok: { type: 'boolean' },
        },
      },
    },
    gaps: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['severity', 'location', 'description', 'suggested_fix'],
        properties: {
          severity: { type: 'string', enum: ['blocker', 'high', 'medium', 'low', 'info'] },
          location: { type: 'string' }, description: { type: 'string' }, suggested_fix: { type: 'string' },
        },
      },
    },
    notes: { type: 'string' },
  },
};

const DIMENSIONS = [
  {
    key: 'mult',
    title: 'value-curve: decimator/terminal multiplier (ActivityCurveLib.decMultBps)',
    body: `DIMENSION: decimator + terminal-dec burn multiplier — \`ActivityCurveLib.decMultBps\` in contracts/libraries/ActivityCurveLib.sol (a NEW untracked file — \`git show :contracts/...\` won't exist; just read it).
Locked spec §2.1: K=235, MIN=10000, vA=17049, vB=17676, MAX=17833, seg-B knee=500, effective cap=30000.
Body must be: s==0 → 10000 (the 1.0x no-op MUST be preserved); s>=30000 → 17833; s<=235 → 10000 + s*7049/235;
s<=500 → 17049 + (s-235)*627/265; else → 17676 + (s-500)*157/29500.
Compute & check these waypoints: decMultBps(0)=10000, (235)=17049, (305)=17214, (500)=17676, (30000)=17833, and
(29999) just below MAX (must be <17833 and monotonic). Check continuity at 235 (left=17049,right=17049) and at
500 (left=17676,right=17676). Confirm 17833 is byte-identical to the OLD pre-reshape decimator-multiplier maximum
(use git diff on FLIP.sol + DegenerusGameDecimatorModule.sol to find the old MAX the multiplier saturated to).
Confirm the s==0 no-op path is still honored downstream (FLIP \`_decEffectiveAmount\` / Decimator short-circuit when
multBps <= BPS_DENOMINATOR). Also confirm BOTH consumer sites (FLIP.sol ~_decimatorBurnMultiplier and
DegenerusGameDecimatorModule.sol recordTerminalDecBurn ~:786) call the SAME lib fn (covered deeper by the 'bucket'
dimension, but note it).`,
  },
  {
    key: 'roi',
    title: 'value-curve: Degenerette ROI (_roiBpsFromScore)',
    body: `DIMENSION: Degenerette ROI — \`_roiBpsFromScore\` in contracts/modules/DegenerusGameDegeneretteModule.sol.
Locked spec §2.2: K=ACTIVITY_SCORE_MAX_POINTS=305, MIN=ROI_MIN_BPS=9000, vA=ROI_VA_BPS=9891, vB=ROI_VB_BPS=9970,
MAX=ROI_MAX_BPS=9990. Body must be: s>=30000 → 9990; s<=305 → 9000 + s*891/305; s<=500 → 9891 + (s-305)*79/195;
else → 9970 + (s-500)*20/29500. Compute & check: roi(0)=9000, (305)=9891, (500)=9970, (30000)=9990; monotonic;
continuity at 305 and 500. CRITICAL SOLVENCY INVARIANT: ROI is STRICTLY < 10000 at every score (MAX=9990) — confirm
no input yields >=10000. Confirm the constants ROI_MIN_BPS=9000 and ROI_MAX_BPS=9990 exist (grep) and that
ROI_VA_BPS=9891 / ROI_VB_BPS=9970. Confirm the old pre-clamp \`if (score > 305) score = 305\` at the ROI entry is
GONE (folded into the s>=30000 branch) — check git diff.`,
  },
  {
    key: 'wwxrp',
    title: 'value-curve: WWXRP high ROI (_wwxrpHighValueRoi)',
    body: `DIMENSION: WWXRP high-value ROI — \`_wwxrpHighValueRoi\` in contracts/modules/DegenerusGameDegeneretteModule.sol.
Locked spec §2.3: K=305, base(MIN)=WWXRP_HIGH_ROI_BASE_BPS=9000, vA=WWXRP_HIGH_ROI_VA_BPS=10791,
vB=WWXRP_HIGH_ROI_VB_BPS=10950, MAX=WWXRP_HIGH_ROI_MAX_BPS=10990. Body must be: s>=30000 → 10990; s<=305 →
9000 + s*1791/305; s<=500 → 10791 + (s-305)*159/195; else → 10950 + (s-500)*40/29500. Compute & check:
wwxrp(0)=9000, (305)=10791, (500)=10950, (30000)=10990; monotonic; continuity at 305 and 500. Confirm the base/max
constants exist and equal 9000/10990. Confirm the old pre-clamp \`if (score > 305) score = 305\` at the WWXRP entry
is GONE — check git diff. Note: this curve legitimately exceeds 10000 (it is a >100% high-roi path, by design) —
do NOT flag that as a solvency break; the <10000 invariant is ONLY for _roiBpsFromScore.`,
  },
  {
    key: 'century',
    title: 'value-curve: century bonus (ActivityCurveLib.centuryBps) + both call sites',
    body: `DIMENSION: century mint/afking bonus — \`ActivityCurveLib.centuryBps\` (lib) consumed by BOTH
contracts/modules/DegenerusGameMintModule.sol (~:1714) AND contracts/modules/GameAfkingModule.sol (~:837).
Locked spec §2.4: K=305, MIN=0, vA=9000(90%), vB=9800(98%), MAX=10000(100%). Body must be: s>=30000 → 10000;
s<=305 → s*9000/305; s<=500 → 9000 + (s-305)*800/195; else → 9800 + (s-500)*200/29500. Compute & check:
centuryBps(0)=0, (305)=9000, (500)=9800, (30000)=10000; monotonic; continuity at 305 and 500.
ANTI-DRIFT (the whole point of the shared helper): confirm BOTH Mint and Afking compute
bonusQty = baseQty * ActivityCurveLib.centuryBps(score) / ActivityCurveLib.CENTURY_MAX_BPS, with NO divergent inline
copy in either file (grep both files for any local century arithmetic). Confirm the independent 20-ETH \`maxBonus\`
cap is KEPT at both sites (Mint ~:1715 / Afking ~:838) — the bonus must still be ETH-capped after the bps math.
Confirm the old per-site pre-clamps (Mint old \`cachedScore>305?305:..\`, Afking old \`score>305\`) are GONE.`,
  },
  {
    key: 'lootbox',
    title: 'value-curve: lootbox EV (_lootboxEvMultiplierFromScore)',
    body: `DIMENSION: lootbox EV multiplier — \`_lootboxEvMultiplierFromScore\` in contracts/storage/DegenerusGameStorage.sol.
Locked spec §2.5: KEEP the 0..60 neutral anchor VERBATIM (9000→10000); reshape governs 60..cap. K=400, MIN=9000,
NEUTRAL=10000@60, vA=13950@400, vB=14390@500, MAX=14500@30000. Body must be: s<=60 → 9000 + s*1000/60;
s>=30000 → 14500; s<=400 → 10000 + (s-60)*3950/340; s<=500 → 13950 + (s-400)*440/100; else →
14390 + (s-500)*110/29500. Compute & check: ev(0)=9000, (60)=10000, (400)=13950, (500)=14390, (30000)=14500;
monotonic; continuity at 60, 400, 500. Confirm vA derives from the FULL (9000,14500) range (139.5% at K=400), NOT
the 10000 anchor (USER decision #4). Confirm the ≤60 branch is byte-identical to the OLD code (git diff: the
0..60 anchor must be unchanged). SOLVENCY: max EV=14500 and the call site must still gate on LOOTBOX_EV_BENEFIT_CAP
(grep where _lootboxEvMultiplierFromScore is consumed; confirm the benefit cap still applies).`,
  },
  {
    key: 'bucket',
    title: 'bucket ladder + exact inverse + floor clamps + single-lib delegation (no drift)',
    body: `DIMENSION (VERIFY-02): the bucket ladder, its EXACT inverse, the per-path floor clamps, and the no-drift
single-lib delegation. Files: contracts/libraries/ActivityCurveLib.sol (decBucket, minScoreForBucket),
contracts/FLIP.sol, contracts/modules/DegenerusGameDecimatorModule.sol.
Locked spec §3/§4. Forward ladder (absolute thresholds, lower bucket = better): 12@0, 11@10, 10@30, 9@55, 8@85,
7@120, 6@180, 5@250, 4@300, 3@500, 2@1000. Inverse minScoreForBucket: 12(or higher)→0, 11→10, 10→30, 9→55,
8→85, 7→120, 6→180, 5→250, 4→300, 3→500, 2(or lower)→1000.
CHECKS:
- Enumerate the 10 threshold constants in decBucket and confirm each equals the table.
- ROUND-TRIP: for every bucket b in 2..12, decBucket(minScoreForBucket(b), 2) must == b; and decBucket(T-1) must
  land one bucket WORSE than decBucket(T) at every threshold T (boundary correctness).
- Floor clamps: FLIP normal path minBucket = (lvl%100==0) ? 2 : 5 (find this in FLIP.sol, unchanged); terminal-dec
  path passes a fixed floor of 2 (DegenerusGameDecimatorModule.sol TERMINAL_DEC_MIN_BUCKET=2). Confirm decBucket
  applies \`if (bucket < minBucket) bucket = minBucket\`.
- ANTI-DRIFT: confirm FLIP.sol and DecimatorModule.sol DELEGATE to ActivityCurveLib (decMultBps/decBucket) and
  that the OLD local bodies (e.g. _decimatorBurnMultiplier, _adjustDecimatorBucket, _terminalDecBucket, and the old
  arithmetic \`reduction = round((12-minBucket)*s/235)\`) are DELETED (git diff) — no duplicated body that could drift.
- Confirm \`minScoreForBucket\` is the inverse used at decimator CLAIM time to seal the lootbox EV score
  (DegenerusGameDecimatorModule.sol ~:689 returns ActivityCurveLib.minScoreForBucket(bucket); trace that it feeds
  _lootboxEvMultiplierFromScore at claim). A wrong inverse would compute claim EV from a wrong score even on a
  fresh deploy.`,
  },
  {
    key: 'migration',
    title: 'pre-clamp removal + full consumer migration sweep + stale-constant removal (the v69 failure class)',
    body: `DIMENSION (VERIFY-03 — the NAMED RISK: the v69 incomplete-migration failure class). Be EXHAUSTIVE.
(1) PRE-CLAMP REMOVAL — confirm via \`git diff\` that ALL of these §1 pre-clamp sites are GONE (the curve fns now
receive the raw, hard-cap-bounded score so the high end is reachable):
  - FLIP.sol: old \`if (bonusPoints > 235) bonusPoints = 235\` (fed BOTH mult + bucket).
  - DegenerusGameDecimatorModule.sol: old terminal-burn \`if (bonusPoints > 235) ... = 235\` AND the terminal-boost
    duplicate (two sites).
  - DegenerusGameDegeneretteModule.sol: old \`if (score > 305) score = 305\` at ROI entry AND at WWXRP entry.
  - DegenerusGameMintModule.sol: old \`_score = cachedScore > 305 ? 305 : cachedScore\`.
  - GameAfkingModule.sol: old afking-century \`if (... > 305) ... = 305\`.
(2) STALE CONSTANT REMOVAL — \`git grep -nE 'ACTIVITY_SCORE_MID_POINTS|ACTIVITY_SCORE_HIGH_POINTS|ROI_MID_BPS|ROI_HIGH_BPS' contracts/\`
  must return ZERO hits (definitions removed AND no residual reference). Also hunt for any now-ORPHANED old per-site
  cap constant (e.g. *_ACTIVITY_CAP_POINTS / DECIMATOR_ACTIVITY_CAP*) that is defined but no longer referenced —
  flag orphans (low/info).
(3) KEPT CONSTANTS — confirm these are STILL present (design §5): every MIN/MAX curve-endpoint constant, BPS_DENOMINATOR=10000,
  the bucket floors (DECIMATOR_MIN_BUCKET_NORMAL=5 / DECIMATOR_MIN_BUCKET_100=2 / TERMINAL_DEC_MIN_BUCKET=2 — or
  equivalent), LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS=60, and ACTIVITY_SCORE_MAX_POINTS=305 (shared K for ROI+WWXRP).
(4) FULL READ-SITE SWEEP — \`git grep -nE 'playerActivityScore|activityScore|cachedScore|bonusPoints'\` across contracts/
  and for EACH read-site that feeds a reward computation, confirm it flows into one of the NEW curve fns
  (decMultBps / decBucket / minScoreForBucket / centuryBps / _roiBpsFromScore / _wwxrpHighValueRoi /
  _lootboxEvMultiplierFromScore) and NOT through any leftover old saturated arithmetic (e.g. \`*100/3\`, \`/235\`,
  \`/305\`, \`/23_500\`, \`/30_500\` divisors, or a stale \`> 235\`/\`> 305\` clamp). The v69 bug was exactly a consumer
  left on the old arithmetic — find any such residual. Note any consumer that is intentionally NOT score-scaled
  (e.g. affiliate taper is OUT OF SCOPE — do not flag it).`,
  },
  {
    key: 'bounds',
    title: 'build + storageless lib + EIP-170 + read-side gas + advanceGame non-implication + solvency caps',
    body: `DIMENSION (VERIFY-04). Use the EMPIRICAL GROUND TRUTH above for build/test/size facts; verify the structural claims in source.
- BUILD: confirm the empirical build is clean (exit 0). If the empirical block shows any error/warning of concern, flag it.
- STORAGELESS LIB: read contracts/libraries/ActivityCurveLib.sol — confirm it declares ONLY \`internal constant\`
  values and \`internal pure\` functions, NO state variables, NO storage. (A pure internal lib inlines into callers
  and has no standalone deployed bytecode.)
- EIP-170: from the empirical sizes, confirm DegenerusGame AND FLIP runtime (deployed) bytecode are < 24576 bytes.
  Report the exact sizes and headroom. If sizes are missing from empirical data, say so (UNCERTAIN).
- READ-SIDE GAS: the new curve fns are straight-line branch ladders — confirm they introduce NO loops and NO new
  SLOADs/storage reads in the hot read paths (decimatorBurn / placeBet / lootbox-open / century). Grep the curve
  bodies for storage access; confirm only memory/constant math.
- advanceGame 16.7M CEILING NOT IMPLICATED: grep the advanceGame call chain (advanceGame / _advance* in
  contracts/) — confirm NONE of decMultBps/decBucket/minScoreForBucket/centuryBps/_roiBpsFromScore/
  _wwxrpHighValueRoi/_lootboxEvMultiplierFromScore is invoked inside the advance loop (the reshape is read-side,
  settled on player actions, not in the per-tick advance). Report what calls each curve.
- SOLVENCY CAPS not widened vs old: ROI strictly <10000 (MAX 9990); lootbox EV <=14500 AND still gated by
  LOOTBOX_EV_BENEFIT_CAP at the consumer; century <=100% (10000 bps) AND still ETH-capped by the 20-ETH maxBonus;
  multiplier <=17833. Confirm each cap value is unchanged from the old code (git diff the named MAX constants).`,
  },
];

// ---- Phase 1: parallel independent review across all dimensions (barrier — the critic needs all reports) ----
phase('Review');
const reports = (await parallel(
  DIMENSIONS.map((d) => () =>
    agent(`${PREAMBLE}\n\n====================\n${d.body}\n\nSet dimension="${d.key}".`, {
      label: `review:${d.key}`,
      phase: 'Review',
      schema: FINDINGS_SCHEMA,
    })
  )
)).filter(Boolean);

// ---- Phase 2: completeness critic (needs the full set of reports) ----
phase('Completeness');
const CRITIC_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['any_uncovered', 'missed_items', 'overall_assessment'],
  properties: {
    any_uncovered: { type: 'boolean' },
    missed_items: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['kind', 'location', 'concern', 'severity'],
        properties: {
          kind: { type: 'string' }, location: { type: 'string' },
          concern: { type: 'string' },
          severity: { type: 'string', enum: ['blocker', 'high', 'medium', 'low', 'info'] },
        },
      },
    },
    overall_assessment: { type: 'string' },
  },
};

const critic = await agent(
  `${PREAMBLE}

====================
ROLE: COMPLETENESS CRITIC. Eight dimension verifiers have reviewed the v70 reshape. Their structured reports:
${JSON.stringify(reports, null, 2)}

Your job: find what they MISSED. Independently sweep for:
- Any activity-score read-site / consumer NOT covered by the 'migration' report (re-run \`git grep\` yourself; the
  v69 failure was a missed consumer — be paranoid).
- Any stale/orphaned constant still defined or referenced that no report flagged.
- Any curve waypoint, monotonicity break, or knee DIScontinuity not actually computed (a report claiming MATCHES
  without showing the integer math at the knees is suspect — spot-check the riskiest one yourself).
- Any "keep verbatim" element (lootbox 0..60 anchor, the s==0 multiplier no-op, the 20-ETH maxBonus cap, the
  LOOTBOX_EV_BENEFIT_CAP gate, the FLIP lvl%100 floor selection) that was silently changed.
- Any event whose emitted VALUE shifts (indexer/off-chain parity, design §7) that is worth noting as INFO.
- Any contradiction BETWEEN the eight reports.
- The TEST oracle question: do the dirty test files (ConsumerPointEquivalence / V69ConsumerMigrationFixes /
  DegeneretteHeroScore) actually assert the NEW curve values (not the old ones), and did the empirical run pass?
List anything real in missed_items with a severity; set any_uncovered=true if you found a genuine coverage hole.`,
  { label: 'completeness-critic', phase: 'Completeness', schema: CRITIC_SCHEMA }
);

// ---- Phase 3: adversarially verify every flagged gap (default-skeptical) ----
phase('Verify findings');
const allGaps = [];
for (const r of reports) {
  for (const g of (r.gaps || [])) {
    if (g.severity === 'info') continue; // info notes don't need adversarial confirmation
    allGaps.push({ source: `review:${r.dimension}`, severity: g.severity, location: g.location, description: g.description, suggested_fix: g.suggested_fix });
  }
}
for (const m of (critic.missed_items || [])) {
  if (m.severity === 'info') continue;
  allGaps.push({ source: 'critic', severity: m.severity, location: m.location, description: m.concern, suggested_fix: '' });
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['is_real_defect', 'reasoning', 'recommended_action'],
  properties: {
    is_real_defect: { type: 'boolean' },
    reasoning: { type: 'string' },
    recommended_action: { type: 'string' },
  },
};

let verifiedGaps = [];
if (allGaps.length > 0) {
  log(`${allGaps.length} non-info gap(s) flagged — adversarially confirming each`);
  verifiedGaps = (await parallel(
    allGaps.map((g) => () =>
      agent(
        `${PREAMBLE}

====================
ROLE: ADVERSARIAL SKEPTIC. A reviewer flagged the following potential defect in the v70 reshape. Default to
is_real_defect=FALSE unless you can PROVE it is real from the actual working-tree code. Re-read the code yourself,
re-derive the numbers, and decide.

FLAGGED BY: ${g.source} (severity ${g.severity})
LOCATION: ${g.location}
CLAIM: ${g.description}
SUGGESTED FIX (if any): ${g.suggested_fix}

If real, give the exact code evidence and the minimal correct fix. If not real (reviewer misread, intended by
design per the locked spec / USER rulings, or already correct), explain why.`,
        { label: `verify:${(g.location || g.source).slice(0, 28)}`, phase: 'Verify findings', schema: VERDICT_SCHEMA }
      ).then((v) => ({ ...g, verdict: v }))
    )
  )).filter(Boolean);
}

const confirmedDefects = verifiedGaps.filter((g) => g.verdict && g.verdict.is_real_defect);

return {
  summary: {
    dimensions_reviewed: reports.length,
    dimension_verdicts: reports.map((r) => ({ dimension: r.dimension, verdict: r.verdict, gap_count: (r.gaps || []).length })),
    critic_any_uncovered: critic.any_uncovered,
    critic_missed_count: (critic.missed_items || []).length,
    gaps_flagged: allGaps.length,
    confirmed_defects: confirmedDefects.length,
  },
  reports,
  critic,
  verifiedGaps,
  confirmedDefects,
};
