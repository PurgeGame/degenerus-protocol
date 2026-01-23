# Using Real Chainlink VRF on Sepolia

This guide explains how to deploy and test with **real Chainlink VRF** on Sepolia testnet instead of the mock VRF coordinator.

## Why Use Real Chainlink VRF?

**Mock VRF (Default):**
- ✅ Instant fulfillment
- ✅ No LINK needed
- ✅ Faster testing
- ❌ Not production-like

**Real Chainlink VRF:**
- ✅ Production-like testing
- ✅ Real Chainlink nodes fulfill requests
- ✅ Tests subscription funding & management
- ❌ Requires real LINK tokens (free from faucet)
- ❌ Slower (30-60 seconds per fulfillment)

Use **real VRF** when you want to test the complete production flow before mainnet.

---

## 📋 Prerequisites

### 1. Get Sepolia LINK Tokens

**Option A: Chainlink Faucet (Recommended)**
1. Visit: https://faucets.chain.link/sepolia
2. Connect your wallet (deployer address)
3. Request 20 LINK tokens (free for testnet)
4. Wait ~30 seconds for tokens to arrive

**Option B: Use Existing LINK**
- If you already have Sepolia LINK, skip this step
- Minimum needed: ~2 LINK for testing (each VRF request costs ~0.25 LINK)

**Verify LINK Balance:**
```bash
# Check on Sepolia Etherscan
https://sepolia.etherscan.io/address/YOUR_DEPLOYER_ADDRESS
```

### 2. Ensure You Have Sepolia ETH

You'll need:
- **Deployer:** 0.5 Sepolia ETH (for deployment + gas)
- **Players:** 0.05 Sepolia ETH each

Get from: https://sepoliafaucet.com/

---

## 🚀 Deployment with Real Chainlink VRF

### Deploy Command

```bash
# Deploy with real Chainlink VRF
npx hardhat run scripts/deploy/deploy-sepolia-testnet.js --network sepolia --realvrf
```

### What Happens

```
╔════════════════════════════════════════════════════════════════╗
║  SEPOLIA TESTNET DEPLOYMENT (COSTS ÷ 1,000,000)               ║
╚════════════════════════════════════════════════════════════════╝

Loaded deployer from wallets.json: 0xceE410a785AA2D4a78130FB9bF519408c115C21b

=== STEP 1: DEPLOYING/CONFIGURING DEPENDENCIES ===

Mode: REAL Chainlink VRF
Tokens: Mock tokens

MockStETH deployed at 0x...
Using real Sepolia LINK at 0x779877A7B0D9E8603169DdbD7836e478b4624789
Using real Chainlink VRF Coordinator at 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B
⚠️  NOTE: You will need to fund the subscription with real LINK!

=== STEP 2: PRECOMPUTING ADDRESSES ===
...

=== STEP 3: DEPLOYING CONTRACTS ===
...

=== STEP 4: SETTING UP VRF SUBSCRIPTION ===

Creating VRF subscription on real Chainlink coordinator...
VRF Subscription created: 12345678...
Game added as VRF consumer

⚠️  IMPORTANT: Fund your subscription with LINK!
   Visit: https://vrf.chain.link/sepolia/12345678...
   Or use LINK faucet: https://faucets.chain.link/sepolia
   Minimum: 2 LINK recommended for testing

╔════════════════════════════════════════════════════════════════╗
║  DEPLOYMENT COMPLETE!                                          ║
╚════════════════════════════════════════════════════════════════╝
```

### Key Outputs

1. **VRF Subscription ID:** Saved to `deployment-sepolia.json`
2. **Subscription URL:** Link to fund your subscription
3. **All Contract Addresses:** Available in `deployment-sepolia.json`

---

## 💰 Funding Your Subscription

### Method 1: Via Chainlink Website (Easiest)

1. **Open the Subscription Page:**
   ```
   https://vrf.chain.link/sepolia/YOUR_SUBSCRIPTION_ID
   ```
   (The deploy script prints this URL)

2. **Connect Your Wallet:**
   - Click "Connect Wallet"
   - Select the deployer wallet from `wallets.json`

3. **Add Funds:**
   - Click "Add Funds"
   - Enter amount: **5 LINK** (recommended for testing)
   - Confirm transaction
   - Wait ~30 seconds for confirmation

4. **Verify:**
   - Balance should show "5 LINK"
   - Consumer should show your Game contract address

### Method 2: Via Hardhat Console

```bash
npx hardhat console --network sepolia
```

