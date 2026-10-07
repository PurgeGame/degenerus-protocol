// Test-side seeding and decoding of the packed trait buckets via hardhat_setStorageAt.
//
// Trait headers hold a uint32 count and seven uint32 tail lanes. Full data words have eight lanes.
// The full buffer level and per-parity bitmap gate validity; lanes hold wallet IDs, the position in the `wallets` table (id 0 is the dummy; elements carry the address in bits 0..159).
// Every storage root is read from the checked-in layout oracle (scripts/layout/golden/DegenerusGame.json),
// which the layout gate verifies against production, so a layout shift cannot leave a stale literal here.
import hre from "hardhat";
import { readFileSync } from "node:fs";

const GAME_LAYOUT = JSON.parse(
  readFileSync(new URL("../../scripts/layout/golden/DegenerusGame.json", import.meta.url), "utf8")
);
function layoutEntry(label) {
  const entry = GAME_LAYOUT.find((item) => item.label === label);
  if (!entry) throw new Error(`bucketSeed: ${label} missing from the DegenerusGame layout oracle`);
  return entry;
}
const rootOf = (label) => BigInt(layoutEntry(label).slot);

const TRAIT_SLOT = rootOf("lvlTraitEntry");
const OWNER_SLOT = rootOf("wallets");
const WALLET_IDS_SLOT = rootOf("walletIds");

const QUEUE_SLOT = rootOf("ticketQueue");
const PENDING_SLOT = rootOf("ticketPending");
const FAR_FUTURE_OWED_SLOT = rootOf("farFutureOwed");
const TRAIT_BITMAP_SLOT = rootOf("traitBucketLive");
const BUFFER_LEVELS_SLOT = rootOf("ticketBufferLevels");
const BUFFER_LEVELS_SHIFT = BigInt(layoutEntry("ticketBufferLevels").offset) * 8n;
const queueStorageKey = (key) => { const lvl = BigInt(key) & 0x3fffffn; return (BigInt(key) & 0xc00000n) | (lvl === 0n ? 0n : (lvl - 1n) % 100n + 1n); };
const ownerStorageKey = (lvl) => BigInt(lvl);
const LANE_MASK = 0xffffffffn;
const TICKET_SLOT_BIT = 1n << 23n;
const TICKET_FAR_FUTURE_BIT = 1n << 22n;
const LEVEL_MASK = (1n << 22n) - 1n;

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
 * registered globally; the bucket's lanes name their wallet IDs.
 */
async function seedTraitBucket(addr, lvl, trait, holders, opts = {}) {
  const traitSlot = opts.traitSlot ?? TRAIT_SLOT;
  const ownerSlot = opts.ownerSlot ?? OWNER_SLOT;

  const ownersLen = ownerLengthSlot(lvl, ownerSlot);
  const lanes = [];
  for (const h of holders) lanes.push(await registerOwner(addr, h, ownerSlot));

  const stampShift = BUFFER_LEVELS_SHIFT + (BigInt(lvl) & 1n) * 24n;
  const stamps = await getStorage(addr, BUFFER_LEVELS_SLOT);
  const bitmapSlot = (opts.traitBitmapSlot ?? TRAIT_BITMAP_SLOT) + (BigInt(lvl) & 1n);
  const sameLevel = ((stamps >> stampShift) & 0xffffffn) === BigInt(lvl);
  const bits = sameLevel ? await getStorage(addr, bitmapSlot) : 0n;
  await setStorage(addr, bitmapSlot, bits | (1n << BigInt(trait)));
  await setStorage(addr, BUFFER_LEVELS_SLOT, (stamps & ~(0xffffffn << stampShift)) | (BigInt(lvl) << stampShift));
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
  const idSlot = mapSlot(BigInt(holder), WALLET_IDS_SLOT);
  let id = (await getStorage(addr, idSlot)) & LANE_MASK;
  if (id === 0n) {
    const count = await getStorage(addr, ownerSlot);
    id = count;
    if (id > LANE_MASK) throw new Error('wallet id namespace exhausted');
    await setStorage(addr, dataBase(ownerSlot) + count, BigInt(holder));
    await setStorage(addr, ownerSlot, count + 1n);
    await setStorage(addr, idSlot, id);
  }
  return id;
}

/** Address held by wallet-table element `id` (zero for id 0 or an unallocated id). */
async function walletAddressOf(addr, id) {
  const owner = (await getStorage(addr, dataBase(OWNER_SLOT) + BigInt(id))) & ((1n << 160n) - 1n);
  return hre.ethers.getAddress("0x" + owner.toString(16).padStart(40, "0"));
}

