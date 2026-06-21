export const meta = {
  name: 'foil-reaudit-session6',
  description: 'Adversarial-verify reaudit of the v71 foil day-bucket redesign before the freeze commit',
  phases: [
    { title: 'Review', detail: 'isolated reviewer per invariant dimension' },
    { title: 'Verify', detail: 'independent skeptic refutes each flagged finding' },
  ],
}

// ---------------------------------------------------------------------------
// Shared context handed to every reviewer (neutral defensive-engineering frame).
// ---------------------------------------------------------------------------
const REPO = '/home/zak/Dev/PurgeGame/degenerus-audit'

const FILES = `
Key files (read what you need; the foil feature spans these):
- contracts/modules/DegenerusGameFoilPackModule.sol  (NEW — buy, claim, claim-batch, drain, payout, _deriveFoilLines)
- contracts/storage/DegenerusGameStorage.sol         (foil state @ end, ~line 2391+: foilRecord, dailyFoilDraw, foilBuyers, cursors, masks, helpers _foilRecordFor/_foilMultFor/_foilDrainPending/_foilBoughtThisLevel/_packFoilDraw/_foilDrawFor)
- contracts/DegenerusTraitUtils.sol                  (foilCuts / foilTrait / packedTraitsFoil — the boosted color ladder producer)
- contracts/modules/DegenerusGameMintModule.sol      (processTicketBatch + _drainFoil hook on leftover write budget)
- contracts/modules/DegenerusGameAdvanceModule.sol   (advanceGame: day clamp @~184, readiness gates @~237/284 using _foilDrainPending, rollDailyQuest forceFoil @~1254, payDailyJackpot caller @~499/579)
- contracts/modules/DegenerusGameJackpotModule.sol   (payDailyJackpot: questDay=_simulatedDayIndex() @302, dailyFoilDraw seal @1590 & @1850, hero exclusion roll)
- contracts/DegenerusGame.sol                        (facade: purchase(...,bool foil) -> _purchaseWithFoil orchestration @~609, claimFoilMatch / claimFoilMatchMany delegatecall stubs @~713)
- contracts/modules/DegenerusGameDegeneretteModule.sol (resolveEthSpinFromBox / resolveFlipSpinsFromBox / resolveWwxrpSpinFromBox — box-spin resolvers, customTicket param)
`

const DESIGN = `
DESIGN (LOCKED + USER-approved — do NOT propose redesigns; report only defects against THIS design):
- foilRecord[lvl][buyer] packs resolveDay[0:24] | multBps[24:40] | activityScore[40:56]. Presence (slot != 0) IS the one-pack-per-cycle cap. No signatures stored.
- BUY (buyFoilPack, delegatecalled from the facade's _purchaseWithFoil): guard "if (_simulatedDayIndex() > dailyIdx + 1) revert" (multi-day-stall block); resolveDay = (!rngLockedFlag && dailyIdx < day) ? day : day + 1; activityScore frozen at buy; pushes foilBuyers[resolveDay] = (lvl<<160 | buyer); raises foilLastResolveDay (high-water) / foilDrainDay (low-water).
- DRAIN (_processFoilDrain, delegatecalled from MintModule._drainFoil after the normal queue, on leftover budget): walks foilDrainDay -> foilLastResolveDay over SEALED buckets (rngWordByDay[dd] != 0); per buyer files 16 traits via the shared _deriveFoilLines(buyer, lvl, rngWordByDay[resolveDay], multBps); budget charge 35 units/buyer; whole-buyer deferral; resumable via foilCursor; NO stamp.
- CLAIM (claimFoilMatch / _tryClaimFoilMatch): re-derives lines via the SAME _deriveFoilLines; require(day >= resolveDay); reads dailyFoilDraw[day] for the winning sets; CEI marker keccak(player,L,day,drawKind,ticketIndex) set before payout; _payFoilTier stakes faces into a 40/40/20 ETH/FLIP/WWXRP Degenerette box-spin seeded off the day's word, RTP = the FROZEN activityScore, customTicket = the matched line sel.
- BATCH (claimFoilMatchMany): permissionless; each item runs as "try this.claimFoilMatch(...)" (external self-call under delegatecall -> facade stub -> module), revert-isolated; per-settled FLIP keeper bounty (live game only).
- JACKPOT seal: dailyFoilDraw[questDay] = _packFoilDraw(mainSet, bonusSet, level), questDay = _simulatedDayIndex(). "foil == jackpot by construction": the jackpot samples traitBurnTicket (which the drain filed the 16 boosted foil entries into) and the claim reads the SAME sealed sets.

USER BAR (weight findings to this): the ONLY blocking outcomes are (1) a BRICK — a reachable state where advanceGame / a foil buy / a claim permanently reverts or wedges the game, especially under multi-day VRF stalls; or (2) a HORRIBLE ADVANTAGE — address-grinding a winning line, steering the resolving word, double-paying a tuple, or draining value beyond design. A cosmetic stall-window quirk that cannot brick and confers no advantage is WONTFIX (report as INFO, not a defect).
`

