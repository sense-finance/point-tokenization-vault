// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Test, console} from "forge-std/Test.sol";
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
        proof[0] = 0x0184945bd5da6f8f02554c3782cb952616dbdac575835608781ae718e6eca25c;
        proof[1] = 0xc7899642466ab83ca8d52429c5bb4d7654e09316c8d4fbecff3a4a545de41572;
        proof[2] = 0xcea9f210f2cec43ba76de766b46c97ed49078050d7dc13b995cbcda69cda6e4d;
        proof[3] = 0x1f051849573fac3a646dd3b66aeaa77af0fe1c07f8f4cdc18360120605bbb984;
        proof[4] = 0xd5cf6d1326ef924a07c73754288ffe62b323df5e22a3eae95dded15ee3cdcd03;

        address USER = 0x25E426b153e74Ab36b2685c3A464272De60888Ae;
        uint256 AMOUNT = 52792622184887167898;

        vm.prank(USER);
        vaultV0_1_0.redeemRewards(PointTokenVault.Claim(pointsId, AMOUNT, AMOUNT, proof), USER);
    }

    function test_FailedRedemptionRights1_BadProof() public {
        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x01ec7d9e741987772101f24e85052734e05f2f58760e7b2b79c887c4fd58c3ba;
        proof[1] = 0x6980c76aae17071569c29f94445a68b72b974739d2a2824b8b97f6cbbbdda0b9;
        proof[2] = 0x01ec7d9e741987772101f24e85052734e05f2f58760e7b2b79c887c4fd58c3ba;
        proof[3] = 0x1dcf5cd8d0d9f76170c4003e236c16f1e4c563d053a0b863c3d8edd173c62acf;

        address USER = 0x25E426b153e74Ab36b2685c3A464272De60888Ae;
        uint256 AMOUNT = 52792622184887167898;

        vm.prank(USER);
        vm.expectRevert(PointTokenVault.ProofInvalidOrExpired.selector);
        vaultV0_1_0.redeemRewards(PointTokenVault.Claim(pointsId, AMOUNT, AMOUNT, proof), USER);
    }

    function test_RedemptionRights1_ClaimTooMuch() public {
        bytes32[] memory proof = new bytes32[](5);
        proof[0] = 0x0184945bd5da6f8f02554c3782cb952616dbdac575835608781ae718e6eca25c;
        proof[1] = 0xc7899642466ab83ca8d52429c5bb4d7654e09316c8d4fbecff3a4a545de41572;
        proof[2] = 0xcea9f210f2cec43ba76de766b46c97ed49078050d7dc13b995cbcda69cda6e4d;
        proof[3] = 0x1f051849573fac3a646dd3b66aeaa77af0fe1c07f8f4cdc18360120605bbb984;
        proof[4] = 0xd5cf6d1326ef924a07c73754288ffe62b323df5e22a3eae95dded15ee3cdcd03;

        address USER = 0x25E426b153e74Ab36b2685c3A464272De60888Ae;
        uint256 TOTAL_CLAIMABLE = 52792622184887167898;
        uint256 CLAIM_AMOUNT = TOTAL_CLAIMABLE + 10;

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
        string merged2;
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

        string[] memory users = vm.parseJsonKeys(rf.alphaDistribution, string.concat(".pTokens"));
        for (uint256 i = 0; i < users.length; i++) {
            RedemptionData memory rd;
            address user = stringToAddress(users[i]);
            userAccountedFor[user] = true;

            rd.pTokenBalance = kpSats.balanceOf(user);
            rd.claimedPoints = vaultV0_1_0.claimedPTokens(user, pointsId);
            rd.totalClaimablePoints = vm.parseJsonUint(
                rf.alphaDistribution,
                string.concat(".pTokens.", vm.toString(user), ".", vm.toString(pointsId), ".accumulatingPoints")
            );

            rd.unclaimedPoints = rd.totalClaimablePoints - rd.claimedPoints;
            rd.totalRedeemableBalance = rd.pTokenBalance + rd.unclaimedPoints;

            // uni overrides
            if (user == 0x24C694d193B19119bcDea9D40a3b0bfaFb281E6D) {
                rd.totalRedeemableBalance += 6487631537430741114;
            }
            if (user == 0x44Cb2d713BDa3858001f038645fD05E23E5DE03D) {
                rd.totalRedeemableBalance += 27597767454066598826095;
            }

            expectedRedemptionRights = rd.totalRedeemableBalance * rewardsPerPToken / 2e18;
            try vm.parseJsonUint(
                rf.merged, string.concat(".redemptionRights.", vm.toString(user), ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmount = amount;
            } catch {
                redemptionRightAmount = 0;
            }

            assertLe(redemptionRightAmount, expectedRedemptionRights);
            assertApproxEqAbs(redemptionRightAmount, expectedRedemptionRights, 1e10);

            expectedRedemptionRights = 0;
            redemptionRightAmount = 0;
        }

        // account for users with pToken balances, but no claimable tokens
        string[] memory balanceUsers = vm.parseJsonKeys(rf.balances, string.concat(".balances"));
        for (uint256 i = 0; i < balanceUsers.length; i++) {
            address user = stringToAddress(balanceUsers[i]);
            if (!userAccountedFor[user]) {
                RedemptionData memory rd;
                userAccountedFor[user] = true;

                rd.pTokenBalance = kpSats.balanceOf(user);
                rd.totalRedeemableBalance = rd.pTokenBalance;

                // uni overrides
                if (user == 0x24C694d193B19119bcDea9D40a3b0bfaFb281E6D) {
                    rd.totalRedeemableBalance += 6487631537430741114;
                }
                if (user == 0x44Cb2d713BDa3858001f038645fD05E23E5DE03D) {
                    rd.totalRedeemableBalance += 27597767454066598826095;
                }

                expectedRedemptionRights = rd.totalRedeemableBalance * rewardsPerPToken / 2e18;

                redemptionRightAmount;
                try vm.parseJsonUint(
                    rf.merged,
                    string.concat(".redemptionRights.", vm.toString(user), ".", vm.toString(pointsId), ".amount")
                ) returns (uint256 amount) {
                    redemptionRightAmount = amount;
                } catch {
                    redemptionRightAmount = 0;
                }

                assertLe(redemptionRightAmount, expectedRedemptionRights);
                assertApproxEqAbs(redemptionRightAmount, expectedRedemptionRights, 1e10);

                expectedRedemptionRights = 0;
                redemptionRightAmount = 0;
            }
        }
    }

    function test_RedemptionRightsCalculatedAmount_Dec3() public {
        uint256 rewardsPerPToken = 63381137368827226;

        uint256 originalReceivedTokens = 1324312 * 1e17;
        uint256 newTokens = 2546753846 * 1e13;
        uint256 expectedProportion = originalReceivedTokens * 1e18 / (originalReceivedTokens + newTokens);

        uint256 expectedRedemptionRights;
        uint256 redemptionRightAmountOriginal;
        uint256 redemptionRightAmountDec3;

        RedemptionFiles memory rf;
        rf.root = vm.projectRoot();
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution.json");
        rf.merged = vm.readFile(rf.path);
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution-03Dec24.json");
        rf.merged2 = vm.readFile(rf.path);

        string[] memory users = vm.parseJsonKeys(rf.merged, string.concat(".redemptionRights"));
        for (uint256 i = 0; i < users.length; i++) {
            try vm.parseJsonUint(
                rf.merged, string.concat(".redemptionRights.", users[i], ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmountOriginal = amount;
            } catch {
                redemptionRightAmountOriginal = 0;
            }

            try vm.parseJsonUint(
                rf.merged2, string.concat(".redemptionRights.", users[i], ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmountDec3 = amount;
            } catch {
                redemptionRightAmountDec3 = 0;
            }

            uint256 proportion = redemptionRightAmountOriginal * 1e18 / redemptionRightAmountDec3;

            assertApproxEqAbs(proportion, expectedProportion, 1e10);
        }
    }

    function test_RedemptionRightsCalculatedAmount_Jan7() public {
        uint256 rewardsPerPToken = 63381137368827226;

        uint256 originalReceivedTokens = 1324312 * 1e17;
        uint256 newTokens = 2546753846 * 1e13 + 2546753846 * 1e13; // same new token amount as dec3
        uint256 expectedProportion = originalReceivedTokens * 1e18 / (originalReceivedTokens + newTokens);

        uint256 expectedRedemptionRights;
        uint256 redemptionRightAmountOriginal;
        uint256 redemptionRightAmountJan7;

        RedemptionFiles memory rf;
        rf.root = vm.projectRoot();
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution.json");
        rf.merged = vm.readFile(rf.path);
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution-07Jan25.json");
        rf.merged2 = vm.readFile(rf.path);

        string[] memory users = vm.parseJsonKeys(rf.merged, string.concat(".redemptionRights"));
        for (uint256 i = 0; i < users.length; i++) {
            try vm.parseJsonUint(
                rf.merged, string.concat(".redemptionRights.", users[i], ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmountOriginal = amount;
            } catch {
                redemptionRightAmountOriginal = 0;
            }

            try vm.parseJsonUint(
                rf.merged2, string.concat(".redemptionRights.", users[i], ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmountJan7 = amount;
            } catch {
                redemptionRightAmountJan7 = 0;
            }

            uint256 proportion = redemptionRightAmountOriginal * 1e18 / redemptionRightAmountJan7;

            assertApproxEqAbs(proportion, expectedProportion, 1e10);
        }
    }

    function test_RedemptionRightsCalculatedAmount_Feb6() public {
        uint256 rewardsPerPToken = 63381137368827226;

        uint256 originalReceivedTokens = 1324312 * 1e17;
        uint256 newTokens = 2546753846 * 1e13 + 2546753846 * 1e13 + 20374030768 * 1e12;
        uint256 expectedProportion = originalReceivedTokens * 1e18 / (originalReceivedTokens + newTokens);

        uint256 expectedRedemptionRights;
        uint256 redemptionRightAmountOriginal;
        uint256 redemptionRightAmountJan7;

        RedemptionFiles memory rf;
        rf.root = vm.projectRoot();
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution.json");
        rf.merged = vm.readFile(rf.path);
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution-06Feb25.json");
        rf.merged2 = vm.readFile(rf.path);

        string[] memory users = vm.parseJsonKeys(rf.merged, string.concat(".redemptionRights"));
        for (uint256 i = 0; i < users.length; i++) {
            try vm.parseJsonUint(
                rf.merged, string.concat(".redemptionRights.", users[i], ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmountOriginal = amount;
            } catch {
                redemptionRightAmountOriginal = 0;
            }

            try vm.parseJsonUint(
                rf.merged2, string.concat(".redemptionRights.", users[i], ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmountJan7 = amount;
            } catch {
                redemptionRightAmountJan7 = 0;
            }

            uint256 proportion = redemptionRightAmountOriginal * 1e18 / redemptionRightAmountJan7;

            assertApproxEqAbs(proportion, expectedProportion, 1e10);
        }
    }

    function test_RedemptionRightsCalculatedAmount_Apr1() public {
        uint256 rewardsPerPToken = 63381137368827226;

        uint256 originalReceivedTokens = 1324312 * 1e17;
        uint256 newTokens =
            2546753846 * 1e13 + 2546753846 * 1e13 + 20374030768 * 1e12 + 20374030768 * 1e12 + 20374030768 * 1e12;
        uint256 expectedProportion = originalReceivedTokens * 1e18 / (originalReceivedTokens + newTokens);

        uint256 expectedRedemptionRights;
        uint256 redemptionRightAmountOriginal;
        uint256 redemptionRightAmountApr1;

        RedemptionFiles memory rf;
        rf.root = vm.projectRoot();
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution.json");
        rf.merged = vm.readFile(rf.path);
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution-01Apr25.json");
        rf.merged2 = vm.readFile(rf.path);

        string[] memory users = vm.parseJsonKeys(rf.merged, string.concat(".redemptionRights"));
        for (uint256 i = 0; i < users.length; i++) {
            try vm.parseJsonUint(
                rf.merged, string.concat(".redemptionRights.", users[i], ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmountOriginal = amount;
            } catch {
                redemptionRightAmountOriginal = 0;
            }

            try vm.parseJsonUint(
                rf.merged2, string.concat(".redemptionRights.", users[i], ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmountApr1 = amount;
            } catch {
                redemptionRightAmountApr1 = 0;
            }

            uint256 proportion = redemptionRightAmountOriginal * 1e18 / redemptionRightAmountApr1;

            assertApproxEqAbs(proportion, expectedProportion, 1e10);
        }
    }

    function test_RedemptionRightsCalculatedAmount_Apr29() public {
        uint256 rewardsPerPToken = 63381137368827226;

        uint256 originalReceivedTokens = 1324312 * 1e17;
        uint256 newTokens = 2546753846 * 1e13 + 2546753846 * 1e13 + 20374030768 * 1e12 + 20374030768 * 1e12
            + 20374030768 * 1e12 + 20374030768 * 1e12;
        uint256 expectedProportion = originalReceivedTokens * 1e18 / (originalReceivedTokens + newTokens);

        uint256 expectedRedemptionRights;
        uint256 redemptionRightAmountOriginal;
        uint256 redemptionRightAmountJan7;

        RedemptionFiles memory rf;
        rf.root = vm.projectRoot();
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution.json");
        rf.merged = vm.readFile(rf.path);
        rf.path = string.concat(rf.root, "/js-scripts/generateRedemptionRights/out/merged-distribution-29Apr25.json");
        rf.merged2 = vm.readFile(rf.path);

        string[] memory users = vm.parseJsonKeys(rf.merged, string.concat(".redemptionRights"));
        for (uint256 i = 0; i < users.length; i++) {
            try vm.parseJsonUint(
                rf.merged, string.concat(".redemptionRights.", users[i], ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmountOriginal = amount;
            } catch {
                redemptionRightAmountOriginal = 0;
            }

            try vm.parseJsonUint(
                rf.merged2, string.concat(".redemptionRights.", users[i], ".", vm.toString(pointsId), ".amount")
            ) returns (uint256 amount) {
                redemptionRightAmountJan7 = amount;
            } catch {
                redemptionRightAmountJan7 = 0;
            }

            uint256 proportion = redemptionRightAmountOriginal * 1e18 / redemptionRightAmountJan7;

            assertApproxEqAbs(proportion, expectedProportion, 1e10);
        }
    }

    function stringToAddress(string memory _address) internal returns (address) {
        // Remove "0x" prefix if present
        bytes memory _addressBytes = bytes(_address);
        if (
            _addressBytes.length >= 2 && _addressBytes[0] == "0" && (_addressBytes[1] == "x" || _addressBytes[1] == "X")
        ) {
            string memory _cleanAddress = new string(_addressBytes.length - 2);
            for (uint256 i = 0; i < _addressBytes.length - 2; i++) {
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
        for (uint256 i = 0; i < 40; i++) {
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
