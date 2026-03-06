/**
 * Sim Bridge: inline re-implementation of simulator formulas for Hardhat cross-validation.
 * Each function is a direct port from the simulator TypeScript modules, using BigInt
 * arithmetic with floor division to match Solidity behavior.
 *
 * These functions are intentionally independent of the simulator codebase to avoid
 * cross-project build dependencies. They match the simulator logic exactly.
 */

// ─── Price Lookup (port of simulator/src/mechanics/priceLookup.ts) ───

const ETH_001 = 10_000_000_000_000_000n;
const ETH_002 = 20_000_000_000_000_000n;
const ETH_004 = 40_000_000_000_000_000n;
const ETH_008 = 80_000_000_000_000_000n;
const ETH_012 = 120_000_000_000_000_000n;
const ETH_016 = 160_000_000_000_000_000n;
const ETH_024 = 240_000_000_000_000_000n;

/**
 * Returns the ticket price in wei for the given game level.
 * Direct port of PriceLookupLib.sol / simulator priceLookup.ts.
 * @param {number} level - Game level (0-based)
 * @returns {bigint} Price in wei
 */
export function priceForLevel(level) {
  if (level < 5) return ETH_001;
  if (level < 10) return ETH_002;

  const pos = level % 100;
  if (level >= 100 && pos === 0) return ETH_024;

  if (pos < 30) return ETH_004;
  if (pos < 60) return ETH_008;
  if (pos < 90) return ETH_012;
  return ETH_016;
}

// ─── Pool Routing (port of simulator/src/mechanics/poolRouting.ts) ───

const BPS_BASE = 10_000n;

const TICKET_NEXT_BPS = 9000n;
const TICKET_FUTURE_BPS = 1000n;
const LOOTBOX_NEXT_BPS = 1000n;
const LOOTBOX_FUTURE_BPS = 9000n;

/**
 * Split ticket payment amount into next/future pool shares.
 * @param {bigint} amount - Total payment in wei
 * @returns {{ nextPool: bigint, futurePool: bigint }}
 */
export function routeTicketSplit(amount) {
  return {
    nextPool: (amount * TICKET_NEXT_BPS) / BPS_BASE,
    futurePool: (amount * TICKET_FUTURE_BPS) / BPS_BASE,
  };
}

/**
 * Split lootbox payment amount into next/future pool shares.
 * @param {bigint} amount - Total payment in wei
 * @returns {{ nextPool: bigint, futurePool: bigint }}
 */
export function routeLootboxSplit(amount) {
  return {
    nextPool: (amount * LOOTBOX_NEXT_BPS) / BPS_BASE,
    futurePool: (amount * LOOTBOX_FUTURE_BPS) / BPS_BASE,
  };
}

// ─── Whale Bundle (port of simulator/src/mechanics/passPricing.ts) ───

const ETH_UNIT = 10n ** 18n;
const WHALE_EARLY_PRICE = 2_400_000_000_000_000_000n; // 2.4 ETH
const WHALE_STANDARD_PRICE = 4n * ETH_UNIT; // 4 ETH

const BOON_DISCOUNT_BPS = {
  0: 0n,
  1: 1000n,
  2: 2500n,
  3: 5000n,
};

/**
 * Calculate whale bundle price.
 * @param {number} level - Current game level
 * @param {number} qty - Number of bundles
 * @param {number} boonTier - 0-3
 * @returns {bigint} Total price in wei
 */
export function calculateWhaleBundlePrice(level, qty, boonTier) {
  if (level <= 3) {
    return WHALE_EARLY_PRICE * BigInt(qty);
  }

  const discountBps = BOON_DISCOUNT_BPS[boonTier] ?? 0n;
  const unitPrice = (WHALE_STANDARD_PRICE * (10000n - discountBps)) / 10000n;
  return unitPrice * BigInt(qty);
}

// ─── Deity Pass (port of simulator/src/mechanics/passPricing.ts) ─────

const DEITY_BASE_PRICE = 24n * ETH_UNIT;

/**
 * Calculate deity pass price using triangular pricing T(k).
 * Price = DEITY_BASE_PRICE + T(k) * ETH, where T(k) = k*(k+1)/2.
 * @param {number} passesSold - Number of passes already sold (0-indexed)
 * @param {number} boonTier - 0-3
 * @returns {bigint} Price in wei
 */
export function calculateDeityPassPrice(passesSold, boonTier) {
  const k = BigInt(passesSold);
  const triangular = (k * (k + 1n)) / 2n;
  const basePrice = DEITY_BASE_PRICE + triangular * ETH_UNIT;

  const discountBps = BOON_DISCOUNT_BPS[boonTier] ?? 0n;
  if (discountBps === 0n) return basePrice;

  return (basePrice * (10000n - discountBps)) / 10000n;
}
