// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PointTokenVault} from "../PointTokenVault.sol";
import {PointTokenVaultScripts} from "../script/PointTokenVault.s.sol";

contract SetRedemptionEtherFiS4Feb25 is Test {
    PointTokenVault vaultV1_0_0 = PointTokenVault(payable(0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61));
    bytes32 pointsId = LibString.packTwo("Rumpel kPt: ETHERFI S4", "kpEF-4");
    ERC20 kingToken = ERC20(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(MAINNET_RPC_URL, 21_882_150); // Block mined at Feb-19-2025 06:16:59 PM +UTC
        vm.selectFork(forkId);

        PointTokenVaultScripts scripts = new PointTokenVaultScripts();
        scripts.setRedemptionEtherFi19Feb25();
    }

    event RewardsClaimed(
        address indexed owner, address indexed receiver, bytes32 indexed pointsId, uint256 amount, uint256 fee
    );

    function test_RedeemRewards1() public {
        bytes32[] memory empty = new bytes32[](0);
        address USER = 0x2E11E6ac295249642253FA47419849153BD8EFC1;
        uint256 AMOUNT = 93053350810428;

        vm.prank(USER);
        vm.expectEmit(true, true, true, true);
        emit RewardsClaimed(USER, USER, pointsId, AMOUNT, 0);
        vaultV1_0_0.redeemRewards(PointTokenVault.Claim(pointsId, AMOUNT, AMOUNT, empty), USER);
    }

    function test_FailedRedeemRewards_ClaimTooMuch() public {
        bytes32[] memory empty = new bytes32[](0);
        address USER = 0x2E11E6ac295249642253FA47419849153BD8EFC1;
        uint256 AMOUNT = 93053350810428 + 2;

        vm.prank(USER);
        vm.expectRevert();
        vaultV1_0_0.redeemRewards(PointTokenVault.Claim(pointsId, AMOUNT, AMOUNT, empty), USER);
    }
}
