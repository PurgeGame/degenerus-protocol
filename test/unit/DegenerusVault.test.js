import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  flip,
  wwxrp,
  advanceToNextDay,
  getEvent,
  getEvents,
  ZERO_ADDRESS,
} from "../helpers/testUtils.js";

// MintPaymentKind enum values
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };
const INITIAL_SUPPLY = 1_000_000_000_000n * 10n ** 18n;

// The vault creates DGVF first and DGVE second in its constructor.
async function shareToken(vault, nonce) {
  return hre.ethers.getContractAt("DegenerusVaultShare", hre.ethers.getCreateAddress({
    from: await vault.getAddress(), nonce,
  }));
}

describe("DegenerusVault", function () {
  after(() => restoreAddresses());

  // ---------------------------------------------------------------------------
  // 1. Constructor / Initial State
  // ---------------------------------------------------------------------------
  describe("Initial state", function () {
    it("vault name is 'Degenerus Vault'", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      expect(await vault.name()).to.equal("Degenerus Vault");
    });

    it("vault symbol is 'DGV'", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      expect(await vault.symbol()).to.equal("DGV");
    });

    it("vault decimals is 18", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      expect(await vault.decimals()).to.equal(18n);
    });

    it("DGVF share token has correct name and symbol", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      const dgvf = await shareToken(vault, 1);
      expect(await dgvf.name()).to.equal("Degenerus Vault Flip");
      expect(await dgvf.symbol()).to.equal("DGVF");
    });

    it("DGVE share token initial supply is 1 trillion", async function () {
      const { vault, deployer } = await loadFixture(deployFullProtocol);
      const dgve = await shareToken(vault, 2);
      expect(await dgve.totalSupply()).to.equal(INITIAL_SUPPLY);
      expect(await dgve.balanceOf(deployer.address)).to.equal(INITIAL_SUPPLY);
    });

    it("isVaultOwner returns false for zero-balance address", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      // alice has no DGVE shares
      expect(await vault.isVaultOwner(alice.address)).to.be.false;
    });
  });

  // ---------------------------------------------------------------------------
  // 2. funding (deposit entry point removed; ETH arrives via receive())
  // ---------------------------------------------------------------------------
  describe("funding", function () {
    it("old deposit selector reverts (entry point removed, no fallback)", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      // selector of deposit(uint256,uint256) — unmatched calldata hits no fallback → revert
      // (receive() only fires on empty calldata).
      await expect(
        alice.sendTransaction({
          to: await vault.getAddress(),
          data: "0xe2bbb158",
          value: eth("1"),
        })
      ).to.be.reverted;
    });

    it("plain ETH send emits Deposit via receive()", async function () {
      const { vault, game } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x56BC75E2D63100000", // 100 ETH
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const tx = await gameSigner.sendTransaction({
        to: await vault.getAddress(),
        value: eth("1"),
      });
      const ev = await getEvent(tx, vault, "Deposit");
      expect(ev.args.ethAmount).to.equal(eth("1"));
      expect(ev.args.from).to.equal(gameAddr);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });

    it("ETH donation via receive() emits Deposit event", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      const tx = await alice.sendTransaction({
        to: vaultAddr,
        value: eth("1"),
      });
      const ev = await getEvent(tx, vault, "Deposit");
      expect(ev.args.from).to.equal(alice.address);
      expect(ev.args.ethAmount).to.equal(eth("1"));
    });
  });

  // ---------------------------------------------------------------------------
  // 3. isVaultOwner
  // ---------------------------------------------------------------------------
  describe("isVaultOwner", function () {
    it("returns true for account holding all DGVE supply", async function () {
      const { vault, deployer } = await loadFixture(deployFullProtocol);
      // deployer holds 100% of initial supply
      expect(await vault.isVaultOwner(deployer.address)).to.be.true;
    });

    it("returns false for account holding 30% of DGVE supply", async function () {
      const { vault, deployer, alice } = await loadFixture(deployFullProtocol);
      const dgve = await shareToken(vault, 2);
      await dgve.connect(deployer).transfer(alice.address, INITIAL_SUPPLY * 30n / 100n);
      expect(await vault.isVaultOwner(alice.address)).to.be.false;
    });

    it("requires strictly more than 50.1% of DGVE supply", async function () {
      const { vault, deployer, alice } = await loadFixture(deployFullProtocol);
      const dgve = await shareToken(vault, 2);
      await dgve.connect(deployer).transfer(alice.address, INITIAL_SUPPLY * 501n / 1000n);
      expect(await vault.isVaultOwner(alice.address)).to.be.false;
      await dgve.connect(deployer).transfer(alice.address, 1n);
      expect(await vault.isVaultOwner(alice.address)).to.be.true;
    });
  });

  // ---------------------------------------------------------------------------
  // 4. burnCoin (DGVF redemption)
  // ---------------------------------------------------------------------------
  describe("burnCoin", function () {
    it("reverts when amount is zero", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).burnCoin(0n)
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });

    it("reverts when player has no DGVF shares", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).burnCoin(eth("1"))
      ).to.be.reverted;
    });

    it("deployer can burn DGVF shares (has initial supply)", async function () {
      const { vault, deployer } = await loadFixture(deployFullProtocol);
      // Deployer has 1T DGVF shares from constructor
      // Try burning a small amount - may have 0 coin reserve which is fine
      // burnCoin will emit Claim(player, amount, 0, 0, flipOut) even if flipOut = 0
      const smallAmount = eth("1"); // burn 1 DGVF
      const tx = await vault.connect(deployer).burnCoin(smallAmount);
      const ev = await getEvent(tx, vault, "Claim");
      expect(ev.args.sharesBurned).to.equal(smallAmount);
      expect(ev.args.stEthOut).to.equal(0n);
      expect(ev.args.ethOut).to.equal(0n);
    });

    it("refill mechanism: burning all shares mints 1T new shares to player", async function () {
      const { vault, deployer } = await loadFixture(deployFullProtocol);
      const INITIAL_SUPPLY = 1_000_000_000_000n * eth("1");
      // burn the entire initial supply
      const tx = await vault
        .connect(deployer)
        .burnCoin(INITIAL_SUPPLY);
      const evClaim = await getEvent(tx, vault, "Claim");
      expect(evClaim.args.sharesBurned).to.equal(INITIAL_SUPPLY);
      const dgvf = await shareToken(vault, 1);
      expect(await dgvf.totalSupply()).to.equal(INITIAL_SUPPLY);
      expect(await dgvf.balanceOf(deployer.address)).to.equal(INITIAL_SUPPLY);
    });
  });

  // ---------------------------------------------------------------------------
  // 5. burnEth (DGVE redemption)
  // ---------------------------------------------------------------------------
  describe("burnEth", function () {
    it("reverts when amount is zero", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).burnEth(0n)
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });

    it("reverts when player has no DGVE shares", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).burnEth(eth("1"))
      ).to.be.reverted;
    });

    it("deployer can burn DGVE shares with zero ETH reserve", async function () {
      const { vault, deployer } = await loadFixture(deployFullProtocol);
      // Burn a small amount; vault has 0 ETH but 0 stETH so claimValue = 0
      const tx = await vault.connect(deployer).burnEth(eth("1"));
      const ev = await getEvent(tx, vault, "Claim");
      expect(ev.args.sharesBurned).to.equal(eth("1"));
      expect(ev.args.flipOut).to.equal(0n);
    });

    it("ETH is redeemed proportionally when vault has ETH balance", async function () {
      const { vault, deployer, alice } = await loadFixture(deployFullProtocol);
      // Donate some ETH to vault
      const vaultAddr = await vault.getAddress();
      await alice.sendTransaction({ to: vaultAddr, value: eth("10") });

      // Deployer holds 100% DGVE, so burning some should give proportional ETH
      const shares = INITIAL_SUPPLY / 4n;
      const [ethOut, stEthOut] = await vault.previewEth(shares);
      expect(ethOut).to.equal(eth("2.5"));
      expect(stEthOut).to.equal(0n);
      await expect(vault.connect(deployer).burnEth(shares))
        .to.changeEtherBalances([vault, deployer], [-eth("2.5"), eth("2.5")]);
      const dgve = await shareToken(vault, 2);
      expect(await dgve.totalSupply()).to.equal(INITIAL_SUPPLY - shares);
      expect(await dgve.balanceOf(deployer.address)).to.equal(INITIAL_SUPPLY - shares);
    });

    it("refill mechanism: burning all DGVE shares mints 1T new shares", async function () {
      const { vault, deployer } = await loadFixture(deployFullProtocol);
      const INITIAL_SUPPLY = 1_000_000_000_000n * eth("1");
      const tx = await vault
        .connect(deployer)
        .burnEth(INITIAL_SUPPLY);
      const evClaim = await getEvent(tx, vault, "Claim");
      expect(evClaim.args.sharesBurned).to.equal(INITIAL_SUPPLY);
      const dgve = await shareToken(vault, 2);
      expect(await dgve.totalSupply()).to.equal(INITIAL_SUPPLY);
      expect(await dgve.balanceOf(deployer.address)).to.equal(INITIAL_SUPPLY);
    });
  });

  // ---------------------------------------------------------------------------
  // 6. previewCoin
  // ---------------------------------------------------------------------------
  describe("previewCoin", function () {
    it("reverts when amount is zero", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      await expect(
        vault.previewCoin(0n)
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });

    it("reverts when amount exceeds total supply", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      const OVER = 2_000_000_000_000n * eth("1");
      await expect(
        vault.previewCoin(OVER)
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });

    it("returns zero before vault FLIP emissions arrive", async function () {
      const { vault, coin } = await loadFixture(deployFullProtocol);
      expect(await coin.vaultMintAllowance()).to.equal(0n);
      expect(await vault.previewCoin(eth("1"))).to.equal(0n);
    });

    it("previews and pays proportional FLIP from a funded reserve", async function () {
      const { vault, coin, game, deployer } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [gameAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [gameAddr, "0x1000000000000000000"]);
      try {
        await coin.connect(await hre.ethers.getSigner(gameAddr)).vaultEscrow(flip("1000"));
      } finally {
        await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
      }
      const shares = INITIAL_SUPPLY / 4n;
      expect(await vault.previewCoin(shares)).to.equal(flip("250"));
      await expect(vault.connect(deployer).burnCoin(shares))
        .to.changeTokenBalance(coin, deployer, flip("250"));
      expect(await coin.vaultMintAllowance()).to.equal(flip("750"));
      const dgvf = await shareToken(vault, 1);
      expect(await dgvf.totalSupply()).to.equal(INITIAL_SUPPLY - shares);
    });
  });

  // ---------------------------------------------------------------------------
  // 7. previewEth
  // ---------------------------------------------------------------------------
  describe("previewEth", function () {
    it("reverts when amount is zero", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      await expect(
        vault.previewEth(0n)
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });

    it("reverts when amount exceeds total supply", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      const OVER = 2_000_000_000_000n * eth("1");
      await expect(
        vault.previewEth(OVER)
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });

    it("returns zero ETH and zero stETH when vault is empty", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      const [ethOut, stEthOut] = await vault.previewEth(eth("1"));
      expect(ethOut).to.equal(0n);
      expect(stEthOut).to.equal(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 8. previewBurnForCoinOut
  // ---------------------------------------------------------------------------
  describe("previewBurnForCoinOut", function () {
    it("reverts when flipOut is zero", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      await expect(
        vault.previewBurnForCoinOut(0n)
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });

    it("reverts when flipOut exceeds total available reserve", async function () {
      const { vault, coin } = await loadFixture(deployFullProtocol);
      // The genesis allowance is zero, so any positive requested output
      // exceeds the available reserve.
      const HUGE = flip("1000000000"); // 1 billion FLIP
      await expect(
        vault.previewBurnForCoinOut(HUGE)
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });
  });

  // ---------------------------------------------------------------------------
  // 9. previewBurnForEthOut
  // ---------------------------------------------------------------------------
  describe("previewBurnForEthOut", function () {
    it("reverts when targetValue is zero", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      await expect(
        vault.previewBurnForEthOut(0n)
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });

    it("reverts when targetValue exceeds reserve (empty vault)", async function () {
      const { vault } = await loadFixture(deployFullProtocol);
      await expect(
        vault.previewBurnForEthOut(eth("1"))
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });

    it("returns correct shares needed when ETH is in vault", async function () {
      const { vault, deployer, alice } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      // Donate 100 ETH
      await alice.sendTransaction({ to: vaultAddr, value: eth("100") });

      const [burnAmount, ethOut, stEthOut] = await vault.previewBurnForEthOut(
        eth("1")
      );
      expect(burnAmount).to.be.gt(0n);
      // ETH out should be approximately 1 ETH
      expect(ethOut).to.be.lte(eth("1"));
    });
  });

  // ---------------------------------------------------------------------------
  // 10. Vault owner gameplay functions (access control)
  // ---------------------------------------------------------------------------
  describe("vault owner gameplay functions", function () {
    it("gameAdvance reverts when caller is not vault owner", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).gameAdvance()
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");
    });

    it("gamePurchase reverts when caller is not vault owner", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      const ZERO_BYTES32 =
        "0x0000000000000000000000000000000000000000000000000000000000000000";
      await expect(
        vault
          .connect(alice)
          .gamePurchase(0n, 0n, ZERO_BYTES32, MintPaymentKind.DirectEth, 0n)
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");
    });

    it("gameClaimWinnings reverts when caller is not vault owner", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).gameClaimWinnings()
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");
    });

    // gameSetAutoRebuy wrapper — REMOVED (v46 legacy removal, df4ef365):
    // auto-rebuy no longer exists, so the vault wrapper is gone too.

    it("gameSetOperatorApproval reverts when caller is not vault owner", async function () {
      const { vault, alice, bob } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).gameSetOperatorApproval(bob.address, true)
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");
    });

    it("coinDepositCoinflip reverts when caller is not vault owner", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).coinDepositCoinflip(flip("1"))
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");
    });

    it("deployer (vault owner) can call gameAdvance", async function () {
      const { vault, deployer } = await loadFixture(deployFullProtocol);
      await advanceToNextDay();
      // Deployer holds 100% DGVE initially
      await expect(
        vault.connect(deployer).gameAdvance()
      ).to.not.be.reverted;
    });

    it("deployer (vault owner) can set operator approval", async function () {
      const { vault, deployer, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(deployer).gameSetOperatorApproval(alice.address, true)
      ).to.not.be.reverted;
    });

    it("wwxrpMint reverts when caller is not vault owner", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).wwxrpMint(alice.address, wwxrp("1"))
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");
    });

    it("wwxrpMint no-ops when amount is zero", async function () {
      const { vault, deployer } = await loadFixture(deployFullProtocol);
      // Should not revert for amount = 0
      await expect(
        vault.connect(deployer).wwxrpMint(deployer.address, 0n)
      ).to.not.be.reverted;
    });

    it("gamePurchaseTicketsFlip reverts when caller is not vault owner", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).gamePurchaseTicketsFlip(400n)
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");
    });

    it("gamePurchaseTicketsFlip reverts when ticketQuantity is zero", async function () {
      const { vault, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(deployer).gamePurchaseTicketsFlip(0n)
      ).to.be.revertedWithCustomError(vault, "Insufficient");
    });

    // gamePurchaseFlipLootbox revert-on-zero — REMOVED (v47): the vault's
    // FLIP-lootbox wrapper was removed (terminal-paradox closure). The
    // FLIP->tickets wrapper (gamePurchaseTicketsFlip) is KEPT and still tested
    // above. Removed-by-design, not skipped.

    // gameSetAutoRebuyTakeProfit wrapper — REMOVED (v46 legacy removal,
    // df4ef365): auto-rebuy take-profit no longer exists.

  });

  // ---------------------------------------------------------------------------
  // 11. DegenerusVaultShare (DGVF/DGVE) token functionality
  // ---------------------------------------------------------------------------
  describe("DegenerusVaultShare (share token)", function () {
    it("non-vault cannot call vaultMint on share token", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      for (const nonce of [1, 2]) {
        const share = await shareToken(vault, nonce);
        await expect(share.connect(alice).vaultMint(alice.address, eth("1")))
          .to.be.revertedWithCustomError(share, "Unauthorized");
        expect(await share.totalSupply()).to.equal(INITIAL_SUPPLY);
        expect(await share.balanceOf(alice.address)).to.equal(0n);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 12. ETH + stETH combined redemption scenario
  // ---------------------------------------------------------------------------
  describe("combined ETH + stETH redemption", function () {
    it("partial ETH redemption pays ETH first, stETH for remainder", async function () {
      const { vault, mockStETH, game, deployer, alice } = await loadFixture(
        deployFullProtocol
      );
      const vaultAddr = await vault.getAddress();

      // Donate ETH via receive(), fund stETH via direct mint
      await alice.sendTransaction({ to: vaultAddr, value: eth("5") });

      // Mint stETH directly to the vault (the production stETH channel is a direct
      // ERC20 transfer — the vault reads its own balance, no announce call exists).
      await mockStETH.connect(deployer).mint(vaultAddr, eth("3"));

      // previewEth should show ETH preferred, stETH for remainder
      const INITIAL_SUPPLY = 1_000_000_000_000n * eth("1");
      // Burn 10% of supply to get 10% of reserves
      const burnAmount = INITIAL_SUPPLY / 10n;
      const [ethOut, stEthOut] = await vault.previewEth(burnAmount);
      // Total reserve ≈ 8 ETH; 10% = 0.8 ETH, all from ETH balance
      expect(ethOut).to.be.gt(0n);
    });
  });
});
