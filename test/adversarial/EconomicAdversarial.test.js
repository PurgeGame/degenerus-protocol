import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  advanceToNextDay,
  eth,
  getEvent,
  getEvents,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

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

async function resolveCoinflipDay(game, coinflip, epoch, rngWord) {
  const gameAddr = await game.getAddress();
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [gameAddr],
  });
  await hre.ethers.provider.send("hardhat_setBalance", [
    gameAddr,
    "0x1000000000000000000",
  ]);
  const gameSigner = await hre.ethers.getSigner(gameAddr);
  await coinflip
    .connect(gameSigner)
    .processCoinflipPayouts(false, rngWord, epoch);
  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [gameAddr],
  });
}

async function advanceUntilLevel(
  game,
  mockVRF,
  caller,
  targetLevel,
  maxDays = 180,
  requireUnlocked = false
) {
  let requestId = await getLastVRFRequestId(mockVRF);
  for (let day = 0; day < maxDays; day++) {
    const levelBefore = await game.level();
    if (levelBefore >= targetLevel) {
      if (!requireUnlocked || !(await game.rngLocked())) return;
    }

    await advanceToNextDay();
    await game.connect(caller).advanceGame();

    let levelNow = await game.level();
    if (levelNow >= targetLevel) {
      if (!requireUnlocked || !(await game.rngLocked())) return;
    }

    const nextRequestId = await getLastVRFRequestId(mockVRF);
    if (nextRequestId > requestId) {
      await mockVRF.fulfillRandomWords(nextRequestId, 111_000n + BigInt(day));
      await game.connect(caller).advanceGame();
      levelNow = await game.level();
      if (levelNow >= targetLevel) {
        if (!requireUnlocked || !(await game.rngLocked())) return;
      }
      requestId = nextRequestId;
    }
  }
  throw new Error(`failed to reach level ${targetLevel.toString()} within ${maxDays} days`);
}

function weightedBucket(value32) {
  const scaled = (value32 * 75n) >> 32n;
  if (scaled < 10n) return 0n;
  if (scaled < 20n) return 1n;
  if (scaled < 30n) return 2n;
  if (scaled < 40n) return 3n;
  if (scaled < 49n) return 4n;
  if (scaled < 58n) return 5n;
  if (scaled < 67n) return 6n;
  return 7n;
}

function traitFromWord(value64) {
  const low = value64 & 0xffffffffn;
  const high = (value64 >> 32n) & 0xffffffffn;
  const category = weightedBucket(low);
  const sub = weightedBucket(high);
  return (category << 3n) | sub;
}

function packedTraitsFromSeed(seed) {
  const mask64 = (1n << 64n) - 1n;
  const traitA = traitFromWord(seed & mask64);
  const traitB = traitFromWord((seed >> 64n) & mask64) | 64n;
  const traitC = traitFromWord((seed >> 128n) & mask64) | 128n;
  const traitD = traitFromWord((seed >> 192n) & mask64) | 192n;
  return Number(
    traitA | (traitB << 8n) | (traitC << 16n) | (traitD << 24n)
  );
}

