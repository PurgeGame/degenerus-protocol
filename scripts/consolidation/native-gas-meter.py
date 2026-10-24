"""Native Amsterdam gas dimensions from Geth's opcode tracer, before refunds.

The block header reports max(execution, state), not execution alone. Runtime
execution gas is read directly from the root frame. The intrinsic charge is
inferred from the initial budget, so EIP-2780 pricing is preserved.
"""
METER = r"""{
 first: null, last: null, refund: 0,
 step: function(log, db) {
   this.refund = log.getRefund();
   if (log.getDepth() == 1) {
     if (this.first === null) this.first = log.getGas();
     this.last = {gas: log.getGas(), cost: log.getCost(), op: log.op.toNumber()};
   }
 },
 fault: function(log, db) {},
 result: function(ctx, db) {
   return {first: this.first, last: this.last, refund: this.refund,
           receiptGas: ctx.gasUsed, error: ctx.error || null};
 }
}"""


def measured_gas(meter, transaction_gas_limit):
    assert not meter["error"] and meter["last"]["op"] in (0, 0xF3), "successful root must stop or return"
    # Read the actual intrinsic charge from the client's initial runtime budget.
    # Amsterdam EIP-2780 no longer uses the legacy 21,000 base.
    intrinsic = min(transaction_gas_limit, 16_777_216) - meter["first"]
    # Let g be gross gas and r the uncapped refund. receipt = g-min(r,floor(g/5)).
    # Therefore receipt + min(r,ceil(receipt/4)) is an upper bound on g (at most 1 high).
    receipt = meter["receiptGas"]
    gross_upper = receipt + min(meter["refund"], (receipt + 3) // 4)
    frame_execution = meter["first"] - meter["last"]["gas"] + meter["last"]["cost"]
    return {"receiptGas": receipt, "grossGasUpperBound": gross_upper,
            "grossFrameUpperBound": gross_upper - intrinsic,
            "frameExecutionBudgetConsumed": frame_execution, "intrinsicGas": intrinsic}
