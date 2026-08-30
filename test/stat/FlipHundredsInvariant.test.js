// SPDX-License-Identifier: AGPL-3.0-only
//
// FlipHundredsInvariant.test.js — combined seven-site gate for the 100-FLIP award granule.
//
// SUPERSEDES the three-site whole-FLIP floor gate this file used to carry
// (D-279-INLINE-01). The granule moved from 1 FLIP to 100 FLIP, and the sites split into
// three shapes, each with a different mechanism — this file is the single place that
// asserts ALL of them are present, so a partial revert at any one site fails here even if
// its own suite is deleted:
//
//   §3a BUDGET-SPLIT (exact integer unit math, no probabilistic rounding)
//     1. `_awardDailyCoinToTraitWinners`  — JackpotModule
//     2. `_awardFarFutureCoinJackpot`     — JackpotModule
//
//   §3b BIG-LEG TRUNCATE (no RNG at all)
//     3. `_payGoldenTicket`               — JackpotModule
//
//   §3c THRESHOLD-GATED BERNOULLI COLLAPSE (EV-preserving above 1,000 FLIP)
//     4. `_resolvePresaleBox`             — LootboxModule
//     5. `_settleLootboxRoll`             — LootboxModule
//     6. `_resolveBet`                    — DegeneretteModule
//     7. `_flipSpinChain`                  — DegeneretteModule (both FLIP-spin
//                                            entry points delegate to it)
//
// It also carries the NEGATIVE assertions — the paths deliberately left ragged, each of
// which would look like an oversight to the next audit pass without a test saying so:
//   - the mint-boost flip credit (`_purchaseForWithCached`) — out of scope
//   - the degenerette affiliate `refFlip` and every other affiliate FLIP path — owner-ruled out
//   - `acc.flipMint` at the `resolveDegeneretteBets` flush — rounding the caller-composed
//     aggregate is the one real grind in this design, so its ABSENCE is load-bearing
//
// CROSS-CITES:
//   - .planning/PLAN-FLIP-ROUND-HUNDREDS.md §3a / §3b / §3c / §4
//   - D-279-INLINE-01 SUPERSEDED (the inline whole-FLIP floor is gone from all sites)
//   - D-40N-BUR-MINTBOOST-OUT-01 (mint-boost stays fractional)
//   - test/stat/FlipRoundHundredsEv.test.js (EV-neutrality of the primitive itself)

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const ONE_FLIP = 10n ** 18n;
const UNIT = 100n * ONE_FLIP; // FlipRoundLib.FLIP_ROUND_UNIT
const THRESHOLD = 1_000n * ONE_FLIP; // FlipRoundLib.FLIP_ROUND_THRESHOLD

const SRC = (rel) => path.resolve(process.cwd(), rel);
const JACKPOT = SRC("contracts/modules/DegenerusGameJackpotModule.sol");
const LOOTBOX = SRC("contracts/modules/DegenerusGameLootboxModule.sol");
const DEGENERETTE = SRC("contracts/modules/DegenerusGameDegeneretteModule.sol");
const MINT = SRC("contracts/modules/DegenerusGameMintModule.sol");
const LIB = SRC("contracts/libraries/FlipRoundLib.sol");

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

// The gated collapse as applied on-chain, for the invariant sweeps. At or below the
// threshold the award keeps the whole-FLIP floor rather than paying wei-scale residue.
function jsRoundGated(amount, slice) {
  if (amount <= THRESHOLD) return (amount / ONE_FLIP) * ONE_FLIP;
  let hundreds = amount / UNIT;
  const remFlip = (amount % UNIT) / ONE_FLIP;
  if (remFlip !== 0n && slice < remFlip) hundreds += 1n;
  return hundreds * UNIT;
}

// The §3a unit split, for the invariant sweeps. Every paid winner takes the SAME share;
// `leftover` is the part of the budget the equal-share rule declines to mint.
function splitUnits(budgetWei, maxWinners) {
  const units = budgetWei / UNIT;
  const cap = units < maxWinners ? units : maxWinners;
  if (cap === 0n) return { units, cap: 0n, amount: 0n, leftover: units };
  return { units, cap, amount: (units / cap) * UNIT, leftover: units % cap };
}

