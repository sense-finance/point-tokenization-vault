// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BatchScript} from "forge-safe/src/BatchScript.sol";

import {PointTokenVault} from "../PointTokenVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {CREATE3} from "solmate/utils/CREATE3.sol";
import {LibString} from "solady/utils/LibString.sol";

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
    address public SEOPLIA_ADMIN_SAFE = 0xec48011b60be299A2684F36Bdb3B498a61A6CbF3; // todo: change to actual admin safe

    function run() public returns (address) {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        PointTokenVault pointTokenVaultImplementation = new PointTokenVault();

        PointTokenVault pointTokenVault = PointTokenVault(
            address(
                new ERC1967Proxy(
                    address(pointTokenVaultImplementation), abi.encodeCall(PointTokenVault.initialize, (msg.sender))
                )
            )
        );

        // Set roles
        pointTokenVault.grantRole(pointTokenVault.MERKLE_UPDATER_ROLE(), SEOPLIA_MERKLE_BOT_SAFE);
        pointTokenVault.grantRole(pointTokenVault.DEFAULT_ADMIN_ROLE(), SEOPLIA_ADMIN_SAFE);
        pointTokenVault.grantRole(pointTokenVault.OPERATOR_ROLE(), SEPOLIA_OPERATOR_SAFE);

        // Remove self
        pointTokenVault.revokeRole(pointTokenVault.DEFAULT_ADMIN_ROLE(), msg.sender);

        require(!pointTokenVault.hasRole(pointTokenVault.DEFAULT_ADMIN_ROLE(), msg.sender), "Self role not removed");

        vm.stopBroadcast();

        return address(pointTokenVault);
    }

    function deployPointTokenVault(address admin) public returns (PointTokenVault) {
        string memory version = vm.envString("VERSION");

        PointTokenVault pointTokenVaultImplementation = PointTokenVault(
            CREATE3.deploy(
                keccak256(bytes(string.concat("PointTokenVault", "-v", version))), type(PointTokenVault).creationCode, 0
            )
        );

        PointTokenVault pointTokenVault = PointTokenVault(
            CREATE3.deploy(
                keccak256(bytes(string.concat("PointTokenVaultProxy", "-v", version))),
                abi.encodePacked(
                    type(ERC1967Proxy).creationCode,
                    abi.encode(
                        address(pointTokenVaultImplementation), abi.encodeCall(PointTokenVault.initialize, (admin))
                    )
                ),
                0
            )
        );

        return pointTokenVault;
    }

    function deposit() public returns (uint256) {
        vm.startBroadcast(JIM_PRIVATE_KEY);

        ERC20 token = ERC20(0x791a051631c9c4cDf4E03Fb7Aec3163AE164A34B);
        PointTokenVault pointTokenVault = PointTokenVault(0xbff7Fb79efC49504afc97e74F83EE618768e63E9);
        token.symbol();

        token.approve(address(pointTokenVault), 2.5e18);
        pointTokenVault.deposit(token, 2.5e18, JIM);

        vm.stopBroadcast();

        return token.balanceOf(JIM);
    }

    function upgrade() public {
        vm.startBroadcast();

        PointTokenVault currentPointTokenVault = PointTokenVault(0xbff7Fb79efC49504afc97e74F83EE618768e63E9);

        PointTokenVault PointTokenVaultImplementation = new PointTokenVault();

        currentPointTokenVault.upgradeToAndCall(address(PointTokenVaultImplementation), bytes(""));

        vm.stopBroadcast();
    }

    function deployPToken() public {
        vm.startBroadcast(JIM_PRIVATE_KEY);

        PointTokenVault pointTokenVault = PointTokenVault(0xbff7Fb79efC49504afc97e74F83EE618768e63E9);

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

    function setCap() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address pointTokenVault = 0xbff7Fb79efC49504afc97e74F83EE618768e63E9;

        bytes memory txn =
            abi.encodeWithSelector(PointTokenVault.setCap.selector, 0x791a051631c9c4cDf4E03Fb7Aec3163AE164A34B, 10e18);
        addToBatch(pointTokenVault, 0, txn);

        executeBatch(SEOPLIA_ADMIN_SAFE, true);
        vm.stopBroadcast();
    }
}
