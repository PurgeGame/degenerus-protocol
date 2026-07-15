// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title DecimatorBountyRegression — keeper box-bounty on claimDecimatorJackpotMany
/// @notice Pins the per-settled-box FLIP flip-credit the decimator batch claim pays its caller
///         during a live game:
///           bounty = settled * BOX_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT / mintPrice
///         and the rules around it:
///           1. LIVE      — a live-game batch claim credits the keeper exactly one box-bounty per
///                          settled winner; the credit lands as a next-day coinflip STAKE
///                          (creditFlip -> _addDailyFlip), surfaced by coinflipAmount.
///           2. SCALES    — N settled winners credit N * the per-box bounty.
///           3. GAME-OVER — no liveness is needed post-gameOver, so the bounty is NOT paid (the
///                          winners still settle into claimable, the keeper just earns nothing).
///           4. ETH-VALUE — the FLIP credit holds its ETH-reimbursement value across the price
///                          curve: credit * mintPrice / PRICE_COIN_UNIT == settled * target.
///           5. FAUCET    — the bounty is far below the FLIP a winner had to burn to exist, so a
///                          keeper cannot manufacture boxes to farm it.
///
/// @dev A winning DecBet + claim round + winning-subbucket offset are installed directly via
///      vm.store (bypassing the expensive VRF-winning-subbucket resolution), then a keeper batch
///      claims. Share size is kept dust-small (< 0.01 ETH) so the settle takes the no-box dust path
///      and the test isolates the bounty rather than the lootbox payout machinery.
contract DecimatorBountyRegression is DeployProtocol {
    // forge inspect DegenerusGame storageLayout (Stage B POST layout):
    uint256 internal constant SLOT_HEADER = 0; // packed flags incl. gameOver @ byte 21
    uint256 internal constant SLOT_POOLS_1 = 1; // currentPrizePool[0:128] | claimablePool[128:256]
    uint256 internal constant SLOT_DEC_BURN = 40; // mapping(uint24 => mapping(address => DecBet))
    uint256 internal constant SLOT_DEC_CLAIM_ROUNDS = 42; // mapping(uint24 => DecClaimRound) (one slot)
    uint256 internal constant SLOT_DEC_OFFSET_PACKED = 43; // mapping(uint24 => uint64)

    uint256 internal constant PRICE_COIN_UNIT = 1000 ether;
    uint256 internal constant BOX_BOUNTY_ETH_TARGET = 15_000_000_000_000; // mirror of the module constant

    uint24 internal constant LVL = 50;
    uint8 internal constant DENOM = 2;
    uint8 internal constant SUB = 0;

    address internal keeper;
    address internal winnerA;
    address internal winnerB;

    function setUp() public {
        _deployProtocol();
        keeper = makeAddr("dec_keeper");
        winnerA = makeAddr("dec_winnerA");
        winnerB = makeAddr("dec_winnerB");
    }

    // ----------------------------------------------------------------------
    //                       storage-slot writers
    // ----------------------------------------------------------------------

    /// @dev decClaimRounds[lvl] = {uint96 poolWei | uint128 totalBurn | uint32 rngWord} (one slot).
    function _setClaimRound(
        uint24 lvl,
        uint96 poolWei,
        uint128 totalBurn,
        uint32 rngWord
    ) internal {
        bytes32 slot = keccak256(abi.encode(uint256(lvl), SLOT_DEC_CLAIM_ROUNDS));
        uint256 packed = uint256(poolWei) |
            (uint256(totalBurn) << 96) |
            (uint256(rngWord) << 224);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev decBucketOffsetPacked[lvl] winning subbucket for `denom` (4 bits at (denom-2)*4).
    function _setWinningSub(uint24 lvl, uint8 denom, uint8 sub) internal {
        bytes32 slot = keccak256(abi.encode(uint256(lvl), SLOT_DEC_OFFSET_PACKED));
        uint256 w = uint256(vm.load(address(game), slot));
        uint256 shift = uint256(denom - 2) * 4;
        w = (w & ~(uint256(0xF) << shift)) | (uint256(sub) << shift);
        vm.store(address(game), slot, bytes32(w));
    }

    /// @dev decBurn[lvl][player] = {uint192 burn | uint8 bucket | uint8 subBucket | uint8 claimed=0}.
    function _setEntry(
        uint24 lvl,
        address player,
        uint192 burn,
        uint8 bucket,
        uint8 sub
    ) internal {
        bytes32 inner = keccak256(abi.encode(uint256(lvl), SLOT_DEC_BURN));
        bytes32 slot = keccak256(abi.encode(player, uint256(inner)));
        uint256 packed = uint256(burn) |
            (uint256(bucket) << 192) |
            (uint256(sub) << 200);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Seed claimablePool (slot 1 high 128 bits) so the lootbox-portion debit cannot underflow.
    function _setClaimablePool(uint128 value) internal {
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_POOLS_1)));
        w = (w & ((uint256(1) << 128) - 1)) | (uint256(value) << 128);
        vm.store(address(game), bytes32(SLOT_POOLS_1), bytes32(w));
    }

    /// @dev Set the gameOver flag (slot 0, byte 21).
    function _setGameOver() internal {
        uint256 w = uint256(vm.load(address(game), bytes32(SLOT_HEADER)));
        w |= (uint256(1) << (21 * 8));
        vm.store(address(game), bytes32(SLOT_HEADER), bytes32(w));
    }

    /// @dev Install one winning entry whose pro-rata share is dust (< 0.01 ETH).
    ///      poolWei 0.01 ETH * burn 500 / totalBurn 1000 = 0.005 ETH share.
    function _installDustWinner(address player) internal {
        _setEntry(LVL, player, uint192(500 ether), DENOM, SUB);
    }

    function _expectedBounty(uint256 settled) internal view returns (uint256) {
        return (settled * BOX_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / game.mintPrice();
    }

    function _claim(address caller, address[] memory players) internal {
        vm.prank(caller);
        game.claimDecimatorJackpotMany(players, LVL);
    }

    function _one(address a) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = a;
    }

    // ----------------------------------------------------------------------
    //                              tests
    // ----------------------------------------------------------------------

    function test_LiveBatchClaimPaysOneBoxBountyPerSettledBox() public {
        _setClaimRound(LVL, uint96(0.01 ether), uint128(1000 ether), uint32(uint256(keccak256("dbr"))));
        _setWinningSub(LVL, DENOM, SUB);
        _setClaimablePool(1 ether);
        _installDustWinner(winnerA);

        uint256 before = coinflip.coinflipAmount(keeper);
        _claim(keeper, _one(winnerA));
        uint256 credited = coinflip.coinflipAmount(keeper) - before;

        uint256 expected = _expectedBounty(1);
        assertGt(expected, 0, "fixture: nonzero bounty");
        assertEq(credited, expected, "one settled box credits exactly one box-bounty to the keeper");

        // ETH-VALUE: the FLIP credit reimburses exactly the per-box ETH target at this price.
        assertEq(
            (credited * game.mintPrice()) / PRICE_COIN_UNIT,
            BOX_BOUNTY_ETH_TARGET,
            "bounty holds its ETH-reimbursement value across the price curve"
        );

        // FAUCET: far below the 500 FLIP the winner had to burn to be a box at all.
        assertLt(credited, 500 ether, "bounty << burn cost to manufacture a winning box");

        emit log_named_uint("dec_box_bounty_flip", credited);
        emit log_named_uint("mint_price", game.mintPrice());
    }

    function test_BountyScalesWithSettledBoxCount() public {
        _setClaimRound(LVL, uint96(0.01 ether), uint128(1000 ether), uint32(uint256(keccak256("dbr2"))));
        _setWinningSub(LVL, DENOM, SUB);
        _setClaimablePool(1 ether);
        _installDustWinner(winnerA);
        _installDustWinner(winnerB);

        address[] memory players = new address[](2);
        players[0] = winnerA;
        players[1] = winnerB;

        uint256 before = coinflip.coinflipAmount(keeper);
        _claim(keeper, players);
        uint256 credited = coinflip.coinflipAmount(keeper) - before;

        assertEq(credited, _expectedBounty(2), "two settled boxes credit exactly twice the per-box bounty");
    }

    function test_NoBountyForAlreadyClaimedOrNonWinner() public {
        _setClaimRound(LVL, uint96(0.01 ether), uint128(1000 ether), uint32(uint256(keccak256("dbr3"))));
        _setWinningSub(LVL, DENOM, SUB);
        _setClaimablePool(1 ether);
        // winnerA is in a LOSING subbucket (sub 1 != winning sub 0): not a winner, settles nothing.
        _setEntry(LVL, winnerA, uint192(500 ether), DENOM, 1);

        uint256 before = coinflip.coinflipAmount(keeper);
        _claim(keeper, _one(winnerA));
        assertEq(coinflip.coinflipAmount(keeper), before, "no settled box -> no bounty");
    }

    function test_NoBountyAfterGameOver() public {
        _setClaimRound(LVL, uint96(0.01 ether), uint128(1000 ether), uint32(uint256(keccak256("dbr4"))));
        _setWinningSub(LVL, DENOM, SUB);
        _installDustWinner(winnerA);
        _setGameOver(); // post-gameOver: winners settle into claimable, keeper earns no liveness bounty

        uint256 before = coinflip.coinflipAmount(keeper);
        _claim(keeper, _one(winnerA));
        assertEq(
            coinflip.coinflipAmount(keeper),
            before,
            "post-gameOver batch claim pays no keeper bounty"
        );
    }
}
