// Current source-structure guards. Historical git-diff gates were permanently
// skipped and depended on obsolete line numbers and unavailable commit history.
// Runtime RNG properties live in Ent05KeccakRefactorInvariant and the Foundry suites.
import { expect } from "chai";
import fs from "node:fs";

const JACKPOT_MODULE_PATH = "contracts/modules/DegenerusGameJackpotModule.sol";

describe("Current shared RNG structure", function () {
  it("hero color path does NOT route through weightedColorBucket (colour bits preserved)", function () {
    // The PROPERTY is load-bearing: the hero override must never derive a
    // colour through `weightedColorBucket`, whose /256 ladder is heavy-tailed
    // and would bias hero colours.
    //
    // `_rollMainTraits` delegates to `_rollBoard`, which rolls the base board
    // off `JackpotBucketLib.getRandomTraits`, rolls the hero via
    // `_rollHeroSymbol`, and applies it inline:
    //     traits[heroQuadrant] = (traits[heroQuadrant] & 0xF8) | heroSymbol;
    // i.e. it PRESERVES the existing colour bits outright and replaces only the
    // low 3 symbol bits — no colour is derived on this path at all.
    //
    // So the negation is asserted over the whole hero call chain, and the
    // positive evidence is the 0xF8 colour-preserving mask in `_rollBoard`.
    const source = fs.readFileSync(JACKPOT_MODULE_PATH, "utf8");
    const start = source.indexOf("function _rollBoard(");
    expect(start, "could not locate _rollBoard in module source").to.be.gte(0);

    let depth = 0;
    let bodyEnd = -1;
    let openSeen = false;
    for (let i = start; i < source.length; i++) {
      const c = source[i];
      if (c === "{") {
        depth++;
        openSeen = true;
      } else if (c === "}") {
        depth--;
        if (openSeen && depth === 0) {
          bodyEnd = i + 1;
          break;
        }
      }
    }
    expect(bodyEnd, "could not locate end of _rollBoard body").to.be.gte(0);

    const body = source.slice(start, bodyEnd);

    // Negation, over the whole hero call chain: neither function that makes up
    // the hero override may reach weightedColorBucket.
    for (const fn of [
      "function _rollBoard(",
      "function _rollHeroSymbol(",
    ]) {
      const fnStart = source.indexOf(fn);
      expect(fnStart, `could not locate ${fn} in module source`).to.be.gte(0);
      let d = 0, seen = false, end = -1;
      for (let i = fnStart; i < source.length; i++) {
        if (source[i] === "{") { d++; seen = true; }
        else if (source[i] === "}") { d--; if (seen && d === 0) { end = i + 1; break; } }
      }
      expect(end, `could not locate end of ${fn}`).to.be.gte(0);
      expect(
        source.slice(fnStart, end),
        `${fn} must not route the hero colour through weightedColorBucket`,
      ).to.not.include("weightedColorBucket");
    }

    // Positive evidence: the override preserves the existing colour bits and
    // replaces only the low 3 symbol bits. If this mask ever widens past 0xF8 the
    // hero path starts writing colour, and this gate must fail.
    expect(
      /traits\[heroQuadrant\]\s*=\s*\(\s*traits\[heroQuadrant\]\s*&\s*0xF8\s*\)\s*\|\s*heroSymbol\s*;/.test(
        body,
      ),
      "_rollBoard must preserve the colour bits via the 0xF8 mask and write only the symbol",
    ).to.equal(true);

    // `_rollMainTraits` must still delegate to `_rollBoard`, the sole function
    // that applies the hero override onto the base board.
    const mainStart = source.indexOf("function _rollMainTraits(");
    expect(mainStart, "could not locate _rollMainTraits in module source").to.be.gte(0);
    let md = 0, mseen = false, mend = -1;
    for (let i = mainStart; i < source.length; i++) {
      if (source[i] === "{") { md++; mseen = true; }
      else if (source[i] === "}") { md--; if (mseen && md === 0) { mend = i + 1; break; } }
    }
    expect(source.slice(mainStart, mend)).to.include("_rollBoard(");
  });


});
