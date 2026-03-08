import { readFileSync, writeFileSync, existsSync, copyFileSync, unlinkSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_CONTRACT_FILE = resolve(
  __dirname,
  "../../contracts/ContractAddresses.sol"
);

/**
 * Patch ContractAddresses.sol with concrete addresses before compilation.
 *
 * @param {Map<string, string>} addressMap - Predicted protocol addresses (key → address)
 * @param {object} external - External/config addresses:
 *   { STETH_TOKEN, LINK_TOKEN, VRF_COORDINATOR, WXRP, CREATOR }
 * @param {number} deployDayBoundary - Computed DEPLOY_DAY_BOUNDARY value
 * @param {string} vrfKeyHash - 32-byte VRF key hash (hex string with 0x prefix)
 * @param {string} [contractFilePath] - Optional path to ContractAddresses.sol (for testnet builds)
 */
export function patchContractAddresses(
  addressMap,
  external,
  deployDayBoundary,
  vrfKeyHash,
  contractFilePath
) {
  const CONTRACT_FILE = contractFilePath || DEFAULT_CONTRACT_FILE;
  const BACKUP_FILE = CONTRACT_FILE + ".bak";

  // Back up original (only if no backup exists yet)
  if (!existsSync(BACKUP_FILE)) {
    copyFileSync(CONTRACT_FILE, BACKUP_FILE);
  }

  let src = readFileSync(CONTRACT_FILE, "utf8");

  // Patch address constants from predicted map
  for (const [key, addr] of addressMap) {
    src = replaceAddressConstant(src, key, addr);
  }

  // Patch external addresses
  for (const [key, addr] of Object.entries(external)) {
    if (key === "VRF_KEY_HASH") continue; // handled separately
    if (addr) {
      src = replaceAddressConstant(src, key, addr);
    }
  }

  // Patch DEPLOY_DAY_BOUNDARY
  src = src.replace(
    /uint48 internal constant DEPLOY_DAY_BOUNDARY = \d+;/,
    `uint48 internal constant DEPLOY_DAY_BOUNDARY = ${deployDayBoundary};`
  );

  // Patch VRF_KEY_HASH
  if (vrfKeyHash) {
    src = src.replace(
      /bytes32 internal constant VRF_KEY_HASH = 0x[0-9a-fA-F]+;/,
      `bytes32 internal constant VRF_KEY_HASH = ${vrfKeyHash};`
    );
  }

  writeFileSync(CONTRACT_FILE, src, "utf8");
}

/**
 * Restore ContractAddresses.sol to its original (all-zeros) state.
 * @param {string} [contractFilePath] - Optional path (must match the one used in patch)
 */
export function restoreContractAddresses(contractFilePath) {
  const CONTRACT_FILE = contractFilePath || DEFAULT_CONTRACT_FILE;
  const BACKUP_FILE = CONTRACT_FILE + ".bak";
  if (existsSync(BACKUP_FILE)) {
    copyFileSync(BACKUP_FILE, CONTRACT_FILE);
  }
}

/**
 * Clean up the backup file (call after successful deploy).
 * @param {string} [contractFilePath] - Optional path (must match the one used in patch)
 */
export function cleanupBackup(contractFilePath) {
  const CONTRACT_FILE = contractFilePath || DEFAULT_CONTRACT_FILE;
  const BACKUP_FILE = CONTRACT_FILE + ".bak";
  if (existsSync(BACKUP_FILE)) {
    unlinkSync(BACKUP_FILE);
  }
}

// --- Internal ---

function replaceAddressConstant(src, constantName, address) {
  // Match: address internal constant NAME = address(0);
  //   or:  address internal constant NAME = address(0x...);
  const regex = new RegExp(
    `(address internal constant ${constantName} = )address\\(0x?[0-9a-fA-F]*\\);`
  );
  const replacement = `$1address(${address});`;
  return src.replace(regex, replacement);
}
