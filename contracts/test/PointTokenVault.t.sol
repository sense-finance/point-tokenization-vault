// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PointTokenVault} from "../PointTokenVault.sol";
import {PointTokenHub} from "../PointTokenHub.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {LibString} from "solady/utils/LibString.sol";

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract PointTokenVaultTest is Test {
    PointTokenHub PTHubSingleton = new PointTokenHub();
    PointTokenVault PTVSingleton = new PointTokenVault();

    PointTokenHub pointTokenHub;
    PointTokenVault pointTokenVault;

    MockERC20 pointEarningToken;
    MockERC20 rewardToken;

    address vitalik = makeAddr("vitalik");
    address toly = makeAddr("toly");
    address illia = makeAddr("illia");
    address admin = makeAddr("admin");
    address merkleUpdater = makeAddr("merkleUpdater");

    function setUp() public {
        pointTokenHub = PointTokenHub(
            address(new ERC1967Proxy(address(PTHubSingleton), abi.encodeCall(PointTokenHub.initialize, ())))
        );
        pointTokenVault = PointTokenVault(
            address(
                new ERC1967Proxy(address(PTVSingleton), abi.encodeCall(PointTokenVault.initialize, (pointTokenHub)))
            )
        );

        pointTokenHub.grantRole(pointTokenHub.DEFAULT_ADMIN_ROLE(), address(admin));
        pointTokenHub.grantRole(pointTokenHub.MINT_BURN_ROLE(), address(pointTokenVault));

        pointTokenVault.grantRole(pointTokenVault.DEFAULT_ADMIN_ROLE(), address(admin));
        pointTokenVault.grantRole(pointTokenVault.MERKLE_UPDATER_ROLE(), address(merkleUpdater));

        // Deploy a mock token
        pointEarningToken = new MockERC20("Test Token", "TST", 18);
        rewardToken = new MockERC20("Reward Token", "RWT", 18);
    }

    function test_Sanity() public view {
        assertEq(address(pointTokenVault.pointTokenHub()), address(pointTokenHub));
    }

    function test_Deposit() public {
        pointEarningToken.mint(vitalik, 1.123e18);

        // Can deposit for yourself
        vm.startPrank(vitalik);
        pointEarningToken.approve(address(pointTokenVault), 1.123e18);
        pointTokenVault.deposit(pointEarningToken, 0.5e18, vitalik);
        vm.stopPrank();

        assertEq(pointEarningToken.balanceOf(vitalik), 0.623e18);
        assertEq(pointTokenVault.balances(vitalik, pointEarningToken), 0.5e18);

        // Can deposit for someone else
        vm.prank(vitalik);
        pointTokenVault.deposit(pointEarningToken, 0.623e18, toly);

        assertEq(pointEarningToken.balanceOf(vitalik), 0);
        assertEq(pointTokenVault.balances(toly, pointEarningToken), 0.623e18);
        assertEq(pointTokenVault.balances(vitalik, pointEarningToken), 0.5e18);
    }

    function test_Withdraw() public {
        pointEarningToken.mint(vitalik, 1.123e18);

        // Can withdraw for yourself
        vm.startPrank(vitalik);
        pointEarningToken.approve(address(pointTokenVault), 1.123e18);
        pointTokenVault.deposit(pointEarningToken, 1.123e18, vitalik);
        pointTokenVault.withdraw(pointEarningToken, 0.623e18, vitalik);
        vm.stopPrank();

        assertEq(pointEarningToken.balanceOf(vitalik), 0.623e18);
        assertEq(pointTokenVault.balances(vitalik, pointEarningToken), 0.5e18);

        // Can withdraw with a different receiver
        vm.prank(vitalik);
        pointTokenVault.withdraw(pointEarningToken, 0.5e18, toly);

        assertEq(pointEarningToken.balanceOf(vitalik), 0.623e18);
        assertEq(pointEarningToken.balanceOf(toly), 0.5e18);

        assertEq(pointTokenVault.balances(toly, pointEarningToken), 0);
        assertEq(pointTokenVault.balances(vitalik, pointEarningToken), 0);
    }

    function test_ProxyUpgrade() public {
        PointTokenHub newPointTokenHub = new PointTokenHub();
        PointTokenVault newPointTokenVault = new PointTokenVault();

        // Only admin can upgrade
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, vitalik, pointTokenHub.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(vitalik);
        pointTokenHub.upgradeToAndCall(address(newPointTokenHub), bytes(""));

        vm.prank(admin);
        pointTokenHub.upgradeToAndCall(address(newPointTokenHub), bytes(""));

        // Only admin role can upgrade
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, vitalik, pointTokenVault.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(vitalik);
        pointTokenVault.upgradeToAndCall(address(newPointTokenVault), bytes(""));

        vm.prank(admin);
        pointTokenVault.upgradeToAndCall(address(newPointTokenVault), bytes(""));

        // Check that the state is still there.
        assertEq(address(pointTokenVault.pointTokenHub()), address(pointTokenHub));
        // Check that the implementation has been updated.
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

        // Only merkle root updater role can update root
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, vitalik, pointTokenVault.MERKLE_UPDATER_ROLE()
            )
        );
        vm.prank(vitalik);
        pointTokenVault.updateRoot(root);

        // Update the root
        vm.prank(merkleUpdater);
        pointTokenVault.updateRoot(root);
    }

    function test_ExecuteAuth(address lad) public {
        vm.assume(lad != admin);
        // Only admin can exec
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, lad, pointTokenVault.DEFAULT_ADMIN_ROLE()
            )
        );
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

        vm.prank(merkleUpdater);
        pointTokenVault.updateRoot(root);

        // Can't claim with the wrong proof
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, 1e18, badProof);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        pointTokenVault.claimPointTokens(claims, vitalik);

        // Can't claim with the wrong claimable amount
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(pointsId, 0.9e18, 0.9e18, goodProof);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        pointTokenVault.claimPointTokens(claims, vitalik);

        // Can't claim with the wrong pointsId
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(bytes32("123"), 1e18, 1e18, goodProof);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        pointTokenVault.claimPointTokens(claims, vitalik);

        // Can claim with the right proof
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, 1e18, goodProof);
        pointTokenVault.claimPointTokens(claims, vitalik);

        assertEq(pointTokenHub.pointTokens(pointsId).balanceOf(vitalik), 1e18);

        // Can't use the same proof twice
        vm.expectRevert(PointTokenVault.ClaimTooLarge.selector);
        pointTokenVault.claimPointTokens(claims, vitalik);
    }

    function test_DistributionTwoRecipients() public {
        bytes32 pointsId = LibString.packTwo("Eigen Layer Point", "pEL");

        // Merkle tree created from leaves [keccack(vitalik, pointsId, 1e18), keccack(toly, pointsId, 0.5e18)].
        bytes32 root = 0x4e40a10ce33f33a4786960a8bb843fe0e170b651acd83da27abc97176c4bed3c;

        vm.prank(merkleUpdater);
        pointTokenVault.updateRoot(root);

        bytes32[] memory vitalikProof = new bytes32[](1);
        vitalikProof[0] = 0x6d0fcb8de12b1f57f81e49fa18b641487b932cdba4f064409fde3b05d3824ca2;

        PointTokenVault.Claim[] memory claims = new PointTokenVault.Claim[](1);

        // Vitalik can claim
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, 1e18, vitalikProof);
        pointTokenVault.claimPointTokens(claims, vitalik);

        assertEq(pointTokenHub.pointTokens(pointsId).balanceOf(vitalik), 1e18);

        bytes32[] memory tolyProof = new bytes32[](1);
        tolyProof[0] = 0x77ec2184ee10de8d8164b15f7f9e734a985dbe8a49e28feb2793ab17c9ed215c;

        // Illia can execute toly's claim, but can only send the tokens to toly
        vm.prank(illia);
        claims[0] = PointTokenVault.Claim(pointsId, 0.5e18, 0.5e18, tolyProof);
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

        vm.prank(merkleUpdater);
        pointTokenVault.updateRoot(root);

        PointTokenVault.Claim[] memory claims = new PointTokenVault.Claim[](1);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, 1e18, proof);

        vm.prank(vitalik);
        pointTokenVault.claimPointTokens(claims, vitalik);

        rewardToken.mint(address(pointTokenVault), 3e18);

        vm.prank(admin);
        pointTokenHub.setRedemption(pointsId, rewardToken, 2e18, false);

        bytes32[] memory empty = new bytes32[](0);
        vm.prank(vitalik);
        pointTokenVault.redeemRewards(PointTokenVault.Claim(pointsId, 2e18, 2e18, empty), vitalik);

        assertEq(rewardToken.balanceOf(vitalik), 2e18);
    }

    event RewardsClaimed(address indexed owner, address indexed receiver, bytes32 indexed pointsId, uint256 amount);

    function test_MerkleBasedRedemption() public {
        bytes32 pointsId = LibString.packTwo("Eigen Layer Point", "pEL");
        bytes32 root = 0x409fd0e46d8453765fb513ae35a1899d667478c40233b67360023c86927eb802;

        bytes32[] memory validProofVitalikPToken = new bytes32[](2);
        validProofVitalikPToken[0] = 0x6d0fcb8de12b1f57f81e49fa18b641487b932cdba4f064409fde3b05d3824ca2;
        validProofVitalikPToken[1] = 0xae126f1299213c869259b52ab24f7270f3cce1de54c187271c52373d8947c2fe;

        // Set up the Merkle root and redemption parameters
        vm.prank(merkleUpdater);
        pointTokenVault.updateRoot(root);
        vm.prank(admin);
        pointTokenHub.setRedemption(pointsId, rewardToken, 2e18, true); // Set isMerkleBased true

        // Mint tokens and distribute
        vm.prank(admin);
        rewardToken.mint(address(pointTokenVault), 5e18); // Ensure enough rewards are in the vault

        PointTokenVault.Claim[] memory claims = new PointTokenVault.Claim[](1);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, 1e18, validProofVitalikPToken);

        // Vitalik redeems with a valid proof
        vm.prank(vitalik);
        pointTokenVault.claimPointTokens(claims, vitalik);

        // Must use a merkle proof to redeem rewards
        bytes32[] memory empty = new bytes32[](0);
        vm.prank(vitalik);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        pointTokenVault.redeemRewards(PointTokenVault.Claim(pointsId, 2e18, 2e18, empty), vitalik);

        bytes32[] memory validProofVitalikRedemption = new bytes32[](1);
        validProofVitalikRedemption[0] = 0x4e40a10ce33f33a4786960a8bb843fe0e170b651acd83da27abc97176c4bed3c;

        // Redeem the tokens for rewards with the right proof
        vm.prank(vitalik);
        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(vitalik, vitalik, pointsId, 2e18);
        pointTokenVault.redeemRewards(PointTokenVault.Claim(pointsId, 2e18, 2e18, validProofVitalikRedemption), vitalik);

        assertEq(rewardToken.balanceOf(vitalik), 2e18);
    }

    function test_PartialClaim() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x6d0fcb8de12b1f57f81e49fa18b641487b932cdba4f064409fde3b05d3824ca2;
        bytes32 root = 0x4e40a10ce33f33a4786960a8bb843fe0e170b651acd83da27abc97176c4bed3c;

        PointTokenVault.Claim[] memory claims = new PointTokenVault.Claim[](1);

        bytes32 pointsId = LibString.packTwo("Eigen Layer Point", "pEL");

        vm.prank(merkleUpdater);
        pointTokenVault.updateRoot(root);

        // Can do a partial claim
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, 0.5e18, proof);
        pointTokenVault.claimPointTokens(claims, vitalik);

        assertEq(pointTokenHub.pointTokens(pointsId).balanceOf(vitalik), 0.5e18);

        // Can only claim the remainder, no more
        vm.prank(vitalik);
        vm.expectRevert(PointTokenVault.ClaimTooLarge.selector);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, 0.75e18, proof);
        pointTokenVault.claimPointTokens(claims, vitalik);

        // Can claim the rest
        vm.prank(vitalik);
        claims[0] = PointTokenVault.Claim(pointsId, 1e18, 0.5e18, proof);
        pointTokenVault.claimPointTokens(claims, vitalik);

        assertEq(pointTokenHub.pointTokens(pointsId).balanceOf(vitalik), 1e18);
    }

    // additional tests:
    // set rewards before the distribution has taken place
    // decimals and dust checks
    // implementation is locked down
    // fuzz deposit/withdraw/claim
    // not just anyone can mint or burn
    // redemption rights
    // only msg.sender can use redemption rights
    // must have point token to use redemption rights
    // can set receiver for reward redemption
    // Test distribution with multiple tokens
    // Test distribution with multiple receivers
    // Test distribution with multiple tokens and multiple receivers
    // Weird setRedemption possibilities
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
