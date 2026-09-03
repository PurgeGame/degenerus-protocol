// Test-side seeding and decoding of the packed trait buckets via hardhat_setStorageAt.
//
// lvlTraitEntry[lvl][trait] (slot 8) is a uint256[] whose length word holds the occurrence
// count and whose data words hold eight uint32 lanes each; a lane is a position in the
// per-level owner registry lvlEntryOwner[lvl] (slot 67). Seeding a bucket therefore appends
// every holder to the registry and writes the lanes that name those positions.
import hre from "hardhat";

const TRAIT_SLOT = 8n;
const OWNER_SLOT = 67n;
const LANE_MASK = 0xffffffffn;

const pad32 = (v) => hre.ethers.toBeHex(BigInt(v), 32);

function mapSlot(key, base) {
  return BigInt(
    hre.ethers.keccak256(
      hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "uint256"], [BigInt(key), BigInt(base)])
    )
  );
}

function bucketLengthSlot(lvl, trait, traitSlot = TRAIT_SLOT) {
  return mapSlot(lvl, traitSlot) + BigInt(trait);
}

function ownerLengthSlot(lvl, ownerSlot = OWNER_SLOT) {
  return mapSlot(lvl, ownerSlot);
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
 * appended to lvlEntryOwner[lvl]; the bucket's lanes name those positions.
 */
async function seedTraitBucket(addr, lvl, trait, holders, opts = {}) {
  const traitSlot = opts.traitSlot ?? TRAIT_SLOT;
  const ownerSlot = opts.ownerSlot ?? OWNER_SLOT;

  const ownersLen = ownerLengthSlot(lvl, ownerSlot);
  let ownerCount = await getStorage(addr, ownersLen);
  const ownersData = dataBase(ownersLen);
  const lanes = [];
  for (const h of holders) {
    await setStorage(addr, ownersData + ownerCount, BigInt(h) & ((1n << 160n) - 1n));
    lanes.push(ownerCount);
    ownerCount += 1n;
  }
  await setStorage(addr, ownersLen, ownerCount);

  const lenSlot = bucketLengthSlot(lvl, trait, traitSlot);
  await setStorage(addr, lenSlot, BigInt(holders.length));
  const base = dataBase(lenSlot);
  for (let w = 0; w * 8 < lanes.length; ++w) {
    let word = 0n;
    for (let j = 0; j < 8 && w * 8 + j < lanes.length; ++j) {
      word |= (lanes[w * 8 + j] & LANE_MASK) << BigInt(32 * j);
    }
    await setStorage(addr, base + BigInt(w), word);
  }
}

/** Decode the bucket back to holder addresses through the registry. */
async function readTraitBucket(addr, lvl, trait, opts = {}) {
  const traitSlot = opts.traitSlot ?? TRAIT_SLOT;
  const ownerSlot = opts.ownerSlot ?? OWNER_SLOT;
  const lenSlot = bucketLengthSlot(lvl, trait, traitSlot);
  const len = Number(await getStorage(addr, lenSlot));
  const base = dataBase(lenSlot);
  const ownersData = dataBase(ownerLengthSlot(lvl, ownerSlot));
  const out = [];
  let word = 0n;
  for (let i = 0; i < len; ++i) {
    if (i % 8 === 0) word = await getStorage(addr, base + BigInt(i >> 3));
    const lane = (word >> BigInt(32 * (i & 7))) & LANE_MASK;
    const owner = await getStorage(addr, ownersData + lane);
    out.push(hre.ethers.getAddress("0x" + owner.toString(16).padStart(40, "0")));
  }
  return out;
}

export {
  TRAIT_SLOT,
  OWNER_SLOT,
  bucketLengthSlot,
  ownerLengthSlot,
  seedTraitBucket,
  readTraitBucket,
};
