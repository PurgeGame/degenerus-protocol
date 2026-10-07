import { expect } from "chai";
import hre from "hardhat";
import { readFileSync } from "node:fs";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol, giveWalletId, restoreAddresses } from "../helpers/deployFixture.js";
import { wireIcons32 } from "../../scripts/lib/deployHelpers.js";

const ICONS = JSON.parse(readFileSync("scripts/data/icons32Data.symbolOrder.json", "utf8"));
const FIELDS = ["rimColor", "badgeBackgroundColor", "symbolColor", "backgroundColor", "outlineColor"];
const inherit = () => Object.fromEntries(FIELDS.map((key) => [key, ""]));
const colors = () => Object.fromEntries(FIELDS.map((key, i) => [key, ["#ff69b4", "#102030", "#abcdef", "#556677", "#FEDCBA"][i]]));
const geometry = (radius = 4600, centerX = 0, centerY = 0) => ({ radius, centerX, centerY });

function decode(uri) {
  const json = JSON.parse(Buffer.from(uri.split(",")[1], "base64").toString());
  return { json, svg: Buffer.from(json.image.split(",")[1], "base64").toString() };
}

async function impersonate(address) {
  await hre.network.provider.send("hardhat_impersonateAccount", [address]);
  await hre.network.provider.send("hardhat_setBalance", [address, "0x56BC75E2D63100000"]);
  return hre.ethers.getSigner(address);
}

async function fixture() {
  const f = await loadFixture(deployFullProtocol);
  await wireIcons32(f.icons32, ICONS, { finalize: true });
  const gameSigner = await impersonate(await f.game.getAddress());
  for (let id = 0; id < 31; id++) {
    if (id === 0 || id === 6) continue; // Genesis owners are contracts.
    await f.deityPass.connect(gameSigner).mint(id === 9 ? f.bob.address : f.alice.address, id);
  }
  await hre.network.provider.send("hardhat_stopImpersonatingAccount", [await f.game.getAddress()]);
  const renderer = await (await hre.ethers.getContractFactory("DeityPassCustomizationRenderer"))
    .deploy(await f.deityPass.getAddress());
  await f.deityPass.connect(f.deployer).setRenderer(await renderer.getAddress());
  return { ...f, renderer };
}

