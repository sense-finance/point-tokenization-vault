// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PTV} from "../src/PTV.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CounterTest is Test {
    PTV singleton = new PTV();

    function setUp() public {
        PTV ptv = PTV(
            address(new ERC1967Proxy{salt: bytes32(salt)}(address(singleton), abi.encodeCall(PTV.initialize, (owner))))
        );
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testFuzz_SetNumber(uint256 x) public {
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }
}
