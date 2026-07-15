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

// Presale is a single latch: `lootboxPresaleActiveFlag()` returns `!presaleOver`,
// where presaleOver is set only by the coin-presale-box 50-ETH cap. Mint-only
// lootbox spend no longer tracks a 200-ETH counter and no longer closes the flag,
// and neither does the level-3 transition. These guards lock that independence.
const MintPaymentKind = { DirectEth: 0 };

// Lootbox ETH split BPS — rake-free 90/10 future/next for every mint-only lootbox
// buy (must match LOOTBOX_SPLIT_FUTURE_BPS / LOOTBOX_SPLIT_NEXT_BPS in
// DegenerusGameMintModule). The vault gets 0 regardless of presale state.
const FUTURE_BPS = 9000n;
const NEXT_BPS = 1000n;

describe("Presale flag is independent of mint-lootbox volume", function () {
  after(() => restoreAddresses());

  async function buyLootbox(game, signer, amount) {
    return game
      .connect(signer)
      .purchase(
        ZERO_ADDRESS,
        0n,
        amount,
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
  // 1. Sanity: the flag mirrors !presaleOver on a fresh deploy
  // -------------------------------------------------------------------------
  it("presale flag is active on fresh deploy", async () => {
    const { game } = await loadFixture(deployFullProtocol);
    expect(await game.lootboxPresaleActiveFlag()).to.equal(true);
    // The box sale is open with its full 50-ETH capacity ahead of it.
    expect(await game.presaleBoxEthRemaining()).to.equal(eth("50"));
  });

  // -------------------------------------------------------------------------
  // 2. Mint-only lootbox volume never closes the flag (the key invariant)
  // -------------------------------------------------------------------------
  it("flag stays on well past the former 200-ETH mint cap", async () => {
    const { game, alice, bob, carol } = await loadFixture(deployFullProtocol);
    await buyLootbox(game, alice, eth("100"));
    await buyLootbox(game, bob, eth("150"));
    await buyLootbox(game, carol, eth("120")); // cumulative = 370 ETH mint-lootbox
    expect(await game.lootboxPresaleActiveFlag()).to.equal(true);
  });

  it("a single very large mint-only lootbox buy does not close the flag", async () => {
    const { game, alice } = await loadFixture(deployFullProtocol);
    await buyLootbox(game, alice, eth("500"));
    expect(await game.lootboxPresaleActiveFlag()).to.equal(true);
  });

  it("the flag stays on across many mint-only lootbox buys (no accidental close)", async () => {
    const { game, alice, bob, carol } = await loadFixture(deployFullProtocol);
    for (let i = 0; i < 6; i++) {
      await buyLootbox(game, bob, eth("30"));
      await buyLootbox(game, carol, eth("30"));
    }
    // 360 ETH of mint lootbox spend, still open — closure is box-cap-only.
    expect(await game.lootboxPresaleActiveFlag()).to.equal(true);
    expect(await game.presaleBoxEthRemaining()).to.equal(eth("50"));
  });

  // -------------------------------------------------------------------------
  // 3. Mint-only lootbox buys emit the canonical box-creation event
  // -------------------------------------------------------------------------
  it("mint-only lootbox buy emits LootBoxBuy while the box sale is open", async () => {
    const { game, alice, mintModule } = await loadFixture(deployFullProtocol);
    const tx = await buyLootbox(game, alice, eth("250"));
    const ev = await getLootBoxBuyEvent(tx, mintModule);
    expect(ev.fragment.inputs.map((input) => input.name)).to.deep.equal([
      "buyer",
      "index",
      "amount",
    ]);
    expect(ev.args.buyer).to.equal(alice.address);
    expect(ev.args.amount).to.equal(eth("250"));
    expect(await game.lootboxPresaleActiveFlag()).to.equal(true);
  });

  // -------------------------------------------------------------------------
  // 4. Rake-free 90/10 future/next split, vault gets 0 (unchanged by presale)
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
