// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxDgnrsSigFigs.test.js — three-significant-figure collapse on both DGNRS box legs.
//
// The DGNRS counterpart to the 100-FLIP granule. A FIXED granule cannot work here: both
// box legs price against a LIVE pool balance (`dgnrs.poolBalance(...)`), so the award
// spans orders of magnitude over a game's life and any constant step would be the entire
// prize at the small end and invisible at the large end. Three significant figures is
// scale-free — round-looking at every magnitude, and never a full 1% of the award (the
// discarded tail is under one unit in the third figure, so the relative cost is under
// 1/mantissa: worst case 1/100, best case 1/999).
//
//   SITE A — `_presaleBoxDgnrsReward`   (the presale box's 40% DGNRS branch)
//   SITE B — `_lootboxDgnrsReward`      (the lootbox DGNRS leg)
//
// OWNER-RULED (2026-08-06):
//   - SCOPE: the two box legs only. The AdvanceModule affiliate-pool DGNRS reward is NOT
//     collapsed, matching the standing ruling that every affiliate path stays out of the
//     award-rounding work. [03a] pins that negatively.
//   - FORM: a plain truncate. No entropy is threaded anywhere, so this adds nothing to the
//     RNG-window ledger and the collapse cannot be steered by anyone.
//
// ORDERING AT SITE B is load-bearing and asserted below: the collapse runs BEFORE the
// `dgnrsAmount > poolBalance` clamp. Collapsing after the clamp would truncate the pool
// balance itself and leave dust permanently unpayable at the bottom of the pool.
//
// CROSS-CITES:
//   - contracts/libraries/SigFigLib.sol
//   - .planning/PLAN-FLIP-ROUND-HUNDREDS.md (the FLIP-side granule this mirrors)

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const SRC = (rel) => path.resolve(process.cwd(), rel);
const LOOTBOX = SRC("contracts/modules/DegenerusGameLootboxModule.sol");
const ADVANCE = SRC("contracts/modules/DegenerusGameAdvanceModule.sol");
const LIB = SRC("contracts/libraries/SigFigLib.sol");

function extractBody(source, signature) {
  const fnIdx = source.indexOf(signature);
  if (fnIdx < 0) return null;
  let depth = 0;
  let bodyStart = -1;
  for (let i = fnIdx; i < source.length; i++) {
    if (source[i] === "{") {
      if (depth === 0) bodyStart = i;
      depth++;
    } else if (source[i] === "}") {
      depth--;
      if (depth === 0) return source.slice(bodyStart, i + 1);
    }
  }
  return null;
}

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
  const body = extractBody(fs.readFileSync(file, "utf8"), signature);
  expect(body, `\`${signature}\` body not found in ${file}`).to.not.equal(null);
  return stripLineComments(body);
}

// The on-chain collapse, replicated exactly.
function floorToThreeSigFigs(amount) {
  let scale = 1n;
  let mantissa = amount;
  while (mantissa >= 1000n) {
    mantissa /= 10n;
    scale *= 10n;
  }
  return mantissa * scale;
}

