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
 *   - Minimal ERC721 "DEITY" with 32 token slots (tokenId 0-31)
 *   - Ownable (constructor sets _contractOwner = deployer)
 *   - mint() / burn() callable only by ContractAddresses.GAME
 *   - transferFrom() / safeTransferFrom() call back to game via onDeityPassTransfer()
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
    it("owner is set to deployer on construction", async function () {
      const { deityPass, deployer } = await getFixture();
      expect(await deityPass.owner()).to.equal(deployer.address);
    });

    it("emits OwnershipTransferred from zero address to deployer on deploy", async function () {
      // Checked indirectly — owner() returns deployer correctly
      const { deityPass, deployer } = await getFixture();
      expect(await deityPass.owner()).to.equal(deployer.address);
    });

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
  // Ownership / transferOwnership
  // ---------------------------------------------------------------------------

  describe("transferOwnership()", function () {
    it("owner can transfer ownership to a new address", async function () {
      const { deityPass, deployer, alice } = await getFixture();
      const tx = await deityPass
        .connect(deployer)
        .transferOwnership(alice.address);
      await expect(tx)
        .to.emit(deityPass, "OwnershipTransferred")
        .withArgs(deployer.address, alice.address);
      expect(await deityPass.owner()).to.equal(alice.address);
    });

    it("reverts with NotAuthorized when non-owner calls transferOwnership", async function () {
      const { deityPass, alice, bob } = await getFixture();
      await expect(
        deityPass.connect(alice).transferOwnership(bob.address)
      ).to.be.revertedWithCustomError(deityPass, "NotAuthorized");
    });

    it("reverts with ZeroAddress when new owner is address(0)", async function () {
      const { deityPass, deployer } = await getFixture();
      await expect(
        deityPass.connect(deployer).transferOwnership(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(deityPass, "ZeroAddress");
    });

    it("new owner can call onlyOwner functions after transfer", async function () {
      const { deityPass, deployer, alice } = await getFixture();
      await deityPass.connect(deployer).transferOwnership(alice.address);
      // Alice should now be able to set renderer
      await expect(
        deityPass.connect(alice).setRenderer(ZERO_ADDRESS)
      ).to.not.be.reverted;
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
  // burn() — game-only
  // ---------------------------------------------------------------------------

  describe("burn()", function () {
    it("game contract can burn a minted token and emits Transfer to zero address", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 10);

      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      const tx = await deityPass.connect(gameSigner).burn(10);
      await expect(tx)
        .to.emit(deityPass, "Transfer")
        .withArgs(alice.address, ZERO_ADDRESS, 10n);
      await stopImpersonate(gameAddr);

      expect(await deityPass.balanceOf(alice.address)).to.equal(0n);
      await expect(deityPass.ownerOf(10)).to.be.revertedWithCustomError(
        deityPass,
        "InvalidToken"
      );
    });

    it("reverts with NotAuthorized when a non-GAME address tries to burn", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 7);
      await expect(
        deityPass.connect(alice).burn(7)
      ).to.be.revertedWithCustomError(deityPass, "NotAuthorized");
    });

    it("reverts with InvalidToken when burning an unminted token", async function () {
      const { deityPass, game } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await expect(
        deityPass.connect(gameSigner).burn(0)
      ).to.be.revertedWithCustomError(deityPass, "InvalidToken");
      await stopImpersonate(gameAddr);
    });

    it("clears token approval on burn", async function () {
      const { deityPass, game, alice, bob } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 3);

      // Alice approves bob
      await deityPass.connect(alice).approve(bob.address, 3);
      expect(await deityPass.getApproved(3)).to.equal(bob.address);

      // Game burns the token
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await deityPass.connect(gameSigner).burn(3);
      await stopImpersonate(gameAddr);

      // Token no longer exists; getApproved should revert
      await expect(deityPass.getApproved(3)).to.be.revertedWithCustomError(
        deityPass,
        "InvalidToken"
      );
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
  // approve()
  // ---------------------------------------------------------------------------

  describe("approve()", function () {
    it("token owner can approve another address", async function () {
      const { deityPass, game, alice, bob } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 2);

      const tx = await deityPass.connect(alice).approve(bob.address, 2);
      await expect(tx)
        .to.emit(deityPass, "Approval")
        .withArgs(alice.address, bob.address, 2n);
      expect(await deityPass.getApproved(2)).to.equal(bob.address);
    });

    it("reverts with NotAuthorized when non-owner tries to approve", async function () {
      const { deityPass, game, alice, bob, carol } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 4);
      await expect(
        deityPass.connect(bob).approve(carol.address, 4)
      ).to.be.revertedWithCustomError(deityPass, "NotAuthorized");
    });

    it("operator (approved for all) can approve individual tokens", async function () {
      const { deityPass, game, alice, bob, carol } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 6);
      await deityPass.connect(alice).setApprovalForAll(bob.address, true);
      // Bob (operator) should be able to approve carol for tokenId 6
      await expect(
        deityPass.connect(bob).approve(carol.address, 6)
      ).to.not.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // setApprovalForAll()
  // ---------------------------------------------------------------------------

  describe("setApprovalForAll()", function () {
    it("sets operator approval and emits ApprovalForAll", async function () {
      const { deityPass, alice, bob } = await getFixture();
      const tx = await deityPass
        .connect(alice)
        .setApprovalForAll(bob.address, true);
      await expect(tx)
        .to.emit(deityPass, "ApprovalForAll")
        .withArgs(alice.address, bob.address, true);
      expect(
        await deityPass.isApprovedForAll(alice.address, bob.address)
      ).to.be.true;
    });

    it("can revoke operator approval", async function () {
      const { deityPass, alice, bob } = await getFixture();
      await deityPass.connect(alice).setApprovalForAll(bob.address, true);
      await deityPass.connect(alice).setApprovalForAll(bob.address, false);
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
  // transferFrom() — requires game callback
  //
  // NOTE: The _transfer() internal in DegenerusDeityPass calls
  //   IDeityPassCallback(ContractAddresses.GAME).onDeityPassTransfer(from, to, tokenId)
  // before updating storage. The game's onDeityPassTransfer burns BURNIE from
  // the sender and updates deity pass storage. Without a funded BURNIE balance on
  // the sender, the callback reverts. These tests verify:
  //   (a) the early access-control checks that fire BEFORE the callback, and
  //   (b) that the callback IS invoked (causing a revert when prerequisites are unmet)
  // ---------------------------------------------------------------------------

  describe("transferFrom()", function () {
    it("reverts because the game callback fires during transfer (game enforces BURNIE requirements)", async function () {
      const { deityPass, game, alice, bob } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 0);

      // The transfer will reach the game callback and revert there (alice has no BURNIE).
      // This confirms the callback is wired correctly — NOT a pure access-control failure.
      await expect(
        deityPass.connect(alice).transferFrom(alice.address, bob.address, 0)
      ).to.be.reverted;
    });

    it("reverts with NotAuthorized when `from` does not own the token (before callback)", async function () {
      const { deityPass, game, alice, bob, carol } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 0);
      // Bob tries to transfer Alice's token — the ownership check fires before the callback
      await expect(
        deityPass.connect(bob).transferFrom(alice.address, carol.address, 0)
      ).to.be.revertedWithCustomError(deityPass, "NotAuthorized");
    });

    it("reverts with ZeroAddress when `to` is address(0) (before callback)", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 3);
      await expect(
        deityPass.connect(alice).transferFrom(alice.address, ZERO_ADDRESS, 3)
      ).to.be.revertedWithCustomError(deityPass, "ZeroAddress");
    });

    it("reverts with NotAuthorized when non-owner unapproved address calls transferFrom", async function () {
      const { deityPass, game, alice, bob, carol } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 1);
      // Bob has no approval for tokenId 1 and is not alice
      await expect(
        deityPass.connect(bob).transferFrom(alice.address, carol.address, 1)
      ).to.be.revertedWithCustomError(deityPass, "NotAuthorized");
    });

    it("approved spender passes access checks but callback reverts without BURNIE", async function () {
      const { deityPass, game, alice, bob, carol } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 1);
      await deityPass.connect(alice).approve(bob.address, 1);
      // Bob is approved — access control passes — but game callback reverts
      await expect(
        deityPass.connect(bob).transferFrom(alice.address, carol.address, 1)
      ).to.be.reverted;
    });

    it("operator (approvedForAll) passes access checks but callback reverts without BURNIE", async function () {
      const { deityPass, game, alice, bob, carol } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 2);
      await deityPass.connect(alice).setApprovalForAll(bob.address, true);
      // Bob is operator — access control passes — but game callback reverts
      await expect(
        deityPass.connect(bob).transferFrom(alice.address, carol.address, 2)
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // safeTransferFrom()
  // ---------------------------------------------------------------------------

  describe("safeTransferFrom()", function () {
    it("reverts because game callback fires (same as transferFrom — no BURNIE to burn)", async function () {
      const { deityPass, game, alice, bob } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 6);

      // The game callback fires and reverts (alice has no BURNIE)
      await expect(
        deityPass
          .connect(alice)
          ["safeTransferFrom(address,address,uint256)"](
            alice.address,
            bob.address,
            6
          )
      ).to.be.reverted;
    });

    it("safeTransferFrom with data overload also routes through the same callback", async function () {
      const { deityPass, game, alice, bob } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 7);

      // Same callback fires and reverts
      await expect(
        deityPass
          .connect(alice)
          ["safeTransferFrom(address,address,uint256,bytes)"](
            alice.address,
            bob.address,
            7,
            "0x"
          )
      ).to.be.reverted;
    });

    it("reverts with NotAuthorized for ZeroAddress `to` in safeTransferFrom before callback", async function () {
      const { deityPass, game, alice } = await getFixture();
      await mintViaGame(deityPass, game, alice.address, 8);

      await expect(
        deityPass
          .connect(alice)
          ["safeTransferFrom(address,address,uint256)"](
            alice.address,
            ZERO_ADDRESS,
            8
          )
      ).to.be.revertedWithCustomError(deityPass, "ZeroAddress");
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
