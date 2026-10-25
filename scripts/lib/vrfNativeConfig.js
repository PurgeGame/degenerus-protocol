// Deployment lane and native billing parameters, pinned to the public v2.5 configuration.
export const ETHEREUM_VRF_KEY = "0x8077df514608a09f83e4e8d300645594e5d7234665448ba83f51a50f842bd3d9";
export const BASE_SEPOLIA_VRF_KEY = "0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71";
export const TEST_VRF_KEY = `0x${"ab".repeat(32)}`;
export function vrfNativeConfig(keyHash, production = false) {
  const key = keyHash?.toLowerCase();
  let laneMaxGasPrice, premium;
  if (key === ETHEREUM_VRF_KEY || (!production && key === TEST_VRF_KEY)) {
    laneMaxGasPrice = 200_000_000_000n; premium = 24n;
  } else if (key === BASE_SEPOLIA_VRF_KEY) {
    laneMaxGasPrice = 30_000_000_000n; premium = 60n;
  } else throw new Error(`Unsupported VRF lane key: ${keyHash}`);
  const billedGas = 300_000n;
  const stressCost = billedGas * 1_000_000_000n * (100n + premium) / 100n;
  const minimum = laneMaxGasPrice * 350_000n * (100n + premium) / 100n;
  const lowWater = 2n * minimum + 5n * 12n * stressCost;
  const target = lowWater + 2n * 400n * stressCost;
  return {laneMaxGasPrice, premium, billedGas, stressCost, minimum, lowWater, target};
}
export function nativeSeed(config, value) {
  const minimum = config.target > 100_000_000_000_000_000n ? config.target : 100_000_000_000_000_000n;
  if (!value) return minimum;
  if (!/^\d+(\.\d{1,18})?$/.test(value)) throw new Error("VRF_NATIVE_SEED must be an ETH decimal");
  const [whole, fraction = ""] = value.split(".");
  const seed = BigInt(whole) * 10n ** 18n + BigInt(fraction.padEnd(18, "0"));
  if (seed < minimum) throw new Error(`VRF_NATIVE_SEED below required ${minimum} wei`);
  return seed;
}