describe("Economic Adversarial Suite", function () {
  this.timeout(600_000);

  after(function () {
    restoreAddresses();
  });

  it("caps non-deity recycling extraction at 1000 BURNIE per rebet", async function () {
    const { game, coinflip, coin, vault, alice } = await loadFixture(
      deployFullProtocol
    );

    await giveBurnie(coin, vault, alice.address, eth("2000000"));

    const firstStake = eth("500000");
    const firstDepositTx = await coinflip
      .connect(alice)
      .depositCoinflip(ZERO_ADDRESS, firstStake);
    const firstStakeEvent = await getEvent(
      firstDepositTx,
      coinflip,
      "CoinflipStakeUpdated"
    );
    const targetDay = firstStakeEvent.args.day;

    // Odd rngWord => win day.
    await resolveCoinflipDay(game, coinflip, targetDay, 1n);

    const secondStake = eth("200000");
    const secondDepositTx = await coinflip
      .connect(alice)
      .depositCoinflip(ZERO_ADDRESS, secondStake);
    const secondStakeEvent = await getEvent(
      secondDepositTx,
      coinflip,
      "CoinflipStakeUpdated"
    );

    const observedBonus = secondStakeEvent.args.amount - secondStake;
    expect(observedBonus).to.equal(eth(1000));
  });

  it("enforces the Degenerette ETH payout cap at 10% of futurePrizePool on extreme wins", async function () {
    const {
      game,
      deployer,
      alice,
      mockVRF,
      degeneretteModule,
    } = await loadFixture(deployFullProtocol);

    const rngWord = 987654321n;
    const lootboxIndex = await game.lootboxRngIndexView();
    const resultSeedHex = hre.ethers.solidityPackedKeccak256(
      ["uint256", "uint48", "bytes1"],
      [rngWord, lootboxIndex, "0x51"] // QUICK_PLAY_SALT
    );
    const resultSeed = BigInt(resultSeedHex);
    const forcedTicket = packedTraitsFromSeed(resultSeed);

    const amountPerTicket = eth("0.01");
    const placeTx = await game.connect(alice).placeFullTicketBets(
      ZERO_ADDRESS,
      0, // ETH
      amountPerTicket,
      1,
      forcedTicket,
      255,
      { value: amountPerTicket }
    );
    const betPlaced = await getEvent(placeTx, degeneretteModule, "BetPlaced");
    const betId = betPlaced.args.betId;

    await advanceToNextDay();
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    await mockVRF.fulfillRandomWords(requestId, rngWord);
    await game.connect(deployer).advanceGame();

    expect(await game.lootboxRngWord(lootboxIndex)).to.not.equal(0n);

    const poolBefore = await game.rewardPoolView();
    const claimableBefore = await game.claimableWinningsOf(alice.address);
    const maxEth = (poolBefore * 1000n) / 10_000n;

    const resolveTx = await game
      .connect(alice)
      .resolveDegeneretteBets(ZERO_ADDRESS, [betId]);
    const cappedEvents = await getEvents(resolveTx, degeneretteModule, "PayoutCapped");
    expect(cappedEvents.length).to.be.gte(1);
    expect(cappedEvents[0].args.cappedEthPayout).to.equal(maxEth);

    const claimableAfter = await game.claimableWinningsOf(alice.address);
    expect(claimableAfter - claimableBefore).to.equal(maxEth);
  });

  it("locks self-referral attempts to the vault fallback during real purchases", async function () {
    const { game, affiliate, bob, vault } = await loadFixture(deployFullProtocol);

    const bobCode = hre.ethers.encodeBytes32String("BOB_REF");
    await affiliate.connect(bob).createAffiliateCode(bobCode, 10);

    const mintPrice = await game.mintPrice();
    await game.connect(bob).purchase(
      ZERO_ADDRESS,
      400n,
      0n,
      bobCode,
      MintPaymentKind.DirectEth,
      { value: mintPrice }
    );

    const referrer = await affiliate.getReferrer(bob.address);
    expect(referrer).to.equal(await vault.getAddress());
  });

  it("applies deity affiliate claim flip bonus as 20% of score (not 200x)", async function () {
    const { game, coinflip, affiliate, mockVRF, deployer, alice, bob, carol } =
      await loadFixture(deployFullProtocol);

    // Give Alice a deity pass so claim path enables the deity bonus branch.
    await game.connect(alice).purchaseDeityPass(ZERO_ADDRESS, 0, {
      value: eth("24"),
    });

    const aliceCode = hre.ethers.encodeBytes32String("ALICE_REF");
    await affiliate.connect(alice).createAffiliateCode(aliceCode, 0);

    // Level-1 affiliate activity for Alice.
    await game.connect(bob).purchase(
      ZERO_ADDRESS,
      2_400_000n,
      0n,
      aliceCode,
      MintPaymentKind.DirectEth,
      { value: eth("60") }
    );

    const level1Score = await affiliate.affiliateScore(1, alice.address);
    expect(level1Score).to.be.gt(0n);

    await advanceUntilLevel(game, mockVRF, deployer, 1n, 180, true);

    // Feed level-2 threshold so we can claim level-1 affiliate DGNRS at level 2.
    await game.connect(carol).purchase(
      ZERO_ADDRESS,
      2_800_000n,
      0n,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      { value: eth("70") }
    );

    await advanceUntilLevel(game, mockVRF, deployer, 2n);
    expect(await game.level()).to.equal(2n);

    const expectedBonus = (level1Score * 2000n) / 10_000n;
    expect(expectedBonus).to.be.gt(0n);

    const preStake = await coinflip.coinflipAmount(alice.address);
    const claimTx = await game.connect(alice).claimAffiliateDgnrs(ZERO_ADDRESS);
    const stakeEvents = await getEvents(claimTx, coinflip, "CoinflipStakeUpdated");
    const aliceStakeEvent = stakeEvents.find(
      (ev) => ev.args.player.toLowerCase() === alice.address.toLowerCase()
    );
    expect(aliceStakeEvent).to.not.equal(undefined);
    expect(aliceStakeEvent.args.amount).to.equal(expectedBonus);

    const postStake = await coinflip.coinflipAmount(alice.address);
    expect(postStake - preStake).to.equal(expectedBonus);
  });
});