const REVIEW_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['dimension', 'invariant_holds', 'findings'],
  properties: {
    dimension: { type: 'string' },
    invariant_holds: { type: 'boolean', description: 'true iff you found no real defect for this dimension' },
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
          kind: { type: 'string', enum: ['brick', 'advantage', 'correctness', 'value-leak', 'other'] },
          anchor: { type: 'string', description: 'file:line or function name' },
          explanation: { type: 'string' },
          repro: { type: 'string', description: 'concrete sequence/state that triggers it, or "n/a"' },
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
    refuted: { type: 'boolean', description: 'true iff the claimed defect does NOT actually hold against the real code' },
    is_real_blocking_defect: { type: 'boolean', description: 'true ONLY if it is a real reachable brick or horrible-advantage per the USER bar' },
    defect_class: { type: 'string', enum: ['brick', 'advantage', 'correctness', 'value-leak', 'none'] },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    reasoning: { type: 'string' },
  },
}

const DIMENSIONS = [
  {
    key: 'mint-claim-identity',
    title: 'mint == claim derivation identity',
    focus: `Verify the load-bearing invariant: the four match lines a buyer's pack files into the jackpot trait buckets at DRAIN equal the four lines the CLAIM re-derives. Both call _deriveFoilLines(buyer, lvl, entropy, multBps). Confirm, against the real code, that for any given pack ALL FOUR inputs are identical between the drain and the claim:
  (a) buyer: drain reads address(uint160(packedLvlBuyer)) from the bucket entry; claim takes player param. Same?
  (b) lvl: drain reads uint24(packedLvlBuyer >> 160) from the bucket entry; claim reads L from dailyFoilDraw[day]. Could these ever differ for a real claimable tuple? (The bucket entry's lvl was set at buy = _activeTicketLevel(); the foilRecord outer key = same lvl; the claim looks up _foilRecordFor(player, L) where L comes from the DRAW. Trace whether L == the pack's stored lvl always holds.)
  (c) entropy: drain uses rngWordByDay[dd] (dd = the bucket/resolveDay); claim uses rngWordByDay[resolveDay] (from the record). Same day key?
  (d) multBps: drain uses _foilMultFor(buyer, lvl); claim uses the record's multBps field. Same packed slot, same accessor math?
If any input can diverge for a reachable claimable tuple, that breaks foil==jackpot — flag it with the exact divergence path.`,
  },
  {
    key: 'resolveday-guard',
    title: 'resolveDay rule + multi-day-stall guard (steering / address-grinding)',
    focus: `Probe whether a buyer can ever know or influence the word their lines derive from (rngWordByDay[resolveDay]) at buy time. The buy sets resolveDay = (!rngLockedFlag && dailyIdx < day) ? day : day + 1, guarded by "if (day > dailyIdx + 1) revert" (day = _simulatedDayIndex()).
  - Enumerate the reachable (rngLockedFlag, dailyIdx, day) states at buy. For each, is rngWordByDay[resolveDay] already sealed/requested/derivable (e.g. a fulfilled-but-unapplied VRF word, or a gap-backfill that makes a future day's word a deterministic keccak of a public word)? If yes for any reachable state the guard admits, a buyer could grind addresses offline for a winning line -> horrible advantage. If every admitted state leaves resolveDay's word genuinely future/unrequested, the invariant holds.
  - Check the "slip into today" slice (!rngLockedFlag && dailyIdx < day): is today's word provably unrequested there?
  - BRICK check: does the guard ever revert a buy in a state the caller cannot escape (i.e. can they always advanceGame to clear it, permissionlessly)? A buy that reverts forever = brick.`,
  },
  {
    key: 'level-transition',
    title: 'level-matches-across-transition (codex #3 — no dead pack)',
    focus: `A foil pack bought near a level/cycle transition must remain claimable: the cycle level it stored (foilRecord outer key = _activeTicketLevel() at buy, also carried in the bucket entry) must equal the level the resolving day's draw records (dailyFoilDraw[resolveDay].level). The claim reads L from the draw, then _foilRecordFor(player, L) — if L != the pack's stored level, present=false and the pack is a dead (unclaimable) buy despite being paid for.
  - Trace _activeTicketLevel() vs the level written into dailyFoilDraw at the day resolveDay actually resolves. Consider: buy in the brief pre-RNG-request slice on a transition day; buy on the last purchase day; buy when jackpotPhaseFlag flips. Does resolveDay's draw always carry the SAME level the pack recorded?
  - Also confirm the drain files into traitBurnTicket[lvl] for the SAME lvl, so the jackpot for that day samples the pack's entries.
  - Any reachable buy that becomes permanently unclaimable (paid, never payable) is a value-leak/correctness defect — flag with the transition sequence.`,
  },
  {
    key: 'permissionless-claim-batch',
    title: 'permissionless claim + try/catch batch isolation + double-claim',
    focus: `Review claimFoilMatch / claimFoilMatchMany / _tryClaimFoilMatch for:
  - Value routing: every credit (whalePassClaims, the spin payout) goes to `+'`player`'+` (the pack owner), never msg.sender. Confirm a third party triggering a claim cannot redirect value to themselves.
  - Double-pay: the CEI marker keccak256(abi.encode(player, L, day, drawKind, ticketIndex)) is set BEFORE _payFoilTier. Confirm a tuple pays at most once. Check the uint24-domain guard "if (day > type(uint24).max) return false" — without it, day and day+2^24 alias the same draw/line but mint distinct markers (re-pay). Is the guard correct and complete?
  - Batch isolation: each item runs as "try this.claimFoilMatch(...)" (external self-call: address(this)==GAME under delegatecall -> facade stub -> module). Confirm a single revert (non-claimable tuple OR a payout spin that reverts, e.g. an ETH tier too large for the frozen pool) rolls back ONLY that tuple and the loop continues. Confirm no shared in-memory state leaks across iterations to corrupt later items.
  - Keeper bounty: settled-count-gated, live-game only. Can a padded/duplicate batch farm the bounty without settling real new wins? (Duplicates hit the marker -> revert -> not counted.) Confirm.`,
  },
  {
    key: 'frozen-activity-payout',
    title: 'frozen activity score + payout EV-neutrality + spin safety',
    focus: `The spin RTP uses activityScore FROZEN at buy (foilRecord[40:56]), passed to _payFoilTier (no live read). Verify:
  - The frozen score is the SAME basis foilBoostBps used at buy (consistency), and that freezing removes any claim-timing or claimant-identity RTP lever.
  - uint16 truncation: the score is stored as uint16(score). Can a real activity score exceed 65535 and truncate to a wrong (e.g. tiny) value, mispricing the spin? What is the actual score range (check _playerActivityScore)? If truncation is lossy in a reachable range, flag it.
  - Payout safety: faces (7/65/1000) are STAKES into the box-spin. ETH lane is pool-capped + recircs over-cap to lootbox; FLIP/WWXRP are free mints. Confirm no solvency break / unbounded ETH drain. Confirm the matched line sel as customTicket is EV-neutral under the per-N degenerette tables (the spin tables are calibrated per gold-count N).
  - require(rw != 0) in _payFoilTier: a sealed draw always retained a nonzero word, so this only fails closed. Confirm it can't brick a legitimately-claimable tuple (i.e. dailyFoilDraw[day] present => rngWordByDay[day] != 0). Trace whether a present draw can coexist with a zero word.`,
  },
  {
    key: 'codex2-wallday-clamp',
    title: 'codex #2 — dailyFoilDraw keyed on wall day vs clamped processed day',
    focus: `payDailyJackpot writes dailyFoilDraw[questDay] with questDay = _simulatedDayIndex() (WALL day), but advanceGame can CLAMP the processed day: line ~184 "if (day > dIdx + 1 && rngWordByDay[dIdx + 1] != 0) day = dIdx + 1" (RNGREUSE guard), and gap-backfill paths derive earlier days' words. So during a stall the winning sets stored at dailyFoilDraw[wallDay] may be derived from rngWordByDay[clampedDay], not rngWordByDay[wallDay].
  - Determine: for a foil claim against day D, does the claim ever read a dailyFoilDraw[D] whose stored sets were rolled from a DIFFERENT word than rngWordByDay[D]? If so the foil match for that D is no longer "== the jackpot for D".
  - Critical question for the USER bar: can this desync (a) BRICK anything (a revert in advanceGame, the drain, or a claim), or (b) confer ADVANTAGE — i.e. can a buyer, given the multi-day-stall buy guard, predict or steer the stored sets to win? Remember the buy guard "day > dailyIdx + 1 -> revert" blocks foil buys during multi-day stalls; the resolving word is future at buy. Does that fully neutralize any steering even with the wall-day key?
  - If it is at worst a transient consistency quirk (no brick, no advantage), say so explicitly and classify INFO. If you find a reachable brick or steering, flag it HIGH with the exact day sequence.`,
  },
  {
    key: 'drain-brick-budget',
    title: 'drain no-brick / budget accounting / readiness gate / gas envelope',
    focus: `Review the foil drain for any way it bricks advanceGame or starves the jackpot:
  - Budget exactness: the defer guard "if (room < (FOIL_PACK_ENTRIES*2)+3)" must EQUAL the charge "room -= (FOIL_PACK_ENTRIES*2)+3" (both 35). If the guard were smaller than the charge, an unchecked underflow could drain everything in one tx (gas blowout). Confirm equality and the unchecked arithmetic is safe.
  - Resumability: foilDrainDay / foilCursor persist a budget-short deferral; whole-buyer deferral (never a partial pack). Confirm a buyer is never double-resolved nor skipped across resume.
  - Readiness gate: _foilDrainPending() (foilLastResolveDay != 0 && foilDrainDay <= last && rngWordByDay[foilDrainDay] != 0) blocks the jackpot draw (AdvanceModule @~237/284) until the sealed bucket drains. Confirm a future-dated (unsealed) bucket does NOT gate the draw (the walk breaks on entropy==0), so a pack bought for a far-future resolveDay can't wedge advanceGame.
  - MintModule._drainFoil: short-circuits on !_foilDrainPending() (no delegatecall, single SLOAD) and defers without delegatecall when room can't fit one pack. Confirm the no-foil advance carries zero foil cost and no brick surface.
  - Combined gas: normal queue + foil drain share one write-budget envelope. Confirm the worst-case combined advance stays under the advance-chain gas ceiling (no unbounded loop; the drain is budget-bounded and resumable).
  - Cursor/high-water bookkeeping at buy: foilLastResolveDay / foilDrainDay updates (lines ~284-288). Could a sparse/out-of-order resolveDay sequence make the drain walk a huge empty range, or skip a sealed bucket? Trace.`,
  },
  {
    key: 'value-conservation-orchestration',
    title: 'facade orchestration + value conservation (payment / pool / affiliate)',
    focus: `Review the buy-side money flow for conservation and no-strand/no-revert:
  - Facade _purchaseWithFoil: fresh = min(msg.value, cost) (cost = mintCost + 10*priceWei); overpay (msg.value - fresh) -> _creditAfkingValue (no strand, no revert). mintFresh = min(fresh, mintCost) to the ticket leg via purchaseWith; the foil leg gets (fresh - mintFresh). Confirm the arithmetic never underflows and the split conserves ETH exactly (every wei is spent, credited, or refunded to afking).
  - buyFoilPack payment: ethUsed = min(ethSent, cost); shortfall "remaining" debited from claimable down to the 1-wei sentinel (remaining + 1 > uint128(bal) -> revert), never borrowing the afking principal above it; DirectEth forbids claimable. Confirm the low-half subtraction balancesPacked[buyer] = bal - remaining can't borrow into the high (afking) half.
  - Pool fork 75/25 on the foil cost (FOIL_TO_FUTURE_BPS=2500), frozen/unfrozen routing. Confirm the foil cost lands fully in the pools (futureShare + nextShare == cost).
  - Affiliate 20/5 (fresh ethUsed at fresh rate, claimable remaining at recycle rate, level+1, score 0); recycle bonus 10% when remaining >= 3*priceWei; one creditFlip. Confirm no double-credit and that quest idempotency (handlePurchase completionMask) prevents the ticket leg + foil leg from double-rewarding the daily primary / mint streak.
  - Confirm a foil pack records exactly 10 price-equivalent mint units (FOIL_PACK_TICKETS*4*TICKET_SCALE) and that this matches the intent (10 ticket prices -> 10 units of activity).`,
  },
  {
    key: 'layout-eip170',
    title: 'storage layout append-at-end + EIP-170 (no slot move)',
    focus: `Confirm the storage layout change is purely additive — the foil state (foilRecord, dailyFoilDraw, foilBuyers, foilCursor/foilDrainDay/foilLastResolveDay) is appended AFTER the last pre-existing variable (boxPlayers) in DegenerusGameStorage.sol, and NO pre-existing variable's slot or offset moved. Use "forge inspect <Contract> storage-layout" (run from ${REPO}) on DegenerusGame (or a concrete deployable like the harness) to confirm the pre-foil variables keep their exact slots and the three cursors (foilCursor uint32, foilDrainDay uint24, foilLastResolveDay uint24) pack into ONE slot. Also confirm every production contract is under the 24,576 EIP-170 runtime limit via "forge build --via-ir --sizes" (MintModule is the tight one — expect ~754 B margin). Report any slot move or oversize as a blocking defect; otherwise invariant_holds=true.`,
  },
]

