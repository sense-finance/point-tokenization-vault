// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {PointTokenVault, PointTokenHub} from "../PointTokenVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract DeployPointTokenSystem is Script {
    address payable public JIM = payable(0xD6633c1382896079D3576eC43519d844a8C80B56);
    address payable public SAM = payable(0xeeD5B3026060218Dc270AE672be6468053e65E39);
    address payable public AVA = payable(0xb30C79546800EF35Ea1fAae56A5faA5C03332D9F);

    uint256 JIM_PRIVATE_KEY = 0x70be68eaa723b433c6b8806f3851d3e04f51a1beed15146dc9fba0873f3b7772;
    uint256 SAM_PRIVATE_KEY = 0x8563bad6b0b906b890cd3272ee8748b7d0e20d6e49917e769af364598e96b466;
    uint256 AVA_PRIVATE_KEY = 0x7617580e9556785c7f9bb93e652df98b6acd0de459300711afbcf53e40ce0358;

    address public SEOPLIA_SAFE_ADDRESS = 0xec48011b60be299A2684F36Bdb3B498a61A6CbF3;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MERKLE_BOT_A");
        vm.startBroadcast(deployerPrivateKey);

        // MockERC20 token = MockERC20(0x758d92D1ade72Bce33c5677a23208280c259F00A);
        // PointTokenHub pointTokenHub = PointTokenHub(0x81bDb5C8fedEfeeee890607aB49D64bb2fa94edb);
        // PointTokenVault pointTokenVault = PointTokenVault(0x8Ff06724e15B6ACcAeD6164DE2ab9FA15c4980ad);

        // token.balanceOf(SAM);

        // token.approve(address(pointTokenVault), 5e18);
        // pointTokenVault.deposit(token, 5e18, SAM);

        // token.balanceOf(SAM);

        // PointTokenHub PTHubSingleton = new PointTokenHub();
        // PointTokenVault PTVSingleton = new PointTokenVault();

        // TODO: use create two for deterministic addresses across chains

        // PointTokenHub pointTokenHub = PointTokenHub(
        //     address(new ERC1967Proxy(address(PTHubSingleton), abi.encodeCall(PointTokenHub.initialize, ())))
        // );
        // PointTokenVault pointTokenVault = PointTokenVault(
        //     address(
        //         new ERC1967Proxy(address(PTVSingleton), abi.encodeCall(PointTokenVault.initialize, (pointTokenHub)))
        //     )
        // );

        // pointTokenVault.upgradeToAndCall(address(PTVSingleton), bytes(""));

        // pointTokenHub.setTrusted(address(pointTokenVault), true);

        // pointTokenHub.transferOwnership(SEOPLIA_SAFE_ADDRESS);
        // pointTokenVault.transferOwnership(SEOPLIA_SAFE_ADDRESS);

        vm.stopBroadcast();
    }
}
