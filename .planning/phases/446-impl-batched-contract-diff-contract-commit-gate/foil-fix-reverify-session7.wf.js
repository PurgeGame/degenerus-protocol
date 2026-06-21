export const meta = {
  name: 'foil-fix-reverify-session7',
  description: 'Re-verify the foil last-jackpot-day level reroute + liveness gate fix across all phase boundaries',
  phases: [
    { title: 'Review', detail: 'independent derivation of the boundary table + gate review' },
    { title: 'Verify', detail: 'adversarial refutation of any flagged residual' },
  ],
}

const REPO = '/home/zak/Dev/PurgeGame/degenerus-audit'

const CONTEXT = `
Working dir: ${REPO}. Solidity 0.8.34, via-IR, delegatecall facade/module architecture.

A fix was just applied to contracts/modules/DegenerusGameFoilPackModule.sol (buyFoilPack + _payFoilTier).
The foil pack is a 10x-priced SKU that bets on a future daily jackpot draw. At buy it freezes a record
foilRecord[lvl][buyer] = resolveDay|multBps|activityScore and pushes foilBuyers[resolveDay] = (lvl<<160|buyer).
A drain files 16 boosted trait entries (derived from rngWordByDay[resolveDay]) into traitBurnTicket[lvl], which
the level-lvl jackpot samples. The CLAIM (claimFoilMatch) reads L from dailyFoilDraw[day].level, looks up
foilRecord[L][player], requires day >= resolveDay, re-derives the line from rngWordByDay[resolveDay], compares to
dailyFoilDraw[day]'s sealed sets, and pays a 40/40/20 box-spin.

LEVEL MODEL (verify against code, do not assume):
- _activeTicketLevel() = jackpotPhaseFlag ? level : level + 1   (DegenerusGameMintStreakUtils.sol:139)
- the storage var "level" is written ONLY at the last-purchase-day RNG request (_finalizeRngRequest, AdvanceModule ~1753: level = purchaseLevel = old+1).
- Purchase-phase daily seals dailyFoilDraw at purchaseLevel (= level+1 normally) (AdvanceModule:499 -> JackpotModule payDailyJackpot(false,purchaseLevel) -> _emitDailyWinningTraits ... dailyFoilDraw[questDay]=_packFoilDraw(...,lvl)).
- Jackpot-phase daily seals at level (AdvanceModule:579 payDailyJackpot(true, level)).
- The purchase->jackpot transition is SAME wall day (the last purchase day's transition + day-1 jackpot run on the same wall day; "Do not unlock here" comment ~557). resolveDay rule (FoilPackModule): resolveDay = (!rngLockedFlag && dailyIdx < day) ? day : day+1.
- Multi-day-stall buy guard: if (_simulatedDayIndex() > dailyIdx + 1) revert.

THE FIX (just applied, in buyFoilPack):
  uint24 lvl = _activeTicketLevel();
  if (jackpotPhaseFlag && rngLockedFlag) {
    uint8 cnt = jackpotCounter; uint8 comp = compressedJackpotFlag;
    uint8 step = comp == 2 ? JACKPOT_LEVEL_CAP : (comp == 1 && cnt != 0 && cnt < JACKPOT_LEVEL_CAP - 1 ? 2 : 1);
    if (cnt + step >= JACKPOT_LEVEL_CAP) lvl = level + 1;   // final jackpot day -> next cycle
  }
This mirrors the mint module's stranded-ticket reroute (_callTicketPurchase, DegenerusGameMintModule.sol:1896-1903).
Also added at buyFoilPack top: if (gameOver) revert E(); if (_livenessTriggered()) revert E();
And changed require(rw != 0) -> if (rw == 0) revert E() in _payFoilTier.

PRIOR DEFECT being closed (FOIL-XLVL-01 / FOIL-LVL-BOUNDARY-01, SAME bug): a pack bought on the FINAL jackpot
day after the daily RNG request keyed at _activeTicketLevel()=level, but resolveDay=day+1 is the next cycle's
first day (sealed at level+1), and no level-draw >= day+1 remains -> permanently unclaimable. The reroute keys it
at level+1 to match.

USER BAR: blocking outcomes are ONLY (1) a BRICK (reachable permanent revert/wedge of advanceGame, a foil buy that
can never succeed, or a claim path that bricks) or (2) a HORRIBLE ADVANTAGE (address-grinding a winning line,
steering the resolving word, double-pay, value drain). A self-inflicted narrow-window value-leak that cannot brick
and confers no advantage is below the bar.
`

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['dimension', 'fix_correct', 'findings'],
  properties: {
    dimension: { type: 'string' },
    fix_correct: { type: 'boolean', description: 'true iff the fix is correct for this dimension and introduces no new defect' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'title', 'severity', 'kind', 'anchor', 'explanation', 'repro'],
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          severity: { type: 'string', enum: ['CATASTROPHE', 'HIGH', 'MEDIUM', 'LOW', 'INFO'] },
          kind: { type: 'string', enum: ['brick', 'advantage', 'correctness', 'value-leak', 'regression', 'other'] },
          anchor: { type: 'string' },
          explanation: { type: 'string' },
          repro: { type: 'string' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['finding_id', 'refuted', 'is_real_blocking_defect', 'defect_class', 'confidence', 'reasoning'],
  properties: {
    finding_id: { type: 'string' },
    refuted: { type: 'boolean' },
    is_real_blocking_defect: { type: 'boolean' },
    defect_class: { type: 'string', enum: ['brick', 'advantage', 'correctness', 'value-leak', 'regression', 'none'] },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    reasoning: { type: 'string' },
  },
}

const DIMENSIONS = [
  {
    key: 'boundary-table',
    title: 'level-keying reroute: full boundary table consistency',
    focus: `Build the authoritative table of EVERY reachable foil-buy state and verify the post-fix keyed level
(lvl) equals dailyFoilDraw[resolveDay].level (the level the claim reads back) — i.e. the pack is always claimable.
Enumerate at least: (a) mid purchase phase, pre-RNG-request (slip-into-today, resolveDay=day); (b) mid purchase
phase, post-request (resolveDay=day+1); (c) LAST purchase day pre-request; (d) LAST purchase day post-request
(level already pre-incremented, jackpotPhaseFlag still false); (e) mid jackpot phase, non-final day, pre/post
request; (f) FINAL jackpot day, pre-request; (g) FINAL jackpot day, post-request (THE fixed case) — normal,
compressed (compressedJackpotFlag==1, the nextStep=2 middle days), and TURBO (compressedJackpotFlag==2, single
physical day, cnt==0 but step==CAP). For EACH: state the values of jackpotPhaseFlag/rngLockedFlag/level/
jackpotCounter, the resolveDay, the level dailyFoilDraw[resolveDay] will actually seal at, the post-fix keyed lvl,
and whether they MATCH. Flag any state where keyed lvl != seal level (a dead/mis-keyed pack), OR where the reroute
fires when it should NOT (over-routing a pack that was already correct), OR where it fails to fire when it should.
Confirm the previously-broken final-jackpot-day case is now consistent. Confirm turbo (cnt==0,step==CAP -> fires)
and compressed step logic match the JackpotModule's actual counter progression.`,
  },
  {
    key: 'fix-side-effects',
    title: 'reroute side-effects: cap, drain, claim, queue coherence',
    focus: `With the reroute changing lvl on the final jackpot day, verify every downstream use of lvl in buyFoilPack
stays coherent: the one-per-cycle cap _foilBoughtThisLevel(buyer, lvl) now keys at level+1 (confirm a buyer can
still buy exactly one pack per cycle, no accidental double-block or double-allow across the transition); the
foilRecord write, the foilBuyers[resolveDay] push carrying (lvl<<160|buyer), the priceWei = priceForLevel(lvl)
used for cost AND the affiliate basis AND the quest, and the boost. Then verify the DRAIN (_resolveFoilBuyer reads
lvl from the packed bucket entry, _foilMultFor(buyer,lvl), files into traitBurnTicket[lvl]) and the CLAIM
(re-derives via _deriveFoilLines with the same lvl) remain identical to each other (the mint==claim invariant) for
a rerouted pack. Confirm no off-by-one was introduced in pricing/cap that lets a pack be bought free or
double-bought, and that the rerouted pack's 16 entries land in the same traitBurnTicket bucket the level+1 jackpot
samples.`,
  },
  {
    key: 'liveness-gameover-gate',
    title: 'added liveness/gameOver gate correctness',
    focus: `The fix added at buyFoilPack top: if (gameOver) revert E(); if (_livenessTriggered()) revert E();.
Verify: (1) it does NOT block legitimate jackpot-phase foil buys — _livenessTriggered() returns false when
(lastPurchaseDay || jackpotPhaseFlag) (DegenerusGameStorage.sol:1463), so confirm a normal jackpot-phase or
purchase-phase buy is unaffected; (2) it correctly blocks a foil-only buy during a liveness-timeout window and
post-gameOver (the gap the prior INFO-FOIL-LIVENESS-GATE finding named) — trace that a pure foil buy (ticketQty=0,
so the facade's ticket leg with mintCost==0 is skipped) now hits this gate; (3) the gate ordering vs the existing
address(this)==GAME check is sound (delegatecall context). Confirm no brick: the gate only reverts the buy
itself, never advanceGame or a claim. Flag if the gate is too broad (blocks a legitimate buy) or too narrow
(still reachable post-gameover).`,
  },
  {
    key: 'require-and-regression',
    title: 'require->revert E() + no regression to the prior clean dimensions',
    focus: `(1) Confirm the _payFoilTier change require(rw != 0) -> if (rw == 0) revert E() is behavior-identical
(both revert when rw==0) and matches the suite convention (revert E()). Confirm rw==0 is unreachable for a
legitimately sealed draw (dailyFoilDraw[day] present => rngWordByDay[day]!=0) so it only fails closed. (2) Sanity-
check that the three edits (level reroute, gate, require) are confined to buyFoilPack/_payFoilTier and did NOT
perturb the previously-verified-clean paths: the drain budget accounting, the permissionless claim / try-catch
batch isolation, the double-claim uint24 guard, the value-conservation pool/affiliate split, and storage layout.
Read the surrounding code to confirm no variable shadowing, no changed control flow elsewhere, and that JACKPOT_
LEVEL_CAP=5 added as a private constant matches the other modules' value. Flag any regression.`,
  },
]

const results = await pipeline(
  DIMENSIONS,
  (d) =>
    agent(
      `You are a meticulous defensive smart-contract reviewer verifying a just-applied fix. ${CONTEXT}

DIMENSION: ${d.title}

${d.focus}

Read the ACTUAL current code (the fix is already in the working tree). Trace concrete reachable states. Be
adversarial — try to construct a brick, a mis-keyed/dead pack, an over-block, or an advantage the fix may have
introduced or failed to close. Report ONLY defects grounded in the real code with a concrete trigger. If the fix
is correct for this dimension, set fix_correct=true, findings=[]. For the boundary-table dimension, you MUST
include your full per-state table in the explanation of an INFO finding even if everything matches, so it can be
audited.`,
      { label: `review:${d.key}`, phase: 'Review', schema: SCHEMA }
    ),
  (review, d) => {
    const flagged = (review?.findings || []).filter(
      (f) => f.severity === 'CATASTROPHE' || f.severity === 'HIGH' || f.severity === 'MEDIUM'
    )
    if (flagged.length === 0) return { dimension: d.title, key: d.key, review, verdicts: [] }
    return parallel(
      flagged.map((f) => () =>
        agent(
          `You are an independent adversarial verifier. A reviewer flagged a potential defect in a just-applied
fix to a Solidity on-chain game. Default to refuted=true unless you independently reproduce the exact reachable
trigger against the real code. ${CONTEXT}

FLAGGED (dimension ${d.title}):
  id ${f.id} | ${f.title} | sev ${f.severity} | kind ${f.kind}
  anchor: ${f.anchor}
  explanation: ${f.explanation}
  claimed repro: ${f.repro}

Independently read the cited code and trace. Decide refuted (does it actually NOT hold?) and is_real_blocking_defect
(a real reachable BRICK or HORRIBLE ADVANTAGE per the USER bar; a narrow self-inflicted value-leak with no brick/
advantage is NOT blocking). Show your trace.`,
          { label: `verify:${f.id}`, phase: 'Verify', schema: VERDICT_SCHEMA }
        ).then((v) => ({ ...v, finding: f, dimension: d.title }))
      )
    ).then((verdicts) => ({ dimension: d.title, key: d.key, review, verdicts: verdicts.filter(Boolean) }))
  }
)

const confirmed = []
const survived = []
for (const r of results.filter(Boolean)) {
  for (const v of r.verdicts) {
    if (!v.refuted && v.is_real_blocking_defect) {
      confirmed.push({ dimension: r.dimension, ...v.finding, defect_class: v.defect_class, verifier_reasoning: v.reasoning })
    } else if (!v.refuted && v.defect_class !== 'none') {
      survived.push({ dimension: r.dimension, title: v.finding.title, defect_class: v.defect_class, severity: v.finding.severity, reasoning: v.reasoning })
    }
  }
}

log(`Fix re-verify: ${confirmed.length} confirmed blocking, ${survived.length} non-blocking survived`)

return {
  confirmed_blocking_defects: confirmed,
  non_blocking_survived: survived,
  per_dimension: results.filter(Boolean).map((r) => ({
    dimension: r.dimension,
    fix_correct: r.review?.fix_correct,
    findings: (r.review?.findings || []).map((f) => ({ id: f.id, severity: f.severity, kind: f.kind, title: f.title, explanation: f.explanation })),
  })),
}
