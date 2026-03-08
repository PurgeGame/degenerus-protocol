import hre from "hardhat";

const { ethers, network } = hre;

function formatError(error) {
  if (!error) return "unknown error";
  if (error.shortMessage) return error.shortMessage;
  if (error.message) return error.message.split("\n")[0];
  return String(error);
}

const MAX_UINT32 = (1n << 32n) - 1n;

export class PlayerManager {
  constructor({ signers, contracts, stats }) {
    this.signers = signers;
    this.contracts = contracts;
    this.stats = stats;
    this.players = [];
    this.affiliateCodes = new Map();
  }

  async initPlayers() {
    for (let i = 0; i < 20; i += 1) {
      const signer = this.signers[i];
      const address = await signer.getAddress();
      let group = "Conservative";
      let passType = 0;
      if (i <= 9) {
        group = "Deity";
        passType = 1;
      } else if (i <= 14) {
        group = "Whale";
        passType = 2;
      }
      this.players.push({ index: i, signer, address, group, passType });
    }
  }

  getPlayer(index) {
    return this.players[index];
  }

  async safeAction({ label, playerIndex, action }) {
    try {
      return await action();
    } catch (error) {
      console.log(
        `  ${label} failed (player ${playerIndex}): ${formatError(error)}`
      );
      return null;
    }
  }

  async setupReferrals() {
    const affiliate = this.contracts.affiliate;
    const referrersA = [0, 1, 2, 3, 4];
    const referrersB = [10, 11, 12];

    for (const idx of [...referrersA, ...referrersB]) {
      const player = this.getPlayer(idx);
      const code = ethers.id(`REF_${idx}`);
      await this.safeAction({
        label: "createAffiliateCode",
        playerIndex: idx,
        action: async () => {
          await affiliate.connect(player.signer).createAffiliateCode(code, 10);
          this.affiliateCodes.set(idx, code);
        }
      });
    }

    for (let i = 5; i <= 9; i += 1) {
      const refIdx = referrersA[(i - 5) % referrersA.length];
      const code = this.affiliateCodes.get(refIdx);
      await this.safeAction({
        label: "referPlayer",
        playerIndex: i,
        action: async () => {
          await affiliate.connect(this.getPlayer(i).signer).referPlayer(code);
        }
      });
    }

    for (let i = 13; i <= 14; i += 1) {
      const refIdx = referrersB[(i - 13) % referrersB.length];
      const code = this.affiliateCodes.get(refIdx);
      await this.safeAction({
        label: "referPlayer",
        playerIndex: i,
        action: async () => {
          await affiliate.connect(this.getPlayer(i).signer).referPlayer(code);
        }
      });
    }
  }

  async purchaseDeityPasses() {
    const game = this.contracts.game;
    for (let i = 0; i <= 9; i += 1) {
      const symbolId = i % 32;
      await this.safeAction({
        label: "purchaseDeityPass",
        playerIndex: i,
        action: async () => {
          // Deity pass price: 24 + T(n) ETH where T(n) = n*(n+1)/2
          // For the first few, just send enough ETH (contract calculates exact price)
          const price = ethers.parseEther("50");
          await game.connect(this.getPlayer(i).signer).purchaseDeityPass(
            ethers.ZeroAddress,
            symbolId,
            { value: price }
          );
          // Contract refunds excess, track approximate
          this.stats.recordTickets(i, 560n);
        }
      });
    }
  }

  async purchaseWhaleBundles() {
    const game = this.contracts.game;
    // Whale bundle: 2.4 ETH per bundle at levels 0-3
    const price = ethers.parseEther("2.4");
    for (let i = 10; i <= 14; i += 1) {
      await this.safeAction({
        label: "purchaseWhaleBundle",
        playerIndex: i,
        action: async () => {
          await game.connect(this.getPlayer(i).signer).purchaseWhaleBundle(
            ethers.ZeroAddress,
            1,
            { value: price }
          );
          this.stats.recordEthSpend(i, price);
          this.stats.recordTickets(i, 40n);
        }
      });
    }
  }

  async configureAfk() {
    const game = this.contracts.game;
    const whaleEthKeep = ethers.parseEther("10");
    const whaleBurnieKeep = ethers.parseEther("200000");
    const deityBurnieKeep = ethers.parseEther("100000");

    for (let i = 0; i <= 9; i += 1) {
      await this.safeAction({
        label: "setAfKingMode",
        playerIndex: i,
        action: async () => {
          await game
            .connect(this.getPlayer(i).signer)
            .setAfKingMode(ethers.ZeroAddress, true, 0, deityBurnieKeep);
        }
      });
    }

    for (let i = 10; i <= 14; i += 1) {
      await this.safeAction({
        label: "setAfKingMode",
        playerIndex: i,
        action: async () => {
          await game
            .connect(this.getPlayer(i).signer)
            .setAfKingMode(ethers.ZeroAddress, true, whaleEthKeep, whaleBurnieKeep);
        }
      });
    }
  }

