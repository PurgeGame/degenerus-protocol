// Test-side seeding and decoding of the packed trait buckets via hardhat_setStorageAt.
//
// Trait headers hold a uint32 count and seven uint32 tail lanes. Full data words have eight lanes.
// The full buffer level and per-parity bitmap gate validity; owners resolve through one permanent global registry.
import hre from "hardhat";

const TRAIT_SLOT = 8n;
const OWNER_SLOT = 67n;
const queueStorageKey = (key) => { const lvl = BigInt(key) & 0x3fffffn; return (BigInt(key) & 0xc00000n) | (lvl === 0n ? 0n : (lvl - 1n) % 100n + 1n); };
const ownerStorageKey = (lvl) => BigInt(lvl);
const LANE_MASK = 0xffffffffn;
const TRAIT_BITMAP_SLOT = 75n;

const pad32 = (v) => hre.ethers.toBeHex(BigInt(v), 32);

function mapSlot(key, base) {
  return BigInt(
    hre.ethers.keccak256(
      hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "uint256"], [BigInt(key), BigInt(base)])
    )
  );
}

function bucketLengthSlot(lvl, trait, traitSlot = TRAIT_SLOT) {
  return mapSlot(BigInt(lvl) & 1n, traitSlot) + BigInt(trait);
}

function ownerLengthSlot(lvl, ownerSlot = OWNER_SLOT) {
  return BigInt(ownerSlot);
}

function dataBase(lengthSlot) {
  return BigInt(hre.ethers.keccak256(pad32(lengthSlot)));
}

async function setStorage(addr, slot, value) {
  await hre.network.provider.send("hardhat_setStorageAt", [addr, pad32(slot), pad32(value)]);
}

async function getStorage(addr, slot) {
  return BigInt(await hre.ethers.provider.getStorage(addr, pad32(slot)));
}

/**
 * Replace lvlTraitEntry[lvl][trait] with one occurrence per holder, in order. Holders are
 * registered globally; the bucket's lanes name their immutable zero-based positions.
 */
async function seedTraitBucket(addr, lvl, trait, holders, opts = {}) {
  const traitSlot = opts.traitSlot ?? TRAIT_SLOT;
  const ownerSlot = opts.ownerSlot ?? OWNER_SLOT;

  const ownersLen = ownerLengthSlot(lvl, ownerSlot);
  const lanes = [];
  for (const h of holders) lanes.push((await registerOwner(addr, h, ownerSlot)) - 1n);

  const stampShift = 112n + (BigInt(lvl) & 1n) * 24n;
  const stamps = await getStorage(addr, 5n);
  const bitmapSlot = (opts.traitBitmapSlot ?? TRAIT_BITMAP_SLOT) + (BigInt(lvl) & 1n);
  const sameLevel = ((stamps >> stampShift) & 0xffffffn) === BigInt(lvl);
  const bits = sameLevel ? await getStorage(addr, bitmapSlot) : 0n;
  await setStorage(addr, bitmapSlot, bits | (1n << BigInt(trait)));
  await setStorage(addr, 5n, (stamps & ~(0xffffffn << stampShift)) | (BigInt(lvl) << stampShift));
  const lenSlot = bucketLengthSlot(lvl, trait, traitSlot);
  const fullWords = Math.floor(lanes.length / 8);
  let tail = 0n;
  for (let j = fullWords * 8; j < lanes.length; ++j) tail |= (lanes[j] & LANE_MASK) << BigInt(32 * (j & 7));
  await setStorage(addr, lenSlot, BigInt(holders.length) | (tail << 32n));
  const base = dataBase(lenSlot);
  for (let w = 0; w < fullWords; ++w) {
    let word = 0n;
    for (let j = 0; j < 8 && w * 8 + j < lanes.length; ++j) {
      word |= (lanes[w * 8 + j] & LANE_MASK) << BigInt(32 * j);
    }
    await setStorage(addr, base + BigInt(w), word);
  }
}

async function registerOwner(addr, holder, ownerSlot = OWNER_SLOT) {
  const locator = mapSlot(BigInt(holder), 13n);
  let id = (await getStorage(addr, locator)) & LANE_MASK;
  if (id === 0n) {
    const count = await getStorage(addr, ownerSlot);
    id = count + 1n;
    if (id > LANE_MASK) throw new Error('stable owner namespace exhausted');
    await setStorage(addr, dataBase(ownerSlot) + count, BigInt(holder));
    await setStorage(addr, ownerSlot, id);
    await setStorage(addr, locator, id);
  }
  return id;
}

