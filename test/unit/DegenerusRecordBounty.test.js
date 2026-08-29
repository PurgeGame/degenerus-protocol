import { expect } from "chai";
import hre from "hardhat";
import { loadFixture, time } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { ZERO_ADDRESS } from "../helpers/testUtils.js";

/*
 * DegenerusRecordBounty Unit Tests
 *
 * Contract: contracts/DegenerusRecordBounty.sol
 *
 * Architecture summary:
 *   - Soulbound ERC721 "BIGGEST" with 5 trophies (tokenId = RECORD_KIND_*),
 *     the fifth being the scheduled Dice Run's high-point record
 *   - All five mint to the VAULT at deploy; Coinflip force-moves a trophy on
 *     every record ratchet via recordSet (COINFLIP-only)
 *   - Holder transfers/approvals always revert (soulbound)
 *   - tokenURI carries the record name, the standing mark in the record's own
 *     unit, and the current holder's days-held count
 *   - Admin render surface (setRenderer / setRenderColors) gated by DGVE
 *     vault ownership
 */

describe("DegenerusRecordBounty", function () {
  after(function () {
    restoreAddresses();
  });

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

  async function getBounty(f) {
    return hre.ethers.getContractAt(
      "DegenerusRecordBounty",
      f.deployedAddrs.get("RECORD_BOUNTY")
    );
  }

  // Move record `kind` to `to` at `mark` as the Coinflip contract would.
  async function recordSetViaCoinflip(f, bounty, kind, to, mark) {
    const coinflipAddr = f.deployedAddrs.get("COINFLIP");
    const signer = await impersonate(coinflipAddr);
    const tx = await bounty.connect(signer).recordSet(kind, to, mark);
    return tx;
  }

  function decodeTokenURI(uri) {
    expect(uri).to.match(/^data:application\/json;base64,/);
    const json = JSON.parse(
      Buffer.from(uri.split(",")[1], "base64").toString("utf8")
    );
    return json;
  }

  function attr(json, traitType) {
    const found = json.attributes.find((a) => a.trait_type === traitType);
    expect(found, `attribute ${traitType}`).to.not.equal(undefined);
    return found.value;
  }

  // ---------------------------------------------------------------------------
  // Deploy state
  // ---------------------------------------------------------------------------

  describe("deploy state", function () {
    it("mints all five trophies to the VAULT with unset marks", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      const home = f.deployedAddrs.get("VAULT");
      expect(await bounty.balanceOf(home)).to.equal(5n);
      // And not the deployer: an unclaimed record parks with the protocol's own
      // body rather than with a person.
      expect(await bounty.balanceOf(f.deployer.address)).to.equal(0n);
      for (let i = 0; i < 5; i++) {
        expect(await bounty.ownerOf(i)).to.equal(home);
        const [holder, mark, , daysHeld] = await bounty.recordInfo(i);
        expect(holder).to.equal(home);
        expect(mark).to.equal(0n);
        expect(daysHeld).to.equal(0n);
      }
    });

    it("exposes ERC721 identity and interfaces", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      expect(await bounty.name()).to.equal("The BIGGEST Degenerus");
      expect(await bounty.symbol()).to.equal("BIGGEST");
      expect(await bounty.supportsInterface("0x80ac58cd")).to.equal(true);
      expect(await bounty.supportsInterface("0x5b5e139f")).to.equal(true);
      expect(await bounty.supportsInterface("0x01ffc9a7")).to.equal(true);
      expect(await bounty.supportsInterface("0xffffffff")).to.equal(false);
    });
  });

  // ---------------------------------------------------------------------------
  // recordSet
  // ---------------------------------------------------------------------------

  describe("recordSet()", function () {
    it("reverts NotAuthorized for any caller but COINFLIP", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      await expect(
        bounty.connect(f.alice).recordSet(0, f.alice.address, 1n)
      ).to.be.revertedWithCustomError(bounty, "NotAuthorized");
    });

    it("rejects unknown kinds and the zero holder", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      const signer = await impersonate(f.deployedAddrs.get("COINFLIP"));
      await expect(
        bounty.connect(signer).recordSet(5, f.alice.address, 1n)
      ).to.be.revertedWithCustomError(bounty, "InvalidToken");
      await expect(
        bounty.connect(signer).recordSet(0, ZERO_ADDRESS, 1n)
      ).to.be.revertedWithCustomError(bounty, "ZeroAddress");
    });

    it("moves the trophy, stamps the mark, and emits Transfer", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      const tx = await recordSetViaCoinflip(
        f, bounty, 1, f.alice.address, hre.ethers.parseEther("2")
      );
      await expect(tx)
        .to.emit(bounty, "Transfer")
        .withArgs(f.deployedAddrs.get("VAULT"), f.alice.address, 1n);
      expect(await bounty.ownerOf(1)).to.equal(f.alice.address);
      expect(await bounty.balanceOf(f.deployedAddrs.get("VAULT"))).to.equal(4n);
      expect(await bounty.balanceOf(f.alice.address)).to.equal(1n);
    });

    it("keeps the days-held clock on a self-ratchet, restarts it on a takeover", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      await recordSetViaCoinflip(f, bounty, 1, f.alice.address, 10n);
      const [, , sinceDay] = await bounty.recordInfo(1);

      await time.increase(3 * 86400);
      await recordSetViaCoinflip(f, bounty, 1, f.alice.address, 20n);
      const [, mark, sinceAfterSelf, daysHeld] = await bounty.recordInfo(1);
      expect(mark).to.equal(20n);
      expect(sinceAfterSelf).to.equal(sinceDay);
      expect(daysHeld).to.equal(3n);

      await recordSetViaCoinflip(f, bounty, 1, f.bob.address, 30n);
      const [holder, , sinceAfterTake, heldAfterTake] = await bounty.recordInfo(1);
      expect(holder).to.equal(f.bob.address);
      expect(sinceAfterTake).to.equal(sinceDay + 3n);
      expect(heldAfterTake).to.equal(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // Soulbound surface
  // ---------------------------------------------------------------------------

  describe("soulbound", function () {
    it("blocks every transfer and approval surface", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      await expect(
        bounty.connect(f.deployer).approve(f.alice.address, 0)
      ).to.be.revertedWithCustomError(bounty, "Soulbound");
      await expect(
        bounty.connect(f.deployer).setApprovalForAll(f.alice.address, true)
      ).to.be.revertedWithCustomError(bounty, "Soulbound");
      await expect(
        bounty.connect(f.deployer).transferFrom(f.deployer.address, f.alice.address, 0)
      ).to.be.revertedWithCustomError(bounty, "Soulbound");
      await expect(
        bounty
          .connect(f.deployer)
          ["safeTransferFrom(address,address,uint256)"](
            f.deployer.address, f.alice.address, 0
          )
      ).to.be.revertedWithCustomError(bounty, "Soulbound");
      await expect(
        bounty
          .connect(f.deployer)
          ["safeTransferFrom(address,address,uint256,bytes)"](
            f.deployer.address, f.alice.address, 0, "0x"
          )
      ).to.be.revertedWithCustomError(bounty, "Soulbound");
      expect(await bounty.getApproved(0)).to.equal(ZERO_ADDRESS);
      expect(
        await bounty.isApprovedForAll(f.deployer.address, f.alice.address)
      ).to.equal(false);
    });
  });

  // ---------------------------------------------------------------------------
  // tokenURI
  // ---------------------------------------------------------------------------

  describe("tokenURI()", function () {
    it("names each trophy The Biggest <record> with the shared description", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      const names = [
        "The Biggest Flip",
        "The Biggest Degenerette",
        "The Biggest Luckbox",
        "The Biggest Pack Ripped",
        "The Biggest Dice Run",
      ];
      for (let i = 0; i < 5; i++) {
        const json = decodeTokenURI(await bounty.tokenURI(i));
        expect(json.name).to.equal(names[i]);
        expect(json.description).to.equal(
          "A trophy certifying that the holder is one of the biggest degenerates on Earth."
        );
        expect(attr(json, "Record")).to.equal(names[i]);
        expect(json.image).to.match(/^data:image\/svg\+xml;base64,/);
      }
    });

    it("formats the mark in each record's own unit", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      await recordSetViaCoinflip(
        f, bounty, 0, f.alice.address, hre.ethers.parseEther("215000")
      );
      await recordSetViaCoinflip(
        f, bounty, 1, f.alice.address, hre.ethers.parseEther("1.2345")
      );
      await recordSetViaCoinflip(
        f, bounty, 2, f.alice.address, hre.ethers.parseEther("5")
      );
      await recordSetViaCoinflip(f, bounty, 3, f.alice.address, 123n);
      // The dice run's unit is SCORE BASIS POINTS: 1,234,500 is a 123.45x high point.
      await recordSetViaCoinflip(f, bounty, 4, f.alice.address, 1_234_500n);

      expect(attr(decodeTokenURI(await bounty.tokenURI(0)), "Record Size"))
        .to.equal("215000 FLIP");
      expect(attr(decodeTokenURI(await bounty.tokenURI(1)), "Record Size"))
        .to.equal("1.2345 ETH");
      expect(attr(decodeTokenURI(await bounty.tokenURI(2)), "Record Size"))
        .to.equal("5.0000 ETH");
      expect(attr(decodeTokenURI(await bounty.tokenURI(3)), "Record Size"))
        .to.equal("123 tickets");
      expect(attr(decodeTokenURI(await bounty.tokenURI(4)), "Record Size"))
        .to.equal("123.45x");
    });

    it("counts days held as a numeric attribute", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      await recordSetViaCoinflip(f, bounty, 2, f.alice.address, 10n);
      await time.increase(7 * 86400);
      const json = decodeTokenURI(await bounty.tokenURI(2));
      expect(attr(json, "Days Held")).to.equal(7);
      const [, , , daysHeld] = await bounty.recordInfo(2);
      expect(daysHeld).to.equal(7n);
    });

    it("renders the default badge art with the record label and wordmark", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      const json = decodeTokenURI(await bounty.tokenURI(3));
      const svg = Buffer.from(json.image.split(",")[1], "base64").toString("utf8");
      expect(svg).to.include("BIGGEST PACK RIPPED");
      expect(svg).to.include("DEGENERUS");
      expect(svg).to.include("#3f1a82");
      expect(svg).to.include("#d9d9d9");
    });

    it("renders the dice run's own label", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      const json = decodeTokenURI(await bounty.tokenURI(4));
      const svg = Buffer.from(json.image.split(",")[1], "base64").toString("utf8");
      expect(svg).to.include("BIGGEST DICE RUN");
    });

    it("reverts InvalidToken for tokenId >= 5", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      await expect(bounty.tokenURI(5)).to.be.revertedWithCustomError(
        bounty, "InvalidToken"
      );
      await expect(bounty.ownerOf(5)).to.be.revertedWithCustomError(
        bounty, "InvalidToken"
      );
      await expect(bounty.getApproved(5)).to.be.revertedWithCustomError(
        bounty, "InvalidToken"
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Admin render surface
  // ---------------------------------------------------------------------------

  describe("admin render surface", function () {
    it("gates setRenderer and setRenderColors behind vault ownership", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      await expect(
        bounty.connect(f.alice).setRenderer(f.bob.address)
      ).to.be.revertedWithCustomError(bounty, "NotAuthorized");
      await expect(
        bounty.connect(f.alice).setRenderColors("#000000", "#ffffff")
      ).to.be.revertedWithCustomError(bounty, "NotAuthorized");

      await expect(bounty.connect(f.deployer).setRenderer(f.bob.address))
        .to.emit(bounty, "RendererUpdated")
        .withArgs(ZERO_ADDRESS, f.bob.address);
      expect(await bounty.renderer()).to.equal(f.bob.address);
      await bounty.connect(f.deployer).setRenderer(ZERO_ADDRESS);
    });

    it("validates hex colors and applies them to the render", async function () {
      const f = await getFixture();
      const bounty = await getBounty(f);
      await expect(
        bounty.connect(f.deployer).setRenderColors("red", "#ffffff")
      ).to.be.revertedWithCustomError(bounty, "InvalidColor");
      await expect(
        bounty.connect(f.deployer).setRenderColors("#00ff00", "#zzffff")
      ).to.be.revertedWithCustomError(bounty, "InvalidColor");

      await bounty.connect(f.deployer).setRenderColors("#112233", "#aabbcc");
      const [outline, background] = await bounty.renderColors();
      expect(outline).to.equal("#112233");
      expect(background).to.equal("#aabbcc");
      const json = decodeTokenURI(await bounty.tokenURI(0));
      const svg = Buffer.from(json.image.split(",")[1], "base64").toString("utf8");
      expect(svg).to.include("#112233");
      expect(svg).to.include("#aabbcc");
    });
  });
});