```javascript
// Load deployment info
const deployment = require('./deployment-sepolia.json');
const wallets = require('./wallets.json');

// Connect to LINK token
const linkToken = await ethers.getContractAt(
  "contracts/test/MockLink.sol:MockLink",
  deployment.contracts.LINK_TOKEN
);

// Connect to VRF coordinator
const vrfCoordinator = await ethers.getContractAt(
  [
    "function fundSubscription(uint256 subId, uint96 amount) external"
  ],
  deployment.contracts.VRF_COORDINATOR
);

// Get deployer wallet
const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

// Fund subscription with 5 LINK
const linkAmount = ethers.parseEther("5");
const subId = deployment.vrfSubscriptionId;

// Approve LINK spend
await linkToken.connect(deployer).approve(
  deployment.contracts.VRF_COORDINATOR,
  linkAmount
);

// Fund subscription
await vrfCoordinator.connect(deployer).fundSubscription(subId, linkAmount);

console.log(`Subscription ${subId} funded with 5 LINK`);
```

### Method 3: Direct LINK Transfer (Advanced)

```javascript
// In hardhat console
const subId = deployment.vrfSubscriptionId;
const linkAmount = ethers.parseEther("5");

// Transfer and fund in one transaction
await linkToken.connect(deployer).transferAndCall(
  deployment.contracts.VRF_COORDINATOR,
  linkAmount,
  ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [subId])
);
```

---

## 🎮 Running Simulation with Real VRF

### Start Simulation

```bash
# With simulated day advancement (recommended)
SIMULATE_DAYS=true TARGET_LEVEL=10 PLAYER_COUNT=10 \
  npx hardhat run scripts/test/sepolia-simulation.js --network sepolia

# Without simulated days (slower, more realistic)
TARGET_LEVEL=10 PLAYER_COUNT=10 \
  npx hardhat run scripts/test/sepolia-simulation.js --network sepolia
```

### What's Different with Real VRF

**Output:**
```
⚠️  REAL CHAINLINK VRF MODE
   VRF requests will be fulfilled by Chainlink nodes
   Make sure your subscription is funded with LINK!
   Visit: https://vrf.chain.link/sepolia/12345678...

╔════════════════════════════════════════════════════════════════╗
║  STARTING CONTINUOUS SIMULATION                                ║
╚════════════════════════════════════════════════════════════════╝
```

**VRF Fulfillment:**
- **Mock VRF:** Instant (< 1 second)
- **Real VRF:** 30-60 seconds per request

**During Jackpot Phase:**
```
🔥 BURN PHASE: Players burning gamepieces...
  ✓ Burned 450 total gamepieces
  📅 Advancing dailyIdx by 1 day(s)...
  ⏩ Advancing game...
  Using real Chainlink VRF - waiting for automatic fulfillment...
  ⏩ advanceGame succeeded

  ⏳ Waiting for VRF fulfillment... (this may take 30-60 seconds)
```

---

## 📊 Monitoring VRF Requests

### Via Chainlink Website

1. **Open Subscription Page:**
   ```
   https://vrf.chain.link/sepolia/YOUR_SUBSCRIPTION_ID
   ```

2. **View Request History:**
   - Click "Request History" tab
   - See all VRF requests
   - Status: Pending → Fulfilled
   - Transaction hashes for fulfillments

3. **Monitor Balance:**
   - Each request costs ~0.25 LINK
   - Refill when balance gets low (< 1 LINK)

### Via Sepolia Etherscan

1. **View Game Contract:**
   ```
   https://sepolia.etherscan.io/address/YOUR_GAME_ADDRESS
   ```

2. **Filter Events:**
   - Look for `RandomWordsRequested` events (VRF requested)
   - Look for transactions from VRF coordinator (VRF fulfilled)

### Via Hardhat Console

```javascript
// Check last RNG word
const game = await ethers.getContractAt("DegenerusGame", deployment.contracts.GAME);
const lastRng = await game.lastRngWord();
console.log("Last RNG word:", lastRng);

// Check if RNG is locked (waiting for VRF)
const isLocked = await game.rngLocked();
console.log("RNG locked:", isLocked); // true = waiting for VRF

// Check request ID
const requestId = await game.s_requestId();
console.log("Current request ID:", requestId);
```

---

## 🔧 Troubleshooting

### "Subscription not funded"

**Problem:** VRF requests fail because subscription has no LINK

**Solution:**
1. Check subscription balance: https://vrf.chain.link/sepolia/YOUR_SUB_ID
2. Fund with at least 2 LINK (see "Funding Your Subscription" above)
3. Retry the simulation

### "VRF request taking too long"

**Problem:** VRF fulfillment is slow (> 2 minutes)

**Possible Causes:**
- Sepolia network congestion
- Chainlink node backlog
- Low gas price on request

**Solution:**
1. Wait patiently (up to 5 minutes is normal)
2. Check request on Chainlink website
3. If stuck > 10 minutes, may need to retry level
4. Consider using mock VRF for faster testing

### "Insufficient LINK balance"

**Problem:** Ran out of LINK during simulation

**Solution:**
1. Pause simulation (Ctrl+C)
2. Fund subscription with more LINK
3. Resume simulation
4. Simulation will pick up where it left off

