// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {PointTokenVault, PointTokenHub} from "../PointTokenVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployPointTokenSystem is Script {
    function run(address admin) public {
        vm.startBroadcast();

        PointTokenHub PTHubSingleton = new PointTokenHub();
        PointTokenVault PTVSingleton = new PointTokenVault();

        // TODO: use create two for deterministic addresses across chains

        PointTokenHub pointTokenHub = PointTokenHub(
            address(new ERC1967Proxy(address(PTHubSingleton), abi.encodeCall(PointTokenHub.initialize, ())))
        );
        PointTokenVault pointTokenVault = PointTokenVault(
            address(
                new ERC1967Proxy(address(PTVSingleton), abi.encodeCall(PointTokenVault.initialize, (pointTokenHub)))
            )
        );

        pointTokenHub.setTrusted(address(pointTokenVault), true);

        pointTokenHub.transferOwnership(admin);
        pointTokenVault.transferOwnership(admin);

        vm.stopBroadcast();

        // TODO: return addresses
    }
}
