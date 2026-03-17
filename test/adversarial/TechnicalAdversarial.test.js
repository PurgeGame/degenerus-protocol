import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  advanceTime,
  advanceToNextDay,
  eth,
  getEvent,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };
const RESET_TIME_SECONDS = 82620n;
const EMERGENCY_KEY_HASH =
  "0xcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd";

async function giveBurnie(coin, vault, to, amount) {
  const vaultAddr = await vault.getAddress();
  await hre.ethers.provider.send("hardhat_setBalance", [
    vaultAddr,
    "0x1000000000000000000",
  ]);
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [vaultAddr],
  });
  const vaultSigner = await hre.ethers.getSigner(vaultAddr);
  await coin.connect(vaultSigner).vaultEscrow(amount);
  await coin.connect(vaultSigner).vaultMintTo(to, amount);
  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [vaultAddr],
  });
}

function dayBoundaryTs(deployDayBoundary, dayIdx) {
  return (
    (BigInt(deployDayBoundary) + BigInt(dayIdx) - 1n) * 86400n +
    RESET_TIME_SECONDS
  );
}

async function warpToTimestamp(ts) {
  const latest = await hre.ethers.provider.getBlock("latest");
  const nowTs = BigInt(latest.timestamp);
  const next = ts > nowTs ? ts : nowTs + 1n;
  await hre.network.provider.send("evm_setNextBlockTimestamp", [Number(next)]);
  await hre.network.provider.send("evm_mine");
}

async function runOneDailyCycle(game, deployer, mockVRF, word) {
  await advanceToNextDay();
  await game.connect(deployer).advanceGame();
  const requestId = await getLastVRFRequestId(mockVRF);
  await mockVRF.fulfillRandomWords(requestId, word);

  await game.connect(deployer).advanceGame();
  for (let i = 0; i < 40; i++) {
    if (!(await game.rngLocked())) break;
    await game.connect(deployer).advanceGame();
  }
}

describe("Technical Adversarial Suite", function () {
  this.timeout(600_000);

  after(function () {
    restoreAddresses();
  });

  it("blocks requestLootboxRng during the 15-minute pre-reset window", async function () {
    const {
      game,
      deployer,
      admin,
      alice,
      mockVRF,
      deployDayBoundary,
    } = await loadFixture(deployFullProtocol);

    await admin.connect(deployer).setLootboxRngThreshold(1n);
    await mockVRF.fundSubscription(1n, eth(100));
    await runOneDailyCycle(game, deployer, mockVRF, 777n);

    await game.connect(alice).purchase(
      ZERO_ADDRESS,
      0n,
      eth("0.05"),
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      { value: eth("0.05") }
    );

    const currentDay = await game.currentDayView();
    const nextBoundary = dayBoundaryTs(deployDayBoundary, currentDay + 1n);
    await warpToTimestamp(nextBoundary - 5n * 60n);

    await expect(game.connect(alice).requestLootboxRng()).to.be.reverted;
  });

  it("midday lootbox RNG griefing cannot stall forever and retries after 18h", async function () {
    const {
      game,
      deployer,
      admin,
      alice,
      mockVRF,
      advanceModule,
      deployDayBoundary,
    } = await loadFixture(deployFullProtocol);

    await admin.connect(deployer).setLootboxRngThreshold(1n);
    await mockVRF.fundSubscription(1n, eth(100));
    await runOneDailyCycle(game, deployer, mockVRF, 888n);

    await game.connect(alice).purchase(
      ZERO_ADDRESS,
      0n,
      eth("0.05"),
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      { value: eth("0.05") }
    );

    const currentDay = await game.currentDayView();
    const nextBoundary = dayBoundaryTs(deployDayBoundary, currentDay + 1n);

    // 30 minutes before reset: allowed (outside 15-minute guard).
    await warpToTimestamp(nextBoundary - 30n * 60n);
    await game.connect(alice).requestLootboxRng();
    const firstRequestId = await getLastVRFRequestId(mockVRF);

    // Next day quickly: request is still pending and under 18h timeout.
    await warpToTimestamp(nextBoundary + 60n);
    await expect(
      game.connect(deployer).advanceGame()
    ).to.be.revertedWithCustomError(advanceModule, "RngNotReady");

    await advanceTime(18 * 3600 + 5);
    await game.connect(deployer).advanceGame();
    const retriedRequestId = await getLastVRFRequestId(mockVRF);
    expect(retriedRequestId).to.be.gt(firstRequestId);
  });

  it("gates VRF governance propose behind stall detection", async function () {
    const { game, admin, deployer, mockVRF } = await loadFixture(
      deployFullProtocol
    );

    const EMERGENCY_KEY_HASH_LOCAL = hre.ethers.id("emergency-key");

    // propose should fail without stall
    await expect(
      admin
        .connect(deployer)
        .propose(await mockVRF.getAddress(), EMERGENCY_KEY_HASH_LOCAL)
    ).to.be.revertedWithCustomError(admin, "NotStalled");

    // Create a multi-day stall by never fulfilling any VRF requests.
    await advanceToNextDay();
    await game.connect(deployer).advanceGame();
    for (let i = 0; i < 4; i++) {
      await advanceToNextDay();
      await advanceTime(18 * 3600 + 1);
      try {
        await game.connect(deployer).advanceGame();
      } catch {
        // Some calls may fail on timing edges; the stall condition is the key check.
      }
    }
    expect(await game.rngStalledForThreeDays()).to.equal(true);
  });

  it("reverseFlip cost escalates with queued nudges and resets after settlement", async function () {
    const { game, deployer, alice, coin, vault, mockVRF, advanceModule } =
      await loadFixture(deployFullProtocol);

    await giveBurnie(coin, vault, alice.address, eth("20000"));

    const tx1 = await game.connect(alice).reverseFlip();
    const ev1 = await getEvent(tx1, advanceModule, "ReverseFlip");
    expect(ev1.args.cost).to.equal(eth(100));

    const tx2 = await game.connect(alice).reverseFlip();
    const ev2 = await getEvent(tx2, advanceModule, "ReverseFlip");
    expect(ev2.args.cost).to.equal(eth(150));

    const tx3 = await game.connect(alice).reverseFlip();
    const ev3 = await getEvent(tx3, advanceModule, "ReverseFlip");
    expect(ev3.args.cost).to.equal(eth(225));

    await runOneDailyCycle(game, deployer, mockVRF, 42n);

    const tx4 = await game.connect(alice).reverseFlip();
    const ev4 = await getEvent(tx4, advanceModule, "ReverseFlip");
    expect(ev4.args.cost).to.equal(eth(100));
  });
});
