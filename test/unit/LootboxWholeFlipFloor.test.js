// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxWholeFlipFloor.test.js — Phase 279 Wave 2 TST-BUR-01
//
// Whole-FLIP floor regression on the lootbox-spin FLIP-award site.
//   `_resolveLootboxCommon` in `contracts/modules/DegenerusGameLootboxModule.sol`
//   floors the post-bonus `flipAmount` accumulator to a whole-FLIP multiple
//   (1 FLIP = 1 ether) via inline integer-division floor — `(flipAmount /
//   1 ether) * 1 ether` — before the `if (flipAmount != 0)` guard and the
//   `coinflip.creditFlip(player, flipAmount)` call. The floored value is the
//   single accumulator local, so the `creditFlip` arg, the `LootBoxOpened.flip`
//   event field, and the return tuple all carry the floored amount with no
//   separate pre-floor snapshot.
//
// TEST STRATEGY:
//   The 3 BUR sites have a documented fixture-coverage gap — no deterministic
//   full-state fixture exists for `_resolveLootboxCommon` at the granularity
//   required (level + day + sDGNRS staking + presale state + VRF mock). Per the
//   LBX-02 / `JackpotTicketRollSilentColdBust.test.js` fixture-coverage-gap
//   precedent, the load-bearing evidence is source-level structural proof:
//   `extractBody` + `stripLineComments` + regex + index-ordering. JS-side
//   BigInt boundary math on the floor function `(x / 1e18) * 1e18` is the
//   confirmation layer.
//
// CROSS-CITES:
//   - D-279-INLINE-01 (inline `(x / 1 ether) * 1 ether` floor — no shared helper)
//   - D-279-BUR01-SITE-01 (floor the final post-bonus accumulator once)
//   - D-40N-BUR-DUST-01 (sub-1-FLIP residue evaporates)
//   - D-40N-BUR-SILENT-01 (no consolation / replacement event / redistribution)
//   - test/unit/LootboxWholeTicket.test.js (same `_resolveLootboxCommon` function)
//   - test/unit/JackpotTicketRollSilentColdBust.test.js (extractBody + stripLineComments infra)

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

const ONE_ETHER = 10n ** 18n;

const MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
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

// The whole-FLIP floor as applied on-chain: `(x / 1 ether) * 1 ether`.
function floorWholeFlip(x) {
  return (x / ONE_ETHER) * ONE_ETHER;
}

