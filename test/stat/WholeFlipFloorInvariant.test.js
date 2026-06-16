// SPDX-License-Identifier: AGPL-3.0-only
//
// WholeFlipFloorInvariant.test.js — Phase 279 Wave 2 TST-BUR-04
//
// Whole-FLIP floor invariant sweep across all 3 RNG-amount FLIP-award
// sites, plus a negative cross-site assertion that the mint-boost flip-credit
// path stayed status-quo fractional.
//
// THE INVARIANT:
//   Every observable FLIP-mint amount producible from the 3 BUR sites —
//     BUR-01  `_settleLootboxRoll`            (DegenerusGameLootboxModule.sol)
//     BUR-02  `_awardDailyCoinToTraitWinners` (DegenerusGameJackpotModule.sol)
//     BUR-03  `_awardFarFutureCoinJackpot`    (DegenerusGameJackpotModule.sol)
//   — is a multiple of `1 ether` after the inline `(x / 1 ether) * 1 ether`
//   integer-division floor (D-279-INLINE-01). This is a DETERMINISTIC FLOOR
//   invariant — `amount % (10n ** 18n) === 0n` — NOT EV-neutrality: the BUR
//   floor is not a probabilistic primitive, so there is NO chi-square /
//   Wilson-Hilferty here. The sweep uses the `makeRng` deterministic seeded
//   keccak-counter PRNG (fixed seed → reproducible input sequence) purely to
//   generate representative input variance; a failure is a real failure,
//   never flake.
//
// NEGATIVE CROSS-SITE ASSERTION (D-40N-BUR-MINTBOOST-OUT-01):
//   The mint-boost flip-credit `coinflip.creditFlip(buyer, lootboxFlipCredit)`
//   inside `_purchaseForWithCached` (DegenerusGameMintModule.sol) — is explicitly OUT
//   of v40.0 BUR scope: `lootboxFlipCredit` is a deterministic
//   mint-amount-derived value, NOT an RNG amount, and stays status-quo
//   fractional. This test proves NO whole-FLIP floor was added to that path.
//
// TEST STRATEGY:
//   The 3 BUR sites are all `private` with a documented fixture-coverage gap
//   (no deterministic full-state harness). Per the
//   `JackpotTicketRollSilentColdBust.test.js` fixture-coverage-gap precedent,
//   the load-bearing evidence is source-level structural proof (`extractBody`
//   + `stripLineComments` + regex), combined here into a single cross-site
//   gate. The JS sweep applying the floor to representative inputs is the
//   confirmation layer.
//
// CROSS-CITES:
//   - D-279-INLINE-01 (inline `(x / 1 ether) * 1 ether` floor at all 3 sites)
//   - D-40N-BUR-MINTBOOST-OUT-01 (mint-boost flip-credit OUT of BUR scope)
//   - test/stat/LootboxBernoulliEv.test.js (the `makeRng` keccak-counter PRNG)
//   - test/unit/JackpotTicketRollSilentColdBust.test.js (extractBody + stripLineComments infra)

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";

const ONE_ETHER = 10n ** 18n;

const LOOTBOX_MODULE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
);
const JACKPOT_MODULE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameJackpotModule.sol"
);
const MINT_MODULE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameMintModule.sol"
);

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

// Strip `//` line comments so structural greps do not self-invalidate on
// comment prose (copied from test/unit/JackpotTicketRollSilentColdBust.test.js).
function stripLineComments(body) {
  return body
    .split("\n")
    .map((line) => {
      const idx = line.indexOf("//");
      return idx >= 0 ? line.slice(0, idx) : line;
    })
    .join("\n");
}

