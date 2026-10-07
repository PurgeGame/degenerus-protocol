// SPDX-License-Identifier: AGPL-3.0-only
// Call-site wiring checks for per-award FLIP rounding. Runtime coverage lives in
// FlipRoundHundredsEv, LootboxFlipRoundHundreds, GoldenTicketArmResolve, CrapsBattle,
// and DegeneretteFlipRoundAntiGrind. These checks pin the call sites and immutable
// rounding inputs; they do not substitute copied arithmetic for contract execution.

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const SRC = (rel) => path.resolve(process.cwd(), rel);
const JACKPOT = SRC("contracts/modules/DegenerusGameJackpotDrawModule.sol");
const JACKPOT_CORE = SRC("contracts/modules/DegenerusGameJackpotModule.sol");
const LOOTBOX = SRC("contracts/modules/DegenerusGameLootboxModule.sol");
const DEGENERETTE = SRC("contracts/modules/DegenerusGameDegeneretteModule.sol");
const CRAPS_ENGINE = SRC("contracts/CrapsEngine.sol");

// Brace-match function-body extractor (copied from
// test/unit/JackpotTicketRollSilentColdBust.test.js).
function extractBody(source, signature) {
  const fnIdx = source.indexOf(signature);
  if (fnIdx < 0) return null;
  let depth = 0;
  let bodyStart = -1;
  let bodyEnd = -1;
  for (let i = fnIdx; i < source.length; i++) {
    if (source[i] === "{") {
      if (depth === 0) bodyStart = i;
      depth++;
    } else if (source[i] === "}") {
      depth--;
      if (depth === 0) {
        bodyEnd = i;
        break;
      }
    }
  }
  if (bodyStart < 0 || bodyEnd < 0) return null;
  return source.slice(bodyStart, bodyEnd + 1);
}

// Strip `//` line comments so structural greps do not self-invalidate on comment prose.
function stripLineComments(body) {
  return body
    .split("\n")
    .map((line) => {
      const idx = line.indexOf("//");
      return idx >= 0 ? line.slice(0, idx) : line;
    })
    .join("\n");
}

function bodyOf(file, signature) {
  const source = fs.readFileSync(file, "utf8");
  const body = extractBody(source, signature);
  expect(body, `\`${signature}\` body not found in ${file}`).to.not.equal(null);
  return stripLineComments(body);
}

