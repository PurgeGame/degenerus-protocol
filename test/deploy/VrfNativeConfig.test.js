import { expect } from "chai";
import { vrfNativeConfig, nativeSeed, ETHEREUM_VRF_KEY, BASE_SEPOLIA_VRF_KEY, TEST_VRF_KEY } from "../../scripts/lib/vrfNativeConfig.js";

describe("Native VRF deployment funding", function () {
  it("pins lane price and premium to the selected key", function () {
    const mainnet = vrfNativeConfig(ETHEREUM_VRF_KEY, true);
    expect(mainnet.minimum).to.equal(86_800_000_000_000_000n);
    expect(mainnet.target).to.equal(493_520_000_000_000_000n);
    const base = vrfNativeConfig(BASE_SEPOLIA_VRF_KEY, true);
    expect(base.minimum).to.equal(16_800_000_000_000_000n);
    expect(base.laneMaxGasPrice).to.equal(30_000_000_000n);
    expect(base.premium).to.equal(60n);
  });
  it("rejects mock and unknown lanes for production", function () {
    expect(() => vrfNativeConfig(TEST_VRF_KEY, true)).to.throw("Unsupported VRF lane");
    expect(() => vrfNativeConfig(`0x${"12".repeat(32)}`)).to.throw("Unsupported VRF lane");
  });
  it("requires seed >= max(target, 0.1 ETH)", function () {
    const config = vrfNativeConfig(ETHEREUM_VRF_KEY);
    expect(nativeSeed(config)).to.equal(config.target);
    expect(nativeSeed(config, "0.49352")).to.equal(config.target);
    expect(() => nativeSeed(config, "0.493519999999999999")).to.throw("below required");
    expect(nativeSeed({target: 1n})).to.equal(100_000_000_000_000_000n);
    expect(() => nativeSeed(config, "1e-1")).to.throw("ETH decimal");
  });
});
