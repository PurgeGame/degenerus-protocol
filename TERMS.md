# Terms of Interaction

These terms govern every contract in this repository's `contracts/` tree. The same text
appears as a header comment at the top of each source file. Submitting a transaction to any
of these contracts accepts them.

---

**THIS IS GAMBLING.** Outcomes are decided by chance. You can lose everything you put in
simply by being unlucky. That is the software working exactly as intended, not a malfunction
and not a defect. Do not commit funds you are not prepared to lose entirely.

**The deployed bytecode is the entire agreement.** It controls over every comment, name,
document and statement made about it — including this one. Where any description of the
protocol disagrees with what the deployed code does, the code is what governs. It has been
audited but is not proven correct: it may contain defects the author did not find, and by
interacting with it you accept that risk in full.

**Any state transition the code permits is authorised.** That includes a transaction which
exploits a defect, and it includes sequences the author did not intend or foresee. A bug is
not a breach of these terms. There is no unwritten rule behind the code for a permitted
transaction to violate, and there is no unauthorised access to these contracts.

**You bear all resulting loss**, whether it follows from chance or from a defect. There is no
refund, no rollback, and no privileged party able to restore a position.

Provided **AS IS**, without warranty of any kind, to the fullest extent permitted by law. See
also AGPL-3.0 §§15–17.

---

## What these terms do not do

They do not retract anything the protocol asserts about itself. The invariants published in
`README.md` and the dispositions in `KNOWN-ISSUES.md` are claims about how the code is
intended to behave, and they stand. "Any permitted transition is authorised" allocates the
risk that remains after auditing — it is not an assertion that the protocol has no bugs, nor a
withdrawal of the properties it claims to hold.

Nor do they narrow the scope of a security review. A finding is eligible under the rules in
`KNOWN-ISSUES.md`; these terms describe the position of a participant transacting with the
deployed contracts, not that of someone reviewing them.
