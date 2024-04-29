pragma solidity ^0.8.13;

import {Test, console, console2} from "forge-std/Test.sol";

import {MockPointTokenVault} from "../../mock/MockPointTokenVault.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {LibString} from "solady/utils/LibString.sol";

contract PointTokenVaultHandler is Test {
    MockPointTokenVault public pointTokenVault;

    MockERC20[10] pointEarningTokens = [
        new MockERC20("Test Token", "TST", 18),
        new MockERC20("Test Token", "TST", 18),
        new MockERC20("Test Token", "TST", 18),
        new MockERC20("Test Token", "TST", 18),
        new MockERC20("Test Token", "TST", 18),
        new MockERC20("Test Token", "TST", 18),
        new MockERC20("Test Token", "TST", 18),
        new MockERC20("Test Token", "TST", 18),
        new MockERC20("Test Token", "TST", 18),
        new MockERC20("Test Token", "TST", 18)
    ];

    bytes32[10] pointsIds = [
        LibString.packTwo("First", "test"),
        LibString.packTwo("Second", "test"),
        LibString.packTwo("Third", "test"),
        LibString.packTwo("Fourth", "test"),
        LibString.packTwo("Fifth", "test"),
        LibString.packTwo("Sixth", "test"),
        LibString.packTwo("Seventh", "test"),
        LibString.packTwo("Eighth", "test"),
        LibString.packTwo("Ninth", "test"),
        LibString.packTwo("Tenth", "test")
    ];

    address public currentActor;

    struct Actor {
        address addr;
        uint256 key;
    }

    Actor[] public actors;
    Actor[] public dsts;
    Actor internal actor;

    bytes32[] internal expectedErrors;

    mapping(address => mapping(address => uint256)) pointEarningTokenGhosts;
    mapping(address => mapping(bytes32 => uint256)) claimedPTokensGhosts;

    modifier useRandomActor(uint256 _actorIndex) {
        actor = _selectActor(_actorIndex);
        vm.stopPrank();
        vm.startPrank(actor.addr);
        _;
        delete actor;
        vm.stopPrank();
    }

    modifier resetErrors() {
        _;
        delete expectedErrors;
    }

    constructor(
        MockPointTokenVault pointTokenVault_,
        address[3] memory admins
    ) {
        pointTokenVault = pointTokenVault_;

        vm.prank(admins[1]);
        pointTokenVault.setIsCapped(false);

        for (uint256 i = 0; i < admins.length; i++) {
            Actor memory _actor;
            _actor.addr = admins[i];
            _actor.key = 0;
            actors.push(_actor);
            dsts.push(_actor);
        }

        for (uint256 j = 0; j < 10; j++) {
            Actor memory _actor;
            (_actor.addr, _actor.key) = makeAddrAndKey(string(abi.encodePacked("Actor", vm.toString(j))));
            actors.push(_actor);
            dsts.push(_actor);
        }

        Actor memory zero;
        (zero.addr, zero.key) = makeAddrAndKey(string(abi.encodePacked("Zero")));
        zero.addr = address(0);
        dsts.push(zero);

        for (uint256 k = 0; k < pointsIds.length; k++) {
            pointTokenVault.deployPToken(pointsIds[k]);
        }
    }

    function deposit(
        uint256 actorIndex,
        uint256 dstIndex,
        uint256 amount,
        uint256 tokenIndex
    ) public useRandomActor(actorIndex) {
        actorIndex = bound(actorIndex, 0, 12);
        dstIndex = bound(dstIndex, 0, 12);
        amount = bound(amount, 0, 100000 * 1e18);
        tokenIndex = bound(tokenIndex, 0, 9);

        MockERC20 token = pointEarningTokens[tokenIndex];

        token.mint(currentActor, amount);
        token.approve(address(pointTokenVault), amount);

        uint256 depositorBalanceBefore = token.balanceOf(currentActor);
        uint256 receiverBalanceBefore = pointTokenVault.balances(actors[dstIndex].addr, token);

        try pointTokenVault.deposit(token, amount, actors[dstIndex].addr) {
            uint256 depositorBalanceAfter = token.balanceOf(currentActor);
            uint256 receiverBalanceAfter = pointTokenVault.balances(actors[dstIndex].addr, token);

            pointEarningTokenGhosts[actors[dstIndex].addr][address(token)] += amount;

            assertEq(depositorBalanceBefore - depositorBalanceAfter, amount);
            assertEq(receiverBalanceAfter - receiverBalanceBefore, amount);
        } catch (bytes memory reason) {
            console.log("Unexpected revert: deposit failed!");
            console.logBytes(reason);
        }
    }

    function withdraw(
        uint256 actorIndex,
        uint256 dstIndex,
        uint256 amount,
        uint256 tokenIndex
    ) public useRandomActor(actorIndex) {
        actorIndex = bound(actorIndex, 0, 12);
        dstIndex = bound(dstIndex, 0, 12);
        amount = bound(amount, 0, 100000 * 1e18);
        tokenIndex = bound(tokenIndex, 0, 9);

        MockERC20 token = pointEarningTokens[tokenIndex];

        token.mint(currentActor, amount);
        token.approve(address(pointTokenVault), amount);
        pointTokenVault.deposit(token, amount, currentActor);
        pointEarningTokenGhosts[currentActor][address(token)] += amount;

        uint256 actorBalanceBefore = pointTokenVault.balances(currentActor, token);
        uint256 receiverBalanceBefore = token.balanceOf(actors[dstIndex].addr);

        try pointTokenVault.withdraw(token, amount, actors[dstIndex].addr) {
            uint256 actorBalanceAfter = pointTokenVault.balances(currentActor, token);
            uint256 receiverBalanceAfter = token.balanceOf(actors[dstIndex].addr);

            pointEarningTokenGhosts[currentActor][address(token)] -= amount;

            assertEq(actorBalanceBefore - actorBalanceAfter, amount);
            assertEq(receiverBalanceAfter - receiverBalanceBefore, amount);
        } catch (bytes memory reason) {
            console.log("Unexpected revert: withdraw failed!");
            console.logBytes(reason);
        }
    }

    function claimPTokens(
        uint256 actorIndex,
        uint256 dstIndex,
        uint256 idIndex,
        uint256 totalClaimable,
        uint256 amount
    ) public useRandomActor(actorIndex) {
        actorIndex = bound(actorIndex, 0, 12);
        dstIndex = bound(dstIndex, 0, 12);
        totalClaimable = bound(totalClaimable, 0, 100000 * 1e18);
        amount = bound(amount, 0, 100000 * 1e18);
        idIndex = bound(idIndex, 0, 9);

        bytes32[] memory emptyProof = new bytes32[](0);

        MockPointTokenVault.Claim memory claim = MockPointTokenVault.Claim(
            pointsIds[idIndex],
            totalClaimable,
            amount,
            emptyProof
        );

        uint256 pTokenBalanceBefore = pointTokenVault.pTokens(pointsIds[idIndex]).balanceOf(actors[dstIndex].addr);
        uint256 claimedBalanceBefore = pointTokenVault.claimedPTokens(actors[dstIndex].addr, pointsIds[idIndex]);

        try pointTokenVault.claimPTokens(claim, actors[dstIndex].addr) {
            uint256 pTokenBalanceAfter = pointTokenVault.pTokens(pointsIds[idIndex]).balanceOf(actors[dstIndex].addr);
            uint256 claimedBalanceAfter = pointTokenVault.claimedPTokens(actors[dstIndex].addr, pointsIds[idIndex]);

            claimedPTokensGhosts[actors[dstIndex].addr][pointsIds[idIndex]] += amount;

            assertEq(pTokenBalanceAfter - pTokenBalanceBefore, amount);
            assertEq(claimedBalanceAfter - claimedBalanceBefore, amount);
        } catch (bytes memory reason) {
            if (totalClaimable < claimedBalanceBefore + amount) {
                console.log("Expected revert: totalClaimable < amount");
                assertEq(bytes4(reason), MockPointTokenVault.ClaimTooLarge.selector);
            } else {
                console.log("Unexpected revert: claim failed!");
                console.logBytes(reason);
            }
        }
    }

    // Helper functions ---
    function checkPointEarningTokenGhosts() public view returns (bool) {
        for (uint256 i; i < actors.length; i++) {
            for (uint256 j; j < pointEarningTokens.length; j++) {
                if (
                    pointEarningTokenGhosts[actors[i].addr][address(pointEarningTokens[j])]
                        != pointTokenVault.balances(actors[i].addr, pointEarningTokens[j])
                ) {
                    console.log("Ghost balance:", pointEarningTokenGhosts[actors[i].addr][address(pointEarningTokens[j])]);
                    console.log("Balance according to contract:", pointTokenVault.balances(actors[i].addr, pointEarningTokens[j]));

                    return false;
                }
            }
        }

        return true;
    }

    function checkClaimedPTokensGhosts() public view returns (bool) {
        for (uint i; i < actors.length; i++) {
            for (uint256 j; j < pointsIds.length; j++) {
                if (
                    claimedPTokensGhosts[actors[i].addr][pointsIds[j]]
                        != pointTokenVault.claimedPTokens(actors[i].addr, pointsIds[j])
                ) {
                    console.log("Ghost balance:", claimedPTokensGhosts[actors[i].addr][pointsIds[j]]);
                    console.log("Balance according to contract:", pointTokenVault.claimedPTokens(actors[i].addr, pointsIds[j]));

                    return false;
                }
            }
        }

        return true;
    }

    function checkSumOfPTokenBalances() public view returns (bool) {
        uint256 sumOfBalances;    
        for (uint256 i; i < pointsIds.length; i++) {
            sumOfBalances = 0;
            for (uint256 j; j < actors.length; j++) {
                sumOfBalances += claimedPTokensGhosts[actors[j].addr][pointsIds[i]];
            }

            if (sumOfBalances != pointTokenVault.pTokens(pointsIds[i]).totalSupply()) {
                console.log("PToken index:", i);
                console.log("Sum of balances:", sumOfBalances);

                return false;
            }
        }

        return true;
    }

    function _selectActor(uint256 _actorIndex) internal returns (Actor memory actor_) {
        uint256 index = bound(_actorIndex, 0, actors.length - 1);
        currentActor = actors[index].addr;
        actor_ = actors[index];
    }
}