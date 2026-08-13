import { expect } from "chai";
import hre from "hardhat";
import { readFileSync } from "fs";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";

/** The production icon set. The fixture deploys Icons32Data empty, so the slots
 *  under test are loaded from the same JSON the deploy script uses — the pip
 *  override only means anything against the real slot-29 art. */
const ICON_PATHS = JSON.parse(
  readFileSync("scripts/data/icons32Data.symbolOrder.json", "utf8")
).paths;

/*
 * Gold Dice 6 badge inversion
 *
 * Dice 6 is quadrant 3 / index 5, i.e. symbolId (and Deity Pass tokenId) 29,
 * because both renderers derive quadrant = id / 8 and symbolIdx = id % 8.
 *
 * When — and only when — that symbol is drawn in the canonical gold #ab8d3f,
 * the badge inverts: the middle ring goes white, the inner circle goes dark, and
 * the six die pips flip from white to dark. The outer ring and the die body stay
 * gold. Every other symbol, and Dice 6 in any other color, keeps the standard
 * dark-middle / white-inner / white-pip treatment.
 *
 * The pips carry an explicit fill="#fff" inside the SHARED Icons32 slot 29, which
 * is color-agnostic and may already be finalized on chain, so the inversion is a
 * render-layer CSS override rather than an edit to the icon data.
 */

const GOLD = "#ab8d3f";
const GOLD_RGB = 0xab8d3f;
const NOT_GOLD = "#ed0e11";
const NOT_GOLD_RGB = 0xed0e11;

const DICE6 = 29; // quadrant 3, index 5
const DICE5 = 28;
const DICE7 = 30;
const ZODIAC = 8; // quadrant 1, index 0 — a gold non-dice control

// Ring geometry is shared by both renderers (RING_OUTER/MID/INNER = 46/35/28).
const RING_OUTER_GOLD = `<circle r="46" fill="${GOLD}"/>`;
const RING_MID_STD = '<circle r="35" fill="#111"/>';
const RING_INNER_STD = '<circle r="28" fill="#fff"/>';
const RING_MID_INV = '<circle r="35" fill="#fff"/>';
const RING_INNER_INV = '<circle r="28" fill="#111"/>';

const PIP_STYLE = "<style>#ico circle{fill:#111}</style>";

// Verbatim from AFKingSubscriptionToken._lockGlyph().
const LOCK_GLYPH =
  '<circle cx="36" cy="36" r="11" fill="#111" stroke="#fff" stroke-width="1.5"/>' +
  '<path d="M31.5 35 v-3.5 a4.5 4.5 0 0 1 9 0 V35" fill="none" stroke="#fff" stroke-width="2.2"/>' +
  '<rect x="29.5" y="34.5" width="13" height="9" rx="1.8" fill="#fff"/>';

/** Decode the base64 JSON tokenURI and the base64 SVG inside it. */
function decode(uri) {
  const jsonB64 = uri.replace("data:application/json;base64,", "");
  const json = JSON.parse(Buffer.from(jsonB64, "base64").toString("utf8"));
  const svgB64 = json.image.replace("data:image/svg+xml;base64,", "");
  return { json, svg: Buffer.from(svgB64, "base64").toString("utf8") };
}

/** Assert the inverted gold Dice 6 badge. Color literals are compared
 *  case-insensitively so an uppercase gold setting reads the same. */
function expectInverted(svg) {
  const s = svg.toLowerCase();
  expect(s).to.include(RING_OUTER_GOLD, "outer ring stays gold");
  expect(s).to.include(RING_MID_INV, "middle ring goes white");
  expect(s).to.include(RING_INNER_INV, "inner circle goes dark");
  expect(s).to.not.include(RING_MID_STD);
  expect(s).to.not.include(RING_INNER_STD);
  expect(s).to.include(PIP_STYLE, "pip override present");
  // The die body is a <rect> with no fill of its own, so it inherits the gold
  // ink from the wrapper group; the override targets circles only.
  expect(s).to.include(`fill='${GOLD}'`, "die body inherits gold");
  expect(s).to.include('<rect width="120" height="120" x="5" y="5" rx="18"/>');
  // All six pips are still present and still authored white in the shared icon —
  // the inversion is a render-layer override, not an edit to the icon data.
  expect(s.match(/<circle cx="(39\.8|90\.2)"/g)).to.have.lengthOf(6);
  expect(s.match(/r="10" fill="#fff"/g)).to.have.lengthOf(6);
}

/** Assert the standard (non-inverted) badge. */
function expectStandard(svg) {
  const s = svg.toLowerCase();
  expect(s).to.include(RING_MID_STD, "middle ring stays dark");
  expect(s).to.include(RING_INNER_STD, "inner circle stays white");
  expect(s).to.not.include(RING_MID_INV);
  expect(s).to.not.include(RING_INNER_INV);
  expect(s).to.not.include(PIP_STYLE, "no pip override");
}