### "Consumer not authorized"

**Problem:** Game contract not added as consumer

**Solution:**
```javascript
// In hardhat console
const vrfCoordinator = await ethers.getContractAt(
  ["function addConsumer(uint256 subId, address consumer) external"],
  deployment.contracts.VRF_COORDINATOR
);

await vrfCoordinator.connect(deployer).addConsumer(
  deployment.vrfSubscriptionId,
  deployment.contracts.GAME
);
```

---

## 💡 Best Practices

### When to Use Real VRF

✅ **Use Real VRF When:**
- Testing complete production flow
- Validating subscription management
- Testing VRF request/fulfillment cycle
- Final pre-mainnet validation
- Demonstrating to stakeholders

❌ **Use Mock VRF When:**
- Rapid iteration & development
- Testing game logic (not VRF)
- Multi-level simulations (> 10 levels)
- Time-constrained testing

### LINK Budget Planning

**Per-Level Costs:**
- Purchase phase: 0 LINK
- Burn phase: ~0.25 LINK (one VRF request)
- Jackpot resolution: ~0.25 LINK (one VRF request)

**Total for 10 Levels:**
- ~5 LINK (2 requests per level × 10 levels × 0.25 LINK)

**Recommended Budget:**
- **Short test (1-5 levels):** 2 LINK
- **Medium test (5-10 levels):** 5 LINK
- **Long test (10-20 levels):** 10 LINK

### Optimizing for Cost

1. **Batch Testing:**
   - Test game logic with mock VRF first
   - Use real VRF only for final validation

2. **Target Specific Levels:**
   - Test critical levels (1, 10, 20) with real VRF
   - Use mock VRF for intermediate levels

3. **Monitor Balance:**
   - Check subscription balance regularly
   - Refill before it runs out

---

## 📝 Comparison: Mock vs Real VRF

| Feature | Mock VRF | Real Chainlink VRF |
|---------|----------|-------------------|
| **Speed** | Instant | 30-60 seconds |
| **Cost** | Free | ~0.25 LINK per request |
| **Setup** | Automatic | Manual funding required |
| **Production-like** | No | Yes |
| **Best for** | Development | Final testing |
| **LINK needed** | None | 2+ LINK |
| **Faucet needed** | No | Yes (free) |

---

## 🚀 Quick Reference

### Deploy with Real VRF
```bash
npx hardhat run scripts/deploy/deploy-sepolia-testnet.js --network sepolia --realvrf
```

### Fund Subscription (Website)
```
https://vrf.chain.link/sepolia/YOUR_SUBSCRIPTION_ID
```

### Run Simulation
```bash
SIMULATE_DAYS=true TARGET_LEVEL=10 \
  npx hardhat run scripts/test/sepolia-simulation.js --network sepolia
```

### Get LINK Tokens
```
https://faucets.chain.link/sepolia
```

### Monitor Subscription
```
https://vrf.chain.link/sepolia/YOUR_SUBSCRIPTION_ID
```

---

## ✅ Production Checklist

Before mainnet deployment:

- [ ] Successfully deployed with real Chainlink VRF on Sepolia
- [ ] Funded subscription and completed full simulation
- [ ] Monitored VRF requests and fulfillments
- [ ] Verified LINK costs align with budget
- [ ] Tested subscription refilling
- [ ] Validated jackpot randomness distribution
- [ ] Confirmed no VRF-related errors in logs
- [ ] Documented subscription ID and management process

---

## 🎯 Example: Complete Real VRF Test

```bash
# 1. Deploy with real VRF
npx hardhat run scripts/deploy/deploy-sepolia-testnet.js --network sepolia --realvrf

# 2. Note subscription ID from output
# Example: VRF Subscription created: 123456789...

# 3. Fund subscription (5 LINK)
# Visit: https://vrf.chain.link/sepolia/123456789...
# Connect wallet, add 5 LINK

# 4. Run simulation to level 5
SIMULATE_DAYS=true TARGET_LEVEL=5 PLAYER_COUNT=10 \
  npx hardhat run scripts/test/sepolia-simulation.js --network sepolia

# 5. Monitor progress
# - Console logs show VRF fulfillments
# - Check subscription balance periodically
# - View requests on Chainlink website

# 6. Verify success
# - All levels completed
# - No VRF errors
# - Subscription balance decreased appropriately
```

**Expected Duration:** ~15-30 minutes for 5 levels with real VRF

---

## 💬 Support

**Issues with Real VRF?**
- Check Chainlink VRF docs: https://docs.chain.link/vrf/v2-5/subscription
- View your subscription: https://vrf.chain.link/sepolia
- Verify LINK balance on Etherscan
- Check simulation logs for specific errors

**Still stuck?**
- Review troubleshooting section above
- Check Sepolia network status
- Try mock VRF first to isolate issues

---

**Ready to test with production-like randomness!** 🎲