describe("LootboxDgnrsSigFigs — 3-significant-figure collapse on the DGNRS box legs", function () {
  this.timeout(30_000);

  describe("The primitive", function () {
    it("[00a] `SigFigLib.floorToThreeSigFigs` is a pure floor with no entropy parameter", function () {
      const source = fs.readFileSync(LIB, "utf8");
      const declStart = source.indexOf("function floorToThreeSigFigs");
      expect(declStart, "`floorToThreeSigFigs` not found").to.be.greaterThan(-1);
      const decl = source.slice(declStart, source.indexOf("{", declStart));
      expect(
        /\bpure\b/.test(decl),
        "the primitive must be `pure`"
      ).to.equal(true);
      expect(
        /entropy|seed|random/i.test(decl),
        "the collapse must take NO entropy — it is a deterministic truncate"
      ).to.equal(false);
      expect(
        /\(\s*uint256\s+amount\s*\)/.test(decl),
        "the primitive must take exactly one argument"
      ).to.equal(true);
    });
  });

  describe("Site structure", function () {
    it("[01a] site A `_presaleBoxDgnrsReward` collapses its award", function () {
      const body = bodyOf(LOOTBOX, "function _presaleBoxDgnrsReward(");
      expect(
        /SigFigLib\.floorToThreeSigFigs\(/.test(body),
        "the presale DGNRS branch must collapse via `SigFigLib.floorToThreeSigFigs`"
      ).to.equal(true);
      // The collapse wraps the derivation, so no un-collapsed figure can reach the payout.
      expect(
        /uint256\s+dgnrsAmount\s*=\s*SigFigLib\.floorToThreeSigFigs\(/.test(body),
        "`dgnrsAmount` must be assigned the COLLAPSED figure, not collapsed afterwards"
      ).to.equal(true);
    });

    it("[01b] site B `_lootboxDgnrsReward` collapses BEFORE the pool clamp", function () {
      const body = bodyOf(LOOTBOX, "function _lootboxDgnrsReward(");
      const collapseIdx = body.indexOf("SigFigLib.floorToThreeSigFigs(");
      const clampIdx = body.search(
        /if\s*\(\s*dgnrsAmount\s*>\s*poolBalance\s*\)/
      );
      expect(collapseIdx, "the collapse not found").to.be.greaterThan(-1);
      expect(clampIdx, "the `> poolBalance` clamp not found").to.be.greaterThan(
        -1
      );
      expect(
        collapseIdx,
        "the collapse must precede the pool clamp — collapsing the CLAMPED figure would truncate the pool balance itself and strand dust at the bottom of the pool forever"
      ).to.be.lessThan(clampIdx);
    });
  });

  describe("Negative gate: the affiliate DGNRS path stays ragged (owner-ruled out of scope)", function () {
    it("[03a] the AdvanceModule affiliate-pool DGNRS reward is NOT collapsed", function () {
      const source = stripLineComments(fs.readFileSync(ADVANCE, "utf8"));
      expect(
        /dgnrsReward\s*=\s*\(\s*poolBalance\s*\*\s*AFFILIATE_POOL_REWARD_BPS\s*\)/.test(
          source
        ),
        "the affiliate DGNRS reward derivation must still be present (positive pin to the right site)"
      ).to.equal(true);
      expect(
        /SigFigLib/.test(source),
        "AdvanceModule must not import or apply the collapse — every affiliate path is out of scope"
      ).to.equal(false);
    });
  });

  describe("JS collapse math (confirmation layer)", function () {
    it("zeroes every digit past the third", function () {
      const cases = [
        [0n, 0n],
        [1n, 1n],
        [999n, 999n],
        [1000n, 1000n],
        [1001n, 1000n],
        [1999n, 1990n],
        [123456n, 123000n],
        [999999n, 999000n],
        [1_234_567_890_123_456_789n, 1_230_000_000_000_000_000n],
      ];
      for (const [input, expected] of cases) {
        expect(floorToThreeSigFigs(input)).to.equal(
          expected,
          `floorToThreeSigFigs(${input})`
        );
      }
    });

    it("is a pure floor — never pays more than the raw award, never a full 1% less", function () {
      let x = 42n;
      const next = () => {
        x = (x * 6364136223846793005n + 1442695040888963407n) % (1n << 64n);
        return x >> 5n;
      };
      for (let k = 0; k < 20_000; k++) {
        const raw = next() * (k % 7 === 0 ? 1_000_000_000n : 1n);
        const collapsed = floorToThreeSigFigs(raw);
        expect(collapsed <= raw).to.equal(
          true,
          `collapse of ${raw} paid ${collapsed}, more than the raw award`
        );
        if (raw >= 1000n) {
          // Strictly under 1%: the discarded tail is below one unit in the third figure,
          // and the mantissa is at least 100, so the relative cost is under 1/100.
          expect((raw - collapsed) * 100n < raw).to.equal(
            true,
            `collapse of ${raw} discarded ${raw - collapsed}, at or over 1%`
          );
        } else {
          expect(collapsed).to.equal(raw, "sub-1,000 awards pass through exactly");
        }
      }
    });

    it("always leaves at most three significant digits", function () {
      let x = 7n;
      for (let k = 0; k < 20_000; k++) {
        x = (x * 6364136223846793005n + 1442695040888963407n) % (1n << 64n);
        const collapsed = floorToThreeSigFigs(x);
        const digits = collapsed.toString().replace(/0+$/, "");
        expect(digits.length <= 3).to.equal(
          true,
          `collapse of ${x} gave ${collapsed}, which carries ${digits.length} significant digits`
        );
      }
    });
  });
});
