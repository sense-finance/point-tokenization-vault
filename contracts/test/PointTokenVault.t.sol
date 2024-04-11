// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PointTokenVault, PointTokenMinter} from "../PointTokenVault.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PointTokenVaultTest is Test {
    PointTokenMinter PTMSingleton = new PointTokenMinter();
    PointTokenVault PTVSingleton = new PointTokenVault();

    PointTokenMinter pointTokenMinter;
    PointTokenVault pointTokenVault;

    function setUp() public {
        pointTokenMinter = PointTokenMinter(
            // create 3 determinsitic address for creating uni pools
            address(new ERC1967Proxy(address(PTMSingleton), abi.encodeCall(PointTokenMinter.initialize, ())))
        );
        pointTokenVault = PointTokenVault(
            address(
                new ERC1967Proxy(address(PTVSingleton), abi.encodeCall(PointTokenVault.initialize, (pointTokenMinter)))
            )
        );
    }

    function test_Sanity() public {
        assertEq(address(pointTokenVault.pointTokenMinter()), address(pointTokenMinter));
    }

    // Test proxy upgradability
    // Test distribution
    // Test deposit
    // Test withdraw
    // Test claim points token
    // Test fuzz deposit/withdraw/claim
    // Test claim rewards token unconditional path
    // Test claim rewards token conditional path
    // Test exec function
}
