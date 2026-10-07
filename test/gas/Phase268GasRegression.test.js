// Current purchase-day gas witness. The permanently skipped quickPlay benchmark
// targeted a retired API; current bet gas is covered by KeeperResolveBetWorstCaseGas.
// One mineFlip now composes several checkpoints, so the stage-6 purchase daily is located
// by its Advance stage among the day's chunks and measured as its own chunk at its minimum
// admission allowance (test/helpers/mineFlipChunks.js); a whole transaction is not bounded.
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";
import { walkNextDay } from "../helpers/mineFlipChunks.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

// Per-chunk ceiling (owner rule: one chunk between checkpoints <= 10M).
const ADVANCE_GAME_STAGE6_GAS_CEILING = 10_000_000;
const STAGE_PURCHASE_DAILY = 6n;

describe("SURF-06 — mineFlip STAGE_PURCHASE_DAILY gas under the 10M per-chunk ceiling", function () {
  this.timeout(300_000);

  it("stage-6 (STAGE_PURCHASE_DAILY) chunk stays under ADVANCE_GAME_STAGE6_GAS_CEILING (10M)", async function () {
    const fixture = await loadFixture(deployFullProtocol);

    const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve } = fixture;

    // Light setup: 5 players × 1 ticket each. Drive VRF cycles and capture the
    // first stage-6 chunk.
    const players = [alice, bob, carol, dan, eve];
    for (const p of players) {
      await game.connect(p).purchase(
        0,
        400n,
        0n,
        ZERO_BYTES32,
        MintPaymentKind.DirectEth,
        false,
        { value: eth(0.01) },
      );
    }

    let stage6Gas = null;
    for (let cycle = 0; cycle < 5 && stage6Gas === null; cycle++) {
      await advanceToNextDay();
      // Fixed seed family {36266, 37266, ...} for cycles 0..4 keeps the
      // measured stage reproducible.
      const chunks = await walkNextDay(game, deployer, mockVRF, advanceModule,
        BigInt(cycle * 1000 + 36266), `SURF-06 cycle ${cycle}`);
      const daily = chunks.find((c) => c.stages.includes(STAGE_PURCHASE_DAILY));
      if (daily) stage6Gas = Number(daily.gasUsed);
    }

    expect(stage6Gas, "the fixture must execute STAGE_PURCHASE_DAILY").to.not.equal(null);

    console.log(`[SURF-06 advance-gas] STAGE_PURCHASE_DAILY (stage-6) chunk gas = ${stage6Gas} (ceiling ${ADVANCE_GAME_STAGE6_GAS_CEILING})`);

    // The only load-bearing bound: the purchase-daily chunk (measured at its own minimum
    // admission allowance, an upper bound on the chunk) stays under 10M.
    expect(
      stage6Gas < ADVANCE_GAME_STAGE6_GAS_CEILING,
      `mineFlip stage-6 chunk gas ${stage6Gas} exceeds the ${ADVANCE_GAME_STAGE6_GAS_CEILING} per-chunk ceiling`,
    ).to.equal(true);
  });
});

after(function () {
  restoreAddresses();
});
