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

  // Best-effort pending-tx subscription (requires a node with txpool/pending
  // filter support; harmless no-op otherwise).
  async start(onTarget) {
    try {
      this.provider.on("pending", async (txHash) => {
        try {
          const tx = await this.provider.getTransaction(txHash);
          if (!tx || (tx.to || "").toLowerCase() !== this.gameAddr) return;
          const sel = (tx.data || "0x").slice(0, 10);
          const name = this._interesting(sel);
          if (!name) return;
          const target = { txHash, from: tx.from, selector: sel, name, value: tx.value, gasPrice: tx.gasPrice };
          this.targets.push(target);
          if (this.targets.length > 256) this.targets.shift();
          onTarget?.(target);
        } catch { /* tx vanished from pool */ }
      });
      this._sub = true;
    } catch {
      this._sub = false; // node without pending-subscription support
    }
    return this._sub;
  }

  stop() { if (this._sub) this.provider.removeAllListeners("pending"); }
}