// ---------------------------------------------------------------------------
// Phase 1+2: review each dimension, then adversarially verify every flagged finding.
// Pipeline so a dimension's findings get refuted as soon as its review lands.
// ---------------------------------------------------------------------------
const results = await pipeline(
  DIMENSIONS,
  (d) =>
    agent(
      `You are a meticulous defensive smart-contract reviewer auditing a Solidity 0.8.34 on-chain game module (delegatecall facade-module architecture, via-IR). Working directory: ${REPO}.

DIMENSION TO REVIEW: ${d.title}

${d.focus}

${FILES}
${DESIGN}

Read the actual code (do not rely on the comments alone — verify the comments against the implementation). Trace concrete reachable states. Be adversarial: actively try to construct a brick or an advantage. But report ONLY defects you can ground in the real code with a concrete trigger — no speculation, no style nits. If the invariant holds, say so (invariant_holds=true, findings=[]). For each real concern, give the exact anchor and a concrete repro/state sequence. Default to skepticism about your own findings: if you cannot construct a reachable trigger, it is not a finding.`,
      { label: `review:${d.key}`, phase: 'Review', schema: REVIEW_SCHEMA, isolation: undefined }
    ),
  // Verify stage: refute every flagged finding with an independent skeptic.
  (review, d) => {
    const flagged = (review?.findings || []).filter(
      (f) => f.severity === 'CATASTROPHE' || f.severity === 'HIGH' || f.severity === 'MEDIUM'
    )
    if (flagged.length === 0) return { dimension: d.title, key: d.key, review, verdicts: [] }
    return parallel(
      flagged.map((f) => () =>
        agent(
          `You are an independent adversarial verifier. A prior reviewer flagged a potential defect in this Solidity 0.8.34 on-chain game (delegatecall facade-module architecture). Your job is to REFUTE it: default to refuted=true unless you can independently reproduce the exact reachable trigger against the real code. Working directory: ${REPO}.

FLAGGED FINDING (dimension: ${d.title})
  id: ${f.id}
  title: ${f.title}
  severity: ${f.severity}  kind: ${f.kind}
  anchor: ${f.anchor}
  explanation: ${f.explanation}
  claimed repro: ${f.repro}

${FILES}
${DESIGN}

Independently read the cited code and trace the claimed trigger. Decide: (1) refuted — does the claimed defect actually NOT hold against the real code (a guard/CEI/idempotency/clamp the reviewer missed)? (2) is_real_blocking_defect — is it a REAL reachable BRICK or HORRIBLE ADVANTAGE per the USER bar (a cosmetic stall-window quirk with no brick and no advantage is NOT blocking — set false and defect_class accordingly)? Show your trace in reasoning.`,
          { label: `verify:${f.id}`, phase: 'Verify', schema: VERDICT_SCHEMA }
        ).then((v) => ({ ...v, finding: f, dimension: d.title }))
      )
    ).then((verdicts) => ({ dimension: d.title, key: d.key, review, verdicts: verdicts.filter(Boolean) }))
  }
)