// Deterministic seeded keccak-counter PRNG (copied from
// test/stat/LootboxBernoulliEv.test.js).
function makeRng(seedHex) {
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

// The whole-FLIP floor as applied on-chain: `(x / 1 ether) * 1 ether`.
function floorWholeFlip(x) {
  return (x / ONE_ETHER) * ONE_ETHER;
}

describe("WholeFlipFloorInvariant (stat-suite) — Phase 279 Wave 2 TST-BUR-04", function () {
  this.timeout(120_000);

  describe("Whole-FLIP floor invariant sweep: every floored BUR-site amount is a multiple of 1 ether", function () {
    const N = 20_000;

    it(`[01a] BUR-01 sweep: representative post-bonus flipAmount accumulators floor to whole-FLIP multiples (N=${N})`, function () {
      // Representative variance-roll FLIP accumulator amounts: spin FLIP is
      // an arbitrary wei accumulator (flipNoMultiplier + flipPresale +
      // bonusFlip), bounded but not 1-ether-aligned. Sweep arbitrary wei
      // values in [0, ~50 FLIP) and assert the floor invariant.
      const rng = makeRng("0x" + "279b04a01".padStart(64, "0"));
      for (let i = 0; i < N; i++) {
        const flipAmount = rng() % (ONE_ETHER * 50n);
        const floored = floorWholeFlip(flipAmount);
        expect(
          floored % ONE_ETHER,
          `BUR-01: floored flipAmount ${floored} (from ${flipAmount}) is not a 1-ether multiple`
        ).to.equal(0n);
        expect(
          floored <= flipAmount,
          `BUR-01: floor must never increase the amount (${floored} > ${flipAmount})`
        ).to.equal(true);
        expect(
          flipAmount - floored < ONE_ETHER,
          `BUR-01: residue must be strictly < 1 FLIP (${flipAmount - floored})`
        ).to.equal(true);
      }
    });

    it(`[01b] BUR-02 sweep: representative (coinBudget, cap) pairs floor baseAmount to whole-FLIP multiples (N=${N})`, function () {
      // baseAmount = ((coinBudget / cap) / 1 ether) * 1 ether. Sweep
      // representative coinBudget in [0, ~10000 FLIP) and cap in [1, 100].
      const rng = makeRng("0x" + "279b04a02".padStart(64, "0"));
      for (let i = 0; i < N; i++) {
        const coinBudget = rng() % (ONE_ETHER * 10_000n);
        const cap = (rng() % 100n) + 1n;
        const baseAmount = floorWholeFlip(coinBudget / cap);
        expect(
          baseAmount % ONE_ETHER,
          `BUR-02: floored baseAmount ${baseAmount} (coinBudget=${coinBudget}, cap=${cap}) is not a 1-ether multiple`
        ).to.equal(0n);
        expect(
          baseAmount <= coinBudget / cap,
          `BUR-02: floor must never increase the per-winner share`
        ).to.equal(true);
      }
    });

    it(`[01c] BUR-03 sweep: representative (farBudget, found) pairs floor perWinner to whole-FLIP multiples (N=${N})`, function () {
      // perWinner = ((farBudget / found) / 1 ether) * 1 ether. Sweep
      // representative farBudget in [0, ~5000 FLIP) and found in [1, 10].
      const rng = makeRng("0x" + "279b04a03".padStart(64, "0"));
      for (let i = 0; i < N; i++) {
        const farBudget = rng() % (ONE_ETHER * 5_000n);
        const found = (rng() % 10n) + 1n;
        const perWinner = floorWholeFlip(farBudget / found);
        expect(
          perWinner % ONE_ETHER,
          `BUR-03: floored perWinner ${perWinner} (farBudget=${farBudget}, found=${found}) is not a 1-ether multiple`
        ).to.equal(0n);
        expect(
          perWinner <= farBudget / found,
          `BUR-03: floor must never increase the per-winner share`
        ).to.equal(true);
      }
    });
  });

  describe("3-site source-structural combined gate: all 3 BUR sites carry the inline whole-FLIP floor", function () {
    it("[02a] BUR-01 `_settleLootboxRoll` floors this roll's `flipOut` into `flipAmount`", function () {
      const source = fs.readFileSync(LOOTBOX_MODULE_PATH, "utf8");
      // The per-roll floor moved into `_settleLootboxRoll` (the refactor split
      // the per-roll ticket/FLIP/emit logic out of `_resolveLootboxCommon`).
      // The floor now derives `flipAmount` from this roll's raw `flipOut`.
      const body = stripLineComments(
        extractBody(source, "function _settleLootboxRoll(")
      );
      expect(body, "`_settleLootboxRoll` body not found").to.not.equal(null);
      expect(
        /flipAmount\s*=\s*\(\s*flipOut\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/.test(
          body
        ),
        "BUR-01: `_settleLootboxRoll` must floor this roll's `flipOut` via `(flipOut / 1 ether) * 1 ether`"
      ).to.equal(true);
    });

    it("[02b] BUR-02 `_awardDailyCoinToTraitWinners` floors `baseAmount`", function () {
      const source = fs.readFileSync(JACKPOT_MODULE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _awardDailyCoinToTraitWinners(")
      );
      expect(body, "`_awardDailyCoinToTraitWinners` body not found").to.not.equal(null);
      expect(
        /baseAmount\s*=\s*\(\s*\(\s*coinBudget\s*\/\s*cap\s*\)\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/.test(
          body
        ),
        "BUR-02: `_awardDailyCoinToTraitWinners` must floor `baseAmount` via `((coinBudget / cap) / 1 ether) * 1 ether`"
      ).to.equal(true);
    });

    it("[02c] BUR-03 `_awardFarFutureCoinJackpot` floors `perWinner`", function () {
      const source = fs.readFileSync(JACKPOT_MODULE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _awardFarFutureCoinJackpot(")
      );
      expect(body, "`_awardFarFutureCoinJackpot` body not found").to.not.equal(null);
      expect(
        /perWinner\s*=\s*\(\s*\(\s*farBudget\s*\/\s*found\s*\)\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/.test(
          body
        ),
        "BUR-03: `_awardFarFutureCoinJackpot` must floor `perWinner` via `((farBudget / found) / 1 ether) * 1 ether`"
      ).to.equal(true);
    });
  });

  describe("Negative cross-site assertion: the mint-boost flip-credit path stayed status-quo fractional (D-40N-BUR-MINTBOOST-OUT-01)", function () {
    it("[03a] `_purchaseForWithCached` in DegenerusGameMintModule.sol contains `creditFlip(buyer, lootboxFlipCredit)` (positive pin to the right call site)", function () {
      const source = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      // The flip-credit accumulator + creditFlip lives in `_purchaseForWithCached`
      // (the shared purchase body; `_purchaseFor` / `_purchaseForWith` are thin
      // wrappers that resolve cost inputs and forward); the pin follows it there.
      const body = stripLineComments(
        extractBody(source, "function _purchaseForWithCached(")
      );
      expect(body, "`_purchaseForWithCached` body not found").to.not.equal(null);
      expect(
        body.includes("creditFlip(buyer, lootboxFlipCredit)"),
        "`_purchaseForWithCached` must contain `creditFlip(buyer, lootboxFlipCredit)` — the mint-boost flip-credit call site (positive pin)"
      ).to.equal(true);
    });

    it("[03b] `_purchaseForWithCached` applies NO whole-FLIP floor to `lootboxFlipCredit` — the mint-boost path is OUT of v40.0 BUR scope (D-40N-BUR-MINTBOOST-OUT-01)", function () {
      const source = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _purchaseForWithCached(")
      );
      expect(body, "`_purchaseForWithCached` body not found").to.not.equal(null);
      // No `(... / 1 ether) * 1 ether` floor expression anywhere in the
      // function body — the mint-boost flip-credit stays status-quo fractional.
      expect(
        /\/\s*1 ether\s*\)\s*\*\s*1 ether/.test(body),
        "`_purchaseForWithCached` must NOT apply a `/ 1 ether) * 1 ether` whole-FLIP floor (mint-boost is OUT of BUR scope — D-40N-BUR-MINTBOOST-OUT-01)"
      ).to.equal(false);
      // Specifically, `lootboxFlipCredit` is never reassigned through a floor.
      expect(
        /lootboxFlipCredit\s*=\s*\(\s*lootboxFlipCredit\s*\/\s*1 ether/.test(body),
        "`lootboxFlipCredit` must NOT be reassigned through a whole-FLIP floor"
      ).to.equal(false);
    });
  });
});
