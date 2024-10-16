// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {BatchScript} from "forge-safe/src/BatchScript.sol";

import {PointTokenVault} from "../PointTokenVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {CREATE3} from "solmate/utils/CREATE3.sol";
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
        vm.startBroadcast(JIM_PRIVATE_KEY);

        PointTokenVault pointTokenVault = PointTokenVault(payable(0xbff7Fb79efC49504afc97e74F83EE618768e63E9));

        pointTokenVault.deployPToken(LibString.packTwo("ETHERFI Points", "pEF"));

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

    function setRedemptionENA18Oct24() public {
        address POINT_TOKEN_VAULT_PROXY_V_0_1_0 = 0x1EeEBa76f211C4Dce994b9c5A74BDF25DB649Fa1;
        PointTokenVault pointTokenVault = PointTokenVault(payable(POINT_TOKEN_VAULT_PROXY_V_0_1_0));

        bytes32 POINTS_ID_ETHENA_SATS_S2 = LibString.packTwo("Rumpel kPt: Ethena S2", "kpSATS-2");
        ERC20 ENA = ERC20(0x57e114B691Db790C35207b2e685D4A43181e6061);
        uint256 EXCHANGE_RATE = 2e18;
        bool REDEMPTION_RIGHTS = true;

        pointTokenVault.setRedemption(POINTS_ID_ETHENA_SATS_S2, ENA, EXCHANGE_RATE, REDEMPTION_RIGHTS);

        // bytes32 MERKLE_ROOT_WIT_REDEMPTION_RIGHTS = 0x882aaf07b6b16e5f021a498e1a8c5de540e6ffe9345fdc48b51dd79dc894a059;

        // pointTokenVault.updateRoot(MERKLE_ROOT_WIT_REDEMPTION_RIGHTS);
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