// ---------------------------------------------------------------------------
// Collect: confirmed real blocking defects (survived adversarial refutation).
// ---------------------------------------------------------------------------
const confirmed = []
const survivedQuirks = []
for (const r of results.filter(Boolean)) {
  for (const v of r.verdicts) {
    if (!v.refuted && v.is_real_blocking_defect) {
      confirmed.push({ dimension: r.dimension, ...v.finding, defect_class: v.defect_class, confidence: v.confidence, verifier_reasoning: v.reasoning })
    } else if (!v.refuted && v.defect_class !== 'none') {
      survivedQuirks.push({ dimension: r.dimension, title: v.finding.title, defect_class: v.defect_class, severity: v.finding.severity, reasoning: v.reasoning })
    }
  }
}

log(`Reaudit complete: ${confirmed.length} confirmed blocking defect(s), ${survivedQuirks.length} non-blocking survived item(s)`)

return {
  confirmed_blocking_defects: confirmed,
  non_blocking_survived: survivedQuirks,
  per_dimension: results.filter(Boolean).map((r) => ({
    dimension: r.dimension,
    invariant_holds: r.review?.invariant_holds,
    finding_count: (r.review?.findings || []).length,
    findings: (r.review?.findings || []).map((f) => ({ id: f.id, severity: f.severity, kind: f.kind, title: f.title })),
  })),
}
