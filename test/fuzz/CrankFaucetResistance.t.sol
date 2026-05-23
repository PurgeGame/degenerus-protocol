// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title CrankFaucetResistance -- Proves SAFE-01: the permissionless do-work crank
///        (crankBets / crankBoxes) is faucet-bounded by three caller-independent locks:
///        (1) the purchase-gate (an item must already be a real, purchased, RNG-ready bet/box),
///        (2) the FIXED gas-peg reward (CRANK_*_GAS_UNITS * 0.5 gwei, never measured gas), and
///        (3) the coinflip-credit illiquidity (creditFlip = pending stake, not liquid BURNIE).
///
/// @notice A self-crank / Sybil round-trip is net-zero-or-negative because the BURNIE coinflip
///         credit a cranker earns for resolving their own item is valued, at the protocol's own
///         reference peg, at exactly CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF (0.5 gwei)
///         of ETH — strictly below the real gas the crank transaction costs at any realistic gas
///         price (> 0.5 gwei) over a gasUsed that exceeds the reserved gasUnits. The reward never
///         reads gasleft()/tx.gasprice (REW-03), so it cannot scale up to chase a higher
///         submission price. The credit lands as illiquid coinflip stake (not liquid BURNIE), so
///         it cannot be immediately round-tripped to a profit.
///
///         Also asserts CRANK-04 (WWXRP currency==3 earns exactly zero reward), REW-02 (exactly
///         ONE crank-reward creditFlip per crank tx with the summed amount, never per-item), the
///         one-reward-per-item lock (re-crank of a resolved bet reverts BatchAlreadyTaken at item
///         0; a duplicate in one batch rewards once), and the pre-RNG-word resolution block (a
///         crank whose RNG word has not landed skips the item via the preserved RngNotReady guard,
///         no reward).
///
/// @dev Builds on the 318-01-repaired DeployProtocol fixture (AfKing live at AF_KING). Drives a
///      REAL degenerette bet through the public placeDegeneretteBet API (mirroring the proven
///      DegeneretteFreezeResolution pattern: seed lootboxRngIndex=1, place with word==0, then
///      inject the RNG word and crank). The bet outcome is controlled deterministically against
///      the REAL resolve derivation (packedTraitsDegenerette over keccak(word,index,salt)):
///        - LOSING bets (matches == 0) resolve fully but pay zero winnings, so the ONLY creditFlip
///          in the crank tx is the crank reward itself — isolating the reward for exact counting
///          and peg-equality assertions (a WINNING bet's BURNIE-winnings creditFlip would
///          otherwise be conflated with the reward creditFlip).
///        - One WINNING bet test proves the full resolve path runs end-to-end.
///      The bet owner approves the game as operator so the crank's delegatecall-sender
///      (address(game)) clears _requireApproved. Test-only: no contracts/*.sol mutated.
contract CrankFaucetResistance is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage slot constants (confirmed via `forge inspect ... storage`)
    // -------------------------------------------------------------------------

    /// @dev lootboxRngPacked at slot 35; lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 35;

    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 36;

    /// @dev degeneretteBets mapping root slot (address => betId => packed).
    uint256 private constant DEGENERETTE_BETS_SLOT = 43;

    /// @dev degeneretteBetNonce mapping root slot (address => uint64).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 44;

    /// @dev WWXRP balanceOf mapping root slot.
    uint256 private constant WWXRP_BALANCEOF_SLOT = 2;

    /// @dev WWXRP totalSupply slot.
    uint256 private constant WWXRP_TOTAL_SUPPLY_SLOT = 0;

    // -------------------------------------------------------------------------
    // Crank reward peg mirror (the contract's own FIXED constants, REW-03)
    // -------------------------------------------------------------------------

    /// @dev Reference gas price for the reward peg (DegenerusGame.sol:1495).
    uint256 private constant CRANK_GAS_PRICE_REF = 0.5 gwei;

    /// @dev Reserved per-work-type gas-unit constants (DegenerusGame.sol:1501-1502).
    uint256 private constant CRANK_RESOLVE_BET_GAS_UNITS = 120_000;
    uint256 private constant CRANK_OPEN_BOX_GAS_UNITS = 120_000;

    /// @dev BURNIE per-ETH conversion unit (DegenerusGameStorage:161 / Coinflip:132).
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    /// @dev keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)") — the event
    ///      _addDailyFlip emits once per creditFlip; used to count creditFlip emissions.
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");

    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q' — first-spin salt

    uint48 private constant INDEX = 1; // default lootboxRngIndex seeded in setUp

    /// @dev A fixed RNG word for deterministic resolution (we craft tickets against its result).
    uint256 private constant FIXED_WORD = uint256(keccak256("crank_faucet_fixed_word"));

    address private player;   // bet owner
    address private cranker;  // arbitrary caller of crankBets (self-crank == player)
    address private sybil;    // a distinct Sybil cranker

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        player = makeAddr("crank_player");
        cranker = makeAddr("crank_caller");
        sybil = makeAddr("crank_sybil");
        vm.deal(player, 1000 ether);
        vm.deal(cranker, 1000 ether);
        vm.deal(sybil, 1000 ether);
        vm.deal(address(game), 500 ether);

        // placeDegeneretteBet requires lootboxRngIndex != 0 and the word at that index == 0.
        // Seed index = 1 (word stays 0 until we inject it post-placement).
        uint256 lrPacked = uint256(
            vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)))
        );
        lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(INDEX);
        vm.store(
            address(game),
            bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)),
            bytes32(lrPacked)
        );

        // The crank's onlySelf sub-call delegatecalls resolveBets with msg.sender == address(game).
        // resolveBets -> _resolvePlayer(player) -> _requireApproved(player) needs the game approved
        // as the bet-owner's operator. This is the documented crank resolve relaxation.
        vm.prank(player);
        game.setOperatorApproval(address(game), true);
    }

    // =========================================================================
    // Task 1 — Faucet round-trip <= 0, illiquidity, one-reward-per-item,
    //          pre-RNG-word block
    // =========================================================================

    /// @notice SAFE-01 / T-318-02-01: a player who cranks their OWN resolvable bet earns a
    ///         coinflip credit whose ETH-equivalent at the protocol's own peg equals exactly
    ///         CRANK_RESOLVE_BET_GAS_UNITS * 0.5 gwei — strictly below the real gas cost of the
    ///         crank tx at any realistic gas price (> 0.5 gwei) over a gasUsed that exceeds the
    ///         reserved gasUnits. Net round-trip <= 0. Also proves the illiquidity lock (liquid
    ///         BURNIE balance unchanged; credit is pending coinflip stake). Uses a LOSING bet so
    ///         the reward is the only credit (no winnings creditFlip to conflate).
    function testSelfCrankRoundTripNonPositive() public {
        uint64 betId = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        // Reward valued back at the SAME fixed peg = exactly the reserved ETH (the credit is
        // _ethToBurnieValue(GAS_UNITS * 0.5 gwei, price); converting back at price recovers the wei).
        uint256 expectedRewardEthPeg = CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF;

        uint256 preLiquidBurnie = coin.balanceOf(player);
        uint256 preStake = coinflip.coinflipAmount(player);

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        // Measure the real gas the crank tx consumes (the cranker's true ETH cost driver).
        vm.prank(player);
        uint256 gasBefore = gasleft();
        game.crankBets(players, betIds);
        uint256 gasUsed = gasBefore - gasleft();

        uint256 postLiquidBurnie = coin.balanceOf(player);
        uint256 postStake = coinflip.coinflipAmount(player);

        // (a) Illiquidity: the reward did NOT increase the player's LIQUID BURNIE balance.
        assertEq(
            postLiquidBurnie,
            preLiquidBurnie,
            "self-crank reward must not land as liquid BURNIE (illiquid coinflip stake only)"
        );

        // (b) The reward landed as coinflip pending stake (a positive, non-liquid credit).
        uint256 stakeDelta = postStake - preStake;
        assertGt(stakeDelta, 0, "self-crank earns a positive coinflip stake credit");

        // (c) The earned credit, valued back at the protocol's own peg, equals the reserved
        //     gas-peg ETH and NOT a measured-gas reimbursement.
        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertEq(
            rewardEthAtPeg,
            expectedRewardEthPeg,
            "credit value at peg must equal the FIXED gasUnits * 0.5 gwei reserve (REW-03)"
        );

        // (d) ROUND-TRIP <= 0 (structural): the reward is the FIXED reserve priced at the 0.5 gwei
        //     reference (REW-03 — never measured gas, never tx.gasprice). A real submission pays
        //     gasUsed * (real gas price), and the realistic price floor (1 gwei) is already 2x the
        //     0.5 gwei reference. So even at the 1 gwei floor the reserved-peg reward is strictly
        //     below the real gas the cranker burns to earn it — the round-trip is negative. The
        //     gap only widens as the real price rises (reward fixed, cost scales).
        uint256 realGasCostAt1Gwei = gasUsed * 1 gwei;
        assertLt(
            expectedRewardEthPeg,
            realGasCostAt1Gwei,
            "round-trip <= 0 at the 1 gwei realistic floor: fixed-peg reward < real gas cost"
        );

        // Spot-check a 20 gwei mainnet-typical price — the gap is an order of magnitude.
        uint256 realGasCostAt20Gwei = gasUsed * 20 gwei;
        assertLt(
            expectedRewardEthPeg,
            realGasCostAt20Gwei,
            "round-trip strictly negative at a realistic 20 gwei submission price"
        );

        // Belt-and-suspenders on the illiquidity lock: even if the reserved-peg ETH could be
        // recovered 1:1, it lands as coinflip STAKE (gambled, not withdrawable) — there is no
        // path to convert the credit back to liquid ETH at par, so the round-trip cannot even
        // reach the ETH-peg value, let alone exceed the gas spent.
        assertEq(postLiquidBurnie, preLiquidBurnie, "credit never becomes liquid (re-asserted)");
    }

    /// @notice SAFE-01 fuzz: across fuzzed realistic submission prices and a fuzzed Sybil cranker,
    ///         the fixed-peg reward is ALWAYS below the real gas cost — the round-trip cannot be
    ///         pushed positive by choosing the cranker or the gas price (REW-03: reward never reads
    ///         tx.gasprice/gasleft so it does not scale with the chosen price).
    function testFuzz_RoundTripNonPositiveAcrossGasPrices(uint256 gasPriceWei, uint8 crankerSel) public {
        // Realistic submission prices: 1 gwei .. 2000 gwei (above the 0.5 gwei reference floor).
        gasPriceWei = bound(gasPriceWei, 1 gwei, 2000 gwei);

        uint64 betId = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        address actualCranker = (crankerSel % 2 == 0) ? player : sybil;

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        uint256 preStake = coinflip.coinflipAmount(actualCranker);
        vm.prank(actualCranker);
        uint256 gasBefore = gasleft();
        game.crankBets(players, betIds);
        uint256 gasUsed = gasBefore - gasleft();
        uint256 stakeDelta = coinflip.coinflipAmount(actualCranker) - preStake;

        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        // The reward's ETH-peg value is the FIXED reserve, independent of the chosen gas price.
        assertEq(rewardEthAtPeg, CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF, "reward fixed, price-independent");

        // Round-trip <= 0 at the fuzzed real submission price.
        assertLt(
            rewardEthAtPeg,
            gasUsed * gasPriceWei,
            "round-trip <= 0 at every fuzzed realistic gas price > 0.5 gwei"
        );
    }

    /// @notice The full resolve path runs end-to-end for a WINNING bet: the bet is resolved (slot
    ///         deleted = work done), winnings are paid, and the cranker still earns exactly the
    ///         fixed reward peg on top (the crank reward is independent of the win amount).
    function testWinningBetFullResolvePathStillPegsReward() public {
        uint64 betId = _placeWinningBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        // Count the crank-reward creditFlip specifically: it is the creditFlip emitted from the
        // top-level GAME frame (the post-loop reward), distinct from any winnings creditFlip
        // emitted from inside the resolve sub-call. We isolate it by its amount == the fixed peg.
        uint256 expectedRewardBurnie =
            (CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF * PRICE_COIN_UNIT)
            / PriceLookupLib.priceForLevel(_lvl());

        vm.recordLogs();
        vm.prank(player);
        game.crankBets(players, betIds);

        // The bet was resolved (work done): its slot is deleted.
        assertEq(_readBetPacked(player, betId), 0, "winning bet resolved (slot deleted)");

        // Exactly one CoinflipStakeUpdated carries the fixed crank-reward peg amount.
        assertEq(
            _countCoinflipStakeUpdatedWithAmount(expectedRewardBurnie),
            1,
            "exactly one crank-reward creditFlip at the fixed peg, even alongside a winnings credit"
        );
    }

    /// @notice One-reward-per-item: re-cranking an already-resolved bet reverts BatchAlreadyTaken
    ///         at item 0 (its slot is deleted on first resolve), yielding zero further credit.
    function testReCrankResolvedBetRevertsNoSecondReward() public {
        uint64 betId = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        // First crank resolves and rewards.
        vm.prank(player);
        game.crankBets(players, betIds);

        // The bet slot is now deleted (one-reward state). degeneretteBets[player][betId] == 0.
        assertEq(_readBetPacked(player, betId), 0, "resolved bet slot is zeroed (one-reward lock)");

        uint256 stakeBeforeSecond = coinflip.coinflipAmount(sybil);

        // Second crank by ANYONE: item 0 probe sees the zero slot -> BatchAlreadyTaken, whole call
        // reverts (the loser-gas cap). No second creditFlip.
        vm.prank(sybil);
        vm.expectRevert(bytes4(keccak256("BatchAlreadyTaken()")));
        game.crankBets(players, betIds);

        assertEq(
            coinflip.coinflipAmount(sybil),
            stakeBeforeSecond,
            "re-crank of a resolved bet yields zero additional reward"
        );
    }

    /// @notice One-reward-per-item within ONE batch: the same (player, betId) listed twice rewards
    ///         only once. Item 0 resolves+rewards; the duplicate at index 1 hits the deleted slot,
    ///         the onlySelf resolve reverts InvalidBet (packed==0), is caught, and adds zero.
    function testDuplicateInBatchRewardsOnce() public {
        uint64 betId = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        address[] memory players = new address[](2);
        uint64[] memory betIds = new uint64[](2);
        players[0] = player;
        betIds[0] = betId;
        players[1] = player; // duplicate
        betIds[1] = betId;

        uint256 preStake = coinflip.coinflipAmount(player);
        vm.prank(player);
        game.crankBets(players, betIds);
        uint256 stakeDelta = coinflip.coinflipAmount(player) - preStake;

        uint256 oneItemPeg = CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF;
        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertEq(
            rewardEthAtPeg,
            oneItemPeg,
            "a duplicated item rewards exactly once, not twice"
        );
    }

    /// @notice Pre-RNG-word block (bets): a crank whose RNG word has NOT landed does not resolve
    ///         and does not reward — the onlySelf sub-call hits the preserved RngNotReady guard,
    ///         is caught by try/catch, the bet slot stays intact, and reward stays zero (no
    ///         creditFlip emitted).
    function testCrankBeforeRngWordSkipsAndDoesNotReward() public {
        uint64 betId = _placeLosingBet(player);
        // NOTE: deliberately do NOT inject the RNG word -> lootboxRngWordByIndex[INDEX] == 0.

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        uint256 preStake = coinflip.coinflipAmount(player);

        vm.recordLogs();
        vm.prank(player);
        game.crankBets(players, betIds);

        // No creditFlip emitted (reward == 0 guard).
        assertEq(_countCoinflipStakeUpdated(), 0, "no creditFlip when RNG word has not landed");
        // Bet slot intact (not resolved) -> still re-crankable once the word lands.
        assertGt(_readBetPacked(player, betId), 0, "unresolved bet slot remains intact pre-word");
        // Stake unchanged.
        assertEq(coinflip.coinflipAmount(player), preStake, "no reward for a not-ready crank");
    }

    /// @notice Pre-RNG-word block (boxes / orphan-index gate): crankBoxes on an index whose
    ///         word is zero returns early without rewarding (the orphan-index re-issue coupling).
    function testCrankBoxesBeforeRngWordEmitsNoReward() public {
        // INDEX word is zero (we never inject it here). crankBoxes must early-return at the
        // lootboxRngWordByIndex[index] == 0 guard, emitting no creditFlip.
        uint256 preStake = coinflip.coinflipAmount(sybil);
        vm.recordLogs();
        vm.prank(sybil);
        game.crankBoxes(100);
        assertEq(_countCoinflipStakeUpdated(), 0, "crankBoxes on a wordless index emits no creditFlip");
        assertEq(coinflip.coinflipAmount(sybil), preStake, "no reward from a not-ready box index");
    }

    // =========================================================================
    // Task 2 — WWXRP zero reward + one-creditFlip-per-tx + zero-success no-credit
    // =========================================================================

    /// @notice CRANK-04 / T-318-02-02: cranking a WWXRP-denominated bet (currency == 3) resolves
    ///         the work but credits exactly ZERO reward — the currency==3 fork at
    ///         DegenerusGame.sol:1564 takes the zero-reward branch. Uses a LOSING WWXRP ticket so
    ///         no winnings creditFlip occurs either: the player's stake is unchanged, end to end.
    function testWwxrpCrankEarnsZeroReward() public {
        uint64 betId = _placeLosingWwxrpBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        uint256 preStake = coinflip.coinflipAmount(player);

        vm.recordLogs();
        vm.prank(player);
        game.crankBets(players, betIds);

        // The WWXRP bet WAS resolved (its slot is now deleted) ...
        assertEq(_readBetPacked(player, betId), 0, "WWXRP bet is resolved (work done)");
        // ... but earned ZERO crank reward (currency==3 zero fork), so no creditFlip fired.
        assertEq(_countCoinflipStakeUpdated(), 0, "WWXRP work earns no creditFlip (CRANK-04)");
        assertEq(coinflip.coinflipAmount(player), preStake, "WWXRP reward is exactly zero");
    }

    /// @notice REW-02: a crankBets over N>1 successful items emits exactly ONE crank-reward
    ///         creditFlip with the summed amount, never N separate credits. Uses LOSING bets so
    ///         the only creditFlip is the single post-loop crank reward.
    function testBatchEmitsExactlyOneCreditFlipWithSum() public {
        // Place THREE resolvable LOSING bets for the same player at the same index.
        uint64 b1 = _placeLosingBet(player);
        uint64 b2 = _placeLosingBet(player);
        uint64 b3 = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        address[] memory players = new address[](3);
        uint64[] memory betIds = new uint64[](3);
        players[0] = player; betIds[0] = b1;
        players[1] = player; betIds[1] = b2;
        players[2] = player; betIds[2] = b3;

        uint256 preStake = coinflip.coinflipAmount(player);

        vm.recordLogs();
        vm.prank(player);
        game.crankBets(players, betIds);

        // Exactly ONE creditFlip for the batch (not 3) — losing bets pay no winnings, so the
        // single emission is the post-loop crank reward.
        assertEq(_countCoinflipStakeUpdated(), 1, "exactly one creditFlip per crank tx (REW-02)");

        // Amount == the summed per-item reward (3 * the single-item peg).
        uint256 stakeDelta = coinflip.coinflipAmount(player) - preStake;
        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        uint256 expectedSumPeg = 3 * CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF;
        assertEq(
            rewardEthAtPeg,
            expectedSumPeg,
            "the single creditFlip amount equals the in-memory sum of the 3 item rewards"
        );
    }

    /// @notice REW: a crank that resolves zero items (all skipped: RNG word not landed) emits NO
    ///         creditFlip (the reward != 0 guard at :1578).
    function testZeroSuccessBatchEmitsNoCreditFlip() public {
        // Two real bets, but the RNG word is NOT injected -> both onlySelf resolves hit
        // RngNotReady, caught, zero reward, no creditFlip.
        uint64 b1 = _placeLosingBet(player);
        uint64 b2 = _placeLosingBet(player);

        address[] memory players = new address[](2);
        uint64[] memory betIds = new uint64[](2);
        players[0] = player; betIds[0] = b1;
        players[1] = player; betIds[1] = b2;

        vm.recordLogs();
        vm.prank(player);
        game.crankBets(players, betIds);

        assertEq(_countCoinflipStakeUpdated(), 0, "zero-success batch emits no creditFlip (:1578 guard)");
    }

    // =========================================================================
    // Internal helpers
    // =========================================================================

    /// @dev Active ticket level the crank reward peg is priced at (level==0, not jackpot => 1).
    function _lvl() internal view returns (uint24) {
        return game.level() + 1;
    }

    /// @dev Place a degenerette ETH bet engineered to LOSE (0 matches) against the FIXED_WORD
    ///      spin-0 result, so resolution runs (slot deleted) but pays no winnings — isolating the
    ///      crank reward as the only creditFlip. Returns the betId (per-player nonce).
    function _placeLosingBet(address better) internal returns (uint64 betId) {
        uint32 customTicket = _losingTicketFor(INDEX, FIXED_WORD);
        uint128 betAmount = 0.01 ether; // >= MIN_BET_ETH (0.005 ether)
        vm.prank(better);
        game.placeDegeneretteBet{value: betAmount}(
            address(0), 0, betAmount, 1, customTicket, 0
        );
        betId = _betNonce(better);
    }

    /// @dev Place a degenerette ETH bet engineered to WIN (>=2 matches) against the FIXED_WORD
    ///      spin-0 result, so the full resolve+payout path runs.
    function _placeWinningBet(address better) internal returns (uint64 betId) {
        uint32 customTicket = _winningTicketFor(INDEX, FIXED_WORD);
        uint128 betAmount = 0.01 ether;
        vm.prank(better);
        game.placeDegeneretteBet{value: betAmount}(
            address(0), 0, betAmount, 1, customTicket, 0
        );
        betId = _betNonce(better);
    }

    /// @dev Place a LOSING WWXRP (currency==3) degenerette bet. Seeds the better's WWXRP balance
    ///      via storage write so burnForGame succeeds, then places through the public API.
    function _placeLosingWwxrpBet(address better) internal returns (uint64 betId) {
        uint128 betAmount = 1 ether; // >= MIN_BET_WWXRP (1 ether)
        _seedWwxrpBalance(better, uint256(betAmount) + 1 ether);

        uint32 customTicket = _losingTicketFor(INDEX, FIXED_WORD);
        vm.prank(better);
        game.placeDegeneretteBet(
            address(0), 3, betAmount, 1, customTicket, 0
        );
        betId = _betNonce(better);
    }

    /// @dev Seed a WWXRP balance for `who` (balanceOf slot 2) and bump totalSupply to match.
    function _seedWwxrpBalance(address who, uint256 amount) internal {
        bytes32 balSlot = keccak256(abi.encode(who, uint256(WWXRP_BALANCEOF_SLOT)));
        uint256 prevBal = uint256(vm.load(address(wwxrp), balSlot));
        vm.store(address(wwxrp), balSlot, bytes32(amount));
        uint256 ts = uint256(vm.load(address(wwxrp), bytes32(uint256(WWXRP_TOTAL_SUPPLY_SLOT))));
        // Keep totalSupply consistent with the injected balance (avoid underflow on burn).
        vm.store(
            address(wwxrp),
            bytes32(uint256(WWXRP_TOTAL_SUPPLY_SLOT)),
            bytes32(ts + amount - prevBal)
        );
    }

    /// @dev Inject a lootbox RNG word for an index (lootboxRngWordByIndex mapping at slot 36).
    function _injectLootboxRngWord(uint48 index, uint256 rngWord) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
        vm.store(address(game), slot, bytes32(rngWord));
    }

    /// @dev Read the packed bet for (owner, betId) from degeneretteBets (slot 43).
    function _readBetPacked(address owner, uint64 id) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(owner, uint256(DEGENERETTE_BETS_SLOT)));
        bytes32 leaf = keccak256(abi.encode(uint256(id), uint256(inner)));
        return uint256(vm.load(address(game), leaf));
    }

    /// @dev Read the current degeneretteBetNonce for a player (slot 44).
    function _betNonce(address who) internal view returns (uint64) {
        bytes32 slot = keccak256(abi.encode(who, uint256(DEGENERETTE_BET_NONCE_SLOT)));
        return uint64(uint256(vm.load(address(game), slot)));
    }

    /// @dev The REAL spin-0 result ticket for (index, word), matching _resolveFullTicketBet:
    ///      packedTraitsDegenerette(keccak256(abi.encodePacked(word, uint32(index), 'Q'))).
    function _resultTicketFor(uint48 index, uint256 word) internal pure returns (uint32) {
        uint256 resultSeed = uint256(
            keccak256(abi.encodePacked(word, uint32(index), QUICK_PLAY_SALT))
        );
        return DegenerusTraitUtils.packedTraitsDegenerette(resultSeed);
    }

    /// @dev A customTicket that matches the result in ZERO quadrants (color AND symbol both differ
    ///      in every quadrant) -> matches == 0 -> payout == 0 (a clean loss). The match algorithm
    ///      (_countMatches) compares color = bits 5-3 and symbol = bits 2-0 per quadrant; quadrant
    ///      tag bits 7-6 are ignored. We flip both fields away from the result in each quadrant.
    function _losingTicketFor(uint48 index, uint256 word) internal pure returns (uint32 ticket) {
        uint32 result = _resultTicketFor(index, word);
        for (uint8 q; q < 4; q++) {
            uint8 rQuad = uint8(result >> (q * 8));
            uint8 rColor = (rQuad >> 3) & 7;
            uint8 rSymbol = rQuad & 7;
            uint8 newColor = (rColor + 1) & 7; // guaranteed != rColor
            uint8 newSymbol = (rSymbol + 1) & 7; // guaranteed != rSymbol
            uint8 newQuad = (newColor << 3) | newSymbol; // tag bits 7-6 = 0 (irrelevant to matching)
            ticket |= (uint32(newQuad) << (q * 8));
        }
    }

    /// @dev A customTicket that matches the result in ALL quadrants (color AND symbol) -> matches
    ///      == 8 -> a guaranteed win. We copy the result's color+symbol fields verbatim.
    function _winningTicketFor(uint48 index, uint256 word) internal pure returns (uint32 ticket) {
        uint32 result = _resultTicketFor(index, word);
        for (uint8 q; q < 4; q++) {
            uint8 rQuad = uint8(result >> (q * 8));
            uint8 colorSymbol = rQuad & 0x3F; // bits 5-0 (color + symbol), drop tag bits 7-6
            ticket |= (uint32(colorSymbol) << (q * 8));
        }
    }

    /// @dev Count CoinflipStakeUpdated emissions in the recorded logs from the coinflip contract
    ///      (one is emitted per creditFlip via _addDailyFlip).
    function _countCoinflipStakeUpdated() internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (_isCoinflipStakeUpdated(logs[i])) count++;
        }
    }

    /// @dev Count CoinflipStakeUpdated emissions whose `amount` field equals `wantAmount` (used to
    ///      isolate the fixed-peg crank reward from a variable winnings credit).
    function _countCoinflipStakeUpdatedWithAmount(uint256 wantAmount) internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (!_isCoinflipStakeUpdated(logs[i])) continue;
            // event CoinflipStakeUpdated(address indexed player, uint32 indexed day,
            //                            uint256 amount, uint256 newTotal)
            // amount is the first non-indexed field => first 32 bytes of data.
            (uint256 amount, ) = abi.decode(logs[i].data, (uint256, uint256));
            if (amount == wantAmount) count++;
        }
    }

    function _isCoinflipStakeUpdated(Vm.Log memory entry) internal view returns (bool) {
        return
            entry.emitter == address(coinflip) &&
            entry.topics.length > 0 &&
            entry.topics[0] == COINFLIP_STAKE_UPDATED_SIG;
    }
}
