// SPDX-License-Identifier: AGPL-3.0-only
//
// Statistical seed model for direct lootboxes and redemption orders. Redemption
// mixes the session word with the player in sDGNRS, then uses the human-order
// BoxOpen domain and a one-based box nonce. No amount or former 5-ETH chunk
// enters that draw. This model tests distribution, not production wiring;
// RandomnessSeedInputs and RedemptionForwardBatches execute the real resolver.

import { expect } from "chai";
import hre from "hardhat";

async function deployTester() {
  const Factory = await hre.ethers.getContractFactory("LootboxBernoulliTester");
  const tester = await Factory.deploy();
  await tester.waitForDeployment();
  return tester;
}

// Phase 261/264/266 chi² infrastructure reuse (verbatim re-declaration).
// Source: test/stat/TraitDistribution.test.js / LootboxEntropyDistribution.test.js.
function wilsonHilfertyZ(chi2, df) {
  const term = Math.cbrt(chi2 / df) - (1 - 2 / (9 * df));
  return term / Math.sqrt(2 / (9 * df));
}

// EntropyLib.hash2/hash4 encode each input in a full 32-byte word.
const BOX_OPEN_TAG = 0x426f784f70656en;
function deriveSeed(rngWord, player) {
  return BigInt(hre.ethers.keccak256(hre.ethers.AbiCoder.defaultAbiCoder().encode(
    ["uint256", "uint32"], [rngWord, player]
  )));
}
function redemptionSeed(rngWord, player, nonce = 1) {
  const entropy = deriveSeed(rngWord, player);
  return BigInt(hre.ethers.keccak256(hre.ethers.AbiCoder.defaultAbiCoder().encode(
    ["uint256", "uint32", "uint256", "uint256"], [entropy, player, BOX_OPEN_TAG, nonce]
  )));
}

function makeCallerBSeeds(N) {
  // DegeneretteModule: single-shot per payout.
  const seeds = [];
  for (let i = 0; i < N; i++) {
    const rngWord = BigInt(hre.ethers.keccak256("0x" + ("d2" + i.toString(16).padStart(62, "0"))));
    const player = 0x2000n + BigInt(i);
    seeds.push(deriveSeed(rngWord, player));
  }
  return seeds;
}

function makeCallerCSeeds(N) {
  // First box for distinct beneficiaries and session words.
  const seeds = [];
  for (let i = 0; i < N; i++) {
    const rngWord = BigInt(hre.ethers.keccak256("0x" + ("c0275c" + i.toString(16).padStart(58, "0"))));
    const player = 0x3a00n + BigInt(i);
    seeds.push(redemptionSeed(rngWord, player));
  }
  return seeds;
}

function makeCallerDSeeds(N) {
  // All twenty box nonces for one beneficiary across successive synthetic sessions.
  const seeds = [];
  let rngWord = BigInt(hre.ethers.keccak256("0x" + "d4".padStart(64, "0")));
  const player = 0x4000n;
  for (let i = 0; i < N; i++) {
    if (i % 20 === 0) {
      rngWord = BigInt(hre.ethers.keccak256(hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [rngWord])));
    }
    seeds.push(redemptionSeed(rngWord, player, i % 20 + 1));
  }
  return seeds;
}

