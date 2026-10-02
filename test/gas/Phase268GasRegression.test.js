// Current purchase-day gas witness. The permanently skipped quickPlay benchmark
// targeted a retired API; current bet gas is covered by KeeperResolveBetWorstCaseGas.
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
  getEvents,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

const ADVANCE_GAME_STAGE6_GAS_CEILING = 10_000_000;

describe("SURF-06 — mineFlip STAGE_PURCHASE_DAILY gas under the 10M per-call ceiling", function () {
  this.timeout(120_000);

  it("stage-6 (STAGE_PURCHASE_DAILY) gas stays under ADVANCE_GAME_STAGE6_GAS_CEILING (10M)", async function () {
    const fixture = await loadFixture(deployFullProtocol);

    const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve } = fixture;

    // Light setup: 5 players × 1 ticket each. Drive VRF cycles and capture the
    // first stage-6 receipt.
    const players = [alice, bob, carol, dan, eve];
    for (const p of players) {
      try {
        await game.connect(p).purchase(
          ZERO_ADDRESS,
          400n,
          0n,
          ZERO_BYTES32,
          MintPaymentKind.DirectEth,
          false,
          { value: eth(0.01) },
        );
      } catch (_) {
        // Tolerate purchase failure for any individual player; continue.
      }
    }

    let stage6Gas = null;
    for (let cycle = 0; cycle < 5 && stage6Gas === null; cycle++) {
      await advanceToNextDay();
      try {
        const tx1 = await game.connect(deployer).mineFlip();
        await tx1.wait();
        const requestId = await getLastVRFRequestId(mockVRF);
        if (requestId > 0n) {
          // Fixed seed family {36266, 37266, ...} for cycles 0..4 keeps the
          // measured stage reproducible.
          await mockVRF.fulfillRandomWords(requestId, BigInt(cycle * 1000 + 36266));
        }
      } catch (_) {
        continue;
      }

      for (let i = 0; i < 50; i++) {
        let tx;
        try {
          tx = await game.connect(deployer).mineFlip();
        } catch (_) {
          break;
        }
        const receipt = await tx.wait();
        const events = await getEvents(tx, advanceModule, "Advance");
        if (events.length > 0 && events[0].args.stage === 6n) {
          stage6Gas = Number(receipt.gasUsed);
          break;
        }
        if (!(await game.rngLocked())) break;
      }
    }

    expect(stage6Gas, "the fixture must execute STAGE_PURCHASE_DAILY").to.not.equal(null);

    console.log(`[SURF-06 advance-gas] STAGE_PURCHASE_DAILY (stage-6) gas = ${stage6Gas} (ceiling ${ADVANCE_GAME_STAGE6_GAS_CEILING})`);

    // The only load-bearing bound: a single mineFlip call must stay well under
    // the 10M per-call target (and provably never approach the 16.7M block ceiling).
    expect(
      stage6Gas < ADVANCE_GAME_STAGE6_GAS_CEILING,
      `mineFlip stage-6 gas ${stage6Gas} exceeds the ${ADVANCE_GAME_STAGE6_GAS_CEILING} per-call ceiling`,
    ).to.equal(true);
  });
});

after(function () {
  restoreAddresses();
});
