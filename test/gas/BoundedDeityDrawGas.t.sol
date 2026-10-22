// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {BoundedDeployProtocol} from "../helpers/BoundedDeployProtocol.sol";
import {BoundedGasProbe} from "../helpers/BoundedGasProbe.sol";
import {CoinflipStorage} from "../helpers/CoinflipStorage.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

contract BoundedDeityDrawHost is DegenerusGame, BucketSeed {
    function seed(bool deities) external {
        uint24 day = _simulatedDayIndex();
        dailyIdx = day - 1;
        level = 0;
        _setLevelPrizePool(0, (12_500 * PriceLookupLib.priceForLevel(level) * 400) / PRICE_COIN_UNIT);
        uint32 traits;
        for (uint8 q; q < 4; ++q) {
            uint8 trait = q * 64 + 1;
            traits |= uint32(trait) << (q * 8);
            _seedBucket(1, trait, address(uint160(0xA000 + q)), 4);
            if (deities) deityBySymbol[q * 8 + 1] = _seedWallet(address(uint160(0xD000 + q)));
        }
        dailyFoilDraw[day & 1] = _packFoilDraw(traits, 1, day, 0xCAFE);
    }
    function draw() external {
        (bool ok, bytes memory result) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall(
            abi.encodeWithSignature("payDailyFlipJackpot(uint24,uint256,uint24,uint24)", uint24(1), uint256(0xCAFE), uint24(1), uint24(1)));
        if (!ok) assembly ("memory-safe") { revert(add(result,32),mload(result)) }
    }
}
contract BoundedDeityDrawGasTest is BoundedDeployProtocol, BoundedGasProbe {
    function _run(string memory label, bool deities, bool repeat) private {
        _deployBounded(true);
        vm.warp(block.timestamp + 3 days);
        vm.etch(address(game), vm.getDeployedCode("BoundedDeityDrawGas.t.sol:BoundedDeityDrawHost"));
        BoundedDeityDrawHost host = BoundedDeityDrawHost(payable(address(game)));
        host.seed(deities);
        if (repeat) host.draw();
        _measureBounded(label, address(host), address(this), 0, abi.encodeCall(host.draw, ()), false);
        uint256 total;
        uint24 day = game.currentDayView() + 1;
        for (uint8 q; q < 4; ++q) {
            total += CoinflipStorage.read(address(coinflip), game.walletIdOf(address(uint160(0xA000 + q))), day);
            if (deities) total += CoinflipStorage.read(address(coinflip), game.walletIdOf(address(uint160(0xD000 + q))), day);
        }
        assertEq(total, repeat ? 20_000 : 10_000, "50 equal production FLIP awards per draw");
    }
    function test_G4_FourTraitDrawEmptyDeities() public { _run("G4_draw_empty", false, false); }
    function test_G4_FourTraitDrawPopulatedDeities() public { _run("G4_draw_full", true, false); }
    function test_G4_FourTraitDrawExistingStakes() public { _run("G4_draw_existing", true, true); }
}
