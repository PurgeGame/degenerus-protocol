import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { eth, getEvent, getEvents, ZERO_ADDRESS } from "../helpers/testUtils.js";

/*
 * DegenerusDeityPass Unit Tests
 *
 * Contract: contracts/DegenerusDeityPass.sol
 *
 * Architecture summary:
 *   - Soulbound ERC721 "DEITY" with 32 token slots (tokenId 0-31)
 *   - Admin functions gated by DGVE >50.1% vault ownership (no single-address owner)
 *   - mint() callable only by ContractAddresses.GAME
 *   - All transfers blocked (soulbound) — approve, setApprovalForAll, transferFrom, safeTransferFrom revert
 *   - Optional external renderer (setRenderer) with internal fallback
 *   - setRenderColors() validates hex color format (#rrggbb)
 *   - tokenURI() works for minted tokens, reverts for unminted ones
 */

describe("DegenerusDeityPass", function () {
  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  async function getFixture() {
    return loadFixture(deployFullProtocol);
  }

  async function impersonate(address) {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [address],
    });
    await hre.network.provider.send("hardhat_setBalance", [
      address,
      "0x56BC75E2D63100000", // 100 ETH
    ]);
    return hre.ethers.getSigner(address);
  }

  async function stopImpersonate(address) {
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [address],
    });
  }

  // Mint tokenId via the game contract impersonation
  async function mintViaGame(deityPass, game, to, tokenId) {
    const gameAddr = await game.getAddress();
    const gameSigner = await impersonate(gameAddr);
    await deityPass.connect(gameSigner).mint(to, tokenId);
    await stopImpersonate(gameAddr);
  }

  // ---------------------------------------------------------------------------
  // Initial state / constructor
  // ---------------------------------------------------------------------------

  describe("initial state", function () {
    it("name() returns 'Degenerus Deity Pass'", async function () {
      const { deityPass } = await getFixture();
      expect(await deityPass.name()).to.equal("Degenerus Deity Pass");
    });

    it("symbol() returns 'DEITY'", async function () {
      const { deityPass } = await getFixture();
      expect(await deityPass.symbol()).to.equal("DEITY");
    });

    it("renderer is address(0) on deploy (no external renderer)", async function () {
      const { deityPass } = await getFixture();
      expect(await deityPass.renderer()).to.equal(ZERO_ADDRESS);
    });

    it("initial render colors match defaults", async function () {
      const { deityPass } = await getFixture();
      const [outline, bg, nonCrypto] = await deityPass.renderColors();
      expect(outline).to.equal("#3f1a82");
      expect(bg).to.equal("#d9d9d9");
      expect(nonCrypto).to.equal("#111111");
    });

    it("no tokens are minted on deploy (balanceOf for any user is 0)", async function () {
      const { deityPass, alice, bob } = await getFixture();
      expect(await deityPass.balanceOf(alice.address)).to.equal(0n);
      expect(await deityPass.balanceOf(bob.address)).to.equal(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // ERC165 supportsInterface
  // ---------------------------------------------------------------------------

  describe("supportsInterface()", function () {
    it("supports IERC721 interface (0x80ac58cd)", async function () {
      const { deityPass } = await getFixture();
      expect(await deityPass.supportsInterface("0x80ac58cd")).to.be.true;
    });

    it("supports IERC721Metadata interface (0x5b5e139f)", async function () {
      const { deityPass } = await getFixture();
      expect(await deityPass.supportsInterface("0x5b5e139f")).to.be.true;
    });

    it("supports IERC165 interface (0x01ffc9a7)", async function () {
      const { deityPass } = await getFixture();
      expect(await deityPass.supportsInterface("0x01ffc9a7")).to.be.true;
    });

    it("does not support unknown interface", async function () {
      const { deityPass } = await getFixture();
      expect(await deityPass.supportsInterface("0xdeadbeef")).to.be.false;
    });
  });

  // ---------------------------------------------------------------------------
  // setRenderer()
  // ---------------------------------------------------------------------------

  describe("setRenderer()", function () {
    it("owner can set the renderer address", async function () {
      const { deityPass, deployer, alice } = await getFixture();
      const tx = await deityPass
        .connect(deployer)
        .setRenderer(alice.address);
      await expect(tx)
        .to.emit(deityPass, "RendererUpdated")
        .withArgs(ZERO_ADDRESS, alice.address);
      expect(await deityPass.renderer()).to.equal(alice.address);
    });

    it("can set renderer back to address(0) to disable external rendering", async function () {
      const { deityPass, deployer, alice } = await getFixture();
      await deityPass.connect(deployer).setRenderer(alice.address);
      await deityPass.connect(deployer).setRenderer(ZERO_ADDRESS);
      expect(await deityPass.renderer()).to.equal(ZERO_ADDRESS);
    });

    it("reverts with NotAuthorized when non-owner calls setRenderer", async function () {
      const { deityPass, alice, bob } = await getFixture();
      await expect(
        deityPass.connect(alice).setRenderer(bob.address)
      ).to.be.revertedWithCustomError(deityPass, "NotAuthorized");
    });

    it("emits RendererUpdated with previous and new renderer addresses", async function () {
      const { deityPass, deployer, alice, bob } = await getFixture();
      await deityPass.connect(deployer).setRenderer(alice.address);
      const tx = await deityPass.connect(deployer).setRenderer(bob.address);
      await expect(tx)
        .to.emit(deityPass, "RendererUpdated")
        .withArgs(alice.address, bob.address);
    });
  });

  // ---------------------------------------------------------------------------
  // setRenderColors()
  // ---------------------------------------------------------------------------

  describe("setRenderColors()", function () {
    it("owner can update render colors", async function () {
      const { deityPass, deployer } = await getFixture();
      const tx = await deityPass
        .connect(deployer)
        .setRenderColors("#abcdef", "#123456", "#fedcba");
      await expect(tx)
        .to.emit(deityPass, "RenderColorsUpdated")
        .withArgs("#abcdef", "#123456", "#fedcba");

      const [outline, bg, nonCrypto] = await deityPass.renderColors();
      expect(outline).to.equal("#abcdef");
      expect(bg).to.equal("#123456");
      expect(nonCrypto).to.equal("#fedcba");
    });

    it("reverts with NotAuthorized when non-owner calls setRenderColors", async function () {
      const { deityPass, alice } = await getFixture();
      await expect(
        deityPass
          .connect(alice)
          .setRenderColors("#aabbcc", "#112233", "#aabbcc")
      ).to.be.revertedWithCustomError(deityPass, "NotAuthorized");
    });

    it("reverts with InvalidColor when outline color lacks '#' prefix", async function () {
      const { deityPass, deployer } = await getFixture();
      await expect(
        deityPass
          .connect(deployer)
          .setRenderColors("aabbcc", "#112233", "#aabbcc")
      ).to.be.revertedWithCustomError(deityPass, "InvalidColor");
    });

    it("reverts with InvalidColor when color is too short", async function () {
      const { deityPass, deployer } = await getFixture();
      await expect(
        deityPass.connect(deployer).setRenderColors("#abc", "#112233", "#aabbcc")
      ).to.be.revertedWithCustomError(deityPass, "InvalidColor");
    });

    it("reverts with InvalidColor when color has invalid hex characters", async function () {
      const { deityPass, deployer } = await getFixture();
      await expect(
        deityPass
          .connect(deployer)
          .setRenderColors("#gggggg", "#112233", "#aabbcc")
      ).to.be.revertedWithCustomError(deityPass, "InvalidColor");
    });

    it("reverts with InvalidColor when color is too long", async function () {
      const { deityPass, deployer } = await getFixture();
      await expect(
        deityPass
          .connect(deployer)
          .setRenderColors("#aabbccdd", "#112233", "#aabbcc")
      ).to.be.revertedWithCustomError(deityPass, "InvalidColor");
    });

    it("accepts uppercase hex digits", async function () {
      const { deityPass, deployer } = await getFixture();
      await expect(
        deityPass
          .connect(deployer)
          .setRenderColors("#AABBCC", "#112233", "#FEDCBA")
      ).to.not.be.reverted;
    });

    it("accepts mixed case hex digits", async function () {
      const { deityPass, deployer } = await getFixture();
      await expect(
        deityPass
          .connect(deployer)
          .setRenderColors("#AbCdEf", "#1a2B3c", "#Fe0Dc1")
      ).to.not.be.reverted;
    });

    it("reverts when background color is invalid", async function () {
      const { deityPass, deployer } = await getFixture();
      await expect(
        deityPass
          .connect(deployer)
          .setRenderColors("#aabbcc", "invalid", "#112233")
      ).to.be.revertedWithCustomError(deityPass, "InvalidColor");
    });

    it("reverts when nonCrypto color is invalid", async function () {
      const { deityPass, deployer } = await getFixture();
      await expect(
        deityPass
          .connect(deployer)
          .setRenderColors("#aabbcc", "#112233", "bad")
      ).to.be.revertedWithCustomError(deityPass, "InvalidColor");
    });
  });

  // ---------------------------------------------------------------------------
  // mint() — game-only
  // ---------------------------------------------------------------------------

  describe("mint()", function () {
    it("game contract can mint a token and emits Transfer from zero address", async function () {
      const { deityPass, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      const tx = await deityPass.connect(gameSigner).mint(alice.address, 0);
      await expect(tx)
        .to.emit(deityPass, "Transfer")
        .withArgs(ZERO_ADDRESS, alice.address, 0n);
      await stopImpersonate(gameAddr);

      expect(await deityPass.ownerOf(0)).to.equal(alice.address);
      expect(await deityPass.balanceOf(alice.address)).to.equal(1n);
    });

    it("reverts with NotAuthorized when a non-GAME address tries to mint", async function () {
      const { deityPass, alice, bob } = await getFixture();
      await expect(
        deityPass.connect(alice).mint(bob.address, 0)
      ).to.be.revertedWithCustomError(deityPass, "NotAuthorized");
    });

    it("reverts with InvalidToken for tokenId >= 32", async function () {
      const { deityPass, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await expect(
        deityPass.connect(gameSigner).mint(alice.address, 32)
      ).to.be.revertedWithCustomError(deityPass, "InvalidToken");
      await stopImpersonate(gameAddr);
    });

    it("reverts with InvalidToken for tokenId = 100 (out of range)", async function () {
      const { deityPass, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await expect(
        deityPass.connect(gameSigner).mint(alice.address, 100)
      ).to.be.revertedWithCustomError(deityPass, "InvalidToken");
      await stopImpersonate(gameAddr);
    });

    it("reverts with ZeroAddress when recipient is address(0)", async function () {
      const { deityPass, game } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await expect(
        deityPass.connect(gameSigner).mint(ZERO_ADDRESS, 5)
      ).to.be.revertedWithCustomError(deityPass, "ZeroAddress");
      await stopImpersonate(gameAddr);
    });

    it("reverts with InvalidToken when minting an already-minted tokenId", async function () {
      const { deityPass, game, alice, bob } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 5);

      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await expect(
        deityPass.connect(gameSigner).mint(bob.address, 5)
      ).to.be.revertedWithCustomError(deityPass, "InvalidToken");
      await stopImpersonate(gameAddr);
    });

    it("can mint all 32 tokens (tokenId 0 to 31)", async function () {
      const { deityPass, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      for (let i = 0; i < 32; i++) {
        await deityPass.connect(gameSigner).mint(alice.address, i);
      }
      await stopImpersonate(gameAddr);

      expect(await deityPass.balanceOf(alice.address)).to.equal(32n);
    });

    it("mint at tokenId 31 (last valid) succeeds", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 31);
      expect(await deityPass.ownerOf(31)).to.equal(alice.address);
    });
  });

  // ---------------------------------------------------------------------------
  // burn() — removed (soulbound, no burn function exists)
  // ---------------------------------------------------------------------------

  describe("burn()", function () {
    it("burn function does not exist on soulbound deity pass", async function () {
      const { deityPass } = await getFixture();
      expect(deityPass.burn).to.be.undefined;
    });
  });

  // ---------------------------------------------------------------------------
  // ownerOf() / balanceOf() / getApproved() / isApprovedForAll()
  // ---------------------------------------------------------------------------

  describe("ERC721 view functions", function () {
    it("ownerOf reverts with InvalidToken for unminted tokenId", async function () {
      const { deityPass } = await getFixture();
      await expect(deityPass.ownerOf(0)).to.be.revertedWithCustomError(
        deityPass,
        "InvalidToken"
      );
    });

    it("ownerOf returns the correct owner after mint", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 15);
      expect(await deityPass.ownerOf(15)).to.equal(alice.address);
    });

    it("balanceOf reverts with ZeroAddress for address(0)", async function () {
      const { deityPass } = await getFixture();
      await expect(
        deityPass.balanceOf(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(deityPass, "ZeroAddress");
    });

    it("balanceOf increases by 1 after minting", async function () {
      const { deityPass, game, alice } = await getFixture();
      const before = await deityPass.balanceOf(alice.address);
      await mintViaGame(deityPass, game, alice.address, 20);
      expect(await deityPass.balanceOf(alice.address)).to.equal(before + 1n);
    });

    it("getApproved reverts with InvalidToken for unminted token", async function () {
      const { deityPass } = await getFixture();
      await expect(deityPass.getApproved(0)).to.be.revertedWithCustomError(
        deityPass,
        "InvalidToken"
      );
    });

    it("getApproved returns address(0) for token with no approval", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 1);
      expect(await deityPass.getApproved(1)).to.equal(ZERO_ADDRESS);
    });

    it("isApprovedForAll returns false initially", async function () {
      const { deityPass, alice, bob } = await getFixture();
      expect(
        await deityPass.isApprovedForAll(alice.address, bob.address)
      ).to.be.false;
    });
  });

  // ---------------------------------------------------------------------------
  // approve() — soulbound
  // ---------------------------------------------------------------------------

  describe("approve()", function () {
    it("reverts with Soulbound when token owner tries to approve", async function () {
      const { deityPass, game, alice, bob } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 2);
      await expect(
        deityPass.connect(alice).approve(bob.address, 2)
      ).to.be.revertedWithCustomError(deityPass, "Soulbound");
    });
  });

  // ---------------------------------------------------------------------------
  // setApprovalForAll() — soulbound
  // ---------------------------------------------------------------------------

  describe("setApprovalForAll()", function () {
    it("reverts with Soulbound", async function () {
      const { deityPass, alice, bob } = await getFixture();
      await expect(
        deityPass.connect(alice).setApprovalForAll(bob.address, true)
      ).to.be.revertedWithCustomError(deityPass, "Soulbound");
    });

    it("isApprovedForAll always returns false", async function () {
      const { deityPass, alice, bob } = await getFixture();
      expect(
        await deityPass.isApprovedForAll(alice.address, bob.address)
      ).to.be.false;
    });
  });

  // ---------------------------------------------------------------------------
  // tokenURI()
  // ---------------------------------------------------------------------------

  describe("tokenURI()", function () {
    it("reverts with InvalidToken for unminted token", async function () {
      const { deityPass } = await getFixture();
      await expect(deityPass.tokenURI(0)).to.be.revertedWithCustomError(
        deityPass,
        "InvalidToken"
      );
    });

    it("returns a non-empty string for a minted token", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 0);
      const uri = await deityPass.tokenURI(0);
      expect(uri.length).to.be.gt(0);
    });

    it("starts with 'data:application/json;base64,' prefix", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 0);
      const uri = await deityPass.tokenURI(0);
      expect(uri.startsWith("data:application/json;base64,")).to.be.true;
    });

    it("base64-decoded JSON contains tokenId in the name field", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 5);
      const uri = await deityPass.tokenURI(5);
      const base64Part = uri.replace("data:application/json;base64,", "");
      const json = Buffer.from(base64Part, "base64").toString("utf8");
      expect(json).to.include("Deity Pass #5");
    });

    it("contains 'data:image/svg+xml;base64,' in the image field", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 0);
      const uri = await deityPass.tokenURI(0);
      const base64Part = uri.replace("data:application/json;base64,", "");
      const json = Buffer.from(base64Part, "base64").toString("utf8");
      expect(json).to.include("data:image/svg+xml;base64,");
    });

    it("returns a distinct URI for each tokenId", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 0);
      await mintViaGame(deityPass, game, alice.address, 8);

      const uri0 = await deityPass.tokenURI(0);
      const uri8 = await deityPass.tokenURI(8);
      expect(uri0).to.not.equal(uri8);
    });

    it("tokenURI for quadrant 3 (Dice) token includes 'Dice' in name", async function () {
      const { deityPass, game, alice } = await getFixture();
      // tokenId 24 = quadrant 3, symbolIdx 0 => "Dice 1"
      await mintViaGame(deityPass, game, alice.address, 24);
      const uri = await deityPass.tokenURI(24);
      const base64Part = uri.replace("data:application/json;base64,", "");
      const json = Buffer.from(base64Part, "base64").toString("utf8");
      expect(json).to.include("Dice");
    });
  });

  // ---------------------------------------------------------------------------
  // transferFrom() — soulbound
  // ---------------------------------------------------------------------------

  describe("transferFrom()", function () {
    it("reverts with Soulbound", async function () {
      const { deityPass, game, alice, bob } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 0);
      await expect(
        deityPass.connect(alice).transferFrom(alice.address, bob.address, 0)
      ).to.be.revertedWithCustomError(deityPass, "Soulbound");
    });

    it("reverts with Soulbound even for non-owner caller", async function () {
      const { deityPass, game, alice, bob, carol } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 0);
      await expect(
        deityPass.connect(bob).transferFrom(alice.address, carol.address, 0)
      ).to.be.revertedWithCustomError(deityPass, "Soulbound");
    });
  });

  // ---------------------------------------------------------------------------
  // safeTransferFrom() — soulbound
  // ---------------------------------------------------------------------------

  describe("safeTransferFrom()", function () {
    it("reverts with Soulbound (no-data overload)", async function () {
      const { deityPass, game, alice, bob } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 6);
      await expect(
        deityPass
          .connect(alice)
          ["safeTransferFrom(address,address,uint256)"](
            alice.address,
            bob.address,
            6
          )
      ).to.be.revertedWithCustomError(deityPass, "Soulbound");
    });

    it("reverts with Soulbound (with-data overload)", async function () {
      const { deityPass, game, alice, bob } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 7);
      await expect(
        deityPass
          .connect(alice)
          ["safeTransferFrom(address,address,uint256,bytes)"](
            alice.address,
            bob.address,
            7,
            "0x"
          )
      ).to.be.revertedWithCustomError(deityPass, "Soulbound");
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases — boundary tokenIds
  // ---------------------------------------------------------------------------

  describe("boundary tokenId edge cases", function () {
    it("tokenId 0 (minimum valid) can be minted and queried", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 0);
      expect(await deityPass.ownerOf(0)).to.equal(alice.address);
    });

    it("tokenId 31 (maximum valid) can be minted and queried", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 31);
      expect(await deityPass.ownerOf(31)).to.equal(alice.address);
    });

    it("tokenId 32 is invalid and mint reverts", async function () {
      const { deityPass, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await expect(
        deityPass.connect(gameSigner).mint(alice.address, 32)
      ).to.be.revertedWithCustomError(deityPass, "InvalidToken");
      await stopImpersonate(gameAddr);
    });
  });
});
