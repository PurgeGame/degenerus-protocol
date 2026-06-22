// Live mempool / event watcher (SOAK-02) — multi-actor interaction probes that
// only exist with honest 24/7 traffic. Watches pending txs to the GAME facade to
// spot honest actors' transactions worth racing (front-run / sandwich), and
// shared windows (redemption / advanceGame / jackpot) worth contesting.
//
// Detection-only here; the agent decides whether to act. On a local stand-in the
// mempool is shallow, so this is exercised mainly in live/soak mode.

import { ethers } from "ethers";

export class MempoolWatcher {
  constructor(conn) {
    this.conn = conn;
    this.provider = conn.provider;
    this.gameAddr = conn.address("GAME").toLowerCase();
    this.iface = new ethers.Interface(conn.abi("GAME"));
    this.targets = []; // recent honest tx targets worth contesting
    this._sub = false;
  }

  // Selectors worth racing — shared windows + value-moving honest actions.
  _interesting(selector) {
    const names = ["advanceGame", "purchase", "resolveDegeneretteBets", "claimWinnings",
      "openBoxes", "claimRedemption", "claimFoilMatchMany", "claimDecimatorJackpotMany"];
    for (const n of names) {
      try { if (this.iface.getFunction(n).selector === selector) return n; } catch { /* */ }
    }
    return null;
  }

  // Reliable target detection via BLOCK polling. Over HTTP, ethers implements
  // provider.on("pending") with an eth_newPendingTransactionFilter that hosted
  // RPCs (Alchemy/Infura) garbage-collect — its later eth_getFilterChanges then
  // throws "filter not found" (-32000) from inside ethers' own polling loop,
  // OUTSIDE any callback try/catch, crashing a 24/7 soak. Block polling
  // (eth_blockNumber + eth_getBlockByNumber) uses no expiring filters and is
  // supported everywhere; one block of latency vs mempool-level is adequate for
  // the shared-window contest probes on a 12s-block testnet (true public-mempool
  // front-running via a hosted RPC is not reliably available anyway).
  async start(onTarget) {
    this._busy = false;
    this._onBlock = async (bn) => {
      // One heavy full-block fetch at a time: if the previous getBlock is still
      // in flight (a slow/large Sepolia block via a hosted RPC), drop this block
      // rather than letting concurrent full-block reads pile up and saturate the
      // shared single-threaded provider the tick loop also uses.
      if (this._busy) return;
      this._busy = true;
      try {
        const block = await this.provider.getBlock(bn, true); // prefetch full txs
        if (!block) return;
        for (const tx of block.prefetchedTransactions ?? []) {
          if ((tx.to || "").toLowerCase() !== this.gameAddr) continue;
          const sel = (tx.data || "0x").slice(0, 10);
          const name = this._interesting(sel);
          if (!name) continue;
          const target = { txHash: tx.hash, from: tx.from, selector: sel, name, value: tx.value, gasPrice: tx.gasPrice ?? null };
          this.targets.push(target);
          if (this.targets.length > 256) this.targets.shift();
          onTarget?.(target);
        }
      } catch { /* transient RPC hiccup — skip this block, keep watching */ }
      finally { this._busy = false; }
    };
    try {
      this.provider.on("block", this._onBlock);
      this._sub = true;
    } catch {
      this._sub = false;
    }
    return this._sub;
  }

  stop() { if (this._sub && this._onBlock) this.provider.off("block", this._onBlock); }
}