/** Replace a queue with stable nonzero uint32 wallet IDs. */
async function seedTicketQueue(addr, key, holders) {
  const lanes = [];
  for (const holder of holders) lanes.push(await registerOwner(addr, holder));
  const level = BigInt(key) & ((1n << 22n) - 1n);
  const physical = queueStorageKey(key);
  const lengthSlot = mapSlot(physical, 12n);
  await setStorage(addr, mapSlot(physical, 77n), level);
  await setStorage(addr, lengthSlot, BigInt(holders.length));
  const base = dataBase(lengthSlot);
  for (let w = 0; w * 8 < lanes.length; ++w) {
    let word = 0n;
    for (let j = 0; j < 8 && w * 8 + j < lanes.length; ++j) {
      word |= lanes[w * 8 + j] << BigInt(j * 32);
    }
    await setStorage(addr, base + BigInt(w), word);
  }
}

/** Resolve the persistent pending word for a wallet's stable ID and logical level. */
async function entryOwnerRecordSlot(addr, key, player) {
  const id = (await getStorage(addr, mapSlot(BigInt(player), 13n))) & LANE_MASK;
  if (id === 0n) return null;
  return pad32(mapSlot(id, 78n));
}

async function readEntriesOwed(addr, key, player) {
  const slot = await entryOwnerRecordSlot(addr, key, player);
  if (slot === null) return 0n;
  const shift = BigInt(key) & (1n << 22n) ? 84n : BigInt(key) & (1n << 23n) ? 42n : 0n;
  const word = await getStorage(addr, slot);
  const level = BigInt(key) & ((1n << 22n) - 1n);
  if (((word >> (126n + (shift / 42n) * 24n)) & 0xffffffn) !== level) return 0n;
  const lane = (word >> shift) & ((1n << 42n) - 1n);
  if (!(lane & (1n << 41n))) return 0n;
  const id = (await getStorage(addr, mapSlot(BigInt(player), 13n))) & LANE_MASK;
  return (id << 48n) | (lane & ((1n << 41n) - 1n));
}

/** Decode the bucket back to holder addresses through the registry. */
async function readTraitBucket(addr, lvl, trait, opts = {}) {
  const traitSlot = opts.traitSlot ?? TRAIT_SLOT;
  const ownerSlot = opts.ownerSlot ?? OWNER_SLOT;
  const lenSlot = bucketLengthSlot(lvl, trait, traitSlot);
  const stamp = ((await getStorage(addr, 5n)) >> (112n + (BigInt(lvl) & 1n) * 24n)) & 0xffffffn;
  const header = await getStorage(addr, lenSlot);
  const bits = await getStorage(addr, (opts.traitBitmapSlot ?? TRAIT_BITMAP_SLOT) + (BigInt(lvl) & 1n));
  const len = stamp !== BigInt(lvl) || !(bits & (1n << BigInt(trait))) ? 0 : Number(header & LANE_MASK);
  const base = dataBase(lenSlot);
  const ownersData = dataBase(ownerLengthSlot(lvl, ownerSlot));
  const out = [];
  let word = 0n;
  for (let i = 0; i < len; ++i) {
    if (i % 8 === 0) word = (i >> 3) === Math.floor(len / 8) ? header >> 32n : await getStorage(addr, base + BigInt(i >> 3));
    const lane = (word >> BigInt(32 * (i & 7))) & LANE_MASK;
    const owner = (await getStorage(addr, ownersData + lane)) & ((1n << 160n) - 1n);
    out.push(hre.ethers.getAddress("0x" + owner.toString(16).padStart(40, "0")));
  }
  return out;
}

export {
  queueStorageKey,
  ownerStorageKey,
  TRAIT_SLOT,
  OWNER_SLOT,
  TRAIT_BITMAP_SLOT,
  bucketLengthSlot,
  ownerLengthSlot,
  seedTraitBucket,
  seedTicketQueue,
  readEntriesOwed,
  entryOwnerRecordSlot,
  readTraitBucket,
};
