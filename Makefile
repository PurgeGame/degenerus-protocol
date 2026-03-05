.PHONY: invariant-test invariant-build invariant-clean

# Full cycle: patch -> build -> test -> restore (always restores, even on failure)
invariant-test:
	@echo "Patching ContractAddresses.sol for Foundry..."
	@node scripts/lib/patchForFoundry.js
	@echo "Building with forge..."
	@forge build --force 2>&1 || { node -e "import('./scripts/lib/patchContractAddresses.js').then(m => m.restoreContractAddresses())"; exit 1; }
	@echo "Running Foundry tests..."
	@forge test --match-path "test/fuzz/**" -vvv 2>&1; TEST_EXIT=$$?; \
		echo "Restoring ContractAddresses.sol..."; \
		node -e "import('./scripts/lib/patchContractAddresses.js').then(m => m.restoreContractAddresses())"; \
		exit $$TEST_EXIT

# Just build (for development iteration)
invariant-build:
	@node scripts/lib/patchForFoundry.js
	@forge build --force
	@node -e "import('./scripts/lib/patchContractAddresses.js').then(m => m.restoreContractAddresses())"

# Clean forge artifacts
invariant-clean:
	@rm -rf forge-out cache
