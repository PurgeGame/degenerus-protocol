.PHONY: test test-foundry test-hardhat invariant-test invariant-build invariant-clean

# ── Unified test targets ────────────────────────────────────────────────
# Patches ContractAddresses.sol with Foundry-predicted addresses before
# compilation, then restores the user's version after tests complete.
# User's local ContractAddresses.sol is never lost.

# Run all Foundry fuzz tests (patch → test → restore)
# forge test handles its own compilation with the patched addresses in place.
test-foundry:
	@echo "Patching ContractAddresses.sol for Foundry..."
	@node scripts/lib/patchForFoundry.js
	@echo "Running Foundry tests..."
	@FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge test $(ARGS) 2>&1; TEST_EXIT=$$?; \
		echo "Restoring ContractAddresses.sol..."; \
		node -e "import('./scripts/lib/patchContractAddresses.js').then(m => m.restoreContractAddresses())"; \
		exit $$TEST_EXIT

# Run Hardhat tests (no patching needed — Hardhat deploys fresh)
test-hardhat:
	@npx hardhat test $(ARGS)

# Run both suites
test: test-foundry test-hardhat

# ── Legacy aliases ──────────────────────────────────────────────────────

invariant-test: test-foundry

invariant-build:
	@node scripts/lib/patchForFoundry.js
	@FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge build --force
	@node -e "import('./scripts/lib/patchContractAddresses.js').then(m => m.restoreContractAddresses())"

invariant-clean:
	@rm -rf forge-out cache