describe("LootboxAutoResolveSeedUniqueness (stat-suite, heavy-MC) — TST-LBX-AR-04 chi-square across 3 seed families", function () {
  this.timeout(600_000);

  describe("Per-caller chi² uniformity of bits[224..255] % 100 at N=10K per caller (DegeneretteModule / sDGNRS / redemption order nonces)", function () {
    const N = 10_000;
    const CALLERS = [
      { id: "b-DegeneretteModule", gen: makeCallerBSeeds },
      { id: "c-sDGNRS", gen: makeCallerCSeeds },
      { id: "d-redemption-order-nonces", gen: makeCallerDSeeds },
    ];

    CALLERS.forEach(({ id, gen }) => {
      it(`caller ${id}: chi²(df=99) Wilson-Hilferty Z < 1.645 at α=0.05`, async function () {
        const tester = await deployTester();
        const seeds = gen(N);
        const buckets = new Array(100).fill(0);
        let chainVerifyCount = 0;
        for (let i = 0; i < N; i++) {
          const seed = seeds[i];
          const jsSlice = Number(((seed >> 224n) & 0xffffffffn) % 100n);
          buckets[jsSlice] += 1;
          if (i % 1000 === 0) {
            const chainSlice = await tester.bernoulliSlice(seed);
            expect(Number(chainSlice), `js/chain drift at i=${i}`).to.equal(jsSlice);
            chainVerifyCount++;
          }
        }
        expect(chainVerifyCount).to.be.gte(8);

        // Expected probabilities — uint32 % 100 is effectively uniform: the
        // modulo bias over a 2^32 window is ~2e-8, so every residue has p=1/100.
        const expected = N / 100;
        let chi2 = 0;
        for (let b = 0; b < 100; b++) {
          const diff = buckets[b] - expected;
          chi2 += (diff * diff) / expected;
        }
        const z = wilsonHilfertyZ(chi2, 99);
        expect(
          z < 1.645,
          `caller ${id}: chi²=${chi2.toFixed(3)} df=99 → Z=${z.toFixed(3)} >= 1.645`
        ).to.equal(true);
      });
    });
  });

  describe("Cross-caller pairwise independence — same-index sliceA vs sliceB across the 3 caller pairs", function () {
    const N = 10_000;

    it("pairwise mean-correlation |E[sliceA*sliceB] - E[sliceA]*E[sliceB]| < 50 across all 3 pairs (N=10K)", function () {
      const callers = [
        makeCallerBSeeds(N),
        makeCallerCSeeds(N),
        makeCallerDSeeds(N),
      ];
      const slicesPerCaller = callers.map((seeds) =>
        seeds.map((s) => Number(((s >> 224n) & 0xffffffffn) % 100n))
      );

      for (let i = 0; i < callers.length; i++) {
        for (let j = i + 1; j < callers.length; j++) {
          const a = slicesPerCaller[i];
          const b = slicesPerCaller[j];
          let sumA = 0;
          let sumB = 0;
          let sumProd = 0;
          for (let k = 0; k < N; k++) {
            sumA += a[k];
            sumB += b[k];
            sumProd += a[k] * b[k];
          }
          const meanA = sumA / N;
          const meanB = sumB / N;
          const meanProd = sumProd / N;
          const cov = Math.abs(meanProd - meanA * meanB);
          // Under independence + uniform [0..99] marginals, sd(A*B) ≈ 1000;
          // 3-sigma at N=10K is ~30. Use ±50 (5-sigma) for CI robustness.
          expect(
            cov < 50,
            `pair (${i},${j}): |E[A*B] - E[A]*E[B]| = ${cov.toFixed(3)} > 50`
          ).to.equal(true);
        }
      }
    });
  });

  describe("Cross-slice independence — bits[224..255] vs bits[0..15] (rangeRoll consumer) at the same seed set", function () {
    const N = 10_000;

    it("|E[sliceBernoulli * sliceRange] - E[sliceBernoulli] * E[sliceRange]| < 50 at N=10K (FINDINGS-v39.0.md §4(b) cross-slice independence extended to auto-resolve)", function () {
      const seeds = makeCallerBSeeds(N);
      let sumB = 0;
      let sumR = 0;
      let sumProd = 0;
      for (let i = 0; i < N; i++) {
        const seed = seeds[i];
        const sliceB = Number(((seed >> 224n) & 0xffffffffn) % 100n);
        const sliceR = Number((seed & 0xffffn) % 100n);
        sumB += sliceB;
        sumR += sliceR;
        sumProd += sliceB * sliceR;
      }
      const meanB = sumB / N;
      const meanR = sumR / N;
      const meanProd = sumProd / N;
      const cov = Math.abs(meanProd - meanB * meanR);
      expect(
        cov < 50,
        `cross-slice: |E[B*R] - E[B]*E[R]| = ${cov.toFixed(3)} > 50 (meanB=${meanB.toFixed(3)}, meanR=${meanR.toFixed(3)}, meanProd=${meanProd.toFixed(3)})`
      ).to.equal(true);
    });
  });
});