describe("FlipHundredsInvariant (stat-suite) — seven-site 100-FLIP granule gate", function () {
  this.timeout(60_000);



  describe("§3a budget-split sites carry the exact integer unit math", function () {
    it("[01a] site 1 `_awardDailyCoinToTraitWinners` rounds its own budget to whole 100-FLIP shares", function () {
      const body = bodyOf(JACKPOT, "function _awardDailyCoinToTraitWinners(");
      expect(
        /uint256\s+units\s*=\s*coinBudget\s*\/\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(body),
        "site 1 must reduce its budget to whole FLIP_ROUND_UNIT shares"
      ).to.equal(true);
      expect(
        /uint256\s+cap\s*=\s*units\s*<\s*COIN_DRAW_SHARES\s*\?\s*units\s*:\s*COIN_DRAW_SHARES\s*;/.test(body),
        "site 1 must cap its winner count at COIN_DRAW_SHARES"
      ).to.equal(true);
      expect(
        /uint256\s+amount\s*=\s*\(\s*units\s*\/\s*cap\s*\)\s*\*\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(body),
        "site 1 must pay each winner the same whole-unit share"
      ).to.equal(true);
      expect(
        /\bextra\b|\bextraStart\b|\bbaseUnits\b/.test(body),
        "site 1 must carry no extra-unit machinery"
      ).to.equal(false);
      expect(
        /_coinDrawPlan\s*\(/.test(body),
        "site 1 runs its own split — no shared coin/Craps plan remains to defer to"
      ).to.equal(false);
      expect(
        /_finishJackpotBattle\s*\(/.test(body),
        "site 1 credits winners directly — no shared coin/Craps payout remains to settle through"
      ).to.equal(false);
    });

    it("[01b] `_playJackpotBattle` does no FLIP rounding of its own", function () {
      const body = bodyOf(JACKPOT, "function _runPurchaseJackpotBattle(");
      expect(/_coinDrawPlan\s*\(/.test(body), "the jackpot battle must not re-grow the shared coin/Craps plan").to.equal(false);
      expect(/FlipRoundLib/.test(body), "the jackpot battle performs no local FLIP rounding of its own").to.equal(false);
      expect(/JackpotBattleFieldLib\.prepare\s*\(\s*winners\s*\)/.test(body), "the draw passes its winners to the field library").to.equal(true);
    });

    it("[01e] every battle seat's payment lands on the threshold-gated collapse in the engine", function () {
      const body = bodyOf(CRAPS_ENGINE, "function settleBattle(");
      expect(
        /paid\s*>\s*FlipRoundLib\.FLIP_ROUND_THRESHOLD/.test(body),
        "a seat's payment must be gated on the 1,000-FLIP threshold"
      ).to.equal(true);
      expect(
        /FlipRoundLib\.roundFlipToHundreds\(\s*paid\s*,\s*_hash3\(\s*word\s*,\s*CRAPS_ROUND_TAG\s*,\s*betId\s*\)\s*\)/.test(body),
        "a seat's payment must go through the collapse keyed per bet id"
      ).to.equal(true);
      expect(/FlipRoundLib\.floorWholeFlip\(\s*paid\s*\)/.test(body), "below the threshold the whole-FLIP floor applies").to.equal(true);
    });
  });



  describe("§3b big-leg truncate carries no RNG", function () {
    it("[02a] site 3 `_payGoldenTicket` truncates `flipCredit` to a whole unit", function () {
      const body = bodyOf(JACKPOT_CORE, "function _payGoldenTicket(");
      expect(
        /flipCredit\s*=\s*\(\s*flipCredit\s*\/\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*\)\s*\*\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(
          body
        ),
        "site 3 must truncate `flipCredit` onto a whole 100-FLIP multiple"
      ).to.equal(true);
      // The truncate must precede the credit, so the event and the credit agree.
      const truncIdx = body.indexOf(
        "flipCredit / FlipRoundLib.FLIP_ROUND_UNIT"
      );
      const creditIdx = body.indexOf("coinflip.creditFlip(winner, flipCredit)");
      const emitIdx = body.indexOf("emit GoldenTicketWin(");
      expect(truncIdx).to.be.greaterThan(-1);
      expect(creditIdx).to.be.greaterThan(-1);
      expect(emitIdx).to.be.greaterThan(-1);
      expect(
        truncIdx,
        "the truncate must precede the credit"
      ).to.be.lessThan(creditIdx);
      expect(
        creditIdx,
        "the credit must precede the emit, so `GoldenTicketWin` reports what was credited"
      ).to.be.lessThan(emitIdx);
      // No seed is threaded into this path — that was the whole point of D5.
      expect(
        /roundFlipToHundreds/.test(body),
        "site 3 must NOT call the Bernoulli primitive — it truncates, so no seed has to be threaded through `payGoldenTicketGrand`"
      ).to.equal(false);
    });
  });

  describe("§3c small-award sites carry the threshold-gated collapse", function () {
    const SITES = [
      { n: 4, file: LOOTBOX, sig: "function _resolvePresaleBox(", seed: "seed" },
      {
        n: 5,
        file: LOOTBOX,
        sig: "function _settleLootboxRoll(",
        seed: "rollSeed",
      },
      { n: 6, file: DEGENERETTE, sig: "function _resolveBet(", seed: "rngWord" },
      // Site 7's collapse lives in `_flipSpinChain`, the helper both FLIP-spin entry
      // points delegate to (`resolveFlipSpinsFromBox` for the lootbox roll and the
      // biggest-spin record bounty for its replay). The entry points carry no award
      // arithmetic of their own, so the chain IS the award site.
      { n: 7, file: DEGENERETTE, sig: "function _flipSpinChain(", seed: "seed" },
    ];

    for (const site of SITES) {
      it(`[03${String.fromCharCode(96 + site.n - 3)}] site ${site.n} \`${site.sig
        .replace("function ", "")
        .replace("(", "")}\` gates on the threshold and collapses via the library`, function () {
        const body = bodyOf(site.file, site.sig);
        expect(
          /FlipRoundLib\.FLIP_ROUND_THRESHOLD/.test(body),
          `site ${site.n} must gate on \`FLIP_ROUND_THRESHOLD\` so small awards keep the whole-FLIP floor`
        ).to.equal(true);
        expect(
          /FlipRoundLib\.roundFlipToHundreds\(/.test(body),
          `site ${site.n} must collapse via \`FlipRoundLib.roundFlipToHundreds\``
        ).to.equal(true);
        expect(
          /FlipRoundLib\.floorWholeFlip\(/.test(body),
          `site ${site.n} must floor the sub-threshold branch via \`FlipRoundLib.floorWholeFlip\` — no award leaves a site with wei-scale residue`
        ).to.equal(true);
        expect(
          new RegExp(
            `EntropyLib\\.hash[24]\\(\\s*${site.seed}\\s*[,)]`
          ).test(body),
          `site ${site.n} must key the collapse on a domain-separated hash of \`${site.seed}\``
        ).to.equal(true);
      });
    }

    it("[03e] site 6 carries the collapse delta into `acc.flipMint` so the single flush mints exactly the rounded payout", function () {
      const body = bodyOf(DEGENERETTE, "function _resolveBet(");
      expect(
        /acc\.flipMint\s*\+=\s*rounded\s*-\s*(?:totals\.)?totalPayout\s*;/.test(body),
        "an upward round must add its delta to the accumulator"
      ).to.equal(true);
      expect(
        /acc\.flipMint\s*-=\s*(?:totals\.)?totalPayout\s*-\s*rounded\s*;/.test(body),
        "a downward round must subtract its delta from the accumulator"
      ).to.equal(true);
      // Ordering: the survival flip settles first, so the threshold reads against the
      // number the player actually receives and a lost flip never reaches it.
      const survivalIdx = body.indexOf("EntropyLib.hash4(rngWord, playerId, betId, BET_SURVIVAL_TAG)");
      const roundIdx = body.indexOf("FlipRoundLib.roundFlipToHundreds(");
      expect(survivalIdx).to.be.greaterThan(-1);
      expect(roundIdx).to.be.greaterThan(-1);
      expect(
        survivalIdx,
        "the survival flip must settle BEFORE the collapse — a bet that loses it is zero and must never round"
      ).to.be.lessThan(roundIdx);
    });
  });

  describe("Anti-grind: the caller-composed aggregate is NEVER rounded (§4)", function () {
    it("[04a] `sweepDegeneretteBets` flushes through the shared `_flushOwner`, which mints `acc.flipMint` raw — no collapse at the flush", function () {
      // Bets resolve ONLY through the permissionless in-order sweep `sweepDegeneretteBets`
      // (reached via `game.mineFlip`'s Degenerette stage), which loops queued bets
      // into a shared ResolveAcc and delegates the per-owner payout to `_flushOwner` (called
      // once per owner-run and once at the end of the call). The entry-point body itself
      // does not inline the mint — pin it to the shared flush instead, which it routes through.
      const entry = bodyOf(DEGENERETTE, "function _runDegeneretteWork(");
      expect(
        /_flushOwner\s*\(\s*acc\s*\)\s*;/.test(entry),
        "sweepDegeneretteBets must settle through the shared per-owner flush"
      ).to.equal(true);

      const body = bodyOf(DEGENERETTE, "function _flushOwner(");
      expect(
        /if\s*\(\s*acc\.flipMint\s*!=\s*0\s*\)\s*\{?\s*coin\.mintForGame\(\s*_resolvePayee\(\s*acc\s*\)\s*,\s*acc\.flipMint\s*\)\s*;/.test(
          body
        ),
        "the flush must mint the bare accumulator to the accumulated owner"
      ).to.equal(true);
      expect(
        /FlipRoundLib/.test(body),
        "the flush must NOT round: `betIds[]` is caller-composed and settling is permissionless, so rounding the aggregate would let a caller enumerate batch partitions against the already-committed VRF word and take the split with the most round-ups"
      ).to.equal(false);
    });

    it("[04b] the collapse at site 6 keys on the immutable `betId`, not on anything the caller chose", function () {
      const body = bodyOf(DEGENERETTE, "function _resolveBet(");
      expect(
        /EntropyLib\.hash4\(\s*rngWord\s*,\s*playerId\s*,\s*betId\s*,\s*FLIP_ROUND_TAG\s*\)/.test(
          body
        ),
        "the collapse seed must be `hash4(rngWord, playerId, betId, FLIP_ROUND_TAG)` — all inputs immutable at fulfillment"
      ).to.equal(true);
    });
  });

  describe("Negative gates: the paths deliberately left ragged", function () {


    it("[05b] the degenerette affiliate `refFlip` credit is untouched (owner-ruled out of scope)", function () {
      const body = bodyOf(DEGENERETTE, "function _resolveBet(");
      const refIdx = body.indexOf("uint256 refFlip");
      expect(refIdx, "`refFlip` affiliate credit not found").to.be.greaterThan(
        -1
      );
      // The affiliate credit is emitted from the raw `refFlip * AFFILIATE_BOX_BPS / 10_000`,
      // with no collapse between its derivation and the credit call.
      const creditIdx = body.indexOf("(refFlip * AFFILIATE_BOX_BPS) / 10_000");
      expect(creditIdx).to.be.greaterThan(refIdx);
      const between = body.slice(refIdx, creditIdx);
      expect(
        /FlipRoundLib/.test(between),
        "no collapse may be applied to the affiliate credit — every affiliate FLIP path is out of scope"
      ).to.equal(false);
    });
  });


});
