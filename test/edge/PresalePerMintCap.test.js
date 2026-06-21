import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  getEvents,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

// Mirrors the on-chain constant in DegenerusGameStorage.sol:
//   uint256 internal constant LOOTBOX_PRESALE_ETH_CAP = 200 ether;
const PRESALE_CAP = eth("200");
const MintPaymentKind = { DirectEth: 0 };

// Presale split BPS (must match LOOTBOX_PRESALE_SPLIT_* in DegenerusGameMintModule).
const PRESALE_FUTURE_BPS = 5000n;
const PRESALE_NEXT_BPS = 3000n;
const PRESALE_VAULT_BPS = 2000n;

// Post-presale split BPS.
const POST_FUTURE_BPS = 9000n;
const POST_NEXT_BPS = 1000n;

describe("Presale per-mint cap auto-deactivation", function () {
  after(() => restoreAddresses());

  async function buyLootbox(game, signer, amount) {
    return game
      .connect(signer)
      .purchase(
        ZERO_ADDRESS,
        0n,
        amount,
        ZERO_BYTES32,
        MintPaymentKind.DirectEth,false, 
        { value: amount }
      );
  }

  async function getLootBoxBuyEvent(tx, mintModule) {
    const events = await getEvents(tx, mintModule, "LootBoxBuy");
    expect(events.length).to.equal(1);
    return events[0];
  }

  // -------------------------------------------------------------------------
  // 1. Sanity
  // -------------------------------------------------------------------------
  it("presale flag is active on fresh deploy", async () => {
    const { game } = await loadFixture(deployFullProtocol);
    expect(await game.lootboxPresaleActiveFlag()).to.equal(true);
  });

  // -------------------------------------------------------------------------
  // 2. Below-cap accumulation does not deactivate
  // -------------------------------------------------------------------------
  it("flag stays on when cumulative mint-only lootbox ETH stays below cap", async () => {
    const { game, alice, bob, carol } = await loadFixture(deployFullProtocol);
    await buyLootbox(game, alice, eth("50"));
    await buyLootbox(game, bob, eth("75"));
    await buyLootbox(game, carol, eth("74")); // cumulative = 199 ETH
    expect(await game.lootboxPresaleActiveFlag()).to.equal(true);
  });

  it("flag stays on at cumulative = cap - 1 wei", async () => {
    const { game, alice } = await loadFixture(deployFullProtocol);
    await buyLootbox(game, alice, PRESALE_CAP - 1n);
    expect(await game.lootboxPresaleActiveFlag()).to.equal(true);
  });

  // -------------------------------------------------------------------------
  // 3. Cap-hit deactivation paths
  // -------------------------------------------------------------------------
  it("a mint that brings cumulative to exactly the cap deactivates presale", async () => {
    const { game, alice, bob } = await loadFixture(deployFullProtocol);
    await buyLootbox(game, alice, eth("100"));
    expect(await game.lootboxPresaleActiveFlag()).to.equal(true);
    await buyLootbox(game, bob, eth("100")); // cumulative = 200
    expect(await game.lootboxPresaleActiveFlag()).to.equal(false);
  });

  it("a single mint that overshoots the cap deactivates presale", async () => {
    const { game, alice } = await loadFixture(deployFullProtocol);
    await buyLootbox(game, alice, eth("250"));
    expect(await game.lootboxPresaleActiveFlag()).to.equal(false);
  });

  it("the smallest possible overshoot (cap + 1 wei) deactivates presale", async () => {
    const { game, alice } = await loadFixture(deployFullProtocol);
    await buyLootbox(game, alice, PRESALE_CAP + 1n);
    expect(await game.lootboxPresaleActiveFlag()).to.equal(false);
  });

  // -------------------------------------------------------------------------
  // 4. Triggering mint still receives presale terms (intentional)
  // -------------------------------------------------------------------------
  it("triggering mint emits LootBoxBuy with presale=true", async () => {
    const { game, alice, mintModule } = await loadFixture(deployFullProtocol);
    const tx = await buyLootbox(game, alice, eth("250"));
    const ev = await getLootBoxBuyEvent(tx, mintModule);
    expect(ev.args.presale).to.equal(true);
    expect(await game.lootboxPresaleActiveFlag()).to.equal(false);
  });

  it("triggering mint receives the 50/30/20 presale split (vault gets 20%)", async () => {
    const { game, alice, vault } = await loadFixture(deployFullProtocol);
    const vaultAddr = await vault.getAddress();

    const vaultBefore = await hre.ethers.provider.getBalance(vaultAddr);
    const futureBefore = await game.futurePrizePoolView();
    const nextBefore = await game.nextPrizePoolView();

    const amount = eth("250");
    await buyLootbox(game, alice, amount);

    const vaultAfter = await hre.ethers.provider.getBalance(vaultAddr);
    const futureAfter = await game.futurePrizePoolView();
    const nextAfter = await game.nextPrizePoolView();

    expect(vaultAfter - vaultBefore).to.equal((amount * PRESALE_VAULT_BPS) / 10_000n);
    expect(futureAfter - futureBefore).to.equal((amount * PRESALE_FUTURE_BPS) / 10_000n);
    expect(nextAfter - nextBefore).to.equal((amount * PRESALE_NEXT_BPS) / 10_000n);
  });

  // -------------------------------------------------------------------------
  // 5. Subsequent mints get post-presale terms
  // -------------------------------------------------------------------------
  it("mint after the cap-trip uses 90/10 post-presale split (vault gets 0)", async () => {
    const { game, alice, bob, vault, mintModule } = await loadFixture(
      deployFullProtocol
    );
    const vaultAddr = await vault.getAddress();

    // Trip the cap.
    await buyLootbox(game, alice, eth("250"));
    expect(await game.lootboxPresaleActiveFlag()).to.equal(false);

    // Next buy.
    const vaultBefore = await hre.ethers.provider.getBalance(vaultAddr);
    const futureBefore = await game.futurePrizePoolView();
    const nextBefore = await game.nextPrizePoolView();

    const amount = eth("1");
    const tx = await buyLootbox(game, bob, amount);

    const vaultAfter = await hre.ethers.provider.getBalance(vaultAddr);
    const futureAfter = await game.futurePrizePoolView();
    const nextAfter = await game.nextPrizePoolView();

    expect(vaultAfter - vaultBefore).to.equal(0n);
    expect(futureAfter - futureBefore).to.equal((amount * POST_FUTURE_BPS) / 10_000n);
    expect(nextAfter - nextBefore).to.equal((amount * POST_NEXT_BPS) / 10_000n);

    const ev = await getLootBoxBuyEvent(tx, mintModule);
    expect(ev.args.presale).to.equal(false);
  });

  it("flag remains off across many subsequent mints (no accidental re-arming)", async () => {
    const { game, alice, bob, carol } = await loadFixture(deployFullProtocol);
    await buyLootbox(game, alice, eth("250"));
    expect(await game.lootboxPresaleActiveFlag()).to.equal(false);
    for (let i = 0; i < 5; i++) {
      await buyLootbox(game, bob, eth("10"));
      await buyLootbox(game, carol, eth("10"));
    }
    expect(await game.lootboxPresaleActiveFlag()).to.equal(false);
  });
});
