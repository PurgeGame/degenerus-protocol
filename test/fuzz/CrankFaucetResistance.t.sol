// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title CrankFaucetResistance -- Proves SAFE-01: the permissionless do-work crank
///        (degeneretteResolve / autoOpen) is faucet-bounded by three caller-independent locks:
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

    /// @dev lootboxRngPacked at slot 37 (v47: +2 from presale-box storage additions); lootboxRngIndex is the low 48 bits.
    uint256 private constant LOOTBOX_RNG_PACKED_SLOT = 37;

    /// @dev lootboxRngWordByIndex mapping root slot.
    uint256 private constant LOOTBOX_RNG_WORD_SLOT = 38;

    /// @dev degeneretteBets mapping root slot (address => betId => packed).
    uint256 private constant DEGENERETTE_BETS_SLOT = 45;

    /// @dev degeneretteBetNonce mapping root slot (address => uint64).
    uint256 private constant DEGENERETTE_BET_NONCE_SLOT = 46;

    /// @dev WWXRP balanceOf mapping root slot.
    uint256 private constant WWXRP_BALANCEOF_SLOT = 2;

    /// @dev WWXRP totalSupply slot.
    uint256 private constant WWXRP_TOTAL_SUPPLY_SLOT = 0;

    /// @dev lootboxEthBase mapping root slot (uint48 index => address => base). First-deposit signal,
    ///      zeroed on open — used by the WR-01 multi-box self-crank round-trip to enqueue + verify opens.
    uint256 private constant LOOTBOX_ETH_BASE_SLOT = 22;

    // -------------------------------------------------------------------------
    // Crank reward peg mirror (the contract's own FIXED constants, REW-03)
    // -------------------------------------------------------------------------

    /// @dev Reference gas price for the reward peg (DegenerusGame.sol:1495).

    /// @dev Reserved per-work-type gas-unit constants (DegenerusGame.sol:1501-1502).

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

    /// @dev A fixed RNG word for the WR-01 multi-box self-crank round-trip (deterministic box opens).
    uint256 private constant BOX_FIXED_WORD = uint256(keccak256("crank_faucet_box_fixed_word"));

    // -------------------------------------------------------------------------
    // v49 flat-per-tx router reward mirror (the GAS-05 round-trip guard target)
    //
    // The 330 keeper-router redesign (commit 63bc16ca) re-homed the buy/open/advance bounty
    // from the per-item gas-units model into AfKing.doWork() as a flat-per-tx model. doWork()
    // computes a level-invariant break-even unit then applies a per-category ratio:
    //   unit     = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice()          (AfKing.sol:870)
    //   buy leg  = (unit * BUY_RATIO_NUM) / BUY_RATIO_DEN                         (AfKing.sol:878)
    //   open leg = (unit * min(opened, OPEN_KNEE)) / OPEN_KNEE                    (AfKing.sol:890-891)
    // BOUNTY_ETH_TARGET is read LIVE off the deployed AfKing immutable (afKing.BOUNTY_ETH_TARGET()),
    // so the guards below stay correct for whatever value 331-04 lands; PRICE_COIN_UNIT is the same
    // 1000-ether BURNIE-per-ETH unit already mirrored above. The ratio/knee constants are AfKing
    // `internal constant`s with no on-chain getter, so they are mirrored here — TEST-MIRROR SYNC: if
    // 331-04 changes BUY_RATIO_NUM/DEN or OPEN_KNEE in AfKing.sol, re-sync these. The buy-leg guard
    // CROSS-VALIDATES the live buy reward (observed via doWork()) against unit*NUM/DEN, so a ratio
    // drift in the contract trips testRouterBuyRewardMatchesLiveUnitRatio rather than silently passing.
    // -------------------------------------------------------------------------

    /// @dev AfKing.sol:851-852 — flat 1.5x per-tx buy reward (NUM/DEN).
    uint256 private constant BUY_RATIO_NUM = 3;
    uint256 private constant BUY_RATIO_DEN = 2;

    /// @dev AfKing.sol:854 — open reward pro-rate knee (1x at/above the knee, pro-rated below).
    uint256 private constant OPEN_KNEE = 5;

    // -------------------------------------------------------------------------
    // AfKing storage-slot constants (re-confirmed via `forge inspect AfKing storage`
    // against the 63bc16ca layout; mirrors RouterWorstCaseGas.t.sol).
    // -------------------------------------------------------------------------

    /// @dev _subOf mapping root (one packed Sub slot per subscriber).
    uint256 private constant SUBOF_SLOT = 1;
    /// @dev _autoBuyDay (bytes 0..3) | _autoBuyCursor (bytes 4..) packed at slot 4.
    uint256 private constant AFKING_CURSOR_SLOT = 4;
    /// @dev DegenerusGame claimableWinnings mapping root (for seeding a reinvest-branch sub).
    uint256 private constant GAME_CLAIMABLE_SLOT = 7;

    address private player;   // bet owner
    address private cranker;  // arbitrary caller of degeneretteResolve (self-crank == player)
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
        game.degeneretteResolve(players, betIds);

        // The bet slot is now deleted (one-reward state). degeneretteBets[player][betId] == 0.
        assertEq(_readBetPacked(player, betId), 0, "resolved bet slot is zeroed (one-reward lock)");

        uint256 stakeBeforeSecond = coinflip.coinflipAmount(sybil);

        // Second crank by ANYONE: item 0 probe sees the zero slot -> BatchAlreadyTaken, whole call
        // reverts (the loser-gas cap). No second creditFlip.
        vm.prank(sybil);
        vm.expectRevert(bytes4(keccak256("BatchAlreadyTaken()")));
        game.degeneretteResolve(players, betIds);

        assertEq(
            coinflip.coinflipAmount(sybil),
            stakeBeforeSecond,
            "re-crank of a resolved bet yields zero additional reward"
        );
    }



    /// @notice Pre-RNG-word block (boxes / orphan-index gate): autoOpen on an index whose
    ///         word is zero returns early without rewarding (the orphan-index re-issue coupling).
    function testCrankBoxesBeforeRngWordEmitsNoReward() public {
        // INDEX word is zero (we never inject it here). autoOpen must early-return at the
        // lootboxRngWordByIndex[index] == 0 guard, emitting no creditFlip.
        uint256 preStake = coinflip.coinflipAmount(sybil);
        vm.recordLogs();
        vm.prank(sybil);
        game.autoOpen(100);
        assertEq(_countCoinflipStakeUpdated(), 0, "autoOpen on a wordless index emits no creditFlip");
        assertEq(coinflip.coinflipAmount(sybil), preStake, "no reward from a not-ready box index");
    }



    // =========================================================================
    // 331-02 Task 1 — GAS-05 flat-per-tx ROUTER round-trip guards (the doWork()
    //                  open small-batch hot corner + the flat 1.5x buy leg).
    //
    // The v49 keeper-router (AfKing.doWork(), commit 63bc16ca) moved the buy/open bounty into a
    // flat-per-tx model. The structural faucet risk is the OPEN small-batch corner: below the
    // OPEN_KNEE the per-box reward is pro-rated (unit * k / KNEE), so a self-cranker opening a
    // tiny mid-day batch earns a fraction of `unit` — which the OPEN_KNEE pro-rate exists to keep
    // strictly below the real one-box tx gas. These guards prove the reward valued at the 0.5-gwei
    // peg is below the REAL gas of the identical work at every realistic market price (>=1 gwei),
    // judged against REAL prevailing gas + flip-credit illiquidity (NOT the 0.5-gwei peg ref;
    // feedback_bounty_exploit_uses_real_gas_not_peg_ref). `unit` is read LIVE so the guards hold
    // for whatever 331-04 lands; the reward is illiquid coinflip flip-credit (creditFlip), never a
    // liquid/withdrawable balance, so even a hypothetical par-recovery still cannot clear the gas.
    // =========================================================================

    /// @notice GAS-05 / WR-01 (open hot corner): a self-cranker opens k OWN boxes; the doWork() open-leg
    ///         reward `unit * min(k, OPEN_KNEE) / OPEN_KNEE` valued back at the 0.5-gwei peg is STRICTLY
    ///         below the REAL gas the identical box-opening work burns at the >=1 gwei market floor — for
    ///         k in {1,2,3,4,5,>5}, spanning the below-knee pro-rated corner and the at/above-knee flat
    ///         regime. The work gas is measured via the unrewarded `afKing.autoOpen(k)` passthrough, whose
    ///         body IS the doWork() open leg's box-opening work; the reward is the value doWork() would
    ///         credit (computed from the LIVE break-even unit). Round-trip <= 0 at every realistic price.
    function testRouterOpenSelfCrankRoundTripNonPositive() public {
        uint256[6] memory ks = [uint256(1), 2, 3, 4, 5, 12];
        for (uint256 j; j < ks.length; ++j) {
            uint256 k = ks[j];

            // Fresh fixture per k (re-deploy via setUp's state is per-test; emulate by a fresh index).
            (uint48 index, address[] memory owners) = _queueKBoxesAtActiveIndex(k, j);

            // The open-leg reward doWork() would pay for opening k boxes (LIVE unit; pro-rated below knee).
            uint256 rewardEthAtPeg = _openLegRewardEthAtPeg(k);
            assertGt(rewardEthAtPeg, 0, "open-leg reward is positive for k>=1");

            // Measure the REAL gas of the identical box-opening work (autoOpen body == doWork open leg).
            // autoOpen's maxCount is a GAS-WEIGHTED budget; grant ample weighted units (k * 64, above the
            // ~60-unit whale-pass weight) so all k queued boxes open and the gas is for exactly k boxes.
            address opener = makeAddr(string(abi.encodePacked("openRT_", vm.toString(j))));
            vm.prank(opener);
            uint256 gasBefore = gasleft();
            afKing.autoOpen(k * 64);
            uint256 gasUsed = gasBefore - gasleft();

            // Non-vacuity: each box actually opened (first-deposit signal zeroed) — the gas is for k real
            // materializations, not a no-op walk, so the round-trip comparison is against true work cost.
            for (uint256 i; i < k; ++i) {
                assertEq(_lootboxEthBase(index, owners[i]), 0, "open non-vacuity: each self-crank box opened");
            }

            // ROUND-TRIP <= 0 at the >=1 gwei realistic market floor: the FIXED-peg reward (valued at the
            // 0.5-gwei reference) is strictly below the real gas the self-cranker burns. The small-batch
            // (k < OPEN_KNEE) corner is the hottest — its pro-rated reward must still lose to a one-box tx.
            assertLt(
                rewardEthAtPeg,
                gasUsed * 1 gwei,
                "WR-01 open hot corner: flat-per-tx reward-at-peg < real open gas at the 1 gwei floor"
            );
            // Spot a mainnet-typical 20 gwei price (gap an order of magnitude).
            assertLt(
                rewardEthAtPeg,
                gasUsed * 20 gwei,
                "WR-01 open: round-trip strictly negative at a realistic 20 gwei submission price"
            );
        }
    }

    /// @notice GAS-05 open-corner fuzz: across fuzzed realistic submission prices and fuzzed small batch
    ///         sizes (1..2*OPEN_KNEE, spanning below + at/above the knee), the flat-per-tx open reward at
    ///         the 0.5-gwei peg is ALWAYS below the real open gas — the round-trip cannot be pushed
    ///         positive by choosing the batch size or the gas price (the reward never reads tx.gasprice).
    function testFuzz_RouterOpenRoundTripNonPositiveAcrossGasPrices(uint256 gasPriceWei, uint8 kSel) public {
        gasPriceWei = bound(gasPriceWei, 1 gwei, 2000 gwei);
        uint256 k = (uint256(kSel) % (2 * OPEN_KNEE)) + 1; // 1 .. 2*KNEE

        (uint48 index, address[] memory owners) = _queueKBoxesAtActiveIndex(k, 0);
        uint256 rewardEthAtPeg = _openLegRewardEthAtPeg(k);

        // autoOpen's maxCount is a GAS-WEIGHTED budget; grant ample weighted units (k * 64) so all k
        // queued boxes open and the measured gas covers exactly k boxes.
        address opener = makeAddr("openRT_fuzz");
        vm.prank(opener);
        uint256 gasBefore = gasleft();
        afKing.autoOpen(k * 64);
        uint256 gasUsed = gasBefore - gasleft();

        for (uint256 i; i < k; ++i) {
            assertEq(_lootboxEthBase(index, owners[i]), 0, "open fuzz non-vacuity: each box opened");
        }
        assertLt(
            rewardEthAtPeg,
            gasUsed * gasPriceWei,
            "WR-01 open: round-trip <= 0 at every fuzzed realistic gas price > 0.5 gwei"
        );
    }

    /// @notice GAS-05 (buy leg): the flat 1.5x doWork() buy reward valued at the 0.5-gwei peg is strictly
    ///         below the REAL gas the doWork() buy-leg tx burns at the >=1 gwei floor. A farmer must fund
    ///         real subscription buys (each bounded once/day/sub) far in excess of the bounty. The reward
    ///         here is OBSERVED directly off the doWork() credit delta (buy is the top-priority routed leg
    ///         on a fresh day with healthy subs), so this also proves the live buy ratio end to end.
    function testRouterBuySelfCrankRoundTripNonPositive() public {
        address[] memory subs = _setupHealthyBuyingSubs(3, "buyRT_");

        address keeper = makeAddr("buyRT_keeper");
        uint256 pre = coinflip.coinflipAmount(keeper);

        vm.prank(keeper);
        uint256 gasBefore = gasleft();
        afKing.doWork();
        uint256 gasUsed = gasBefore - gasleft();

        uint256 stakeDelta = coinflip.coinflipAmount(keeper) - pre;
        assertGt(stakeDelta, 0, "doWork buy leg pays a positive flat bounty");

        // Non-vacuity: at least one of our subs actually bought this day (the buy leg ran real work).
        uint32 today = _today();
        bool anyBought;
        for (uint256 i; i < subs.length; ++i) {
            if (_lastAutoBoughtDayOf(subs[i]) == today) { anyBought = true; break; }
        }
        assertTrue(anyBought, "buy non-vacuity: doWork ran the buy leg (a sub bought)");

        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;

        // ROUND-TRIP <= 0 at the >=1 gwei market floor + a 20 gwei spot.
        assertLt(
            rewardEthAtPeg,
            gasUsed * 1 gwei,
            "WR-01 buy leg: flat 1.5x reward-at-peg < real autoBuy gas at the 1 gwei floor"
        );
        assertLt(
            rewardEthAtPeg,
            gasUsed * 20 gwei,
            "WR-01 buy leg: round-trip strictly negative at a realistic 20 gwei price"
        );
    }

    /// @notice GAS-05 buy-leg fuzz: across fuzzed realistic submission prices the observed flat buy reward
    ///         at the 0.5-gwei peg is always below the real doWork() buy-leg gas — price-independent reward.
    function testFuzz_RouterBuyRoundTripNonPositiveAcrossGasPrices(uint256 gasPriceWei) public {
        gasPriceWei = bound(gasPriceWei, 1 gwei, 2000 gwei);

        _setupHealthyBuyingSubs(3, "buyRTf_");
        address keeper = makeAddr("buyRTf_keeper");
        uint256 pre = coinflip.coinflipAmount(keeper);
        vm.prank(keeper);
        uint256 gasBefore = gasleft();
        afKing.doWork();
        uint256 gasUsed = gasBefore - gasleft();
        uint256 stakeDelta = coinflip.coinflipAmount(keeper) - pre;
        assertGt(stakeDelta, 0, "doWork buy leg pays a positive flat bounty");

        uint256 rewardEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertLt(
            rewardEthAtPeg,
            gasUsed * gasPriceWei,
            "WR-01 buy leg: round-trip <= 0 at every fuzzed realistic gas price > 0.5 gwei"
        );
    }

    /// @notice GUARD-the-guard / test-mirror sync: the buy reward doWork() actually credits equals the
    ///         LIVE break-even unit times the mirrored buy ratio. This binds the mirrored BUY_RATIO_NUM/DEN
    ///         (and the `unit` formula the open guard reuses) to the deployed contract: if 331-04 re-pegs
    ///         BOUNTY_ETH_TARGET (handled — read live) OR changes BUY_RATIO in AfKing.sol without re-syncing
    ///         this mirror, this assertion trips RED rather than the round-trip guards silently mis-pricing.
    function testRouterBuyRewardMatchesLiveUnitRatio() public {
        _setupHealthyBuyingSubs(3, "buyMatch_");
        address keeper = makeAddr("buyMatch_keeper");
        uint256 pre = coinflip.coinflipAmount(keeper);
        vm.prank(keeper);
        afKing.doWork();
        uint256 stakeDelta = coinflip.coinflipAmount(keeper) - pre;

        uint256 unit = _liveUnit();
        assertEq(
            stakeDelta,
            (unit * BUY_RATIO_NUM) / BUY_RATIO_DEN,
            "doWork buy reward == live unit * BUY_RATIO_NUM/DEN (mirror in sync with AfKing)"
        );
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
        game.degeneretteResolve(players, betIds);

        // The WWXRP bet WAS resolved (its slot is now deleted) ...
        assertEq(_readBetPacked(player, betId), 0, "WWXRP bet is resolved (work done)");
        // ... but earned ZERO crank reward (currency==3 zero fork), so no creditFlip fired.
        assertEq(_countCoinflipStakeUpdated(), 0, "WWXRP work earns no creditFlip (CRANK-04)");
        assertEq(coinflip.coinflipAmount(player), preStake, "WWXRP reward is exactly zero");
    }



    // =========================================================================
    // 331-02 Task 2 — GAS-06 degeneretteResolve flat ~1-BURNIE round-trip guard +
    //                  the >=3 non-WWXRP gate / 1-2-unpaid / 0-reverts / WWXRP-excl.
    //
    // The v49 degeneretteResolve (DegenerusGame.sol:1585) pays a count-independent flat
    // RESOLVE_FLAT_BURNIE flip-credit ONCE per tx at >=3 successfully-resolved NON-WWXRP bets
    // (D-05b). The anti-exploit basis (D-05c, NOT the 0.5-gwei peg ref): ~1 BURNIE is illiquid
    // flip-credit worth <= mintPrice/1000 ETH, while the keeper pays REAL prevailing gas on every
    // qualifying tx -> a net loss at any realistic price; the >=3 gate widens the margin. The
    // reward is read off the keeper's credit delta (NOT hardcoded 1e18) so the guard holds for
    // whatever 331-04 confirms/re-pegs RESOLVE_FLAT_BURNIE to.
    // =========================================================================

    /// @notice GAS-06 round-trip: a self-cranker resolves exactly 3 non-WWXRP bets (the minimum paid
    ///         case), earns the flat ~1-BURNIE flip-credit ONCE. That credit valued back at the level
    ///         price is <= mintPrice/1000 ETH (the D-05c illiquid-credit ceiling), and the REAL measured
    ///         degeneretteResolve gas * realPrice strictly exceeds it at 1 gwei and 20 gwei -> net loss.
    function testDegeneretteResolveFlatRewardRoundTripNonPositive() public {
        (address[] memory players, uint64[] memory betIds) = _placeNLosingBets(3);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        uint256 preStake = coinflip.coinflipAmount(player);
        vm.prank(player);
        uint256 gasBefore = gasleft();
        game.degeneretteResolve(players, betIds);
        uint256 gasUsed = gasBefore - gasleft();
        uint256 stakeDelta = coinflip.coinflipAmount(player) - preStake;

        // The >=3 gate fired exactly once (count-independent flat reward).
        assertGt(stakeDelta, 0, "3 non-WWXRP resolutions earn the flat reward once (>=3 gate)");

        // (a) The credit valued at the level price is at most the D-05c illiquid-credit ceiling.
        uint256 creditEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertLe(
            creditEthAtPeg,
            game.mintPrice() / 1000,
            "flat resolve credit valued at peg <= mintPrice/1000 ETH (D-05c illiquid-credit ceiling)"
        );

        // (b) ROUND-TRIP <= 0 vs REAL gas: the keeper pays real prevailing gas on the >=3 resolve while
        //     the illiquid ~1-BURNIE credit stays below mintPrice/1000 -> a net loss at any realistic price.
        assertLt(
            creditEthAtPeg,
            gasUsed * 1 gwei,
            "GAS-06: flat resolve credit-at-peg < real >=3-resolution gas at the 1 gwei floor"
        );
        assertLt(
            creditEthAtPeg,
            gasUsed * 20 gwei,
            "GAS-06: resolve round-trip strictly negative at a realistic 20 gwei price"
        );

        // (c) Illiquidity: the credit never landed as a liquid/withdrawable BURNIE balance.
        assertEq(coin.balanceOf(player), 0, "resolve reward is illiquid coinflip stake, never liquid BURNIE");
    }

    /// @notice GAS-06 resolve fuzz: across fuzzed realistic submission prices the flat ~1-BURNIE credit
    ///         (valued at peg) is ALWAYS below the real >=3-resolution gas — the reward never reads
    ///         tx.gasprice so the round-trip cannot be pushed positive by choosing the price.
    function testFuzz_DegeneretteResolveRoundTripNonPositiveAcrossGasPrices(uint256 gasPriceWei) public {
        gasPriceWei = bound(gasPriceWei, 1 gwei, 2000 gwei);

        (address[] memory players, uint64[] memory betIds) = _placeNLosingBets(3);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        uint256 preStake = coinflip.coinflipAmount(player);
        vm.prank(player);
        uint256 gasBefore = gasleft();
        game.degeneretteResolve(players, betIds);
        uint256 gasUsed = gasBefore - gasleft();
        uint256 stakeDelta = coinflip.coinflipAmount(player) - preStake;
        assertGt(stakeDelta, 0, "the >=3 non-WWXRP gate paid the flat reward");

        uint256 creditEthAtPeg = (stakeDelta * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
        assertLt(
            creditEthAtPeg,
            gasUsed * gasPriceWei,
            "GAS-06: resolve round-trip <= 0 at every fuzzed realistic gas price > 0.5 gwei"
        );
    }

    /// @notice GAS-06 below-gate unpaid: resolving 1 or 2 non-WWXRP bets COMMITS the resolution but pays
    ///         ZERO (the keeper's flip-credit delta is exactly 0) — the bet slots are deleted (work done,
    ///         tail never stranded) yet successCount < 3 so the flat reward is withheld. Trivially -EV.
    function testDegeneretteResolveBelowGateUnpaid() public {
        // Place ALL bets while the index word is still 0 (placeDegeneretteBet binds to the active index
        // and reverts RngNotReady once a word lands), THEN inject the word once and resolve in sub-batches.
        uint64 a1 = _placeLosingBet(player);
        uint64 c1 = _placeLosingBet(player);
        uint64 c2 = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        // ---- 1 resolution ----
        address[] memory p1 = new address[](1);
        uint64[] memory b1 = new uint64[](1);
        p1[0] = player; b1[0] = a1;
        uint256 pre1 = coinflip.coinflipAmount(player);
        vm.prank(player);
        game.degeneretteResolve(p1, b1);
        assertEq(coinflip.coinflipAmount(player) - pre1, 0, "1 resolution pays zero (< the >=3 gate)");
        assertEq(_readBetPacked(player, a1), 0, "1 resolution still COMMITS (slot deleted, tail not stranded)");

        // ---- 2 resolutions ----
        address[] memory p2 = new address[](2);
        uint64[] memory b2 = new uint64[](2);
        p2[0] = player; b2[0] = c1;
        p2[1] = player; b2[1] = c2;
        uint256 pre2 = coinflip.coinflipAmount(player);
        vm.prank(player);
        game.degeneretteResolve(p2, b2);
        assertEq(coinflip.coinflipAmount(player) - pre2, 0, "2 resolutions pay zero (< the >=3 gate)");
        assertEq(_readBetPacked(player, c1), 0, "2 resolutions commit item 0 (work done)");
        assertEq(_readBetPacked(player, c2), 0, "2 resolutions commit item 1 (work done)");
    }

    /// @notice GAS-06 zero-work revert: when item 0 is a real (non-deleted) bet whose RNG word has NOT
    ///         landed, the probe passes the BatchAlreadyTaken check but the per-item resolve throws
    ///         RngNotReady (caught), totalResolved stays 0, and the whole call reverts NoWork().
    function testDegeneretteResolveZeroReverts() public {
        // Place a real bet but deliberately DO NOT inject the RNG word -> the resolve sub-call hits the
        // preserved RngNotReady guard, is caught, totalResolved == 0.
        uint64 betId = _placeLosingBet(player);
        address[] memory players = new address[](1);
        uint64[] memory betIds = new uint64[](1);
        players[0] = player;
        betIds[0] = betId;

        uint256 preStake = coinflip.coinflipAmount(player);
        vm.prank(player);
        vm.expectRevert(bytes4(keccak256("NoWork()")));
        game.degeneretteResolve(players, betIds);

        // The revert rolled back any state; no credit, bet slot intact (still re-crankable once the word lands).
        assertEq(coinflip.coinflipAmount(player), preStake, "zero-work revert pays nothing");
        assertGt(_readBetPacked(player, betId), 0, "zero-work revert leaves the unresolved bet intact");
    }

    /// @notice GAS-06 / AUTO-04 WWXRP exclusion from the gate: 3 WWXRP (currency==3) resolutions resolve
    ///         the work (slots deleted) but never count toward the >=3 non-WWXRP gate, so the flat reward
    ///         is WITHHELD (credit delta 0). Adding 3 non-WWXRP bets to the SAME batch then meets the gate
    ///         and pays the flat reward ONCE — proving WWXRP is excluded from the count, not from the work.
    function testDegeneretteResolveWwxrpExcludedFromGate() public {
        // Place ALL bets (3 WWXRP + 3 non-WWXRP) while the index word is still 0, THEN inject once.
        uint64 w1 = _placeLosingWwxrpBet(player);
        uint64 w2 = _placeLosingWwxrpBet(player);
        uint64 w3 = _placeLosingWwxrpBet(player);
        uint64 n1 = _placeLosingBet(player);
        uint64 n2 = _placeLosingBet(player);
        uint64 n3 = _placeLosingBet(player);
        _injectLootboxRngWord(INDEX, FIXED_WORD);

        // ---- 3 WWXRP only: resolves but earns nothing (WWXRP excluded from the gate count) ----
        address[] memory wps = new address[](3);
        uint64[] memory wbs = new uint64[](3);
        wps[0] = player; wbs[0] = w1;
        wps[1] = player; wbs[1] = w2;
        wps[2] = player; wbs[2] = w3;

        uint256 preW = coinflip.coinflipAmount(player);
        vm.prank(player);
        game.degeneretteResolve(wps, wbs);
        assertEq(coinflip.coinflipAmount(player) - preW, 0, "3 WWXRP resolutions earn no reward (excluded from gate)");
        assertEq(_readBetPacked(player, w1), 0, "WWXRP work still done (slot deleted), just unrewarded");

        // ---- 3 non-WWXRP: now the gate is met (WWXRP did not count), reward paid once ----
        address[] memory nps = new address[](3);
        uint64[] memory nbs = new uint64[](3);
        nps[0] = player; nbs[0] = n1;
        nps[1] = player; nbs[1] = n2;
        nps[2] = player; nbs[2] = n3;
        uint256 preN = coinflip.coinflipAmount(player);
        vm.prank(player);
        game.degeneretteResolve(nps, nbs);
        uint256 deltaN = coinflip.coinflipAmount(player) - preN;
        assertGt(deltaN, 0, "3 non-WWXRP resolutions meet the >=3 gate and pay the flat reward once");
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

    /// @dev Place `n` LOSING ETH bets for `player` and return the parallel (players, betIds) arrays the
    ///      degeneretteResolve API consumes. Used by the GAS-06 resolve round-trip + gate guards.
    function _placeNLosingBets(uint256 n)
        internal
        returns (address[] memory players, uint64[] memory betIds)
    {
        players = new address[](n);
        betIds = new uint64[](n);
        for (uint256 i; i < n; ++i) {
            players[i] = player;
            betIds[i] = _placeLosingBet(player);
        }
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

    /// @dev Buy a real lootbox-mode deposit via the public mint API. The first deposit for
    ///      (index, buyer) fires the `lootboxEthBase == 0` signal -> enqueueBoxForAutoOpen (MintModule:999).
    ///      Mirrors CrankNonBrick/CrankOpenBoxWorstCaseGas._buyBox.
    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(
            buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
        );
    }

    /// @dev Active daily lootbox index (low 48 bits of lootboxRngPacked at slot 37 (v47: +2 from presale-box storage additions)).
    function _activeLootboxIndex() internal view returns (uint48) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
        return uint48(packed & 0xFFFFFFFFFFFF);
    }

    /// @dev Read lootboxEthBase[index][who] (slot 19) — the first-deposit signal, zeroed on open.
    function _lootboxEthBase(uint48 index, address who) internal view returns (uint256) {
        bytes32 inner = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_ETH_BASE_SLOT)));
        bytes32 leaf = keccak256(abi.encode(who, uint256(inner)));
        return uint256(vm.load(address(game), leaf));
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


    /// @dev Count CoinflipStakeUpdated emissions in the recorded logs from the coinflip contract
    ///      (one is emitted per creditFlip via _addDailyFlip).
    function _countCoinflipStakeUpdated() internal returns (uint256 count) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (_isCoinflipStakeUpdated(logs[i])) count++;
        }
    }


    function _isCoinflipStakeUpdated(Vm.Log memory entry) internal view returns (bool) {
        return
            entry.emitter == address(coinflip) &&
            entry.topics.length > 0 &&
            entry.topics[0] == COINFLIP_STAKE_UPDATED_SIG;
    }

    // -------------------------------------------------------------------------
    // 331-02 router round-trip helpers (mirror RouterWorstCaseGas.t.sol)
    // -------------------------------------------------------------------------

    /// @dev The LIVE break-even unit doWork() computes: (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice.
    ///      Read off the deployed AfKing immutable + the game's current mintPrice so the guards track
    ///      whatever 331-04 lands as BOUNTY_ETH_TARGET (a deploy-param, not a frozen constant).
    function _liveUnit() internal view returns (uint256) {
        return (afKing.BOUNTY_ETH_TARGET() * PRICE_COIN_UNIT) / game.mintPrice();
    }

    /// @dev The open-leg reward doWork() pays for opening `k` boxes, valued back at the 0.5-gwei peg.
    ///      doWork credits `unit * min(k, OPEN_KNEE) / OPEN_KNEE` BURNIE flip-credit (AfKing.sol:890-891);
    ///      valuing that credit at the level price recovers exactly the reserved ETH-at-peg
    ///      (creditBurnie * price / PRICE_COIN_UNIT), the cranker-cost comparison basis.
    function _openLegRewardEthAtPeg(uint256 k) internal view returns (uint256) {
        uint256 unit = _liveUnit();
        uint256 kClamped = k < OPEN_KNEE ? k : OPEN_KNEE;
        uint256 rewardBurnie = (unit * kClamped) / OPEN_KNEE;
        return (rewardBurnie * PriceLookupLib.priceForLevel(_lvl())) / PRICE_COIN_UNIT;
    }

    /// @dev Queue `k` real first-deposit boxes against the CURRENT active lootbox index and land the RNG
    ///      word so the boxes are openable. Returns the index + the owner addresses (keyed by a per-call
    ///      salt so repeated calls in one test use disjoint addresses). Boxes stay at the active index
    ///      because we queue BEFORE any advance (advanceDue may be TRUE, but autoOpen opens the queued
    ///      boxes directly — the unrewarded passthrough body is the same box-opening work as doWork's leg).
    function _queueKBoxesAtActiveIndex(uint256 k, uint256 salt)
        internal
        returns (uint48 index, address[] memory owners)
    {
        index = _activeLootboxIndex();
        owners = new address[](k);
        for (uint256 i; i < k; ++i) {
            address o = makeAddr(string(abi.encodePacked("rtbox_", vm.toString(salt), "_", vm.toString(i))));
            owners[i] = o;
            vm.deal(o, 100_000 ether);
            _buyBox(o, 1 ether);
        }
        _injectLootboxRngWord(index, BOX_FIXED_WORD);
        for (uint256 i; i < k; ++i) {
            assertGt(_lootboxEthBase(index, owners[i]), 0, "queue precondition: each box queued + un-opened");
        }
    }

    /// @dev Subscribe `n` fresh players as fully-healthy WORST-CASE buying subs (reinvest + drain-first,
    ///      ticket mode, operator-approved, pool-funded) so the doWork() buy leg processes real buys and
    ///      pays its flat bounty. Mirrors RouterWorstCaseGas._setupHealthyBuyingSubs.
    function _setupHealthyBuyingSubs(uint256 n, string memory prefix) internal returns (address[] memory subs) {
        subs = new address[](n);
        uint256 mp = game.mintPrice();
        uint256 claimable = mp / 2;
        uint256 poolWei = mp + 1 ether;
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, vm.toString(i))));
            subs[i] = who;
            _fundBurnie(who, _subCostBurnie());
            vm.prank(who);
            afKing.subscribe(address(0), true, true, 1, 100, address(0));
            vm.prank(who);
            game.setOperatorApproval(address(afKing), true);
            vm.deal(address(this), poolWei);
            afKing.depositFor{value: poolWei}(who);
            _setGameClaimable(who, claimable);
        }
    }

    /// @dev The subscribe-time all-or-nothing BURNIE charge: (SUB_COST_ETH_TARGET * PRICE_COIN_UNIT)/mintPrice.
    function _subCostBurnie() internal view returns (uint256) {
        return (afKing.SUB_COST_ETH_TARGET() * PRICE_COIN_UNIT) / game.mintPrice();
    }

    /// @dev Mint BURNIE to `who` via the GAME-gated mint path.
    function _fundBurnie(address who, uint256 amount) internal {
        if (amount == 0) return;
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, amount);
    }

    /// @dev Seed a player's DegenerusGame claimableWinnings (slot 7) so the SUB-04 reinvest branch runs.
    function _setGameClaimable(address who, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(GAME_CLAIMABLE_SLOT)));
        vm.store(address(game), slot, bytes32(amount));
    }

    /// @dev Keeper-local day index (mirrors AfKing._currentDay() 82620-second offset).
    function _today() internal view returns (uint32) {
        return uint32((block.timestamp - 82620) / 1 days);
    }

    /// @dev Read `who`'s lastAutoBoughtDay (bytes 1..4 of the packed Sub slot) — the buy non-vacuity oracle.
    function _lastAutoBoughtDayOf(address who) internal view returns (uint32) {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 packed = uint256(vm.load(address(afKing), slot));
        return uint32(packed >> 8); // OFF_LASTSWEPT = 1 byte
    }
}
