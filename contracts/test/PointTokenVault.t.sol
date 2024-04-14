// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PointTokenVault, PointTokenHub} from "../PointTokenVault.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {LibString} from "solady/utils/LibString.sol";

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract PointTokenVaultTest is Test {
    PointTokenHub PTHubSingleton = new PointTokenHub();
    PointTokenVault PTVSingleton = new PointTokenVault();

    PointTokenHub pointTokenHub;
    PointTokenVault pointTokenVault;

    MockERC20 token;
    MockERC20 rewardToken;

    address vitalik = makeAddr("vitalik");
    address toly = makeAddr("toly");
    address illia = makeAddr("illia");
    address admin = makeAddr("admin");

    function setUp() public {
        pointTokenHub = PointTokenHub(
            address(new ERC1967Proxy(address(PTHubSingleton), abi.encodeCall(PointTokenHub.initialize, ())))
        );
        pointTokenVault = PointTokenVault(
            address(
                new ERC1967Proxy(address(PTVSingleton), abi.encodeCall(PointTokenVault.initialize, (pointTokenHub)))
            )
        );

        pointTokenHub.setTrusted(address(pointTokenVault), true);

        pointTokenHub.transferOwnership(address(admin));
        pointTokenVault.transferOwnership(address(admin));

        // Deploy a mock token
        token = new MockERC20("Test Token", "TST", 18);
        rewardToken = new MockERC20("Reward Token", "RWT", 18);
    }

    function test_Sanity() public view {
        assertEq(address(pointTokenVault.pointTokenHub()), address(pointTokenHub));
    }

    function test_Deposit() public {
        token.mint(vitalik, 1.123e18);

        // Can deposit for yourself
        vm.startPrank(vitalik);
        token.approve(address(pointTokenVault), 1.123e18);
        pointTokenVault.deposit(token, 0.5e18, vitalik);
        vm.stopPrank();

        assertEq(token.balanceOf(vitalik), 0.623e18);
        assertEq(pointTokenVault.balances(vitalik, token), 0.5e18);

        // Can deposit for someone else
        vm.prank(vitalik);
        pointTokenVault.deposit(token, 0.623e18, toly);

        assertEq(token.balanceOf(vitalik), 0);
        assertEq(pointTokenVault.balances(toly, token), 0.623e18);
        assertEq(pointTokenVault.balances(vitalik, token), 0.5e18);
    }

    function test_Withdraw() public {
        token.mint(vitalik, 1.123e18);

        // Can withdraw for yourself
        vm.startPrank(vitalik);
        token.approve(address(pointTokenVault), 1.123e18);
        pointTokenVault.deposit(token, 1.123e18, vitalik);
        pointTokenVault.withdraw(token, 0.623e18, vitalik);
        vm.stopPrank();

        assertEq(token.balanceOf(vitalik), 0.623e18);
        assertEq(pointTokenVault.balances(vitalik, token), 0.5e18);

        // Can withdraw with a different receiver
        vm.prank(vitalik);
        pointTokenVault.withdraw(token, 0.5e18, toly);

        assertEq(token.balanceOf(vitalik), 0.623e18);
        assertEq(token.balanceOf(toly), 0.5e18);

        assertEq(pointTokenVault.balances(toly, token), 0);
        assertEq(pointTokenVault.balances(vitalik, token), 0);
    }

    function test_ProxyUpgrade() public {
        PointTokenHub newPointTokenHub = new PointTokenHub();
        PointTokenVault newPointTokenVault = new PointTokenVault();

        // Only admin can upgrade
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, vitalik));
        vm.prank(vitalik);
        pointTokenHub.upgradeToAndCall(address(newPointTokenHub), bytes(""));

        vm.prank(admin);
        pointTokenHub.upgradeToAndCall(address(newPointTokenHub), bytes(""));

        // Only admin can upgrade
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, vitalik));
        vm.prank(vitalik);
        pointTokenVault.upgradeToAndCall(address(newPointTokenVault), bytes(""));

        vm.prank(admin);
        pointTokenVault.upgradeToAndCall(address(newPointTokenVault), bytes(""));

        // Check that the state is still there
        assertEq(address(pointTokenVault.pointTokenHub()), address(pointTokenHub));
        // Check that the implementation is updated
        address implementation = address(
            uint160(
                uint256(
                    vm.load(
                        address(pointTokenVault),
                        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc // eip1967 implementation slot
                    )
                )
            )
        );

        assertEq(address(newPointTokenVault), implementation);
    }

    function test_UpdateRoot() public {
        bytes32 root = 0x5842148bc6ebeb52af882a317c765fccd3ae80589b21a9b8cbf21abb630e46a7;

        // Only admin can update root
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, vitalik));
        vm.prank(vitalik);
        pointTokenVault.updateRoot(root, bytes32("1"));

        // Update the root
        vm.prank(admin);
        pointTokenVault.updateRoot(root, bytes32("1"));

        // todo: can't submit bytes32(0)
    }

    function test_ExecuteAuth(address lad) public {
        vm.assume(lad != admin);
        // Only admin can exec
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, lad));
        vm.prank(lad);
        pointTokenVault.execute(vitalik, bytes(""), 0);
    }

    event EchoEvent(string message, address caller);

    function test_Execute() public {
        Echo echo = new Echo();
        CallEcho callEcho = new CallEcho();

        uint256 GAS_LIMIT = 1e9;

        // Execute a simple call
        vm.prank(admin);

        vm.expectEmit(true, true, true, true);
        emit EchoEvent("Hello", address(pointTokenVault));
        pointTokenVault.execute(
            address(callEcho), abi.encodeWithSelector(CallEcho.callEcho.selector, echo, "Hello"), GAS_LIMIT
        );
    }

    function test_Distribution() public {
        // Merkle tree created from leaves [keccack(vitalik, pointsId, 1e18), keccack(toly, pointsId, 0.5e18)].
        bytes32[] memory goodProof = new bytes32[](1);
        goodProof[0] = 0x6d0fcb8de12b1f57f81e49fa18b641487b932cdba4f064409fde3b05d3824ca2;
        bytes32 root = 0x4e40a10ce33f33a4786960a8bb843fe0e170b651acd83da27abc97176c4bed3c;

        bytes32[] memory badProof = new bytes32[](1);
        badProof[0] = 0x6d06cb8de12b1f57f81e49fa18b641487b932cdba4f064409fde3b05d3824ca2;

        PointTokenVault.Claim[] memory claims = new PointTokenVault.Claim[](1);

        bytes32 pointsId = LibString.packTwo("Eigen Layer Point", "pEL");

        vm.prank(admin);
        pointTokenVault.updateRoot(root, pointsId);

        // Can't claim with the wrong proof
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, badProof);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        pointTokenVault.claimPointTokens(claims, vitalik);

        // Can't claim with the wrong claimable amount
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(pointsId, 0.9e18, goodProof);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        pointTokenVault.claimPointTokens(claims, vitalik);

        // Can't claim with the wrong pointsId
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(bytes32("123"), 1e18, goodProof);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        pointTokenVault.claimPointTokens(claims, vitalik);

        // Can claim with the right proof
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, goodProof);
        pointTokenVault.claimPointTokens(claims, vitalik);

        assertEq(pointTokenHub.pointTokens(pointsId).balanceOf(vitalik), 1e18);

        // Can't use the same proof twice
        vm.expectRevert(PointTokenVault.AlreadyClaimed.selector);
        pointTokenVault.claimPointTokens(claims, vitalik);
    }

    function test_DistributionTwoRecipients() public {
        bytes32 pointsId = LibString.packTwo("Eigen Layer Point", "pEL");

        // Merkle tree created from leaves [keccack(vitalik, pointsId, 1e18), keccack(toly, pointsId, 0.5e18)].
        bytes32 root = 0x4e40a10ce33f33a4786960a8bb843fe0e170b651acd83da27abc97176c4bed3c;

        vm.prank(admin);
        pointTokenVault.updateRoot(root, pointsId);

        bytes32[] memory vitalikProof = new bytes32[](1);
        vitalikProof[0] = 0x6d0fcb8de12b1f57f81e49fa18b641487b932cdba4f064409fde3b05d3824ca2;

        PointTokenVault.Claim[] memory claims = new PointTokenVault.Claim[](1);

        // Vitalik can claim
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, vitalikProof);
        pointTokenVault.claimPointTokens(claims, vitalik);

        assertEq(pointTokenHub.pointTokens(pointsId).balanceOf(vitalik), 1e18);

        bytes32[] memory tolyProof = new bytes32[](1);
        tolyProof[0] = 0x77ec2184ee10de8d8164b15f7f9e734a985dbe8a49e28feb2793ab17c9ed215c;

        // Illia can execute toly's claim, but can only send the tokens to toly
        vm.prank(illia);
        claims[0] = PointTokenVault.Claim(pointsId, 0.5e18, tolyProof);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        pointTokenVault.claimPointTokens(claims, illia);

        pointTokenVault.claimPointTokens(claims, toly);

        assertEq(pointTokenHub.pointTokens(pointsId).balanceOf(toly), 0.5e18);
    }

    function test_SimpleRedemption() public {
        bytes32 pointsId = LibString.packTwo("Eigen Layer Point", "pEL");
        bytes32 root = 0x4e40a10ce33f33a4786960a8bb843fe0e170b651acd83da27abc97176c4bed3c;

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x6d0fcb8de12b1f57f81e49fa18b641487b932cdba4f064409fde3b05d3824ca2;

        vm.prank(admin);
        pointTokenVault.updateRoot(root, pointsId);

        PointTokenVault.Claim[] memory claims = new PointTokenVault.Claim[](1);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, proof);

        vm.prank(vitalik);
        pointTokenVault.claimPointTokens(claims, vitalik);

        // todo: before the rewards come in

        rewardToken.mint(address(pointTokenVault), 3e18);

        vm.prank(admin);
        pointTokenHub.setRedemption(pointsId, rewardToken, 2e18, false);

        bytes32[] memory empty = new bytes32[](0);
        vm.prank(vitalik);
        pointTokenVault.redeemRewards(PointTokenVault.Claim(pointsId, 1e18, empty), vitalik);

        assertEq(rewardToken.balanceOf(vitalik), 2e18);
    }

    // additional tests:
    // simple redemption
    // implementation is locked down
    // fuzz deposit/withdraw/claim
    // redemption rights
    // only msg.sender can use redemption rights
    // must have point token to use redemption rights
    // can set receiver for reward redemption
    // Test distribution with multiple tokens
    // Test distribution with multiple receivers
    // Test distribution with multiple tokens and multiple receivers
}

contract Echo {
    event EchoEvent(string message, address caller);

    function echo(string calldata message) public {
        emit EchoEvent(message, msg.sender);
    }
}

contract CallEcho {
    function callEcho(Echo echo, string calldata message) public {
        echo.echo(message);
    }
}