describe("DeityPassCustomizationRenderer", function () {
  this.timeout(300_000);
  after(restoreAddresses);

  it("binds to an existing pass and rejects zero/EOA bindings", async function () {
    const { deityPass, renderer, alice } = await loadFixture(fixture);
    expect(await renderer.pass()).to.equal(await deityPass.getAddress());
    const factory = await hre.ethers.getContractFactory("DeityPassCustomizationRenderer");
    for (const address of [hre.ethers.ZeroAddress, alice.address]) {
      await expect(factory.deploy(address)).to.be.revertedWithCustomError(renderer, "InvalidPass");
    }
    await expect(renderer.render(8, 1, 0, "Aries", "", false, "#111111", "#ffffff", "#111111"))
      .to.be.revertedWithCustomError(renderer, "OnlyPass");
  });

  it("changes Aries's ring to pink while Taurus and every other field remain unchanged", async function () {
    const { deityPass, renderer, alice } = await loadFixture(fixture);
    const taurus = await deityPass.tokenURI(9);
    const before = await renderer.effectiveTokenStyle(8);
    const tx = await renderer.connect(alice).setTokenColors(8, { ...inherit(), rimColor: "#ff69b4" });
    await expect(tx).to.emit(renderer, "TokenColorsUpdated").withArgs(8, Object.values({ ...inherit(), rimColor: "#ff69b4" }), 1);
    await expect(tx).to.emit(renderer, "MetadataUpdate").withArgs(8);
    const after = await renderer.effectiveTokenStyle(8);
    expect(after.overrideMask).to.equal(1);
    expect(after.colors.rimColor).to.equal("#ff69b4");
    for (const key of FIELDS.slice(1)) expect(after.colors[key]).to.equal(before.colors[key]);
    expect(after.geometry).to.deep.equal(before.geometry);
    const { json, svg } = decode(await deityPass.tokenURI(8));
    expect(json.name).to.equal("Deity Pass #8 - Aries");
    expect(svg).to.include('<circle r="46" fill="#ff69b4"/>');
    expect(svg).to.include('stroke="#3f1a82"');
    expect(await deityPass.tokenURI(9)).to.equal(taurus);
    expect((await renderer.effectiveTokenStyle(9)).overrideMask).to.equal(0);
  });

  it("renders all five independent fields and transforms the entire badge", async function () {
    const { deityPass, renderer, alice } = await loadFixture(fixture);
    const taurus = await deityPass.tokenURI(9);
    await renderer.connect(alice).setTokenColors(8, colors());
    await expect(renderer.connect(alice).setTokenGeometry(8, geometry(2400, -1000, 1500)))
      .to.emit(renderer, "TokenGeometryUpdated").withArgs(8, [2400, -1000, 1500], true);
    const style = await renderer.effectiveTokenStyle(8);
    for (const key of FIELDS) expect(style.colors[key]).to.equal(colors()[key]);
    expect(style.overrideMask).to.equal(63);
    expect(style.geometry).to.deep.equal([2400n, -1000n, 1500n]);
    const { svg } = decode(await deityPass.tokenURI(8));
    expect(svg).to.include('fill="#556677" stroke="#FEDCBA" stroke-width="2.2"');
    expect(svg).to.include("<g id='badge' transform='matrix(0.521739 0 0 0.521739 -10.000000 15.000000)'>");
    expect(svg).to.include('<circle r="46" fill="#ff69b4"/>');
    expect(svg).to.include('<circle r="28" fill="#102030"/>');
    expect(svg).to.include("<g fill='#abcdef' stroke='#abcdef'>");
    expect(svg.indexOf("id='badge'")).to.be.lessThan(svg.indexOf('<circle r="46"'));
    expect(svg.indexOf('<circle r="28"')).to.be.lessThan(svg.indexOf(ICONS.paths[8]));
    expect(svg).to.not.include("non-scaling-stroke");
    expect(svg).to.include('viewBox="-52 -52 104 104"');
    expect(await deityPass.tokenURI(9)).to.equal(taurus);
  });

  it("rejects other holders, the Vault administrator, game, and approved game operators on every mutation", async function () {
    const { deityPass, renderer, game, alice, bob, deployer } = await loadFixture(fixture);
    await giveWalletId(game, alice.address);
    await game.connect(alice).setOperatorApproval(0, bob.address, true);
    const gameSigner = await impersonate(await game.getAddress());
    for (const caller of [bob, deployer, gameSigner]) {
      const target = renderer.connect(caller);
      for (const call of [
        () => target.setTokenColors(8, colors()),
        () => target.setTokenGeometry(8, geometry()),
        () => target.clearTokenColors(8),
        () => target.clearTokenGeometry(8),
        () => target.clearTokenCustomization(8),
      ]) await expect(call()).to.be.revertedWithCustomError(renderer, "NotTokenOwner");
    }
    await hre.network.provider.send("hardhat_stopImpersonatingAccount", [await game.getAddress()]);
    await expect(deityPass.connect(alice).setRenderer(hre.ethers.ZeroAddress)).to.be.revertedWithCustomError(deityPass, "NotAuthorized");
    await expect(deityPass.connect(alice).setRenderColors("#ffffff", "#ffffff", "#ffffff"))
      .to.be.revertedWithCustomError(deityPass, "NotAuthorized");
    // Vault majority does not impersonate the Vault contract that owns token 0.
    await expect(renderer.connect(deployer).setTokenColors(0, inherit())).to.be.revertedWithCustomError(renderer, "NotTokenOwner");
  });

  it("rejects unminted and out-of-range IDs on all token reads and writes", async function () {
    const { renderer, alice } = await loadFixture(fixture);
    const target = renderer.connect(alice);
    for (const id of [31, 32, 256, hre.ethers.MaxUint256]) {
      for (const call of [
        () => target.effectiveTokenStyle(id), () => target.tokenCustomization(id),
        () => target.setTokenColors(id, colors()), () => target.setTokenGeometry(id, geometry()),
        () => target.clearTokenColors(id), () => target.clearTokenGeometry(id), () => target.clearTokenCustomization(id),
      ]) await expect(call()).to.be.revertedWithCustomError(renderer, "InvalidToken");
    }
  });

  it("validates every color and rejects malformed/injectable strings atomically", async function () {
    const { renderer, alice } = await loadFixture(fixture);
    await renderer.connect(alice).setTokenColors(8, colors());
    const before = await renderer.tokenCustomization(8);
    for (const field of FIELDS) {
      for (const bad of ["red", "abcdef", "#abc", "#12345678", "#gggggg", "#12345 ", '#123456"/>', "#１２３４５６"]) {
        await expect(renderer.connect(alice).setTokenColors(8, { ...colors(), [field]: bad }))
          .to.be.revertedWithCustomError(renderer, "InvalidColor");
      }
    }
    expect(await renderer.tokenCustomization(8)).to.deep.equal(before);
    await renderer.connect(alice).setTokenColors(8, { ...inherit(), symbolColor: "#aBcDeF" });
    expect((await renderer.effectiveTokenStyle(8)).colors.symbolColor).to.equal("#aBcDeF");
  });

  it("preserves all crypto source art, permits rim/background changes, and rejects crypto ink", async function () {
    const { deityPass, renderer, alice, vault, sdgnrs } = await loadFixture(fixture);
    for (let id = 0; id < 8; id++) {
      const owner = id === 0 ? await impersonate(await vault.getAddress())
        : id === 6 ? await impersonate(await sdgnrs.getAddress()) : alice;
      await expect(renderer.connect(owner).setTokenColors(id, colors()))
        .to.be.revertedWithCustomError(renderer, "UnsupportedSymbolInk");
      await renderer.connect(owner).setTokenColors(id, { ...colors(), symbolColor: "" });
      const { svg } = decode(await deityPass.tokenURI(id));
      expect(svg).to.include(ICONS.paths[id]);
      expect(svg).to.include('<circle r="46" fill="#ff69b4"/>');
      expect(svg).to.not.include("<g fill='");
      expect((await renderer.effectiveTokenStyle(id)).colors.symbolColor).to.equal("");
      await renderer.connect(owner).clearTokenCustomization(id);
      if (id === 0 || id === 6) await hre.network.provider.send("hardhat_stopImpersonatingAccount", [owner.address]);
    }
    expect((await renderer.effectiveTokenStyle(0)).colors.rimColor).to.equal("#ed0e11");
    expect((await renderer.effectiveTokenStyle(6)).colors.rimColor).to.equal("#30d100");
  });

  it("inherits changing defaults per field and supports independent and complete resets", async function () {
    const { deityPass, renderer, alice, deployer } = await loadFixture(fixture);
    await renderer.connect(alice).setTokenColors(8, { ...inherit(), rimColor: "#ff69b4" });
    await renderer.connect(alice).setTokenGeometry(8, geometry(1200, 1000, -1000));
    await deityPass.connect(deployer).setRenderColors("#112233", "#445566", "#778899");
    const style = await renderer.effectiveTokenStyle(8);
    expect(style.colors).to.deep.equal(["#ff69b4", "#ffffff", "#778899", "#445566", "#112233"]);
    expect(style.overrideMask).to.equal(33);
    await expect(renderer.connect(alice).clearTokenColors(8)).to.emit(renderer, "TokenColorsUpdated").withArgs(8, Object.values(inherit()), 32);
    expect((await renderer.effectiveTokenStyle(8)).geometry).to.deep.equal([1200n, 1000n, -1000n]);
    expect((await renderer.effectiveTokenStyle(8)).colors.rimColor).to.equal("#112233");
    await renderer.connect(alice).setTokenColors(8, colors());
    await expect(renderer.connect(alice).clearTokenGeometry(8)).to.emit(renderer, "TokenGeometryUpdated").withArgs(8, [4600, 0, 0], false);
    expect((await renderer.effectiveTokenStyle(8)).overrideMask).to.equal(31);
    expect((await renderer.effectiveTokenStyle(8)).geometry).to.deep.equal([4600n, 0n, 0n]);
    await renderer.connect(alice).setTokenGeometry(8, geometry(1200, -2000, 2000));
    await expect(renderer.connect(alice).clearTokenCustomization(8)).to.emit(renderer, "TokenCustomizationCleared").withArgs(8);
    expect((await renderer.effectiveTokenStyle(8)).overrideMask).to.equal(0);
    expect((await renderer.tokenCustomization(8)).colors).to.deep.equal(Object.values(inherit()));
    expect((await renderer.effectiveTokenStyle(8)).geometry).to.deep.equal([4600n, 0n, 0n]);
    const { svg } = decode(await deityPass.tokenURI(8));
    expect(svg).to.include('<circle r="46" fill="#112233"/>');
    expect(svg).to.include('fill="#445566" stroke="#112233"');
  });

  it("can clear one color without changing other colors or geometry", async function () {
    const { renderer, alice } = await loadFixture(fixture);
    await renderer.connect(alice).setTokenGeometry(8, geometry(2400, 100, -100));
    await renderer.connect(alice).setTokenColors(8, colors());
    await renderer.connect(alice).setTokenColors(8, { ...colors(), rimColor: "" });
    const style = await renderer.effectiveTokenStyle(8);
    expect(style.colors.rimColor).to.equal("#3f1a82");
    for (const field of FIELDS.slice(1)) expect(style.colors[field]).to.equal(colors()[field]);
    expect(style.overrideMask).to.equal(62);
    expect(style.geometry).to.deep.equal([2400n, 100n, -100n]);
  });

  it("exposes exact limits and keeps complete circles inside the stroked rounded card at every edge/corner", async function () {
    const { renderer, deityPass, alice } = await loadFixture(fixture);
    expect(await renderer.geometryBounds()).to.deep.equal([100n, 1200n, 4890n, 4600n, 4890n, 1090n]);
    for (const radius of [1200, 2400, 4600, 4890]) {
      const [lo, hi] = (await renderer.positionBounds(radius)).map(Number);
      for (const x of new Set([lo, 0, hi])) for (const y of new Set([lo, 0, hi])) {
        expect(await renderer.isValidGeometry(radius, x, y)).to.equal(true);
        await renderer.connect(alice).setTokenGeometry(8, geometry(radius, x, y));
        const { svg } = decode(await deityPass.tokenURI(8));
        const matrix = svg.match(/id='badge' transform='matrix\(([^)]+)\)'/)[1].split(" ").map(Number);
        expect(matrix[4]).to.equal(x / 100);
        expect(matrix[5]).to.equal(y / 100);
        const actualRadius = matrix[0] * 46;
        expect(actualRadius).to.be.at.most(radius / 100 + 1e-10);
        // Independent rounded-rectangle membership oracle, including its inner
        // stroke edge: distance to the central 76x76 square is at most 10.9.
        for (let angle = 0; angle < 720; angle++) {
          const theta = angle * Math.PI / 360;
          const px = x / 100 + actualRadius * Math.cos(theta);
          const py = y / 100 + actualRadius * Math.sin(theta);
          const dx = Math.max(Math.abs(px) - 38, 0);
          const dy = Math.max(Math.abs(py) - 38, 0);
          expect(dx * dx + dy * dy).to.be.at.most(10.9 ** 2 + 1e-8);
        }
      }
      for (const [x, y] of [[lo - 1, 0], [hi + 1, 0], [0, lo - 1], [0, hi + 1], [hi + 1, hi + 1]]) {
        expect(await renderer.isValidGeometry(radius, x, y)).to.equal(false);
        await expect(renderer.connect(alice).setTokenGeometry(8, geometry(radius, x, y)))
          .to.be.revertedWithCustomError(renderer, "InvalidGeometry");
      }
    }
  });

  it("rejects undersize, oversize, extreme coordinates, and enlargement of an offset badge atomically", async function () {
    const { renderer, alice } = await loadFixture(fixture);
    await renderer.connect(alice).setTokenGeometry(8, geometry(1200, 3690, -3690));
    for (const value of [geometry(0), geometry(1199), geometry(4891), geometry(65535), geometry(1200, -32768, 32767), geometry(4600, 3690, -3690)]) {
      expect(await renderer.isValidGeometry(...Object.values(value))).to.equal(false);
      await expect(renderer.connect(alice).setTokenGeometry(8, value)).to.be.revertedWithCustomError(renderer, "InvalidGeometry");
    }
    expect((await renderer.effectiveTokenStyle(8)).geometry).to.deep.equal([1200n, 3690n, -3690n]);
    for (const radius of [0, 1199, 4891, 65535]) {
      await expect(renderer.positionBounds(radius)).to.be.revertedWithCustomError(renderer, "InvalidGeometry");
    }
    // Resize + recenter in the same call succeeds.
    await renderer.connect(alice).setTokenGeometry(8, geometry(4890));
  });

  it("preserves every symbol name and path and the legacy default gold Dice 6 treatment", async function () {
    const { renderer, deityPass, game, deployer, alice } = await loadFixture(fixture);
    const gameSigner = await impersonate(await game.getAddress());
    await deityPass.connect(gameSigner).mint(alice.address, 31);
    await hre.network.provider.send("hardhat_stopImpersonatingAccount", [await game.getAddress()]);
    for (let id = 0; id < 32; id++) {
      const before = decode(await deityPass.tokenURI(id));
      expect(before.svg).to.include(ICONS.paths[id]);
      await deityPass.connect(deployer).setRenderer(hre.ethers.ZeroAddress);
      const internal = decode(await deityPass.tokenURI(id));
      expect(before.json.name).to.equal(internal.json.name);
      expect(before.json.description).to.equal(internal.json.description);
      expect(before.svg).to.include(internal.svg.match(/<g transform='matrix\([^']+'><g[^>]*>/)[0].replace(" style='vector-effect:non-scaling-stroke'", ""));
      await deityPass.connect(deployer).setRenderer(await renderer.getAddress());
    }
    await deityPass.connect(deployer).setRenderColors("#Ab8D3f", "#d9d9d9", "#AB8D3F");
    const { svg } = decode(await deityPass.tokenURI(29));
    expect(svg).to.include('<circle r="35" fill="#fff"/>');
    expect(svg).to.include('<circle r="28" fill="#111111"/>');
    expect(svg).to.include("<style>#ico circle{fill:#111}</style>");
    await renderer.connect(alice).setTokenColors(29, { ...inherit(), badgeBackgroundColor: "#123456" });
    expect(decode(await deityPass.tokenURI(29)).svg).to.include('<circle r="28" fill="#123456"/>');
  });

  it("restores byte-identical default artwork after a complete reset", async function () {
    const { renderer, deityPass, alice } = await loadFixture(fixture);
    const original = await deityPass.tokenURI(8);
    await renderer.connect(alice).setTokenColors(8, colors());
    await renderer.connect(alice).setTokenGeometry(8, geometry(1200, 3690, -3690));
    expect(await deityPass.tokenURI(8)).to.not.equal(original);
    await expect(renderer.connect(alice).clearTokenCustomization(8))
      .to.emit(renderer, "MetadataUpdate").withArgs(8);
    expect(await deityPass.tokenURI(8)).to.equal(original);
  });

  it("keeps overrides in this renderer across disable/reactivation and never mutates gameplay", async function () {
    const { renderer, deityPass, deployer, alice } = await loadFixture(fixture);
    const original = decode(await deityPass.tokenURI(8)).json;
    for (const send of [
      () => renderer.connect(alice).setTokenColors(8, colors()),
      () => renderer.connect(alice).setTokenGeometry(8, geometry(1200, 3690, -3690)),
      () => renderer.connect(alice).clearTokenColors(8),
      () => renderer.connect(alice).clearTokenGeometry(8),
      () => renderer.connect(alice).clearTokenCustomization(8),
    ]) {
      const tx = await send();
      const trace = await hre.network.provider.send("debug_traceTransaction", [tx.hash, { disableMemory: true, disableStorage: true, disableStack: true }]);
      // All external calls are STATICCALL (ownerOf); SSTORE occurs only in
      // renderer storage. This excludes changes to rolled colors, odds, boons,
      // scoring, pass ownership, symbol identities, and any gameplay state.
      expect(trace.structLogs.filter(({ op }) => ["CALL", "CALLCODE", "DELEGATECALL", "CREATE", "CREATE2", "SELFDESTRUCT"].includes(op))).to.have.length(0);
      expect(trace.structLogs.filter(({ op, depth }) => op === "SSTORE" && depth !== 1)).to.have.length(0);
    }
    await renderer.connect(alice).setTokenColors(8, colors());
    const customized = await deityPass.tokenURI(8);
    expect(decode(customized).json.name).to.equal(original.name);
    expect(decode(customized).json.description).to.equal(original.description);
    await deityPass.connect(deployer).setRenderer(hre.ethers.ZeroAddress);
    expect(await deityPass.tokenURI(8)).to.not.equal(customized);
    await deityPass.connect(deployer).setRenderer(await renderer.getAddress());
    expect(await deityPass.tokenURI(8)).to.equal(customized);
  });
});
