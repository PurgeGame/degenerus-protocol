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
import { boCustom } from "../helpers/boxOrder.js";

// Mint-only lootbox spend is not capped or counted: no volume threshold closes anything
// and the level-3 transition changes nothing. The 90/10 future/next split is rake-free for
// every buy regardless of volume. These guards lock that independence.
const MintPaymentKind = { DirectEth: 0 };

// Lootbox ETH split BPS — rake-free 90/10 future/next for every mint-only lootbox
// buy (must match LOOTBOX_SPLIT_FUTURE_BPS / LOOTBOX_SPLIT_NEXT_BPS in
// DegenerusGameMintModule). The vault gets 0.
const FUTURE_BPS = 9000n;
const NEXT_BPS = 1000n;

describe("Mint-lootbox routing is independent of volume", function () {
  after(() => restoreAddresses());

  async function buyLootbox(game, signer, amount) {
    return game
      .connect(signer)
      .purchaseOrderFor(
        0,
        0n,
        boCustom(amount),
        ZERO_BYTES32,
        MintPaymentKind.DirectEth,
        false,
        { value: amount }
      );
  }

  async function getLootBoxBuyEvent(tx, mintModule) {
    const events = await getEvents(tx, mintModule, "LootBoxBuy");
    expect(events.length).to.equal(1);
    return events[0];
  }

  // -------------------------------------------------------------------------
  // 1. Mint-only lootbox volume never changes the routing (the key invariant)
  // -------------------------------------------------------------------------
  async function expectSplit(game, signer, amount) {
    const futureBefore = await game.futurePrizePoolView();
    const nextBefore = await game.nextPrizePoolView();
    await buyLootbox(game, signer, amount);
    expect((await game.futurePrizePoolView()) - futureBefore).to.equal(
      (amount * FUTURE_BPS) / 10_000n
    );
    expect((await game.nextPrizePoolView()) - nextBefore).to.equal(
      (amount * NEXT_BPS) / 10_000n
    );
  }

  it("the split holds well past the former 200-ETH mint cap", async () => {
    const { game, alice, bob, carol } = await loadFixture(deployFullProtocol);
    await expectSplit(game, alice, eth("100"));
    await expectSplit(game, bob, eth("150"));
    await expectSplit(game, carol, eth("120")); // cumulative = 370 ETH mint-lootbox
  });

  it("a single very large mint-only lootbox buy routes the same split", async () => {
    const { game, alice } = await loadFixture(deployFullProtocol);
    await expectSplit(game, alice, eth("500"));
  });

  it("the split holds across many mint-only lootbox buys", async () => {
    const { game, bob, carol } = await loadFixture(deployFullProtocol);
    for (let i = 0; i < 6; i++) {
      await expectSplit(game, bob, eth("30"));
      await expectSplit(game, carol, eth("30"));
    }
  });

  // -------------------------------------------------------------------------
  // 2. Mint-only lootbox buys emit the canonical box-creation event
  // -------------------------------------------------------------------------
  it("mint-only lootbox buy emits LootBoxBuy", async () => {
    const { game, alice, mintModule } = await loadFixture(deployFullProtocol);
    const tx = await buyLootbox(game, alice, eth("250"));
    const ev = await getLootBoxBuyEvent(tx, mintModule);
    expect(ev.fragment.inputs.map((input) => input.name)).to.deep.equal([
      "buyer",
      "index",
      "position",
      "amount",
    ]);
    expect(ev.args.buyer).to.equal(await game.walletIdOf_g3120(alice.address));
    expect(ev.args.amount).to.equal(eth("250"));
  });

  // -------------------------------------------------------------------------
  // 3. Rake-free 90/10 future/next split, vault gets 0
  // -------------------------------------------------------------------------
  it("mint-only lootbox routes the rake-free 90/10 future/next split with no vault cut", async () => {
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

    expect(vaultAfter - vaultBefore).to.equal(0n);
    expect(futureAfter - futureBefore).to.equal((amount * FUTURE_BPS) / 10_000n);
    expect(nextAfter - nextBefore).to.equal((amount * NEXT_BPS) / 10_000n);
  });
});
