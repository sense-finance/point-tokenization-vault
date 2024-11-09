// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {PointTokenVault} from "../PointTokenVault.sol";
import {PointTokenVaultScripts} from "../script/PointTokenVault.s.sol";
import {PToken} from "../PToken.sol";

contract SetRedemptionENA4Nov24Test is Test {
    PointTokenVault vaultV0_1_0 = PointTokenVault(payable(0x1EeEBa76f211C4Dce994b9c5A74BDF25DB649Fa1));
    PToken kpSats = PToken(0xdFa21ceC8A46386F5d36F4b07E18BcCcA59f425B);
    bytes32 pointsId = LibString.packTwo("Rumpel kPoint: Ethena S2", "kpSATS");

    mapping(address => bool) userAccountedFor; // pToken holder accounted for

    function setUp() public {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(MAINNET_RPC_URL, 21_112_610); // Block mined at Nov-04-2024 06:51:59 AM +UTC
        vm.selectFork(forkId);

        PointTokenVaultScripts scripts = new PointTokenVaultScripts();
        scripts.setRedemptionENA4Nov24();
    }

    function test_RedemptionRights1() public {
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0x4e0230e7a7546148f373efe52256490c04ea0019e199f2256a375e75cf2b6b96;
        proof[1] = 0xfaca43636023a73bf06295aa693c262efe0bb3231357a68b8ad7eec7e901c8ef;
        proof[2] = 0x03c4c7f992659d2c405eb95248d21dfd7f66c7bdef49d9d33cb97b0b5d35c37a;
        proof[3] = 0x617d803c581341b5720c7932932ca45ebfb90e87a122f801b0d5fe53b747db51;
        proof[4] = 0x620f05d3b25d35da47076de4dceb31f95567ff863138ae7d1fe416ea0bc2ff41;

        address USER = 0x25E426b153e74Ab36b2685c3A464272De60888Ae;
        uint256 AMOUNT = 26396311093240867247;

        vm.prank(USER);
        vaultV0_1_0.redeemRewards(PointTokenVault.Claim(pointsId, AMOUNT, AMOUNT, proof), USER);
    }

    function test_FailedRedemptionRights1_BadProof() public {
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0x000008976022911aeb40e40bcb5754f9529f2080710f7ec1db8ace85c4f7b7f8;
        proof[1] = 0xc6f15a7cbd986873c6b761e81c98ee8ac4afd1c9885b7d8e0ae4de752040ab12;
        proof[2] = 0xca808b743099c608cd9b81872c528c521d76505c116bedabfdcc6307c9c92bfb;
        proof[3] = 0x703f21e968e8791afb70bcf780821f479ea90632b109016d8b24c8637771383c;
        proof[4] = 0x0f76084b6c6777c64b0f591ee64d8c66c54c0bdeb5ce44142823c0f74b856267;

        address USER = 0x25E426b153e74Ab36b2685c3A464272De60888Ae;
        uint256 AMOUNT = 52792622186481736164;

        vm.prank(USER);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        vaultV0_1_0.redeemRewards(PointTokenVault.Claim(pointsId, AMOUNT, AMOUNT, proof), USER);
    }

    function test_RedemptionRights1_ClaimTooMuch() public {
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0x4e0230e7a7546148f373efe52256490c04ea0019e199f2256a375e75cf2b6b96;
        proof[1] = 0xfaca43636023a73bf06295aa693c262efe0bb3231357a68b8ad7eec7e901c8ef;
        proof[2] = 0x03c4c7f992659d2c405eb95248d21dfd7f66c7bdef49d9d33cb97b0b5d35c37a;
        proof[3] = 0x617d803c581341b5720c7932932ca45ebfb90e87a122f801b0d5fe53b747db51;
        proof[4] = 0x620f05d3b25d35da47076de4dceb31f95567ff863138ae7d1fe416ea0bc2ff41;

        address USER = 0x25E426b153e74Ab36b2685c3A464272De60888Ae;
        uint256 TOTAL_CLAIMABLE = 26396311093240867247;
        uint256 CLAIM_AMOUNT = 26396311093240867247 + 10;

        vm.prank(USER);
        vm.expectRevert(PointTokenVault.ClaimTooLarge.selector);
        vaultV0_1_0.redeemRewards(PointTokenVault.Claim(pointsId, TOTAL_CLAIMABLE, CLAIM_AMOUNT, proof), USER);
    }

    struct RedemptionData {
        uint256 pTokenBalance;
        uint256 claimedPoints;
        uint256 totalClaimablePoints;
        uint256 unclaimedPoints;
        uint256 totalRedeemableBalance;
        uint256 currentRedeemableBalance;
    }

    struct RedemptionFiles {
        string root;
        string path;
        string alphaDistribution;
        string merged;
        string balances;
    }

    function test_RedemptionRightsCalculatedAmount() public {
        uint256 rewardsPerPToken = 63381137368827226;

        uint256 expectedRedemptionRights;
        uint256 redemptionRightAmount;

        RedemptionFiles memory rf;
        rf.root = vm.projectRoot();
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/last-alpha-distribution.json");
        rf.alphaDistribution = vm.readFile(rf.path);
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution.json");
        rf.merged = vm.readFile(rf.path);
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/ptoken-snapshot-kpsats.json");
        rf.balances = vm.readFile(rf.path);

        string[] memory users = vm.parseJsonKeys(rf.alphaDistribution,string.concat(".pTokens"));
        for(uint256 i=0; i < users.length; i++) {
            RedemptionData memory rd;
            address user = stringToAddress(users[i]);
            userAccountedFor[user] = true;
            
            rd.pTokenBalance = kpSats.balanceOf(user);
            rd.claimedPoints = vaultV0_1_0.claimedPTokens(user, pointsId);
            rd.totalClaimablePoints  = vm.parseJsonUint(
                rf.alphaDistribution,
                string.concat(".pTokens.", vm.toString(user), ".", vm.toString(pointsId), ".accumulatingPoints")
            );

            rd.unclaimedPoints = rd. totalClaimablePoints - rd.claimedPoints;
            rd.totalRedeemableBalance = rd.pTokenBalance + rd.unclaimedPoints;

            // uni overrides
            if(user == 0x24C694d193B19119bcDea9D40a3b0bfaFb281E6D){
                rd.totalRedeemableBalance += 6487631537430741114;
            }
            if(user == 0x44Cb2d713BDa3858001f038645fD05E23E5DE03D){
                rd.totalRedeemableBalance += 27597767454066598826095;
            }

            expectedRedemptionRights = rd.totalRedeemableBalance * rewardsPerPToken / 2e18;
            try vm.parseJsonUint(
                    rf.merged,
                    string.concat(".redemptionRights.", vm.toString(user), ".", vm.toString(pointsId), ".amount")
                ) returns (uint256 amount) {
                    redemptionRightAmount = amount;
                }
             catch {
                redemptionRightAmount = 0;
            }   

            assertLe(redemptionRightAmount, expectedRedemptionRights);
            assertApproxEqAbs(redemptionRightAmount, expectedRedemptionRights, 1e10);

            expectedRedemptionRights = 0;
            redemptionRightAmount = 0;
        }

        // account for users with pToken balances, but no claimable tokens
        string[] memory balanceUsers = vm.parseJsonKeys(rf.balances,string.concat(".balances"));
        for(uint256 i=0; i < balanceUsers.length; i++) {
            address user = stringToAddress(balanceUsers[i]);
            if(!userAccountedFor[user]){
                RedemptionData memory rd;
                userAccountedFor[user] = true;
                
                rd.pTokenBalance = kpSats.balanceOf(user);
                rd.totalRedeemableBalance = rd.pTokenBalance;

                // uni overrides
                if(user == 0x24C694d193B19119bcDea9D40a3b0bfaFb281E6D){
                    rd.totalRedeemableBalance += 6487631537430741114;
                }
                if(user == 0x44Cb2d713BDa3858001f038645fD05E23E5DE03D){
                    rd.totalRedeemableBalance += 27597767454066598826095;
                }

                expectedRedemptionRights = rd.totalRedeemableBalance * rewardsPerPToken / 2e18;

                redemptionRightAmount;
                try vm.parseJsonUint(
                        rf.merged,
                        string.concat(".redemptionRights.", vm.toString(user), ".", vm.toString(pointsId), ".amount")
                    ) returns (uint256 amount) {
                        redemptionRightAmount = amount;
                    }
                catch {
                    redemptionRightAmount = 0;
                }   

                assertLe(redemptionRightAmount, expectedRedemptionRights);
                assertApproxEqAbs(redemptionRightAmount, expectedRedemptionRights, 1e10);

                expectedRedemptionRights = 0;
                redemptionRightAmount = 0;
            }
        }
    }

    function stringToAddress(string memory _address) internal returns (address) {
        // Remove "0x" prefix if present
        bytes memory _addressBytes = bytes(_address);
        if (_addressBytes.length >= 2 && _addressBytes[0] == "0" && (_addressBytes[1] == "x" || _addressBytes[1] == "X")) {
            string memory _cleanAddress = new string(_addressBytes.length - 2);
            for(uint i = 0; i < _addressBytes.length - 2; i++) {
                bytes(_cleanAddress)[i] = _addressBytes[i + 2];
            }
            _address = _cleanAddress;
        }

        // Check if the string length is correct (40 characters for address without 0x)
        require(bytes(_address).length == 40, "Invalid address length");

        // Convert string to bytes
        bytes memory _hexBytes = bytes(_address);
        uint160 _parsedAddress = 0;

        // Convert each character to its hex value
        for(uint i = 0; i < 40; i++) {
            bytes1 char = _hexBytes[i];
            uint8 digit;
            
            if (uint8(char) >= 48 && uint8(char) <= 57) {
                // 0-9
                digit = uint8(char) - 48;
            } else if (uint8(char) >= 65 && uint8(char) <= 70) {
                // A-F
                digit = uint8(char) - 55;
            } else if (uint8(char) >= 97 && uint8(char) <= 102) {
                // a-f
                digit = uint8(char) - 87;
            } else {
                revert("Invalid character in address string");
            }

            _parsedAddress = _parsedAddress * 16 + digit;
        }

        return address(_parsedAddress);
    }
}

interface OldVault {
    function claimPTokens(PointTokenVault.Claim calldata claim, address account) external;
}
