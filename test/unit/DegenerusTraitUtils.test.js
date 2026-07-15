import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";

// ---------------------------------------------------------------------------
// Fixture: deploy the test-only TraitUtilsTester harness (Plan 02 output).
// The harness exposes weightedColorBucket / traitFromWord / packedTraitsFromSeed
// as external pure passthroughs to the internal-pure DegenerusTraitUtils library.
// ---------------------------------------------------------------------------

async function deployTester() {
  const Tester = await hre.ethers.getContractFactory("TraitUtilsTester");
  const tester = await Tester.deploy();
  await tester.waitForDeployment();
  return { tester };
}

// ---------------------------------------------------------------------------
// Helper: reverse-map a `scaled` value (0..255) to a `rnd` uint32 such that
//   uint32((uint64(rnd) * 256) >> 32) === scaled
// The clean inverse is `rnd = scaled << 24` because
//   (scaled * 2^24 * 256) >> 32 = (scaled * 2^32) >> 32 = scaled.
// ---------------------------------------------------------------------------

function rndForScaled(scaled) {
  return BigInt(scaled) << 24n;
}

describe("DegenerusTraitUtils", function () {

  // =======================================================================
  // TRAIT-05: weightedColorBucket boundary cases.
  // 16 assertions over scaled ∈ {0, 63, 64, 127, 128, 191, 192, 223, 224,
  // 239, 240, 247, 248, 253, 254, 255} with expected color tiers
  // {0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7}.
  // Each boundary is an independent `it` so a failure pinpoints the exact
  // threshold that drifted.
  // =======================================================================

  describe("weightedColorBucket(uint32)", function () {
    const boundaries = [
      // [scaled,  expectedColor]
      [0,   0], [63,  0],
      [64,  1], [127, 1],
      [128, 2], [191, 2],
      [192, 3], [223, 3],
      [224, 4], [239, 4],
      [240, 5], [247, 5],
      [248, 6], [253, 6],
      [254, 7], [255, 7],
    ];

    for (const [scaled, expectedColor] of boundaries) {
      it(`maps scaled=${scaled} to color tier ${expectedColor}`, async function () {
        const { tester } = await loadFixture(deployTester);
        const rnd = rndForScaled(scaled);
        const result = await tester.weightedColorBucket(rnd);
        expect(result).to.equal(BigInt(expectedColor));
      });
    }
  });

  // =======================================================================
  // TRAIT-06: traitFromWord bit-slice composition.
  // Proves the low 32 bits drive color (via weightedColorBucket) and the
  // high 32 bits drive symbol (via & 7) — the two axes are disjoint.
  // Output format: (color << 3) | symbol, so result >> 3 == color and
  // result & 7 == symbol.
  // =======================================================================

  describe("traitFromWord(uint64)", function () {
    it("isolated low-32-bits drive color (high 32 bits zero → symbol = 0)", async function () {
      const { tester } = await loadFixture(deployTester);
      // For each color tier, pick the canonical scaled value at the LOW edge
      // of the tier's range and verify the trait result decomposes as
      // (color << 3) | 0.
      const cases = [
        [0,   0n],   // scaled = 0   → color 0
        [64,  1n],   // scaled = 64  → color 1
        [128, 2n],   // scaled = 128 → color 2
        [192, 3n],   // scaled = 192 → color 3
        [224, 4n],   // scaled = 224 → color 4
        [240, 5n],   // scaled = 240 → color 5
        [248, 6n],   // scaled = 248 → color 6
        [254, 7n],   // scaled = 254 → color 7 (gold)
      ];
      for (const [scaled, expectedColor] of cases) {
        const rndU64 = rndForScaled(scaled); // high 32 bits are zero
        const trait = await tester.traitFromWord(rndU64);
        expect(trait >> 3n).to.equal(expectedColor); // top 3 bits = color
        expect(trait & 7n).to.equal(0n);             // bottom 3 bits = symbol = 0
      }
    });

    it("isolated high-32-bits drive symbol (low 32 bits zero → color = 0)", async function () {
      const { tester } = await loadFixture(deployTester);
      // For each symbol value 0..7, set high 32 bits to that value and verify
      // bottom 3 bits of the result equal the symbol; color stays 0.
      for (let symbol = 0; symbol < 8; symbol++) {
        const high = BigInt(symbol) << 32n;
        const trait = await tester.traitFromWord(high);
        expect(trait & 7n).to.equal(BigInt(symbol)); // symbol passes through
        expect(trait >> 3n).to.equal(0n);            // color stays 0 (low 32 bits = 0)
      }
    });

    it("symbol uses (rnd >> 32) & 7 — only the low 3 bits of the high uint32 matter", async function () {
      const { tester } = await loadFixture(deployTester);
      // High uint32 = 0xFFFFFFFF — only the low 3 bits (= 7) should drive symbol.
      const rnd = (0xFFFFFFFFn << 32n); // low 32 bits = 0 → color = 0
      const trait = await tester.traitFromWord(rnd);
      expect(trait >> 3n).to.equal(0n);  // color from low 32 = 0
      expect(trait & 7n).to.equal(7n);   // symbol from high 32 low 3 bits = 7
    });

    it("composes (color << 3) | symbol when both halves are non-zero", async function () {
      const { tester } = await loadFixture(deployTester);
      // Color 7 (scaled = 254) in low 32 bits, symbol 5 in high 32 bits.
      const low = rndForScaled(254);             // → color 7
      const high = (5n & 7n) << 32n;             // → symbol 5
      const rnd = low | high;
      const trait = await tester.traitFromWord(rnd);
      expect(trait).to.equal((7n << 3n) | 5n);   // = 61
    });
  });

  // =======================================================================
  // TRAIT-06: packedTraitsFromSeed byte-layout assertions.
  // Asserts quadrant flags 0/64/128/192 on the four packed bytes and that
  // the result fits in 32 bits.
  // =======================================================================

  describe("packedTraitsFromSeed(uint256)", function () {
    it("returns a uint32 (fits in 32 bits)", async function () {
      const { tester } = await loadFixture(deployTester);
      // Use a non-trivial seed; result must be within [0, 2^32).
      const seed = 0x1234567890ABCDEFn;
      const packed = await tester.packedTraitsFromSeed(seed);
      expect(packed).to.be.lessThan(1n << 32n);
      expect(packed).to.be.gte(0n);
    });

    it("trait A (low byte) has quadrant flag 0 (bits 7-6 = 00)", async function () {
      const { tester } = await loadFixture(deployTester);
      const packed = await tester.packedTraitsFromSeed(0n);
      const traitA = packed & 0xFFn;
      expect((traitA >> 6n) & 3n).to.equal(0n); // quadrant 0
    });

    it("trait B (byte 1) has quadrant flag 1 (bits 7-6 = 01)", async function () {
      const { tester } = await loadFixture(deployTester);
      const packed = await tester.packedTraitsFromSeed(0n);
      const traitB = (packed >> 8n) & 0xFFn;
      expect((traitB >> 6n) & 3n).to.equal(1n); // quadrant 1
    });

    it("trait C (byte 2) has quadrant flag 2 (bits 7-6 = 10)", async function () {
      const { tester } = await loadFixture(deployTester);
      const packed = await tester.packedTraitsFromSeed(0n);
      const traitC = (packed >> 16n) & 0xFFn;
      expect((traitC >> 6n) & 3n).to.equal(2n); // quadrant 2
    });

    it("trait D (byte 3) has quadrant flag 3 (bits 7-6 = 11)", async function () {
      const { tester } = await loadFixture(deployTester);
      const packed = await tester.packedTraitsFromSeed(0n);
      const traitD = (packed >> 24n) & 0xFFn;
      expect((traitD >> 6n) & 3n).to.equal(3n); // quadrant 3
    });

    it("the four 64-bit lanes drive the four trait bytes independently (color/symbol disjoint per quadrant)", async function () {
      const { tester } = await loadFixture(deployTester);
      // Build a 256-bit seed where each 64-bit lane targets a different color
      // tier: laneA → color 0 (scaled = 0), laneB → color 3 (scaled = 192),
      // laneC → color 5 (scaled = 240), laneD → color 7 (scaled = 254).
      const laneA = rndForScaled(0);    // 64 bits, low 32 = 0
      const laneB = rndForScaled(192);  // 64 bits, low 32 = 192 << 24
      const laneC = rndForScaled(240);
      const laneD = rndForScaled(254);
      const seed = laneA | (laneB << 64n) | (laneC << 128n) | (laneD << 192n);

      const packed = await tester.packedTraitsFromSeed(seed);
      const traitA = packed & 0xFFn;
      const traitB = (packed >> 8n) & 0xFFn;
      const traitC = (packed >> 16n) & 0xFFn;
      const traitD = (packed >> 24n) & 0xFFn;

      // Strip quadrant flag (bits 7-6), then bits 5-3 = color tier.
      expect((traitA & 0x3Fn) >> 3n).to.equal(0n); // color 0
      expect((traitB & 0x3Fn) >> 3n).to.equal(3n); // color 3
      expect((traitC & 0x3Fn) >> 3n).to.equal(5n); // color 5
      expect((traitD & 0x3Fn) >> 3n).to.equal(7n); // color 7 (gold)
    });
  });

});
