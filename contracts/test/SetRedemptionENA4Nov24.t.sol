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
        proof[0] = 0x991fd8976022911aeb40e40bcb5754f9529f2080710f7ec1db8ace85c4f7b7f8;
        proof[1] = 0xc6f15a7cbd986873c6b761e81c98ee8ac4afd1c9885b7d8e0ae4de752040ab12;
        proof[2] = 0xca808b743099c608cd9b81872c528c521d76505c116bedabfdcc6307c9c92bfb;
        proof[3] = 0x703f21e968e8791afb70bcf780821f479ea90632b109016d8b24c8637771383c;
        proof[4] = 0x0f76084b6c6777c64b0f591ee64d8c66c54c0bdeb5ce44142823c0f74b856267;

        address USER = 0x25E426b153e74Ab36b2685c3A464272De60888Ae;
        uint256 AMOUNT = 52792622186481736164;

        vm.prank(USER);
        vaultV0_1_0.redeemRewards(PointTokenVault.Claim(pointsId, AMOUNT, AMOUNT, proof), USER);
    }

    function test_NormalPTokenClaim() public {
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0x8b788cab342842ae529d8efac9659e1af9367270c13caaf4c8b5ef4c67a51402;
        proof[1] = 0xfaca43636023a73bf06295aa693c262efe0bb3231357a68b8ad7eec7e901c8ef;
        proof[2] = 0x2eec07dc470578d8beb2eb4edf89d2309714b87ea0b9e9b2f119df39a28278c7;
        proof[3] = 0x703f21e968e8791afb70bcf780821f479ea90632b109016d8b24c8637771383c;
        proof[4] = 0x0f76084b6c6777c64b0f591ee64d8c66c54c0bdeb5ce44142823c0f74b856267;

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