  async mintBurnieToAll(amount) {
    const coin = this.contracts.coin;
    const gameAddress = await this.contracts.game.getAddress();

    const originalBalance = await ethers.provider.getBalance(gameAddress);

    await network.provider.send("hardhat_impersonateAccount", [gameAddress]);
    await network.provider.send("hardhat_setBalance", [
      gameAddress,
      "0x56BC75E2D63100000" // 100 ETH in hex
    ]);
    const gameSigner = await ethers.getSigner(gameAddress);

    for (let i = 0; i < this.players.length; i += 1) {
      await coin.connect(gameSigner).mintForGame(this.players[i].address, amount);
    }

    await network.provider.send("hardhat_stopImpersonatingAccount", [gameAddress]);

    const balanceHex = "0x" + originalBalance.toString(16);
    await network.provider.send("hardhat_setBalance", [gameAddress, balanceHex]);
  }

  /**
   * Purchase tickets via game.purchase().
   * ticketCount = number of "ticket units" (each unit = quantity 100 = costs priceWei/4).
   */
  async purchaseTickets({ playerIndex, ticketCount, affiliateCode }) {
    const game = this.contracts.game;
    const player = this.getPlayer(playerIndex);
    const mintPrice = await game.mintPrice();
    const ticketCountBig = typeof ticketCount === "bigint" ? ticketCount : BigInt(ticketCount);
    let ticketQuantity = ticketCountBig * 100n;
    if (ticketQuantity > MAX_UINT32) {
      ticketQuantity = MAX_UINT32;
    }
    const adjustedTicketCount = ticketQuantity / 100n;
    // cost = (priceWei * ticketQuantity) / 400
    const cost = (mintPrice * ticketQuantity) / 400n;

    return this.safeAction({
      label: "purchaseTickets",
      playerIndex,
      action: async () => {
        await game.connect(player.signer).purchase(
          player.address,
          ticketQuantity,
          0,
          affiliateCode || ethers.ZeroHash,
          0,
          { value: cost }
        );
        this.stats.recordEthSpend(playerIndex, cost);
        this.stats.recordTickets(playerIndex, adjustedTicketCount);
        return adjustedTicketCount;
      }
    });
  }

  async purchaseLootbox({ playerIndex, amountWei, affiliateCode }) {
    const game = this.contracts.game;
    const player = this.getPlayer(playerIndex);
    const lootboxIndex = await game.lootboxRngIndexView();

    const result = await this.safeAction({
      label: "purchaseLootbox",
      playerIndex,
      action: async () => {
        await game.connect(player.signer).purchase(
          player.address,
          0,
          amountWei,
          affiliateCode || ethers.ZeroHash,
          0,
          { value: amountWei }
        );
        this.stats.recordLootboxPurchase(playerIndex, amountWei);
      }
    });

    if (!result) return null;
    return lootboxIndex;
  }

  async openLootbox({ playerIndex, lootboxIndex }) {
    const game = this.contracts.game;
    const player = this.getPlayer(playerIndex);
    const gameAddress = await game.getAddress();
    const receipt = await this.safeAction({
      label: "openLootbox",
      playerIndex,
      action: async () => {
        const tx = await game
          .connect(player.signer)
          .openLootBox(ethers.ZeroAddress, lootboxIndex);
        return tx.wait();
      }
    });

    if (!receipt) return false;
    for (const log of receipt.logs) {
      if (log.address.toLowerCase() !== gameAddress.toLowerCase()) {
        continue;
      }
      try {
        const parsed = game.interface.parseLog(log);
        if (parsed && parsed.name === "LootBoxOpened") {
          const futureTickets = BigInt(parsed.args.futureTickets);
          const currentTickets = BigInt(parsed.args.currentTickets);
          this.stats.recordTickets(playerIndex, futureTickets + currentTickets);
          return true;
        }
      } catch {
        // Ignore non-matching logs.
      }
    }
    return true;
  }

  async depositCoinflip({ playerIndex, amount, targetDay }) {
    const coinflip = this.contracts.coinflip;
    const player = this.getPlayer(playerIndex);
    await this.safeAction({
      label: "depositCoinflip",
      playerIndex,
      action: async () => {
        await coinflip.connect(player.signer).depositCoinflip(player.address, amount);
        this.stats.recordCoinflipDeposit(playerIndex, amount, targetDay);
      }
    });
  }
}
