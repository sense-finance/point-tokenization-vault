// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PointTokenVault} from "../PointTokenVault.sol";
import {PointTokenVaultScripts} from "../script/PointTokenVault.s.sol";

contract SetRedemptionENA4Nov24Test is Test {
    PointTokenVault vaultV0_1_0 = PointTokenVault(payable(0x1EeEBa76f211C4Dce994b9c5A74BDF25DB649Fa1));
    bytes32 pointsId = LibString.packTwo("Rumpel kPoint: Ethena S2", "kpSATS");

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(MAINNET_RPC_URL, 21_112_610); // Block mined at Nov-04-2024 06:51:59 AM +UTC
        vm.selectFork(forkId);

        PointTokenVaultScripts scripts = new PointTokenVaultScripts();
        scripts.setRedemptionENA4Nov24();
    }

    function test_RedemptionRights1() public {
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0x6258fb3ee01fe8edb76a1ee2cb317cd32b8464c63e31903826acd02863982f31;
        proof[1] = 0xd9d5035f478e73b0e33ae1677a34fb215dd9f25d858d17265608acd57f066e48;
        proof[2] = 0x65c2bc0496edc30a605d1618f867da252e88358e98d08d80ad0d485df4439055;
        proof[3] = 0x9c4c736ac69fbbc0f510cbee646cfcb0a5186004dbb3c577d7c3ab658ddcf209;
        proof[4] = 0x2129557061359b11c571b9a63f6363b144b6ae40058d9731d0e165463fc18438;

        address USER = 0x25E426b153e74Ab36b2685c3A464272De60888Ae;
        uint256 AMOUNT = 26396311093240867247;

        vm.prank(USER);
        vaultV0_1_0.redeemRewards(PointTokenVault.Claim(pointsId, AMOUNT, AMOUNT, proof), USER);
    }

    function test_FailedRedemptionRights1_BadProof() public {
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0x000008976022911aeb40e40bcb5754f9529f2080710f7ec1db8ace85c4f7b7f8;
        proof[1] = 0xc6f15a7cbd986873c6b761e81c98ee8ac4afd1c9885b7d8e0ae4de752040ab12;
        proof[2] = 0xca808b743099c608cd9b81872c528c521d76505c116bedabfdcc6307c9c92bfb;
        proof[3] = 0x703f21e968e8791afb70bcf780821f479ea90632b109016d8b24c8637771383c;
        proof[4] = 0x0f76084b6c6777c64b0f591ee64d8c66c54c0bdeb5ce44142823c0f74b856267;

        address USER = 0x25E426b153e74Ab36b2685c3A464272De60888Ae;
        uint256 AMOUNT = 52792622186481736164;

        vm.prank(USER);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        vaultV0_1_0.redeemRewards(PointTokenVault.Claim(pointsId, AMOUNT, AMOUNT, proof), USER);
    }

    function test_RedemptionRights1_ClaimTooMuch() public {
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0x6258fb3ee01fe8edb76a1ee2cb317cd32b8464c63e31903826acd02863982f31;
        proof[1] = 0xd9d5035f478e73b0e33ae1677a34fb215dd9f25d858d17265608acd57f066e48;
        proof[2] = 0x65c2bc0496edc30a605d1618f867da252e88358e98d08d80ad0d485df4439055;
        proof[3] = 0x9c4c736ac69fbbc0f510cbee646cfcb0a5186004dbb3c577d7c3ab658ddcf209;
        proof[4] = 0x2129557061359b11c571b9a63f6363b144b6ae40058d9731d0e165463fc18438;

        address USER = 0x25E426b153e74Ab36b2685c3A464272De60888Ae;
        uint256 TOTAL_CLAIMABLE = 26396311093240867247;
        uint256 CLAIM_AMOUNT = 26396311093240867247 + 10;

        vm.prank(USER);
        vm.expectRevert(PointTokenVault.ClaimTooLarge.selector);
        vaultV0_1_0.redeemRewards(PointTokenVault.Claim(pointsId, TOTAL_CLAIMABLE, CLAIM_AMOUNT, proof), USER);
    }

    function test_NormalPTokenClaim() public {
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0x6a69b863aea1e9a735f460a6fb449a28b7398f958c4792872d7764700936b79d;
        proof[1] = 0xf88a43494a509c28f8321582f54b7964fc2232a7f109d49a44631cbcfa5d30a9;
        proof[2] = 0x65c2bc0496edc30a605d1618f867da252e88358e98d08d80ad0d485df4439055;
        proof[3] = 0x9c4c736ac69fbbc0f510cbee646cfcb0a5186004dbb3c577d7c3ab658ddcf209;
        proof[4] = 0x2129557061359b11c571b9a63f6363b144b6ae40058d9731d0e165463fc18438;

        address USER = 0x24C694d193B19119bcDea9D40a3b0bfaFb281E6D;
        uint256 AMOUNT = 152407798291890457882;

        vm.prank(USER);
        OldVault(address(vaultV0_1_0)).claimPTokens(PointTokenVault.Claim(pointsId, AMOUNT, AMOUNT, proof), USER);

        assertEq(ERC20(address(vaultV0_1_0.pTokens(pointsId))).balanceOf(USER), AMOUNT);
    }
}

interface OldVault {
    function claimPTokens(PointTokenVault.Claim calldata claim, address account) external;
}
