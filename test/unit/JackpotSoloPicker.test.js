import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";

// ---------------------------------------------------------------------------
// Fixture: deploy the test-only JackpotSoloTester harness (Plan 02 Task 1).
// The harness inherits DegenerusGameJackpotModule and exposes _pickSoloQuadrant
// as an external pure passthrough so Hardhat JS can invoke production bytes.
// ---------------------------------------------------------------------------

async function deployTester() {
  const Tester = await hre.ethers.getContractFactory("JackpotSoloTester");
  const tester = await Tester.deploy();
  await tester.waitForDeployment();
  return { tester };
}

// ---------------------------------------------------------------------------
// Trait byte helpers — [QQ][CCC][SSS] format (quadrant 2 bits, color 3 bits,
// symbol 3 bits). The helper inspects only `(traits[i] >> 3) & 7` for the
// color tier; the quadrant bits at positions 6-7 are NOT inspected and the
// symbol bits at positions 0-2 are not inspected either (only color matters).
// ---------------------------------------------------------------------------

function trait(quadrant, color, symbol) {
  return (BigInt(quadrant & 3) << 6n) | (BigInt(color & 7) << 3n) | BigInt(symbol & 7);
}

// Build a 4-element traits array (BigInt[]) where each entry has the given
// color tier; the quadrant for slot i is i, and the symbol is 0.
function traitsByColors(colors) {
  return [trait(0, colors[0], 0), trait(1, colors[1], 0), trait(2, colors[2], 0), trait(3, colors[3], 0)];
}

// Reference rotation index — must match JackpotBucketLib.soloBucketIndex(entropy):
//   uint8((uint256(3) - (entropy & 3)) & 3)
function rotationIndex(entropy) {
  return (3n - (entropy & 3n)) & 3n;
}

// Critical chi-squared values at alpha = 0.05 for df = goldCount - 1.
const CHI2_CRIT_05 = { 2: 3.841, 3: 5.991, 4: 7.815 };

// Deterministic 256-bit PRNG: keccak256(seed || counter). Cryptographic
// uniformity (suitable for chi-squared bucketing) AND reproducible — the
// fixed seed makes any future failure exactly replayable. We bind to
// ethers' built-in keccak256 so the test has no extra dependency.
function makeRng(seed) {
  const seedHex = "0x" + BigInt.asUintN(256, BigInt(seed)).toString(16).padStart(64, "0");
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    const out = hre.ethers.keccak256(seedHex + counterHex);
    return BigInt(out);
  };
}

