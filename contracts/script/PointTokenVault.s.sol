// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import {PointTokenVault, PointTokenHub} from "../PointTokenVault.sol";

contract DeployPointTokenSystem is Script {
    function run(address admin) public {
        vm.startBroadcast();

        PointTokenHub PTHubSingleton = new PointTokenHub();
        PointTokenVault PTVSingleton = new PointTokenVault();

        // TODO: use create two for deterministic addresses across chains

        pointTokenHub = PointTokenHub(
            address(new ERC1967Proxy(address(PTHubSingleton), abi.encodeCall(PointTokenHub.initialize, ())))
        );
        pointTokenVault = PointTokenVault(
            address(
                new ERC1967Proxy(address(PTVSingleton), abi.encodeCall(PointTokenVault.initialize, (pointTokenHub)))
            )
        );

        pointTokenHub.setTrusted(address(pointTokenVault), true);

        pointTokenHub.transferOwnership(admin);
        pointTokenVault.transferOwnership(admin);

        vm.stopBroadcast();
    }
}
