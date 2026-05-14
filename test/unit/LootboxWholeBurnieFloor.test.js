// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxWholeBurnieFloor.test.js — Phase 279 Wave 2 TST-BUR-01
//
// Whole-BURNIE floor regression on the lootbox-spin BURNIE-award site.
//   `_resolveLootboxCommon` in `contracts/modules/DegenerusGameLootboxModule.sol`
//   floors the post-bonus `burnieAmount` accumulator to a whole-BURNIE multiple
//   (1 BURNIE = 1 ether) via inline integer-division floor — `(burnieAmount /
//   1 ether) * 1 ether` — before the `if (burnieAmount != 0)` guard and the
//   `coinflip.creditFlip(player, burnieAmount)` call. The floored value is the
//   single accumulator local, so the `creditFlip` arg, the `LootBoxOpened.burnie`
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
//   - D-40N-BUR-DUST-01 (sub-1-BURNIE residue evaporates)
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

// The whole-BURNIE floor as applied on-chain: `(x / 1 ether) * 1 ether`.
function floorWholeBurnie(x) {
  return (x / ONE_ETHER) * ONE_ETHER;
}

describe("LootboxWholeBurnieFloor — Phase 279 Wave 2 TST-BUR-01", function () {
  this.timeout(30_000);

  describe("Source-structural proof: `_resolveLootboxCommon` floors `burnieAmount` before the `!= 0` guard and the `creditFlip` call", function () {
    it("[01a] body contains the inline whole-BURNIE floor expression `burnieAmount = (burnieAmount / 1 ether) * 1 ether`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _resolveLootboxCommon(")
      );
      expect(body, "`_resolveLootboxCommon` body not found").to.not.equal(null);
      // Whitespace-tolerant: `burnieAmount = ( burnieAmount / 1 ether ) * 1 ether`.
      const floorPattern =
        /burnieAmount\s*=\s*\(\s*burnieAmount\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/;
      expect(
        floorPattern.test(body),
        "`_resolveLootboxCommon` must floor `burnieAmount` via `(burnieAmount / 1 ether) * 1 ether` (D-279-INLINE-01 / D-279-BUR01-SITE-01)"
      ).to.equal(true);
    });

    it("[01b] index-ordering: the floor expression precedes the `if (burnieAmount != 0)` guard, which precedes the `coinflip.creditFlip(player, burnieAmount)` call", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _resolveLootboxCommon(")
      );
      expect(body, "`_resolveLootboxCommon` body not found").to.not.equal(null);

      const floorIdx = body.search(
        /burnieAmount\s*=\s*\(\s*burnieAmount\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/
      );
      const guardIdx = body.search(/if\s*\(\s*burnieAmount\s*!=\s*0\s*\)/);
      const creditIdx = body.indexOf(
        "coinflip.creditFlip(player, burnieAmount)"
      );

      expect(floorIdx, "floor expression not found").to.be.greaterThan(-1);
      expect(guardIdx, "`if (burnieAmount != 0)` guard not found").to.be.greaterThan(-1);
      expect(
        creditIdx,
        "`coinflip.creditFlip(player, burnieAmount)` call not found"
      ).to.be.greaterThan(-1);

      expect(
        floorIdx,
        "the floor must precede the `if (burnieAmount != 0)` guard so a sub-1-BURNIE accumulator floors to 0 BEFORE the guard"
      ).to.be.lessThan(guardIdx);
      expect(
        guardIdx,
        "the `if (burnieAmount != 0)` guard must precede the `creditFlip` call"
      ).to.be.lessThan(creditIdx);
    });

    it("[01c] the floor precedes the `bonusBurnie` accumulation read — it floors the FINAL post-bonus accumulator, not a per-component value", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _resolveLootboxCommon(")
      );
      expect(body, "`_resolveLootboxCommon` body not found").to.not.equal(null);

      // The `burnieAmount += bonusBurnie;` accumulation must come BEFORE the
      // floor — proving the floor is applied once to the FINAL post-bonus
      // accumulator (D-279-BUR01-SITE-01), not per-component.
      const bonusAddIdx = body.indexOf("burnieAmount += bonusBurnie;");
      const floorIdx = body.search(
        /burnieAmount\s*=\s*\(\s*burnieAmount\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/
      );
      expect(bonusAddIdx, "`burnieAmount += bonusBurnie;` not found").to.be.greaterThan(-1);
      expect(floorIdx, "floor expression not found").to.be.greaterThan(-1);
      expect(
        bonusAddIdx,
        "the presale-bonus accumulation must precede the floor (the floor floors the FINAL post-bonus accumulator once)"
      ).to.be.lessThan(floorIdx);
    });
  });

  describe("Field-consistency: `LootBoxOpened` reads the bare floored `burnieAmount` local — no separate pre-floor snapshot", function () {
    it("[02a] the `LootBoxOpened` emit carries `burnieAmount` as its 7th positional arg, and no other floored/unfloored `burnie*` snapshot is introduced between the floor and the emit", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _resolveLootboxCommon(")
      );
      expect(body, "`_resolveLootboxCommon` body not found").to.not.equal(null);

      // The emit threads `burnieAmount` as its 7th positional arg (the
      // post-Phase-277 signature: player, index, day, amount, targetLevel,
      // futureTickets, burnieAmount, roundedUp).
      const emitMatch = body.match(/emit LootBoxOpened\(([\s\S]*?)\);/);
      expect(emitMatch, "`LootBoxOpened` emit not found").to.not.equal(null);
      const emitArgs = emitMatch[1]
        .split(",")
        .map((a) => a.trim())
        .filter((a) => a.length > 0);
      expect(
        emitArgs.length,
        "`LootBoxOpened` emit must supply 8 positional args"
      ).to.equal(8);
      expect(
        emitArgs[6],
        "the 7th `LootBoxOpened` arg must be the bare floored `burnieAmount` local"
      ).to.equal("burnieAmount");

      // Between the floor and the emit, `burnieAmount` is the only `burnie*`
      // amount local in play — no `burnieFloored`, `burniePreFloor`,
      // `burnieSnapshot`, etc. is introduced. (`bonusBurnie` is block-scoped to
      // the presale `if` BEFORE the floor and is not in the floor->emit span.)
      const floorIdx = body.search(
        /burnieAmount\s*=\s*\(\s*burnieAmount\s*\/\s*1 ether\s*\)\s*\*\s*1 ether/
      );
      const emitIdx = body.indexOf("emit LootBoxOpened(");
      expect(floorIdx, "floor expression not found").to.be.greaterThan(-1);
      expect(emitIdx, "`LootBoxOpened` emit not found").to.be.greaterThan(floorIdx);
      const span = body.slice(floorIdx, emitIdx);
      // No new `uint256 burnie...` / `uint... burnie...` declaration in the span.
      const newBurnieDecl = /\buint\d*\s+burnie\w+\s*=/.exec(span);
      expect(
        newBurnieDecl,
        `no new burnie* snapshot variable may be declared between the floor and the emit (found: ${
          newBurnieDecl ? newBurnieDecl[0] : "none"
        })`
      ).to.equal(null);
    });

    it("[02b] the return tuple's BURNIE element is the bare `burnieAmount` local — `return (futureTickets, burnieAmount, roundedUp)`", function () {
      const source = fs.readFileSync(MODULE_SOURCE_PATH, "utf8");
      const body = stripLineComments(
        extractBody(source, "function _resolveLootboxCommon(")
      );
      expect(body, "`_resolveLootboxCommon` body not found").to.not.equal(null);
      expect(
        /return\s*\(\s*futureTickets\s*,\s*burnieAmount\s*,\s*roundedUp\s*\)/.test(
          body
        ),
        "`_resolveLootboxCommon` must return the bare floored `burnieAmount` local in its tuple"
      ).to.equal(true);
    });
  });

  describe("JS boundary math: `(x / 1 ether) * 1 ether` floor cases (confirmation layer)", function () {
    const CASES = [
      { label: "0.99 BURNIE", input: (ONE_ETHER * 99n) / 100n, expected: 0n },
      { label: "1.99 BURNIE", input: (ONE_ETHER * 199n) / 100n, expected: ONE_ETHER },
      { label: "2.00 BURNIE", input: ONE_ETHER * 2n, expected: ONE_ETHER * 2n },
      { label: "0 BURNIE", input: 0n, expected: 0n },
    ];

    CASES.forEach(({ label, input, expected }) => {
      it(`floors ${label} (${input} wei) to ${expected} wei`, function () {
        expect(floorWholeBurnie(input)).to.equal(expected);
      });
    });

    it("the floored result is always a whole-BURNIE multiple (`% 1 ether == 0`) across the boundary table", function () {
      for (const { input } of CASES) {
        expect(floorWholeBurnie(input) % ONE_ETHER).to.equal(0n);
      }
    });
  });
});