/** Replace a queue with stable nonzero uint32 wallet IDs. */
async function seedTicketQueue(addr, key, holders) {
  const lanes = [];
  for (const holder of holders) lanes.push(await registerOwner(addr, holder));
  const level = BigInt(key) & ((1n << 22n) - 1n);
  const physical = queueStorageKey(key);
  const lengthSlot = mapSlot(physical, QUEUE_SLOT);
  // Queue header: owner count in bits 0..31, occupying level tag in bits 32..55.
  await setStorage(addr, lengthSlot, BigInt(holders.length) | (level << 32n));
  const base = dataBase(lengthSlot);
  for (let w = 0; w * 8 < lanes.length; ++w) {
    let word = 0n;
    for (let j = 0; j < 8 && w * 8 + j < lanes.length; ++j) {
      word |= lanes[w * 8 + j] << BigInt(j * 32);
    }
    await setStorage(addr, base + BigInt(w), word);
  }
}

async function ownerIdOf(addr, player) {
  return (await getStorage(addr, mapSlot(BigInt(player), WALLET_IDS_SLOT))) & LANE_MASK;
}

/** Far-future lanes recycle 100 circular level positions, authenticated by the queue level tag. */
async function farFuturePosition(addr, lvl) {
  if (lvl === 0n) return null;
  const position = (lvl - 1n) % 100n;
  const header = await getStorage(addr, mapSlot((position + 1n) | TICKET_FAR_FUTURE_BIT, QUEUE_SLOT));
  let occupying = (header >> 32n) & 0xffffffn;
  if (occupying === 0n) occupying = position + 1n;
  return occupying === lvl ? position : null;
}

/**
 * Resolve the storage word holding a wallet's owed record for a queue key: near keys
 * share one `ticketPending[id]` word (parity x slot lanes); far-future keys use one
 * 32-bit lane of `farFutureOwed[id][position / 8]`. Returns null for an unregistered wallet.
 */
async function entryOwnerRecordSlot(addr, key, player) {
  const id = await ownerIdOf(addr, player);
  if (id === 0n) return null;
  if (BigInt(key) & TICKET_FAR_FUTURE_BIT) {
    const position = (BigInt(key) & LEVEL_MASK) === 0n ? 0n : ((BigInt(key) & LEVEL_MASK) - 1n) % 100n;
    return pad32(mapSlot(id, FAR_FUTURE_OWED_SLOT) + (position >> 3n));
  }
  return pad32(mapSlot(id, PENDING_SLOT));
}

/**
 * Mirror of DegenerusGameStorage._entryPacked: (ownerId << 48) | owed << 8 | rem, with the
 * far-future snap-done flag at bit 40. Zero when the lane is absent or its level tag is stale.
 */
async function readEntriesOwed(addr, key, player) {
  key = BigInt(key);
  const id = await ownerIdOf(addr, player);
  if (id === 0n) return 0n;
  const level = key & LEVEL_MASK;
  if (key & TICKET_FAR_FUTURE_BIT) {
    const position = await farFuturePosition(addr, level);
    if (position === null) return 0n;
    const word = await getStorage(addr, mapSlot(id, FAR_FUTURE_OWED_SLOT) + (position >> 3n));
    const lane = (word >> (32n * (position & 7n))) & LANE_MASK;
    if (!(lane & 0x80000000n)) return 0n;
    return (id << 48n) | ((lane & 0x3fffffffn) << 8n) | ((lane & 0x40000000n) << 10n);
  }
  const word = await getStorage(addr, mapSlot(id, PENDING_SLOT));
  const parity = level & 1n;
  const shift = parity * 84n + (key & TICKET_SLOT_BIT ? 42n : 0n);
  if (((word >> (168n + parity * 24n)) & 0xffffffn) !== level) return 0n;
  const lane = (word >> shift) & ((1n << 42n) - 1n);
  if (!(lane & (1n << 41n))) return 0n;
  return (id << 48n) | (lane & ((1n << 41n) - 1n));
}

/** Decode the bucket back to holder addresses through the registry. */
async function readTraitBucket(addr, lvl, trait, opts = {}) {
  const traitSlot = opts.traitSlot ?? TRAIT_SLOT;
  const ownerSlot = opts.ownerSlot ?? OWNER_SLOT;
  const lenSlot = bucketLengthSlot(lvl, trait, traitSlot);
  const stamp = ((await getStorage(addr, BUFFER_LEVELS_SLOT)) >> (BUFFER_LEVELS_SHIFT + (BigInt(lvl) & 1n) * 24n)) & 0xffffffn;
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
  registerOwner,
  walletAddressOf,
  ownerIdOf,
  seedTicketQueue,
  readEntriesOwed,
  entryOwnerRecordSlot,
  readTraitBucket,
};
