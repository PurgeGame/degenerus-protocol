.PHONY: test test-foundry test-hardhat check-interfaces check-delegatecall check-raw-selectors check-rng-window check-pool-writes coverage-check invariant-test invariant-build invariant-clean

# ── Interface coverage gate ─────────────────────────────────────────────
# Verifies every function declared in contracts/interfaces/ has a matching
# implementation (by 4-byte selector) on the target contract. Catches the
# class of bug where an interface function is declared but never implemented,
# causing silent staticcall reverts at the call site (see prior mintPackedFor
# incident). Builds contracts first so forge inspect has fresh ABI data.
check-interfaces:
	@FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge build --skip test >/dev/null
	@scripts/check-interface-coverage.sh

# ── Delegatecall alignment gate ─────────────────────────────────────────
# Verifies every interface-bound abi.encodeWithSelector(IFACE.fn.selector, ...)
# delegatecall site in contracts/ targets the address constant that matches
# the interface per the D-03 naming convention. Catches the class of bug
# where a call compiles (selector exists on SOME module) but targets the
# wrong module's address, reverting at runtime on selector mismatch.
# Operates on source text — no forge build prerequisite.
check-delegatecall:
	@scripts/check-delegatecall-alignment.sh

# ── Raw selector & hand-rolled calldata gate ────────────────────────────
# Forbids raw selector literals (`bytes4(0x...)`, `bytes4(keccak256("..."))`)
# and hand-rolled calldata encoders (`abi.encodeWithSignature`, `abi.encodeCall`,
# or `abi.encode*` feeding `.call` / `.delegatecall` / `.staticcall` /
# `transferAndCall`) in production contracts/. Mocks under contracts/mocks/
# are path-excluded — they mimic external Chainlink wire format and are
# intentionally raw. Operates on source text — no forge build prerequisite.
check-raw-selectors:
	@scripts/check-raw-selectors.sh

# ── RNG-window consumer drift gate ──────────────────────────────────────
# Mechanizes the v45 freeze north-star: every read/write of a VRF-word storage
# variable (rngWordCurrent / rngWordByDay / lootboxRngWordByIndex / the
# lootboxRngPacked cursor) must be registered + classified in
# scripts/rng-window-manifest.tsv, and the runtime freeze net
# (RngWindowFreezeHandler) must enumerate the manifest's FROZEN_SET. A new/moved
# consumer that is not classified fails the build, forcing the backward-trace
# review the hand-enumerated runtime net would otherwise silently miss. Operates
# on source text — no forge build prerequisite.
check-rng-window:
	@scripts/check-rng-window.sh

# ── SOLV pool-write drift gate ──────────────────────────────────────────
# Every mutation of a counted ETH-obligation term (and every canonical
# mutator call) must be classified in scripts/pool-write-manifest.tsv.
# Keeps audit/ETH-SUBPOOL-PROVENANCE-PROOF.md true against source drift.
check-pool-writes:
	@scripts/check-pool-writes.sh

# ── External-function coverage classification gate (standalone) ─────────
# Enforces 222-01-COVERAGE-MATRIX.md: every external/public function on
# every deployable source artifact is classified (no universe drift),
# every CRITICAL_GAP has a linked Test Ref (no uncured gaps), and every
# COVERED row still meets the 50% file-level branch-coverage threshold
# in the cached lcov.info (no regressions). STANDALONE target — NOT a
# prerequisite of test-foundry / test-hardhat because forge coverage is
# minutes-long (D-16). Caller runs `forge coverage --report lcov --ir-minimum`
# first to produce lcov.info; then this target consumes the cached lcov
# plus the matrix and reports drift / gaps / regressions in seconds.
coverage-check:
	@scripts/coverage-check.sh

# ── Unified test targets ────────────────────────────────────────────────
# Patches ContractAddresses.sol with Foundry-predicted addresses before
# compilation, then restores the user's version after tests complete.
# User's local ContractAddresses.sol is never lost.

# Run all Foundry fuzz tests (patch → test → restore)
# forge test handles its own compilation with the patched addresses in place.
test-foundry: check-interfaces check-delegatecall check-raw-selectors check-rng-window check-pool-writes
	@echo "Patching ContractAddresses.sol for Foundry..."
	@node scripts/lib/patchForFoundry.js
	@echo "Running Foundry tests..."
	@FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge test $(ARGS) 2>&1; TEST_EXIT=$$?; \
		echo "Restoring ContractAddresses.sol..."; \
		git checkout -- contracts/ContractAddresses.sol; \
		exit $$TEST_EXIT

# Run Hardhat tests (no patching needed — Hardhat deploys fresh)
test-hardhat: check-interfaces check-delegatecall check-raw-selectors check-rng-window check-pool-writes
	@npx hardhat test $(ARGS)

# Run both suites
test: test-foundry test-hardhat

# ── Legacy aliases ──────────────────────────────────────────────────────

invariant-test: test-foundry

invariant-build:
	@node scripts/lib/patchForFoundry.js
	@FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge build --force
	@git checkout -- contracts/ContractAddresses.sol

invariant-clean:
	@rm -rf forge-out cache