describe("DegenerusGameJackpotModule._pickSoloQuadrant", function () {

  // =======================================================================
  // SOLO-08(a): Zero-gold rotation parity.
  // When no winning trait has color==7, the helper returns the existing
  // rotation index `(3 - (entropy & 3)) & 3` — same as v33.0
  // JackpotBucketLib.soloBucketIndex(entropy).
  // =======================================================================

  describe("SOLO-08(a) — zero-gold rotation parity", function () {
    it("returns rotation index when traits contain zero gold (all colors 0-6)", async function () {
      const { tester } = await loadFixture(deployTester);
      // Cover every (entropy & 3) value to verify all 4 rotation outputs.
      // Use color values 0/1/2/3 — none of which are gold (7).
      const traitsZeroGold = traitsByColors([0, 1, 2, 3]);
      for (let lowBits = 0; lowBits < 4; lowBits++) {
        // Vary upper bits to confirm only bits 0-1 matter for the zero-gold path.
        for (const upperBits of [0n, 0xABCDEFn, 1n << 200n]) {
          const entropy = upperBits | BigInt(lowBits);
          const result = await tester.pickSoloQuadrant(traitsZeroGold, entropy);
          const expected = rotationIndex(entropy);
          expect(result).to.equal(expected);
        }
      }
    });

    it("returns rotation index when all traits are color 6 (next-to-gold, no gold)", async function () {
      const { tester } = await loadFixture(deployTester);
      // Color 6 is heavy-tail second-rarest but NOT gold — should still rotate.
      const traitsAllSix = traitsByColors([6, 6, 6, 6]);
      for (let lowBits = 0; lowBits < 4; lowBits++) {
        const entropy = BigInt(lowBits);
        const result = await tester.pickSoloQuadrant(traitsAllSix, entropy);
        expect(result).to.equal(rotationIndex(entropy));
      }
    });
  });

  // =======================================================================
  // SOLO-08(b): One-gold deterministic return.
  // When exactly one winning trait has color==7, the helper returns that
  // quadrant index regardless of entropy bits 4+.
  // =======================================================================

  describe("SOLO-08(b) — one-gold deterministic return", function () {
    for (let goldQuadrant = 0; goldQuadrant < 4; goldQuadrant++) {
      it(`returns quadrant ${goldQuadrant} when only that slot is gold (regardless of entropy)`, async function () {
        const { tester } = await loadFixture(deployTester);
        // Build a traits array where slot `goldQuadrant` is color 7, others are color 0.
        const colors = [0, 0, 0, 0];
        colors[goldQuadrant] = 7;
        const traits = traitsByColors(colors);
        // Sample a wide range of entropies — including bits 4+ varying — and
        // verify the helper always returns goldQuadrant.
        const entropies = [
          0n,
          0xFFFFFFFFn,
          1n << 4n,
          1n << 200n,
          (1n << 4n) | 3n,           // tie-break bit set + low bits set
          0xDEADBEEFn,
          (1n << 255n) - 1n,         // top bit not set, otherwise all ones
        ];
        for (const entropy of entropies) {
          const result = await tester.pickSoloQuadrant(traits, entropy);
          expect(result).to.equal(BigInt(goldQuadrant));
        }
      });
    }
  });

  // =======================================================================
  // SOLO-08(c): 2/3/4-gold uniform distribution.
  // Sample 100K random entropies for each goldCount ∈ {2, 3, 4}; bucket the
  // returned indices; run chi-squared against uniform across gold positions;
  // expect chi² < critical value at alpha = 0.05.
  // =======================================================================

  describe("SOLO-08(c) — multi-gold uniform distribution (chi-squared p > 0.05)", function () {
    this.timeout(180000); // 3 min budget per goldCount sweep

    // For each goldCount, define the trait array and the expected gold-quadrant set.
    const cases = [
      { goldCount: 2, colors: [7, 0, 7, 0], goldQuads: [0, 2] },
      { goldCount: 3, colors: [7, 7, 0, 7], goldQuads: [0, 1, 3] },
      { goldCount: 4, colors: [7, 7, 7, 7], goldQuads: [0, 1, 2, 3] },
    ];

    for (const { goldCount, colors, goldQuads } of cases) {
      it(`distributes uniformly across ${goldCount} gold quadrants over 100K samples`, async function () {
        const { tester } = await loadFixture(deployTester);
        const traits = traitsByColors(colors);
        const SAMPLES = 100_000;
        const counts = new Array(goldCount).fill(0);
        const rng = makeRng(0xC0FFEE ^ goldCount);

        for (let i = 0; i < SAMPLES; i++) {
          const entropy = rng();
          const result = await tester.pickSoloQuadrant(traits, entropy);
          const idx = goldQuads.indexOf(Number(result));
          if (idx < 0) {
            throw new Error(`pickSoloQuadrant returned non-gold quadrant ${result} for goldCount=${goldCount}`);
          }
          counts[idx]++;
        }

        // Chi-squared statistic vs uniform distribution.
        const expected = SAMPLES / goldCount;
        let chi2 = 0;
        for (const c of counts) {
          chi2 += ((c - expected) ** 2) / expected;
        }
        const crit = CHI2_CRIT_05[goldCount];
        expect(chi2, `chi² = ${chi2.toFixed(3)}, counts = ${counts.join(",")}`).to.be.lessThan(crit);
      });
    }

    it("never returns a non-gold quadrant when goldCount >= 1", async function () {
      const { tester } = await loadFixture(deployTester);
      // Spot-check: 1K random entropies on a 2-gold trait array — every result
      // must be in {1, 3} (the gold quadrants in this fixture).
      const traits = traitsByColors([0, 7, 0, 7]);
      const goldSet = new Set([1n, 3n]);
      const rng = makeRng(0xBEEF);
      for (let i = 0; i < 1000; i++) {
        const result = await tester.pickSoloQuadrant(traits, rng());
        expect(goldSet.has(result), `result=${result}`).to.equal(true);
      }
    });
  });

  // =======================================================================
  // SOLO-08(d): Tie-break bit-disjointness from bucket-rotation low-2-bits.
  // The tie-break uses bits 4+ of `entropy` (formula `(entropy >> 4) % goldCount`
  // per D-04 — drops the `& 3` mask). Verify:
  //   1. Varying ONLY bits 0-1 of entropy does NOT change the tie-break output
  //      (bucket rotation reads bits 0-1; tie-break ignores them).
  //   2. Varying ONLY bits 4+ of entropy CAN change the tie-break output.
  //   3. Bits 2-3 are unused by either path (helper output unaffected).
  // =======================================================================

  describe("SOLO-08(d) — tie-break bit-disjointness from bucket-rotation low-2-bits", function () {
    it("low-2-bits (entropy & 3) do NOT affect tie-break output for goldCount >= 2", async function () {
      const { tester } = await loadFixture(deployTester);
      // 2-gold fixture: golds at quadrants 0 and 2.
      const traits = traitsByColors([7, 0, 7, 0]);
      // Pick a base entropy where bits 4+ are fixed; sweep bits 0-1 across {0,1,2,3}.
      const baseEntropy = 0n; // bits 4+ all zero → tie-break index = 0 → goldQuads[0] = 0
      const baseline = await tester.pickSoloQuadrant(traits, baseEntropy);
      for (let lowBits = 0; lowBits < 4; lowBits++) {
        const entropy = baseEntropy | BigInt(lowBits);
        const result = await tester.pickSoloQuadrant(traits, entropy);
        expect(result, `lowBits=${lowBits}`).to.equal(baseline);
      }
      // Now flip bit 4 (tie-break bit): with goldCount=2 and `(entropy >> 4) % 2 == 1`
      // the helper returns goldQuads[1] = 2.
      const flipped = await tester.pickSoloQuadrant(traits, 1n << 4n);
      expect(flipped).to.equal(2n);
    });

    it("bits 2-3 are unused by either path (rotation or tie-break)", async function () {
      const { tester } = await loadFixture(deployTester);
      // Two-gold case — verify bits 2-3 of entropy do not change the output.
      const traits = traitsByColors([7, 0, 7, 0]);
      const entropies = [
        0n,
        1n << 2n,         // bit 2 only
        1n << 3n,         // bit 3 only
        (1n << 2n) | (1n << 3n), // bits 2 and 3
      ];
      const results = [];
      for (const e of entropies) {
        results.push(await tester.pickSoloQuadrant(traits, e));
      }
      // All outputs identical since neither bucket-rotation (bits 0-1) nor
      // tie-break (bits 4+) consumes bits 2-3.
      for (const r of results) {
        expect(r).to.equal(results[0]);
      }
    });

    it("bits 4+ of entropy can change tie-break output for goldCount=3", async function () {
      const { tester } = await loadFixture(deployTester);
      // Three golds at quadrants 0, 1, 3. tie-break = (entropy >> 4) % 3.
      const traits = traitsByColors([7, 7, 0, 7]);
      const goldQuads = [0n, 1n, 3n];
      // Verify the tie-break index can take all three values:
      //   entropy >> 4 == 0 → goldQuads[0] = 0
      //   entropy >> 4 == 1 → goldQuads[1] = 1
      //   entropy >> 4 == 2 → goldQuads[2] = 3
      expect(await tester.pickSoloQuadrant(traits, 0n)).to.equal(goldQuads[0]);
      expect(await tester.pickSoloQuadrant(traits, 1n << 4n)).to.equal(goldQuads[1]);
      expect(await tester.pickSoloQuadrant(traits, 2n << 4n)).to.equal(goldQuads[2]);
      // entropy >> 4 == 3 → 3 % 3 == 0 → goldQuads[0] = 0
      expect(await tester.pickSoloQuadrant(traits, 3n << 4n)).to.equal(goldQuads[0]);
    });
  });

});
