import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
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
 *   { STETH_TOKEN, LINK_TOKEN, VRF_COORDINATOR, CREATOR }
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

  // ContractAddresses.sol is regenerated on demand — predicted addresses are
  // patched in before every build/deploy — so there is no canonical state to
  // snapshot. We deliberately do NOT back it up: a leftover .bak could only
  // resurrect a stale/removed constant on restore.
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
 * Purge any stale ContractAddresses.sol.bak left by older tooling. Backups are
 * no longer created; this only deletes a leftover so it can't resurrect a
 * removed constant. Safe to call when no .bak exists.
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
  //   or:  address internal constant NAME =\n        address(0x...);
  //
  // The `=` may be followed by whitespace including newlines/indent when the
  // declaration spans two lines. Match any whitespace between `=` and the
  // `address(...)` literal so both single-line and multi-line formats work.
  const regex = new RegExp(
    `(address internal constant ${constantName} =\\s*)address\\(0x?[0-9a-fA-F]*\\);`
  );
  const replacement = `$1address(${address});`;
  return src.replace(regex, replacement);
}