describe("FlipHundredsInvariant (stat-suite) — seven-site 100-FLIP granule gate", function () {
  this.timeout(60_000);

  describe("The primitive itself", function () {
    it("[00a] `FlipRoundLib` declares the 100-FLIP granule and the 1,000-FLIP threshold", function () {
      const source = fs.readFileSync(LIB, "utf8");
      expect(
        /uint256\s+internal\s+constant\s+FLIP_ROUND_UNIT\s*=\s*100 ether\s*;/.test(
          source
        ),
        "`FLIP_ROUND_UNIT` must be 100 ether"
      ).to.equal(true);
      expect(
        /uint256\s+internal\s+constant\s+FLIP_ROUND_THRESHOLD\s*=\s*1_000 ether\s*;/.test(
          source
        ),
        "`FLIP_ROUND_THRESHOLD` must be 1_000 ether"
      ).to.equal(true);
    });

    it("[00b] the round-up compares a uint32 window against the WHOLE-FLIP remainder, not the wei remainder", function () {
      const body = bodyOf(LIB, "function roundFlipToHundreds(");
      expect(
        /uint256\s+remFlip\s*=\s*\(\s*amount\s*%\s*FLIP_ROUND_UNIT\s*\)\s*\/\s*1 ether\s*;/.test(
          body
        ),
        "the remainder must be reduced to whole FLIP (0..99) before the roll — a wei compare would need ~67 bits to hold the modulo bias down"
      ).to.equal(true);
      expect(
        /uint32\(entropy\)\s*%\s*100\s*<\s*remFlip/.test(body),
        "the round-up must fire with probability remFlip/100 off a uint32 window"
      ).to.equal(true);
      const source = fs.readFileSync(LIB, "utf8");
      const declStart = source.indexOf("function roundFlipToHundreds");
      const decl = source.slice(declStart, source.indexOf("{", declStart));
      expect(
        /\bpure\b/.test(decl),
        "the primitive must be `pure` — it may read no mutable storage inside a freeze window"
      ).to.equal(true);
    });
  });

  describe("§3a budget-split sites carry the exact integer unit math", function () {
    it("[01a] site 1 `_awardDailyCoinToTraitWinners`", function () {
      const body = bodyOf(JACKPOT, "function _awardDailyCoinToTraitWinners(");
      expect(
        /uint256\s+units\s*=\s*\(\s*coinBudget\s*-\s*spent\s*\)\s*\/\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(
          body
        ),
        "site 1 must split the unbanked budget into whole 100-FLIP units"
      ).to.equal(true);
      expect(
        /if\s*\(\s*cap\s*==\s*0\s*\)\s*return\s*;/.test(body),
        "site 1 must bail when the budget covers no whole unit"
      ).to.equal(true);
      expect(
        /uint256\s+amount\s*=\s*\(\s*units\s*\/\s*cap\s*\)\s*\*\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(
          body
        ),
        "site 1 must pay every pull the SAME `(units / cap)` share"
      ).to.equal(true);
      expect(
        /\bextra\b|\bextraStart\b|\bbaseUnits\b/.test(body),
        "site 1 must carry no extra-unit machinery — equal shares are owner-ruled"
      ).to.equal(false);
    });

    it("[01b] site 2 `_awardFarFutureCoinJackpot`", function () {
      const body = bodyOf(JACKPOT, "function _awardFarFutureCoinJackpot(");
      expect(
        /uint256\s+units\s*=\s*farBudget\s*\/\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(
          body
        ),
        "site 2 must split the budget into whole 100-FLIP units"
      ).to.equal(true);
      expect(
        /if\s*\(\s*payCount\s*==\s*0\s*\)\s*return\s*;/.test(body),
        "site 2 must bail when the budget covers no whole unit"
      ).to.equal(true);
      expect(
        /uint256\s+amount\s*=\s*\(\s*units\s*\/\s*payCount\s*\)\s*\*\s*FlipRoundLib\.FLIP_ROUND_UNIT\s*;/.test(
          body
        ),
        "site 2 must pay every winner the SAME `(units / payCount)` share"
      ).to.equal(true);
      expect(
        /\bextra\b|\bextraStart\b|\bbaseUnits\b/.test(body),
        "site 2 must carry no extra-unit machinery — equal shares are owner-ruled"
      ).to.equal(false);
    });
  });

  describe("§3a: the extra-unit tag is gone from the module entirely", function () {
    it("[01c] `FLIP_EXTRA_UNIT_TAG` is declared nowhere in the jackpot module", function () {
      const source = fs.readFileSync(JACKPOT, "utf8");
      expect(
        /FLIP_EXTRA_UNIT_TAG/.test(stripLineComments(source)),
        "the extra-unit domain separator must be removed with the mechanism it served"
      ).to.equal(false);
    });
  });

  describe("§3b big-leg truncate carries no RNG", function () {
    it("[02a] site 3 `_payGoldenTicket` truncates `flipCredit` to a whole unit", function () {
      const body = bodyOf(JACKPOT, "function _payGoldenTicket(");
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
            `EntropyLib\\.hash2\\(\\s*${site.seed}\\s*[,)]`
          ).test(body),
          `site ${site.n} must key the collapse on a domain-separated hash of \`${site.seed}\``
        ).to.equal(true);
      });
    }

    it("[03e] site 6 carries the collapse delta into `acc.flipMint` so the single flush mints exactly the rounded payout", function () {
      const body = bodyOf(DEGENERETTE, "function _resolveBet(");
      expect(
        /acc\.flipMint\s*\+=\s*rounded\s*-\s*totalPayout\s*;/.test(body),
        "an upward round must add its delta to the accumulator"
      ).to.equal(true);
      expect(
        /acc\.flipMint\s*-=\s*totalPayout\s*-\s*rounded\s*;/.test(body),
        "a downward round must subtract its delta from the accumulator"
      ).to.equal(true);
      // Ordering: the survival flip settles first, so the threshold reads against the
      // number the player actually receives and a lost flip never reaches it.
      const survivalIdx = body.indexOf("EntropyLib.hash2(rngWord, betId)");
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
    it("[04a] `resolveDegeneretteBets` flushes `acc.flipMint` raw — no collapse at the flush", function () {
      const body = bodyOf(DEGENERETTE, "function resolveDegeneretteBets(");
      expect(
        /if\s*\(\s*acc\.flipMint\s*!=\s*0\s*\)\s*coin\.mintForGame\(\s*player\s*,\s*acc\.flipMint\s*\)\s*;/.test(
          body
        ),
        "the flush must mint the bare accumulator"
      ).to.equal(true);
      expect(
        /FlipRoundLib/.test(body),
        "the flush must NOT round: `betIds[]` is caller-composed and settling is permissionless, so rounding the aggregate would let a caller enumerate batch partitions against the already-committed VRF word and take the split with the most round-ups"
      ).to.equal(false);
    });

    it("[04b] the collapse at site 6 keys on the immutable `betId`, not on anything the caller chose", function () {
      const body = bodyOf(DEGENERETTE, "function _resolveBet(");
      expect(
        /EntropyLib\.hash2\(\s*rngWord\s*,\s*uint256\(betId\)\s*\^\s*FLIP_ROUND_TAG\s*\)/.test(
          body
        ),
        "the collapse seed must be `hash2(rngWord, betId ^ FLIP_ROUND_TAG)` — both operands immutable at fulfillment"
      ).to.equal(true);
    });
  });

  describe("Negative gates: the paths deliberately left ragged", function () {
    it("[05a] the mint-boost flip credit stays fractional (D-40N-BUR-MINTBOOST-OUT-01)", function () {
      const body = bodyOf(MINT, "function _purchaseForWithCached(");
      // The buyer credit and the rolled affiliate winner share one Coinflip write, so the
      // mint-boost leg is the first pair of `creditFlipPair` arguments.
      expect(
        /creditFlipPair\(\s*buyer,\s*lootboxFlipCredit\b/.test(body),
        "the mint-boost credit call must still be present (positive pin to the right site)"
      ).to.equal(true);
      expect(
        /FlipRoundLib/.test(body),
        "`_purchaseForWithCached` must apply NO 100-FLIP collapse — the mint-boost path is out of scope"
      ).to.equal(false);
      expect(
        /\/\s*1 ether\s*\)\s*\*\s*1 ether/.test(body),
        "`_purchaseForWithCached` must apply no whole-FLIP floor either"
      ).to.equal(false);
    });

    it("[05b] the degenerette affiliate `refFlip` credit is untouched (owner-ruled out of scope)", function () {
      const body = bodyOf(DEGENERETTE, "function _resolveBet(");
      const refIdx = body.indexOf("uint256 refFlip");
      expect(refIdx, "`refFlip` affiliate credit not found").to.be.greaterThan(
        -1
      );
      // The affiliate credit is emitted from the raw `refFlip * 7 / 100`, with no
      // collapse between its derivation and the credit call.
      const creditIdx = body.indexOf("(refFlip * 7) / 100");
      expect(creditIdx).to.be.greaterThan(refIdx);
      const between = body.slice(refIdx, creditIdx);
      expect(
        /FlipRoundLib/.test(between),
        "no collapse may be applied to the affiliate credit — every affiliate FLIP path is out of scope"
      ).to.equal(false);
    });
  });

  describe("Invariant sweep: every in-scope award lands on a 100-FLIP multiple", function () {
    const N = 2_000;

    it(`[06a] §3a sweep: every paid share is an identical whole unit and the total never overshoots (N=${N})`, function () {
      // Deterministic LCG over budgets — no RNG dependency, no flake.
      let x = 123456789n;
      const next = (mod) => {
        x = (x * 6364136223846793005n + 1442695040888963407n) % (1n << 64n);
        return (x >> 17n) % mod;
      };
      for (let k = 0; k < N; k++) {
        const budget = ONE_FLIP * (next(2_000_000n) + 1n);
        const maxWinners = k % 2 === 0 ? 50n : 10n; // near-future cap / far-future `found`
        const { units, cap, amount, leftover } = splitUnits(budget, maxWinners);
        if (cap === 0n) {
          expect(budget < UNIT).to.equal(
            true,
            "only a sub-unit budget may pay nobody"
          );
          continue;
        }
        expect(amount % UNIT).to.equal(0n, `share ${amount} is not a unit multiple`);
        expect(amount >= UNIT).to.equal(true, "no share may be zero");

        const spent = cap * amount;
        expect(spent <= budget).to.equal(true, "the budget is never overshot");
        expect(leftover).to.equal(units % cap, "leftover is the uneven-division remainder");
        expect(leftover < cap).to.equal(
          true,
          "the leftover is always under one full round of shares"
        );
        // Everything unminted is the leftover units plus the sub-unit dust.
        expect(budget - spent).to.equal(leftover * UNIT + (budget - units * UNIT));
      }
    });

    it(`[06b] §3c sweep: above the threshold every award is a whole unit; at or below it every award is floored to whole FLIP (N=${N})`, function () {
      let x = 987654321n;
      const next = (mod) => {
        x = (x * 6364136223846793005n + 1442695040888963407n) % (1n << 64n);
        return (x >> 17n) % mod;
      };
      for (let k = 0; k < N; k++) {
        // Sweep across the threshold, in wei so sub-1-FLIP dust is exercised too.
        const amount = next(5_000_000n * ONE_FLIP) + next(ONE_FLIP);
        const slice = next(100n);
        const paid = jsRoundGated(amount, slice);
        if (amount <= THRESHOLD) {
          expect(paid).to.equal(
            (amount / ONE_FLIP) * ONE_FLIP,
            `award ${amount} at or below the threshold must be floored to whole FLIP`
          );
          expect(paid % ONE_FLIP).to.equal(
            0n,
            `award ${amount} paid ${paid}, which carries wei-scale residue`
          );
          expect(paid <= amount).to.equal(
            true,
            `the floor must never pay more than the raw award ${amount}`
          );
        } else {
          expect(paid % UNIT).to.equal(
            0n,
            `award ${amount} collapsed to ${paid}, not a unit multiple`
          );
          const delta = paid > amount ? paid - amount : amount - paid;
          expect(delta < UNIT).to.equal(
            true,
            `the collapse moved ${amount} by ${delta}, a full unit or more`
          );
        }
      }
    });

    it("[06c] §3b sweep: the golden-ticket truncate is a pure floor and never overpays", function () {
      let x = 555555555n;
      const next = (mod) => {
        x = (x * 6364136223846793005n + 1442695040888963407n) % (1n << 64n);
        return (x >> 17n) % mod;
      };
      for (let k = 0; k < N; k++) {
        const credit = next(10_000_000n * ONE_FLIP);
        const truncated = (credit / UNIT) * UNIT;
        expect(truncated % UNIT).to.equal(0n);
        expect(truncated <= credit).to.equal(
          true,
          "a truncate may never pay more than the raw credit"
        );
        expect(credit - truncated < UNIT).to.equal(
          true,
          "a truncate may never discard a full unit or more"
        );
      }
    });
  });
});