describe("LootboxWholeFlipFloor — Phase 279 Wave 2 TST-BUR-01", function () {
  this.timeout(30_000);

  describe("Source-structural proof: `_settleLootboxRoll` floors this roll's `flipOut` before the `!= 0` guard and the `creditFlip` call", function () {
    it("[01a] body contains the inline whole-FLIP floor expression `flipAmount = (flipOut / 1 ether) * 1 ether`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _settleLootboxRoll(")
      );
      expect(body, "`_settleLootboxRoll` body not found").to.not.equal(null);
      // Whitespace-tolerant: `flipAmount = ( flipOut / 1 ether ) * 1 ether`.
      const floorPattern =
        /flipAmount\s*=\s*\(\s*flipOut\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/;
      expect(
        floorPattern.test(body),
        "`_settleLootboxRoll` must floor this roll's `flipOut` via `(flipOut / 1 ether) * 1 ether` (D-279-INLINE-01 / D-279-BUR01-SITE-01)"
      ).to.equal(true);
    });

    it("[01b] index-ordering: the floor expression precedes the `if (flipAmount != 0)` guard, which precedes the `coinflip.creditFlip(player, flipAmount)` call", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _settleLootboxRoll(")
      );
      expect(body, "`_settleLootboxRoll` body not found").to.not.equal(null);

      const floorIdx = body.search(
        /flipAmount\s*=\s*\(\s*flipOut\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/
      );
      const guardIdx = body.search(/if\s*\(\s*flipAmount\s*!=\s*0\s*\)/);
      const creditIdx = body.indexOf(
        "coinflip.creditFlip(player, flipAmount)"
      );

      expect(floorIdx, "floor expression not found").to.be.greaterThan(-1);
      expect(guardIdx, "`if (flipAmount != 0)` guard not found").to.be.greaterThan(-1);
      expect(
        creditIdx,
        "`coinflip.creditFlip(player, flipAmount)` call not found"
      ).to.be.greaterThan(-1);

      expect(
        floorIdx,
        "the floor must precede the `if (flipAmount != 0)` guard so a sub-1-FLIP roll floors to 0 BEFORE the guard"
      ).to.be.lessThan(guardIdx);
      expect(
        guardIdx,
        "the `if (flipAmount != 0)` guard must precede the `creditFlip` call"
      ).to.be.lessThan(creditIdx);
    });

    it("[01c] the floor is derived once from this roll's raw `flipOut` draw — per-roll, no cross-roll accumulator", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _settleLootboxRoll(")
      );
      expect(body, "`_settleLootboxRoll` body not found").to.not.equal(null);

      // Post-refactor each roll settles independently: `flipOut` is the single
      // value `_resolveLootboxRoll` returns for THIS roll, floored once. The draw
      // producing `flipOut` must precede the floor (the floor floors that draw).
      const drawIdx = body.search(/\(\s*uint256 flipOut\s*,/);
      const floorIdx = body.search(
        /flipAmount\s*=\s*\(\s*flipOut\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/
      );
      expect(drawIdx, "`flipOut` reward draw not found").to.be.greaterThan(-1);
      expect(floorIdx, "floor expression not found").to.be.greaterThan(-1);
      expect(
        drawIdx,
        "the reward draw producing `flipOut` must precede the floor"
      ).to.be.lessThan(floorIdx);
    });
  });

  describe("Field-consistency: `LootBoxOpened` reads the bare floored `flipAmount` local — no separate pre-floor snapshot", function () {
    it("[02a] the `LootBoxOpened` emit carries `flipAmount` as its 6th positional arg, and no other floored/unfloored `flip*` snapshot is introduced between the floor and the emit", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _settleLootboxRoll(")
      );
      expect(body, "`_settleLootboxRoll` body not found").to.not.equal(null);

      // The emit threads `flipAmount` as its 6th positional arg (the per-roll
      // 7-arg signature, `day` dropped in 4cb9ccbf: player, index, fullAmount,
      // rollLevel, scaledTickets, flipAmount, roundedUp).
      const emitMatch = body.match(/emit LootBoxOpened\(([\s\S]*?)\);/);
      expect(emitMatch, "`LootBoxOpened` emit not found").to.not.equal(null);
      const emitArgs = emitMatch[1]
        .split(",")
        .map((a) => a.trim())
        .filter((a) => a.length > 0);
      expect(
        emitArgs.length,
        "`LootBoxOpened` emit must supply 7 positional args"
      ).to.equal(7);
      expect(
        emitArgs[5],
        "the 6th `LootBoxOpened` arg must be the bare floored `flipAmount` local"
      ).to.equal("flipAmount");

      // Between the floor and the emit, `flipAmount` is the only `flip*`
      // amount local in play — no `flipFloored`, `flipPreFloor`,
      // `flipSnapshot`, etc. is introduced.
      const floorIdx = body.search(
        /flipAmount\s*=\s*\(\s*flipOut\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/
      );
      const emitIdx = body.indexOf("emit LootBoxOpened(");
      expect(floorIdx, "floor expression not found").to.be.greaterThan(-1);
      expect(emitIdx, "`LootBoxOpened` emit not found").to.be.greaterThan(floorIdx);
      const span = body.slice(floorIdx, emitIdx);
      // No new `uint256 flip...` / `uint... flip...` declaration in the span.
      const newFlipDecl = /\buint\d*\s+flip\w+\s*=/.exec(span);
      expect(
        newFlipDecl,
        `no new flip* snapshot variable may be declared between the floor and the emit (found: ${
          newFlipDecl ? newFlipDecl[0] : "none"
        })`
      ).to.equal(null);
    });

    it("[02b] the floored `flipAmount` local is the single source of truth — it feeds the `creditFlip`, and `_settleLootboxRoll` is void (no return tuple re-introduces an unfloored snapshot)", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _settleLootboxRoll(")
      );
      expect(body, "`_settleLootboxRoll` body not found").to.not.equal(null);
      expect(
        body.indexOf("coinflip.creditFlip(player, flipAmount)"),
        "`creditFlip` must use the bare floored `flipAmount` local"
      ).to.be.greaterThan(-1);
      expect(
        /return\s*\(/.test(body),
        "`_settleLootboxRoll` is void — no return tuple carrying a FLIP snapshot"
      ).to.equal(false);
    });
  });

  describe("JS boundary math: `(x / 1 ether) * 1 ether` floor cases (confirmation layer)", function () {
    const CASES = [
      { label: "0.99 FLIP", input: (ONE_ETHER * 99n) / 100n, expected: 0n },
      { label: "1.99 FLIP", input: (ONE_ETHER * 199n) / 100n, expected: ONE_ETHER },
      { label: "2.00 FLIP", input: ONE_ETHER * 2n, expected: ONE_ETHER * 2n },
      { label: "0 FLIP", input: 0n, expected: 0n },
    ];

    CASES.forEach(({ label, input, expected }) => {
      it(`floors ${label} (${input} wei) to ${expected} wei`, function () {
        expect(floorWholeFlip(input)).to.equal(expected);
      });
    });

    it("the floored result is always a whole-FLIP multiple (`% 1 ether == 0`) across the boundary table", function () {
      for (const { input } of CASES) {
        expect(floorWholeFlip(input) % ONE_ETHER).to.equal(0n);
      }
    });
  });
});
