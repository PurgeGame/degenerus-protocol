// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Coinflip} from "../../contracts/Coinflip.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {QaTrace} from "../helpers/QaTrace.sol";

contract XaReentrantGift {
    function deposit(uint32 id) external { Coinflip(ContractAddresses.COINFLIP).depositCoinflip(id,1000); }
}

contract XaCallbackSnapshot {
    address private immutable original;
    address private immutable player;
    uint32 private immutable id;
    address private immutable gift;
    bytes32 private constant ENTERED=keccak256("xa.test.callback.entered");
    constructor(address impl,address p,uint32 key,address gift_) { original=impl;player=p;id=key;gift=gift_; }
    fallback() external payable {
        if (msg.sig == bytes4(keccak256("consumeCoinflipBoon_g2902(uint32)"))) {
            require(msg.sender==ContractAddresses.COINFLIP,"callback sender");
            (,bool done)=Coinflip(ContractAddresses.COINFLIP).questCompletionToday(id);
            require(done,"quest completion visible at callback");
            require(FLIP(ContractAddresses.COIN).balanceOf(player)==8000,"funding already burned");
            require(Coinflip(ContractAddresses.COINFLIP).coinflipAmountById(id)==0,"deposit not yet banked");
            bytes32 guard=ENTERED;bool entered;
            assembly ("memory-safe") { entered := tload(guard) }
            if (gift!=address(0) && !entered) {
                assembly ("memory-safe") { tstore(guard,1) }
                XaReentrantGift(gift).deposit(id);
                require(FLIP(ContractAddresses.COIN).balanceOf(gift)==0,"gift burns its own funds");
                require(Coinflip(ContractAddresses.COINFLIP).coinflipAmountById(id)==1000,"reentry cannot repeat quest reward");
            }
            assembly ("memory-safe") { mstore(0,0) return(0,32) }
        }
        address impl=original;
        assembly ("memory-safe") {
            calldatacopy(0,0,calldatasize())
            let ok:=delegatecall(gas(),impl,0,calldatasize(),0,0)
            returndatacopy(0,0,returndatasize())
            switch ok case 0 { revert(0,returndatasize()) } default { return(0,returndatasize()) }
        }
    }
}

contract XaInitializationAndRollbackTest is DeployProtocol {
    address private constant PLAYER=address(0xA110CE);
    function setUp() public { _deployProtocol(); }
    function _root(string memory id) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(uint256(keccak256(bytes(id)))-1))) & ~uint256(255));
    }
    function test_NamespaceRootsInitializationAndRetiredAddresses() public {
        assertEq(_root("degenerus.storage.quests.v1"),bytes32(QaTrace.QUESTS));
        assertEq(_root("degenerus.storage.affiliate.v1"),bytes32(QaTrace.AFFILIATE));
        assertEq(address(quests),address(coinflip));assertEq(address(affiliate),address(coinflip));
        assertEq(vm.computeCreateAddress(address(this),11).code.length,0,"retired coinflip address");
        assertEq(vm.computeCreateAddress(address(this),15).code.length,0,"retired quests address");
        uint256 active=uint256(vm.load(address(coinflip),bytes32(QaTrace.QUESTS)));
        assertEq(uint8(active>>128),1);assertEq(uint8(active>>136),1);
        assertEq(uint8(active>>24),1);assertEq(uint8(active>>88),7);
        (,uint32 vaultId,)=affiliate.affiliateCode(bytes32("VAULT"));
        (,uint32 sdgnrsId,)=affiliate.affiliateCode(bytes32("DGNRS"));
        assertEq(vaultId,1);assertEq(sdgnrsId,2);
        for(uint256 i;i<4;++i) {
            bytes4 sel=i==0?bytes4(keccak256("initializeXa()")):i==1?bytes4(keccak256("_questCreditFlip(uint32,uint256)")):i==2?bytes4(keccak256("_handleFlip(uint32,uint256)")):bytes4(keccak256("_affiliateCreditFlip(uint32,uint256)"));
            (bool ok,)=address(coinflip).call(abi.encodeWithSelector(sel,uint32(4),uint256(1000000)));
            assertFalse(ok,"internal helper exposed");
        }
    }
    function _ready() private returns (uint32 id,bytes32 stateSlot) {
        vm.prank(address(coinflip));id=game.registerWallet_g9539(PLAYER,true);
        vm.prank(address(game));coin.mintForGame(PLAYER,10000);
        uint256 day=GameTimeLib.currentDayIndexAt(vm.getBlockTimestamp());
        vm.store(address(coinflip),bytes32(QaTrace.QUESTS),bytes32((day|(1<<24))|((day|(2<<24))<<64)));
        stateSlot=keccak256(abi.encode(uint256(id),QaTrace.QUESTS+1));
        vm.store(address(coinflip),stateSlot,bytes32(day|(day<<24)|(day<<48)|(5<<72)|(5<<88)|(uint256(1)<<192)));
    }
    function test_RewardCallbackFailureRollsBackFundingQuestAndStakeThenRetriesOnce() public {
        (uint32 id,bytes32 slot)=_ready();bytes32 before_=vm.load(address(coinflip),slot);
        vm.mockCallRevert(address(game),abi.encodeWithSignature("consumeCoinflipBoon_g2902(uint32)",id),hex"deadbeef");
        vm.expectRevert(bytes4(0xdeadbeef));vm.prank(PLAYER);coinflip.depositCoinflip(0,2000);
        assertEq(coin.balanceOf(PLAYER),10000);assertEq(vm.load(address(coinflip),slot),before_);
        assertEq(coinflip.coinflipAmountById(id),0);
        vm.clearMockedCalls();vm.prank(PLAYER);coinflip.depositCoinflip(0,2000);
        assertEq(coin.balanceOf(PLAYER),8000);assertEq(coinflip.coinflipAmountById(id),2100);
        vm.prank(PLAYER);coinflip.depositCoinflip(0,2000);
        assertEq(coin.balanceOf(PLAYER),6000);assertEq(coinflip.coinflipAmountById(id),4100);
    }
    function test_FormerCallbackBoundarySeesFundingAndCompletedQuestBeforeStake() public {
        (uint32 id,)=_ready();bytes memory code=address(game).code;address saved=address(0xDA7A);
        vm.etch(saved,code);XaCallbackSnapshot probe=new XaCallbackSnapshot(saved,PLAYER,id,address(0));
        vm.etch(address(game),address(probe).code);
        vm.prank(PLAYER);coinflip.depositCoinflip(0,2000);
        vm.etch(address(game),code);
        assertEq(coinflip.coinflipAmountById(id),2100);
    }
    function test_ReentrantGiftUsesGiversFundsAndCannotRepeatCompletedQuest() public {
        (uint32 id,)=_ready();XaReentrantGift gift=new XaReentrantGift();
        vm.prank(address(game));coin.mintForGame(address(gift),1000);
        bytes memory code=address(game).code;address saved=address(0xDA7A);vm.etch(saved,code);
        XaCallbackSnapshot probe=new XaCallbackSnapshot(saved,PLAYER,id,address(gift));
        vm.etch(address(game),address(probe).code);
        vm.prank(PLAYER);coinflip.depositCoinflip(0,2000);
        vm.etch(address(game),code);
        assertEq(coin.balanceOf(PLAYER),8000);assertEq(coin.balanceOf(address(gift)),0);
        assertEq(coinflip.coinflipAmountById(id),3100,"one 100 FLIP quest reward across both deposits");
    }

}
