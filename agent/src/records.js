// Structured, replayable finding recorder (AGT-04/AGT-06).
//
// A flagged violation is captured as a self-contained, replayable record: the
// exact tx sequence that produced it (to/from/selector/args/value/hash/block),
// the pre/post per-actor ledger, the invariant that broke (or the profit-gate
// verdict), and the by-design adjudication. Because every agent action is logged
// as a structured step, a flagged violation is already a reproducible sequence —
// no separate repro step is needed.

import { writeFileSync, mkdirSync, appendFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

const big = (_k, v) => (typeof v === "bigint" ? v.toString() : v);

export class Recorder {
  constructor(dir) {
    this.dir = dir;
    mkdirSync(dir, { recursive: true });
    this.indexPath = resolve(dir, "INDEX.jsonl");
    this.seq = 0;
  }

  // finding: {
  //   kind: "invariant" | "profit" | "brick" | "info",
  //   id, severity, identity, observed, expected, source,
  //   actor, block, txSequence:[...], preLedger, postLedger,
  //   allowlist: null | {id,name,...}, gas: {...}, disposition: "FIX"|"DOCUMENT"|"INFO"
  // }
  record(finding) {
    this.seq += 1;
    const stampMs = nowMs();
    const id = `${String(this.seq).padStart(4, "0")}-${finding.kind}-${(finding.id || "anon").replace(/[^A-Za-z0-9_-]/g, "_")}`;
    const rec = {
      recordId: id,
      capturedAtMs: stampMs,
      kind: finding.kind,
      invariant: finding.id || null,
      severity: finding.severity || "info",
      identity: finding.identity || null,
      observed: finding.observed ?? null,
      expected: finding.expected ?? null,
      source: finding.source || null,
      actor: finding.actor || null,
      block: finding.block ?? null,
      disposition: finding.disposition || "REVIEW",
      allowlist: finding.allowlist || null,
      gas: finding.gas || null,
      replay: {
        rpc: finding.rpc || null,
        txSequence: finding.txSequence || [],
      },
      ledger: { pre: finding.preLedger || null, post: finding.postLedger || null },
      extra: finding.extra || null,
    };
    const path = resolve(this.dir, `${id}.json`);
    writeFileSync(path, JSON.stringify(rec, big, 2));
    appendFileSync(
      this.indexPath,
      JSON.stringify({ recordId: id, kind: rec.kind, severity: rec.severity, invariant: rec.invariant, actor: rec.actor, block: rec.block, capturedAtMs: stampMs }, big) + "\n"
    );
    return path;
  }

  count() {
    if (!existsSync(this.indexPath)) return 0;
    return this.seq;
  }
}

function nowMs() {
  // Plain node runtime (not a Workflow script) — Date is available.
  return Date.now();
}
