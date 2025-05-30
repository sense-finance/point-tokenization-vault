// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {BatchScript} from "forge-safe/src/BatchScript.sol";

import {PointTokenVault} from "../PointTokenVault.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {LibString} from "solady/utils/LibString.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {console} from "forge-std/console.sol";

contract PointTokenVaultScripts is BatchScript {
    // Sepolia Test Accounts
    address payable public JIM = payable(0xD6633c1382896079D3576eC43519d844a8C80B56);
    address payable public SAM = payable(0xeeD5B3026060218Dc270AE672be6468053e65E39);
    address payable public AVA = payable(0xb30C79546800EF35Ea1fAae56A5faA5C03332D9F);

    uint256 JIM_PRIVATE_KEY = 0x70be68eaa723b433c6b8806f3851d3e04f51a1beed15146dc9fba0873f3b7772;
    uint256 SAM_PRIVATE_KEY = 0x8563bad6b0b906b890cd3272ee8748b7d0e20d6e49917e769af364598e96b466;
    uint256 AVA_PRIVATE_KEY = 0x7617580e9556785c7f9bb93e652df98b6acd0de459300711afbcf53e40ce0358;

    address public SEOPLIA_MERKLE_BOT_SAFE = 0xec48011b60be299A2684F36Bdb3B498a61A6CbF3;
    address public SEPOLIA_OPERATOR_SAFE = 0xec48011b60be299A2684F36Bdb3B498a61A6CbF3;
    address public SEOPLIA_ADMIN_SAFE = 0xec48011b60be299A2684F36Bdb3B498a61A6CbF3;

    address public MAINNET_MERKLE_UPDATER = 0xfDE9f367c933A7D7E7348D4a3e6e096d814F5828;
    address public MAINNET_OPERATOR = 0x0c0264Ba7799dA7aF0fd141ba5Ba976E6DcC6C17;
    address public MAINNET_ADMIN = 0x9D89745fD63Af482ce93a9AdB8B0BbDbb98D3e06;
    address public FEE_COLLECTOR = MAINNET_ADMIN;

    function run() public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation and proxy, return proxy
        PointTokenVault pointTokenVault = runDeploy();

        // Set roles
        pointTokenVault.grantRole(pointTokenVault.MERKLE_UPDATER_ROLE(), MAINNET_MERKLE_UPDATER);
        pointTokenVault.grantRole(pointTokenVault.DEFAULT_ADMIN_ROLE(), MAINNET_ADMIN);
        pointTokenVault.grantRole(pointTokenVault.OPERATOR_ROLE(), MAINNET_OPERATOR);

        // Remove deployer
        pointTokenVault.revokeRole(pointTokenVault.DEFAULT_ADMIN_ROLE(), msg.sender);

        require(!pointTokenVault.hasRole(pointTokenVault.DEFAULT_ADMIN_ROLE(), msg.sender), "Deployer role not removed");

        vm.stopBroadcast();

        return address(pointTokenVault);
    }

    function runDeploy() public returns (PointTokenVault) {
        PointTokenVault pointTokenVault = PointTokenVault(
            payable(
                Upgrades.deployUUPSProxy(
                    "PointTokenVault.sol", abi.encodeCall(PointTokenVault.initialize, (msg.sender, FEE_COLLECTOR))
                )
            )
        );

        return pointTokenVault;
    }

    function deposit() public returns (uint256) {
        vm.startBroadcast(JIM_PRIVATE_KEY);

        ERC20 token = ERC20(0x791a051631c9c4cDf4E03Fb7Aec3163AE164A34B);
        PointTokenVault pointTokenVault = PointTokenVault(payable(0xbff7Fb79efC49504afc97e74F83EE618768e63E9));
        token.symbol();

        token.approve(address(pointTokenVault), 2.5e18);
        pointTokenVault.deposit(token, 2.5e18, JIM);

        vm.stopBroadcast();

        return token.balanceOf(JIM);
    }

    function upgrade() public {
        vm.startBroadcast();

        // address currentPointTokenVaultAddress = 0xbff7Fb79efC49504afc97e74F83EE618768e63E9;

        // Once there is a v2, upgrade referencing v1 for automatic OZ safety checks
        // Options memory opts;
        // opts.referenceContract = "PointTokenVaultV1.sol";
        // Upgrades.upgradeProxy(currentPointTokenVaultAddress, "PointTokenVaultV2.sol", "");

        vm.stopBroadcast();
    }

    function deployPToken() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        PointTokenVault pointTokenVault = PointTokenVault(payable(0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61));

        pointTokenVault.deployPToken(LibString.packTwo("Rumpel kPt: ETHERFI S4", "kpEF-4"));

        vm.stopBroadcast();
    }

    function deployMockERC20() public {
        vm.startBroadcast(JIM_PRIVATE_KEY);

        MockERC20 token = new MockERC20("ETHFI", "eETH", 18);

        token.mint(JIM, 100e18);
        token.mint(SAM, 100e18);
        token.mint(AVA, 100e18);

        vm.stopBroadcast();
    }

    function setRedemptionENA4Nov24() public {
        // Core contract and token setup
        PointTokenVault vaultV0_1_0 = PointTokenVault(payable(0x1EeEBa76f211C4Dce994b9c5A74BDF25DB649Fa1));
        bytes32 pointsId = LibString.packTwo("Rumpel kPoint: Ethena S2", "kpSATS");
        ERC20 senaToken = ERC20(0x8bE3460A480c80728a8C4D7a5D5303c85ba7B3b9);
        uint256 rewardsPerPToken = 63381137368827226;
        bool usesRedemptionRights = true;

        // Set redemption parameters
        vm.startBroadcast(MAINNET_OPERATOR);
        vaultV0_1_0.setRedemption(pointsId, senaToken, rewardsPerPToken, usesRedemptionRights);
        vm.stopBroadcast();

        // Update merkle root
        vm.startBroadcast(MAINNET_MERKLE_UPDATER);
        vaultV0_1_0.updateRoot(0xc15c1db3527c77ec3d015a39bc2e5666f43d91993c42841dea0f97d310466798);
        vm.stopBroadcast();
    }

    function setRedemptionEtherFi19Feb25() public {
        // Core contract and token setup
        PointTokenVault vaultV1_0_0 = PointTokenVault(payable(0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61));
        bytes32 pointsId = LibString.packTwo("Rumpel kPt: ETHERFI S4", "kpEF-4");
        ERC20 kingToken = ERC20(0x8F08B70456eb22f6109F57b8fafE862ED28E6040);
        uint256 rewardsPerPToken = 895065548932;
        bool usesRedemptionRights = false;

        // Set redemption parameters
        vm.startBroadcast(MAINNET_OPERATOR);
        vaultV1_0_0.setRedemption(pointsId, kingToken, rewardsPerPToken, usesRedemptionRights);
        vm.stopBroadcast();
    }

    // Useful for emergencies, where we need to override both the current and previous root at once
    // For example, if minting for a specific pToken needs to be stopped, a root without any claim rights for the pToken would need to be pushed twice
    function doublePushRoot(address pointTokenVaultAddress, bytes32 newRoot, address merkleUpdaterSafe) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        bytes memory txn = abi.encodeWithSelector(PointTokenVault.updateRoot.selector, newRoot);
        addToBatch(pointTokenVaultAddress, 0, txn);
        addToBatch(pointTokenVaultAddress, 0, txn);

        executeBatch(merkleUpdaterSafe, true);

        vm.stopBroadcast();
    }

    function setCap() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address pointTokenVaultAddress = 0xbff7Fb79efC49504afc97e74F83EE618768e63E9;

        bytes memory txn =
            abi.encodeWithSelector(PointTokenVault.setCap.selector, 0x791a051631c9c4cDf4E03Fb7Aec3163AE164A34B, 10e18);
        addToBatch(pointTokenVaultAddress, 0, txn);

        executeBatch(SEOPLIA_ADMIN_SAFE, true);
        vm.stopBroadcast();
    }
}
