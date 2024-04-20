// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {PointTokenVault} from "../PointTokenVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {BatchScript} from "forge-safe/src/BatchScript.sol";

contract DeployPointTokenSystem is Script, BatchScript {
    // Sepolia Test Accounts
    address payable public JIM = payable(0xD6633c1382896079D3576eC43519d844a8C80B56);
    address payable public SAM = payable(0xeeD5B3026060218Dc270AE672be6468053e65E39);
    address payable public AVA = payable(0xb30C79546800EF35Ea1fAae56A5faA5C03332D9F);

    uint256 JIM_PRIVATE_KEY = 0x70be68eaa723b433c6b8806f3851d3e04f51a1beed15146dc9fba0873f3b7772;
    uint256 SAM_PRIVATE_KEY = 0x8563bad6b0b906b890cd3272ee8748b7d0e20d6e49917e769af364598e96b466;
    uint256 AVA_PRIVATE_KEY = 0x7617580e9556785c7f9bb93e652df98b6acd0de459300711afbcf53e40ce0358;

    address public SEOPLIA_MERKLE_BOT_SAFE = 0xec48011b60be299A2684F36Bdb3B498a61A6CbF3;
    address public SEPOLIA_OPERATOR_SAFE = 0xec48011b60be299A2684F36Bdb3B498a61A6CbF3;
    address public SEOPLIA_ADMIN_SAFE = 0xec48011b60be299A2684F36Bdb3B498a61A6CbF3; // todo: change to actual admin safe

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        PointTokenVault PointTokenVaultImplementation = new PointTokenVault();

        // TODO: use create two for deterministic addresses across chains
        PointTokenVault pointTokenVault = PointTokenVault(
            address(
                new ERC1967Proxy(address(PointTokenVaultImplementation), abi.encodeCall(PointTokenVault.initialize, ()))
            )
        );

        pointTokenVault.grantRole(pointTokenVault.MERKLE_UPDATER_ROLE(), SEOPLIA_MERKLE_BOT_SAFE);
        pointTokenVault.grantRole(pointTokenVault.DEFAULT_ADMIN_ROLE(), SEOPLIA_ADMIN_SAFE);
        pointTokenVault.grantRole(pointTokenVault.OPERATOR_ROLE(), SEPOLIA_OPERATOR_SAFE);
        pointTokenVault.revokeRole(pointTokenVault.DEFAULT_ADMIN_ROLE(), address(this));

        vm.stopBroadcast();
    }

    function deposit() public {
        vm.startBroadcast(JIM_PRIVATE_KEY);

        ERC20 token = ERC20(0x8Ff06724e15B6ACcAeD6164DE2ab9FA15c4980ad);

        token.approve(address(pointTokenVault), 5e18);
        pointTokenVault.deposit(token, 5e18, JIM);

        vm.stopBroadcast();

        return token.balanceOf(JIM);
    }

    function upgrade() public {
        vm.startBroadcast();

        PointTokenVault currentPointTokenVault = PointTokenVault(0x8Ff06724e15B6ACcAeD6164DE2ab9FA15c4980ad);

        PointTokenVault PointTokenVaultImplementation = new PointTokenVault();

        pointTokenVault.upgradeToAndCall(address(PointTokenVaultImplementation), bytes(""));

        vm.stopBroadcast();
    }

    function deployMockERC20() public {
        vm.startBroadcast(JIM_PRIVATE_KEY);

        MockERC20 token = new MockERC20("Test Token", "TST", 18);

        token.mint(JIM, 100e18);
        token.mint(SAM, 100e18);
        token.mint(AVA, 100e18);

        vm.stopBroadcast();
    }

    function setCap() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bytes32 root = 0x1230000000000000000000000000000000000000000000000000000000000000;

        address pointTokenVault = 0x8Ff06724e15B6ACcAeD6164DE2ab9FA15c4980ad;

        bytes memory txn = abi.encodeWithSelector(PointTokenVault.updateRoot.selector, root);
        addToBatch(pointTokenVault, 0, txn);

        executeBatch(SEOPLIA_ADMIN_SAFE, true);
        vm.stopBroadcast();
    }
}
