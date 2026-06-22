// Funded adversary wallet pool (AGT-01 / SOAK-01).
//
// Holds the agent's OWN wallets — it is one (multi-headed) external actor among
// many. Each wallet is wrapped in an ethers NonceManager so sends serialize
// with replace-by-fee, which matters on a live testnet shared with honest 24/7
// traffic. Below a low-water mark a wallet is drip-refilled from a funder.
//
// local mode  : derive wallets from the standard hardhat dev mnemonic (accounts
//               3+, leaving 0/1/2 = deployer/alice/bob the deploy seeded), funded
//               by account 0. These are real signing keys (full Signer control).
// live  mode  : wallets from cfg.wallets.privateKeys (or a supplied mnemonic),
//               refilled by cfg.wallets.funderPrivateKey.

import { ethers } from "ethers";

// The canonical hardhat / anvil dev mnemonic (accounts are public + unlocked).
const HARDHAT_MNEMONIC = "test test test test test test test test test test test junk";
const path = (i) => `m/44'/60'/0'/0/${i}`;

export class WalletPool {
  constructor(conn, cfg) {
    this.conn = conn;
    this.cfg = cfg;
    this.provider = conn.provider;
    this.wallets = []; // [{ address, signer (NonceManager), raw (Wallet) }]
    this.funder = null;
  }

  async init() {
    const w = this.cfg.wallets;
    if (this.cfg.mode === "local") {
      // Account 0 funds; attacker wallets start at index 3.
      this.funder = wrapRaw(ethers.HDNodeWallet.fromPhrase(HARDHAT_MNEMONIC, undefined, path(0)).connect(this.provider));
      for (let i = 0; i < w.count; i++) {
        const raw = ethers.HDNodeWallet.fromPhrase(HARDHAT_MNEMONIC, undefined, path(3 + i)).connect(this.provider);
        this.wallets.push(wrapRaw(raw));
      }
    } else {
      // live: explicit keys (or derive from a supplied mnemonic).
      const keys = w.privateKeys && w.privateKeys.length ? w.privateKeys : null;
      for (let i = 0; i < w.count; i++) {
        const raw = keys
          ? new ethers.Wallet(keys[i % keys.length], this.provider)
          : ethers.HDNodeWallet.fromPhrase(w.mnemonic || HARDHAT_MNEMONIC, undefined, path(i)).connect(this.provider);
        this.wallets.push(wrapRaw(raw));
      }
      if (w.funderPrivateKey) this.funder = wrapRaw(new ethers.Wallet(w.funderPrivateKey, this.provider));
    }
    await this.refillAll();
    return this;
  }

  addresses() { return this.wallets.map((x) => x.address); }
  get(i) { return this.wallets[i % this.wallets.length]; }
  random(rngIndex) { return this.wallets[rngIndex % this.wallets.length]; }

  // Re-sync every NonceManager from chain — called by the tick watchdog after a
  // hung tick so an abandoned in-flight nonce doesn't wedge subsequent sends.
  resetNonces() { for (const w of this.wallets) { try { w.signer.reset(); } catch { /* */ } } }

  async balance(address) { return this.provider.getBalance(address); }

  // Drip-refill any wallet below the low-water mark; returns injected wei per addr.
  async refillAll() {
    const injected = {};
    if (!this.funder) return injected;
    const low = ethers.parseEther(String(this.cfg.wallets.lowWaterEth));
    const target = ethers.parseEther(String(this.cfg.wallets.fundingEth));
    for (const wlt of this.wallets) {
      const bal = await this.provider.getBalance(wlt.address);
      if (bal < low) {
        const top = target - bal;
        try {
          const tx = await this.funder.signer.sendTransaction({ to: wlt.address, value: top });
          await tx.wait();
          injected[wlt.address] = top;
        } catch (e) {
          // funder may be short on a live faucet — record and continue.
          injected[wlt.address] = 0n;
        }
      }
    }
    return injected;
  }
}

function wrapRaw(raw) {
  return { address: raw.address, raw, signer: new ethers.NonceManager(raw) };
}
