// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import "forge-std/console2.sol";

contract KingDistributionScript is Script {
    address public MAINNET_ADMIN = 0x9D89745fD63Af482ce93a9AdB8B0BbDbb98D3e06;

    address public constant MAINNET_ETHERFI_LRT2_CLAIM = 0x6Db24Ee656843E3fE03eb8762a54D86186bA6B64;
    address public constant MAINNET_LRT2 = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;

    address public constant MAINNET_RUMPEL_MODULE = 0x28c3498B4956f4aD8d4549ACA8F66260975D361a;

    bytes32 public constant EXPECTED_ROOT_3_5_25 = 0xdbf5085b731f41c2bc92d662425123a06978a05ada163f9d0b67353274b3f308;
    bytes32 public constant EXPECTED_ROOT_4_2_25 = 0x2418d9aa8353242b80852b09e1f4a9bb484c771268d8af884fc676b194990531;
    bytes32 public constant EXPECTED_ROOT_5_7_25 = 0x7a9c48553c086965f22bb9b06b5425664421a97167669045a86886d52b7ae08b;

    string public constant REWARD_PATH_3_5_25 = "/js-scripts/etherFiS4Rewards/KingRewards_3_5_25.json";
    string public constant REWARD_PATH_4_2_25 = "/js-scripts/etherFiS4Rewards/KingRewards_4_2_25.json";
    string public constant REWARD_PATH_5_7_25 = "/js-scripts/etherFiS4Rewards/KingRewards_5_7_25.json";

    struct Vars {
        string user;
        address userAdd;
        uint256 amount;
        bytes32 root;
        string projectRoot;
        string claimPath;
        string claims;
        string amountPath;
        string rootPath;
        string proofPath;
        uint256 cumulativeClaimed;
        uint256 thisClaimAmount;
        uint256 ownerBalanceBefore;
        uint256 ownerBalanceAfter;
    }

    struct HistoricalReward {
        uint256 Amount;
        bytes32 AwardDate;
        bytes32 Root;
    }

    function run() public {
        ERC20 lrt2 = ERC20(MAINNET_LRT2);
        ILRT2Claim lrt2Claim = ILRT2Claim(MAINNET_ETHERFI_LRT2_CLAIM);
        RumpelModule rumpelModule = RumpelModule(MAINNET_RUMPEL_MODULE);

        Vars memory v = Vars("", address(0), 0, "", "", "", "", "", "", "", 0, 0, 0, 0);

        v.projectRoot = vm.projectRoot();
        v.claimPath = string.concat(v.projectRoot, REWARD_PATH_5_7_25);
        v.claims = vm.readFile(v.claimPath);
        string[] memory users = vm.parseJsonKeys(v.claims, ".");

        uint256 usersReceivingKing = 0;
        uint256 noNewPoints = 0;
        uint256 pointsDecreased = 0;

        vm.startBroadcast(MAINNET_ADMIN);
        for (uint256 i = 0; i < users.length; i++) {
            v.user = users[i];
            v.userAdd = stringToAddress(v.user);

            v.amountPath = string.concat(".", v.user, ".Amount");
            v.rootPath = string.concat(".", v.user, ".Root");
            v.proofPath = string.concat(".", v.user, ".Proofs");

            if (vm.keyExists(v.claims, v.amountPath)) {
                v.amount = vm.parseJsonUint(v.claims, v.amountPath);
                v.root = vm.parseJsonBytes32(v.claims, v.rootPath);
                bytes32[] memory proof = vm.parseJsonBytes32Array(v.claims, v.proofPath);

                require(v.root == EXPECTED_ROOT_5_7_25, "wrong root");

                v.cumulativeClaimed = lrt2Claim.cumulativeClaimed(v.userAdd);

                if (v.cumulativeClaimed == v.amount) {
                    console2.log(v.userAdd, "No New Points");
                    noNewPoints++;
                    continue;
                }
                if (v.cumulativeClaimed > v.amount) {
                    console2.log(v.userAdd, "Cumulative Greater Than Amount");
                    pointsDecreased++;
                    continue;
                }

                lrt2Claim.claim(v.userAdd, v.amount, v.root, proof);
                v.thisClaimAmount = v.amount - v.cumulativeClaimed;
                console2.log(v.userAdd, v.thisClaimAmount);

                address[] memory owners = ISafe(v.userAdd).getOwners();
                v.ownerBalanceBefore = lrt2.balanceOf(owners[0]);

                RumpelModule.Call[] memory transferCalls;
                transferCalls = new RumpelModule.Call[](1);
                transferCalls[0] = RumpelModule.Call({
                    safe: ISafe(v.userAdd),
                    to: MAINNET_LRT2,
                    data: abi.encodeWithSelector(ERC20.transfer.selector, owners[0], v.thisClaimAmount),
                    operation: Enum.Operation.Call
                });
                rumpelModule.exec(transferCalls);

                v.ownerBalanceAfter = lrt2.balanceOf(owners[0]);
                usersReceivingKing++;

                require(
                    v.ownerBalanceAfter - v.ownerBalanceBefore == v.thisClaimAmount, "User ending balance not right"
                );
                require(v.amount == lrt2Claim.cumulativeClaimed(v.userAdd), "User hasn't claimed full amount");
                require(lrt2.balanceOf(v.userAdd) == 0, "ERROR: Rumpel Wallet ending king balance != 0");
            }
        }
        console2.log(usersReceivingKing, "users receiving king");
        console2.log(noNewPoints, "users have no new points");
        console2.log(pointsDecreased, "users smaller balances");
        vm.stopBroadcast();
    }

    function stringToAddress(string memory _address) internal pure returns (address) {
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

interface ILRT2Claim {
    function claim(
        address account,
        uint256 cumulativeAmount,
        bytes32 expectedMerkleRoot,
        bytes32[] calldata merkleProof
    ) external;

    function cumulativeClaimed(address) external view returns (uint256);
}

interface RumpelModule {
    struct Call {
        ISafe safe;
        address to;
        bytes data;
        Enum.Operation operation;
    }

    function exec(Call[] calldata calls) external;
}

interface ISafe {
    function getOwners() external view returns (address[] memory);
}

library Enum {
    enum Operation {
        Call,
        DelegateCall
    }
}
