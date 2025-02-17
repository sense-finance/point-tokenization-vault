// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import "forge-std/console2.sol";

contract EtherFiS4ClaimScript is Script {
    address public MAINNET_ADMIN = 0x9D89745fD63Af482ce93a9AdB8B0BbDbb98D3e06;
    address public MAINNET_POINT_TOKENIZATION_VAULT = 0xe47F9Dbbfe98d6930562017ee212C1A1Ae45ba61;

    address public constant MAINNET_ETHERFI_LRT2_CLAIM = 0x6Db24Ee656843E3fE03eb8762a54D86186bA6B64;
    address public constant MAINNET_LRT2 = 0x8F08B70456eb22f6109F57b8fafE862ED28E6040;

    address public constant MAINNET_RUMPEL_MODULE = 0x28c3498B4956f4aD8d4549ACA8F66260975D361a;

    bytes32 public constant REWARD_ROOT = 0x2643c31ec7b7d9d1e8aa5202453912b1d02fd33c91b2b07c4dc3fc5965e473c5;
    bytes32 public constant STAKING_ROOT = 0xb580f88a22e883f6cda41930e0fb565338e3103856221b7affda51cad7a5048d;

    // Overrides for wallets who have already claimed king
    // Note the amount they've previously claimed and remove it from their staked rewards
    // https://etherscan.io/tx/0xa7cb70a54384efcc0d265157e20331f94dd998c28f0e961435193220ccd9d2f4
    uint256 public USER_OVERRIDE_PREV_TRANSFER_1 = 19386471377007458; // wallet = 0xce2f33c58f7aF3338a9D4Bd7baAf6F4a01E1Ea30

    // https://etherscan.io/tx/0xd696eede2931d840dd245adcaf2e51e8550e996dcbfcf979cfe98fc53a665a81
    uint256 public USER_OVERRIDE_PREV_TRANSFER_2 = 83345865624621196; // wallet = 0xc64A3628278CDe9239786C057528608c4421b86F

    struct Vars {
        string user;
        address userAdd;
        uint256 amount;
        bytes32 root;
        uint256 stakingRewards;
        uint256 rewardAmount;
        string projectRoot;
        string claimPath;
        string claims;
        string amountPath;
        string historicalRewardsPath;
        string rootPath;
        string proofPath;
        uint256 vaultBalanceBefore;
        uint256 ownerBalanceBefore;
    }

    struct HistoricalReward {
        uint256 Amount;
        bytes32 AwardDate;
        bytes32 Root;
    }

    // 1. get all rumpel wallets (users) from the JSON - for each user:
    // 2. get that users current root & amount (check current root is expected root). amount = total claimable
    // 3. get that users historical reward associated with the last staking reward root. this is the total staking rewards
    // 4. get that users proof
    // 5. claim from the merkle contract (can come from any contract, so directly from merkle)
    // 6. calculate the user's reward amount (^2 - 3)
    // 7. override the total staking rewards for user if they've previously claimed
    // 8. use the module to execute two transfers from the rumpel wallet
    // 8a. transfer reward amount to the point tokenization vault
    // 8b. transfer the staking rewards to the rumpel wallet owner
    function run() public {
        ERC20 lrt2 = ERC20(MAINNET_LRT2);
        ILRT2Claim lrt2Claim = ILRT2Claim(MAINNET_ETHERFI_LRT2_CLAIM);
        RumpelModule rumpelModule = RumpelModule(MAINNET_RUMPEL_MODULE);

        Vars memory v = Vars("", address(0), 0, "", 0, 0, "", "", "", "", "", "", "", 0, 0);

        v.projectRoot = vm.projectRoot();
        v.claimPath = string.concat(v.projectRoot, "/js-scripts/etherFiS4Rewards/KingRewards.json");
        v.claims = vm.readFile(v.claimPath);
        string[] memory users = vm.parseJsonKeys(v.claims, ".");

        vm.startBroadcast(MAINNET_ADMIN);
        for (uint256 i = 0; i < users.length; i++) {
            v.user = users[i];
            v.userAdd = stringToAddress(v.user);
            v.amountPath = string.concat(".", v.user, ".Amount");
            v.historicalRewardsPath = string.concat(".", v.user, ".HistoricalRewards");
            v.rootPath = string.concat(".", v.user, ".Root");
            v.proofPath = string.concat(".", v.user, ".Proofs");

            v.stakingRewards = 0;
            uint256 j = 0;
            if (vm.keyExists(v.claims, v.amountPath)) {
                if (vm.keyExists(v.claims, v.historicalRewardsPath)) {
                    v.amount = vm.parseJsonUint(v.claims, v.amountPath);
                    v.root = vm.parseJsonBytes32(v.claims, v.rootPath);

                    if (REWARD_ROOT != v.root) {
                        revert("ERROR: Current Root not expected");
                    }

                    while (true) {
                        try vm.parseJsonBytes32(
                            v.claims, string.concat(v.historicalRewardsPath, "[", vm.toString(j), "].Root")
                        ) {
                            bytes32 historicalRoot = vm.parseJsonBytes32(
                                v.claims, string.concat(v.historicalRewardsPath, "[", vm.toString(j), "].Root")
                            );
                            if (historicalRoot == STAKING_ROOT) {
                                v.stakingRewards = vm.parseJsonUint(
                                    v.claims, string.concat(v.historicalRewardsPath, "[", vm.toString(j), "].Amount")
                                );
                                break;
                            }
                            j = j + 1;
                        } catch {
                            break;
                        }
                    }
                }

                bytes32[] memory proof = vm.parseJsonBytes32Array(v.claims, v.proofPath);
                lrt2Claim.claim(v.userAdd, v.amount, v.root, proof);

                address[] memory owners = ISafe(v.userAdd).getOwners();
                v.rewardAmount = v.amount - v.stakingRewards;
                if (v.userAdd == 0xce2f33c58f7aF3338a9D4Bd7baAf6F4a01E1Ea30) {
                    v.stakingRewards = v.stakingRewards - USER_OVERRIDE_PREV_TRANSFER_1;
                    console2.log("override staking rewards:");
                    console2.log(v.stakingRewards);
                }
                if (v.userAdd == 0xc64A3628278CDe9239786C057528608c4421b86F) {
                    v.stakingRewards = v.stakingRewards - USER_OVERRIDE_PREV_TRANSFER_2;
                    console2.log("override staking rewards:");
                    console2.log(v.stakingRewards);
                }

                v.vaultBalanceBefore = lrt2.balanceOf(MAINNET_POINT_TOKENIZATION_VAULT);
                v.ownerBalanceBefore = lrt2.balanceOf(owners[0]);

                RumpelModule.Call[] memory transferCalls = new RumpelModule.Call[](2);
                transferCalls[0] = RumpelModule.Call({
                    safe: ISafe(v.userAdd),
                    to: MAINNET_LRT2,
                    data: abi.encodeWithSelector(ERC20.transfer.selector, MAINNET_POINT_TOKENIZATION_VAULT, v.rewardAmount),
                    operation: Enum.Operation.Call
                });
                transferCalls[1] = RumpelModule.Call({
                    safe: ISafe(v.userAdd),
                    to: MAINNET_LRT2,
                    data: abi.encodeWithSelector(ERC20.transfer.selector, owners[0], v.stakingRewards),
                    operation: Enum.Operation.Call
                });
                rumpelModule.exec(transferCalls);

                console2.log(v.userAdd);
                console2.log(v.amount, " - total claim");
                console2.log(v.rewardAmount + v.stakingRewards);
                console2.log(v.rewardAmount, " - reward amount");
                console2.log(v.stakingRewards, " - staking rewards");
                console2.log(lrt2.balanceOf(MAINNET_POINT_TOKENIZATION_VAULT), " - vault balance");
                console2.log(lrt2.balanceOf(owners[0]), " - owner balance");
                console2.log(lrt2.balanceOf(v.userAdd), " - wallet balance");
                console2.log();

                require(lrt2.balanceOf(v.userAdd) == 0, "ERROR: Rumpel Wallet ending king balance != 0");
                require(
                    lrt2.balanceOf(MAINNET_POINT_TOKENIZATION_VAULT) - v.vaultBalanceBefore == v.rewardAmount,
                    "ERROR: Token Vault Delta is Wrong"
                );
                require(
                    lrt2.balanceOf(owners[0]) - v.ownerBalanceBefore == v.stakingRewards, "ERROR: Owner Delta is Wrong"
                );
            }
        }
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
