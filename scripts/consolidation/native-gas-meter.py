"""Native Amsterdam gas dimensions from Geth's opcode tracer, before refunds.

The block header reports max(execution, state), not execution alone. Runtime
execution gas is read directly from the root frame. The intrinsic charge is
inferred from the initial budget, so EIP-2780 pricing is preserved.
"""
METER = r"""{
 first: null, last: null, refund: 0, stack: [], frames: [],
 enter: function(frame) {
   this.stack.push({to: toHex(frame.getTo()), input: toHex(frame.getInput()),
     type: frame.getType(), depth: this.stack.length + 1, first: null, last: null});
 },
 exit: function(result) {
   var frame = this.stack.pop();
   frame.error = result.getError() || null;
   if (frame.first !== null && frame.last !== null)
     frame.executionBudgetConsumed = frame.first - frame.last.gas + frame.last.cost;
   this.frames.push(frame);
 },
 step: function(log, db) {
   if (this.stack.length === 0) this.stack.push({depth: 1, first: null, last: null});
   var frame = this.stack[this.stack.length - 1];
   if (frame.first === null) frame.first = log.getGas();
   frame.last = {gas: log.getGas(), cost: log.getCost(), op: log.op.toNumber()};
   this.refund = log.getRefund();
   if (log.getDepth() == 1) {
     if (this.first === null) this.first = log.getGas();
     this.last = {gas: log.getGas(), cost: log.getCost(), op: log.op.toNumber()};
   }
 },
 fault: function(log, db) {},
 result: function(ctx, db) {
   return {first: this.first, last: this.last, refund: this.refund,
           receiptGas: ctx.gasUsed, error: ctx.error || null, frames: this.frames};
 }
}"""


def measured_gas(meter, transaction_gas_limit, *, schedule="amsterdam"):
    assert not meter["error"] and meter["last"]["op"] in (0, 0xF3), "successful root must stop or return"
    # Read the actual intrinsic charge from the client's initial runtime budget.
    # Amsterdam EIP-2780 no longer uses the legacy 21,000 base.
    assert schedule in ("osaka", "amsterdam"), schedule
    execution_limit = min(transaction_gas_limit, 16_777_216) if schedule == "amsterdam" else transaction_gas_limit
    intrinsic = execution_limit - meter["first"]
    assert intrinsic >= 0, "wrong native gas schedule or transaction limit"
    # Let g be gross gas and r the uncapped refund. receipt = g-min(r,floor(g/5)).
    # Therefore receipt + min(r,ceil(receipt/4)) is an upper bound on g (at most 1 high).
    receipt = meter["receiptGas"]
    gross_upper = receipt + min(meter["refund"], (receipt + 3) // 4)
    frame_execution = meter["first"] - meter["last"]["gas"] + meter["last"]["cost"]
    return {"receiptGas": receipt, "grossGasUpperBound": gross_upper,
            "grossFrameUpperBound": gross_upper - intrinsic,
            "frameExecutionBudgetConsumed": frame_execution, "intrinsicGas": intrinsic,
            "frames": meter.get("frames", [])}
