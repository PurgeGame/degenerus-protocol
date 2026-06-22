// Connection layer — loads the running deployment and builds ethers v6 handles.
//
// Reads the two artifacts emitted by scripts/deploy-local.js Phase 6:
//   deployments/localhost.json   { contracts:{KEY->addr}, mocks:{...}, signers:{...} }
//   deployments/localhost-abis/<SolidityContractName>.json   (raw ABI array)
// A manifest KEY (e.g. "GAME") resolves to its ABI filename via the shared
// KEY_TO_CONTRACT map (e.g. "DegenerusGame"). On a live testnet the sim repo
// supplies the same shape; only the addresses/RPC differ.
//
// DegenerusGame is a delegatecall-module FACADE: every external entrypoint is
// called on the GAME address (module bodies run in Game storage via
// delegatecall). To guarantee every module selector encodes, the GAME handle is
// built from a MERGED ABI = DegenerusGame + all GAME_*_MODULE ABIs (deduped).

import { ethers, FetchRequest } from "ethers";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { KEY_TO_CONTRACT } from "../../scripts/lib/predictAddresses.js";

// KEYs whose ABIs merge into the GAME facade handle (the delegatecall targets).
const GAME_MODULE_KEYS = [
  "GAME_MINT_MODULE",
  "GAME_ADVANCE_MODULE",
  "GAME_WHALE_MODULE",
  "GAME_JACKPOT_MODULE",
  "GAME_DECIMATOR_MODULE",
  "GAME_GAMEOVER_MODULE",
  "GAME_LOOTBOX_MODULE",
  "GAME_BOON_MODULE",
  "GAME_DEGENERETTE_MODULE",
  "GAME_BINGO_MODULE",
  "GAME_AFKING_MODULE",
  "GAME_FOILPACK_MODULE",
];

export class Connection {
  constructor(cfg) {
    this.cfg = cfg;
    // Per-request HTTP timeout (ethers' default is 300s). On a live hosted RPC a
    // single slow/hung call must fail fast and be handled by the tick watchdog,
    // not wedge the single-threaded soak loop for minutes.
    const fr = new FetchRequest(cfg.rpcUrl);
    fr.timeout = 30_000;
    this.provider = new ethers.JsonRpcProvider(fr, undefined, {
      // Avoid ethers' batching surprises against a single-threaded dev node.
      batchMaxCount: 1,
    });
    this.manifest = JSON.parse(readFileSync(cfg.deploymentsPath, "utf8"));
    this._abiCache = new Map();
    this._handleCache = new Map(); // `${key}:${runnerTag}` -> Contract
  }

  address(key) {
    const a = this.manifest.contracts?.[key] ?? this.manifest.mocks?.[key];
    if (!a) throw new Error(`connection: no address for key "${key}" in manifest`);
    return ethers.getAddress(a);
  }

  abi(key) {
    if (this._abiCache.has(key)) return this._abiCache.get(key);
    let abi;
    if (key === "GAME") {
      abi = this._mergedGameAbi();
    } else {
      const name = KEY_TO_CONTRACT[key] ?? key; // mock keys are already names
      abi = this._loadAbiByName(name);
    }
    this._abiCache.set(key, abi);
    return abi;
  }

  _loadAbiByName(name) {
    const path = resolve(this.cfg.abisDir, `${name}.json`);
    return JSON.parse(readFileSync(path, "utf8"));
  }

  // Merge the facade ABI with every module ABI, deduped by canonical fragment
  // so the GAME handle can encode any external entrypoint regardless of whether
  // the facade re-declares the module stub.
  _mergedGameAbi() {
    const seen = new Set();
    const merged = [];
    const add = (fragList) => {
      for (const f of fragList) {
        let key;
        try {
          key = ethers.Fragment.from(f).format("sighash");
        } catch {
          key = JSON.stringify(f); // events/errors/constructors — keep, dedupe loosely
        }
        if (seen.has(key)) continue;
        seen.add(key);
        merged.push(f);
      }
    };
    add(this._loadAbiByName(KEY_TO_CONTRACT.GAME)); // DegenerusGame facade first
    for (const mk of GAME_MODULE_KEYS) {
      const name = KEY_TO_CONTRACT[mk];
      try {
        add(this._loadAbiByName(name));
      } catch {
        /* a module ABI may be absent in a partial deploy — skip */
      }
    }
    return merged;
  }

  // A read-only handle (bound to the provider).
  read(key) {
    return this._handle(key, this.provider, "ro");
  }

  // A handle bound to a signer/NonceManager for sending transactions.
  write(key, runner) {
    // Signer-bound handles are not cached (runner identity matters).
    return new ethers.Contract(this.address(key), this.abi(key), runner);
  }

  _handle(key, runner, tag) {
    const ck = `${key}:${tag}`;
    if (this._handleCache.has(ck)) return this._handleCache.get(ck);
    const h = new ethers.Contract(this.address(key), this.abi(key), runner);
    this._handleCache.set(ck, h);
    return h;
  }

  // Convenience accessors for the legs the ledger/oracle read every tick.
  get game() { return this.read("GAME"); }
  get coin() { return this.read("COIN"); }       // FLIP
  get coinflip() { return this.read("COINFLIP"); }
  get sdgnrs() { return this.read("SDGNRS"); }
  get dgnrs() { return this.read("DGNRS"); }
  get vault() { return this.read("VAULT"); }
  get wwxrp() { return this.read("WWXRP"); }
  get jackpots() { return this.read("JACKPOTS"); }
  get affiliate() { return this.read("AFFILIATE"); }

  get stethAddress() { return this.address("STETH_TOKEN"); }

  async chainId() {
    return Number((await this.provider.getNetwork()).chainId);
  }
}