/** Load the production art for the slots under test into the empty fixture
 *  Icons32Data. setPaths is CREATOR-gated and caps a batch at 10. */
async function loadIcons(icons32) {
  await icons32.setPaths(ZODIAC, [ICON_PATHS[ZODIAC]]);
  await icons32.setPaths(DICE5, [
    ICON_PATHS[DICE5],
    ICON_PATHS[DICE6],
    ICON_PATHS[DICE7],
  ]);
}

describe("Gold Dice 6 badge inversion", function () {
  this.timeout(300_000);

  after(function () {
    restoreAddresses();
  });

  async function impersonate(address) {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [address],
    });
    await hre.network.provider.send("hardhat_setBalance", [
      address,
      "0x56BC75E2D63100000",
    ]);
    return hre.ethers.getSigner(address);
  }

  // ==========================================================================
  // DegenerusDeityPass
  // ==========================================================================
  describe("DegenerusDeityPass", function () {
    async function goldPassFixture() {
      const f = await loadFixture(deployFullProtocol);
      const { deityPass, game, deployer, alice } = f;
      await loadIcons(f.icons32);
      const gameSigner = await impersonate(await game.getAddress());
      for (const id of [DICE5, DICE6, DICE7, ZODIAC]) {
        await deityPass.connect(gameSigner).mint(alice.address, id);
      }
      return { ...f, gameSigner };
    }

    /** Set outline + non-crypto ink, then read a token's internal SVG. */
    async function svgWith(deityPass, deployer, outline, ink, tokenId) {
      await deityPass
        .connect(deployer)
        .setRenderColors(outline, "#d9d9d9", ink);
      return decode(await deityPass.tokenURI(tokenId)).svg;
    }

    it("gold token 29 renders the inverted badge with dark pips", async function () {
      const { deityPass, deployer } = await goldPassFixture();
      const svg = await svgWith(deityPass, deployer, GOLD, GOLD, DICE6);
      expectInverted(svg);
    });

    it("uppercase and mixed-case gold render byte-identically", async function () {
      const { deityPass, deployer } = await goldPassFixture();
      const lower = await svgWith(deityPass, deployer, GOLD, GOLD, DICE6);
      const upper = await svgWith(deityPass, deployer, "#AB8D3F", "#AB8D3F", DICE6);
      const mixed = await svgWith(deityPass, deployer, "#Ab8D3f", "#aB8d3F", DICE6);

      expectInverted(upper);
      expectInverted(mixed);
      // Only the echoed color literal differs; the badge treatment is identical.
      expect(upper.toLowerCase()).to.equal(lower.toLowerCase());
      expect(mixed.toLowerCase()).to.equal(lower.toLowerCase());
    });

    it("non-gold Dice 6 keeps the standard badge", async function () {
      const { deityPass, deployer } = await goldPassFixture();
      const svg = await svgWith(deityPass, deployer, NOT_GOLD, NOT_GOLD, DICE6);
      expectStandard(svg);
    });

    it("requires BOTH the outer ring and the ink to be gold", async function () {
      const { deityPass, deployer } = await goldPassFixture();
      expectStandard(await svgWith(deityPass, deployer, GOLD, NOT_GOLD, DICE6));
      expectStandard(await svgWith(deityPass, deployer, NOT_GOLD, GOLD, DICE6));
    });

    it("gold Dice 5 and Dice 7 keep the standard badge", async function () {
      const { deityPass, deployer } = await goldPassFixture();
      expectStandard(await svgWith(deityPass, deployer, GOLD, GOLD, DICE5));
      expectStandard(await svgWith(deityPass, deployer, GOLD, GOLD, DICE7));
    });

    it("a gold non-dice symbol keeps the standard badge", async function () {
      const { deityPass, deployer } = await goldPassFixture();
      expectStandard(await svgWith(deityPass, deployer, GOLD, GOLD, ZODIAC));
    });

    it("non-gold Dice 6 is structurally identical to its neighbours", async function () {
      const { deityPass, deployer } = await goldPassFixture();
      const dice6 = await svgWith(deityPass, deployer, NOT_GOLD, NOT_GOLD, DICE6);
      const dice5 = await svgWith(deityPass, deployer, NOT_GOLD, NOT_GOLD, DICE5);
      // The whole prelude through the ring block must match byte-for-byte; only
      // the icon path after it differs.
      const prelude = (s) => s.slice(0, s.indexOf("<g transform='matrix"));
      expect(prelude(dice6)).to.equal(prelude(dice5));
    });

    it("external renderer owns the output; empty and reverting fall back", async function () {
      const { deityPass, deployer } = await goldPassFixture();
      await deityPass.connect(deployer).setRenderColors(GOLD, "#d9d9d9", GOLD);

      const ok = await (await hre.ethers.getContractFactory("DeityPassRendererOk")).deploy();
      const empty = await (await hre.ethers.getContractFactory("DeityPassRendererEmpty")).deploy();
      const rev = await (await hre.ethers.getContractFactory("DeityPassRendererRevert")).deploy();

      await deityPass.connect(deployer).setRenderer(await ok.getAddress());
      const external = decode(await deityPass.tokenURI(DICE6)).svg;
      expect(external).to.equal("<svg id='external-deity'/>");
      expect(external).to.not.include(PIP_STYLE, "external output is never recolored");

      for (const r of [empty, rev]) {
        await deityPass.connect(deployer).setRenderer(await r.getAddress());
        expectInverted(decode(await deityPass.tokenURI(DICE6)).svg);
      }

      await deityPass.connect(deployer).setRenderer(hre.ethers.ZeroAddress);
      expectInverted(decode(await deityPass.tokenURI(DICE6)).svg);
    });
  });

  // ==========================================================================
  // AFKingSubscriptionToken
  // ==========================================================================
  describe("AFKingSubscriptionToken", function () {
    async function seatFixture() {
      const f = await loadFixture(deployFullProtocol);
      await loadIcons(f.icons32);
      const seat = await hre.ethers.getContractAt(
        "AFKingSubscriptionToken",
        f.deployedAddrs.get("AFKING_SUB_TOKEN")
      );
      const gameSigner = await impersonate(await f.game.getAddress());
      return { ...f, seat, gameSigner };
    }

    /** Mint a seat to `holder` and stamp its traits; returns the tokenId.
     *  Ids are the serial counter, so the freshly minted one is nextSerial - 1
     *  (the same derivation the Foundry seat harness uses). */
    async function mintSeat(seat, gameSigner, holder, symbolId, trimRgb) {
      await seat.connect(gameSigner).mintSeatFor(holder.address);
      const tokenId = (await seat.nextSerial()) - 1n;
      await seat.connect(holder).setSeatTraits(tokenId, symbolId, 0xd9d9d9, trimRgb);
      return tokenId;
    }

    it("symbolId 29 with gold trim renders the inverted badge", async function () {
      const { seat, gameSigner, alice } = await seatFixture();
      const id = await mintSeat(seat, gameSigner, alice, DICE6, GOLD_RGB);
      expectInverted(decode(await seat.tokenURI(id)).svg);
    });

    it("non-gold trim on symbolId 29 keeps the standard badge", async function () {
      const { seat, gameSigner, alice } = await seatFixture();
      const id = await mintSeat(seat, gameSigner, alice, DICE6, NOT_GOLD_RGB);
      expectStandard(decode(await seat.tokenURI(id)).svg);
    });

    it("gold trim on a non-Dice-6 symbol keeps the standard badge", async function () {
      const { seat, gameSigner, alice, bob } = await seatFixture();
      const a = await mintSeat(seat, gameSigner, alice, DICE5, GOLD_RGB);
      const b = await mintSeat(seat, gameSigner, bob, ZODIAC, GOLD_RGB);
      expectStandard(decode(await seat.tokenURI(a)).svg);
      expectStandard(decode(await seat.tokenURI(b)).svg);
    });

    it("the lock glyph is unchanged and coexists with the inverted badge", async function () {
      const { seat, gameSigner, alice } = await seatFixture();
      const id = await mintSeat(seat, gameSigner, alice, DICE6, GOLD_RGB);
      const svg = decode(await seat.tokenURI(id)).svg;

      // An unsubscribed holder's seat is not locked; the badge still inverts.
      expectInverted(svg);
      // Whichever lock state this seat is in, the glyph text itself is verbatim
      // when present and the badge treatment does not depend on it.
      if (svg.includes('cx="36"')) {
        expect(svg).to.include(LOCK_GLYPH, "lock glyph byte-identical");
      }
    });

    it("external renderer owns the output; empty and reverting fall back", async function () {
      const { seat, gameSigner, alice, deployer } = await seatFixture();
      const id = await mintSeat(seat, gameSigner, alice, DICE6, GOLD_RGB);

      const ok = await (await hre.ethers.getContractFactory("SeatRendererOk")).deploy();
      const empty = await (await hre.ethers.getContractFactory("SeatRendererEmpty")).deploy();
      const rev = await (await hre.ethers.getContractFactory("SeatRendererRevert")).deploy();

      await seat.connect(deployer).setRenderer(await ok.getAddress());
      const external = decode(await seat.tokenURI(id)).svg;
      expect(external).to.equal("<svg id='external-seat'/>");
      expect(external).to.not.include(PIP_STYLE, "external output is never recolored");

      for (const r of [empty, rev]) {
        await seat.connect(deployer).setRenderer(await r.getAddress());
        expectInverted(decode(await seat.tokenURI(id)).svg);
      }

      await seat.connect(deployer).setRenderer(hre.ethers.ZeroAddress);
      expectInverted(decode(await seat.tokenURI(id)).svg);
    });
  });
});
