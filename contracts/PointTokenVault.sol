// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {MulticallUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/MulticallUpgradeable.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {LibString} from "solady/utils/LibString.sol";

import {PToken} from "./PToken.sol";

/// @title Point Token Vault
/// @notice Manages deposits and withdrawals for points-earning assets, point token claims, and reward redemptions.
contract PointTokenVault is UUPSUpgradeable, AccessControlUpgradeable, MulticallUpgradeable {
    using SafeTransferLib for ERC20;
    using MerkleProof for bytes32[];

    bytes32 public constant REDEMPTION_RIGHTS_PREFIX = keccak256("REDEMPTION_RIGHTS");
    bytes32 public constant MERKLE_UPDATER_ROLE = keccak256("MERKLE_UPDATER_ROLE");

    // Deposit asset balancess.
    mapping(address => mapping(ERC20 => uint256)) public balances; // user => point-earning token => balance

    // Merkle root distribution.
    mapping(address => mapping(bytes32 => uint256)) public claimedPTokens; // user => pointsId => claimed
    bytes32 public currRoot;
    bytes32 public prevRoot;
    mapping(address => mapping(bytes32 => uint256)) public claimedRedemptionRights; // user => pointsId => claimed

    mapping(bytes32 => PToken) public pointTokens; // pointsId => pointTokens

    mapping(bytes32 => RedemptionParams) public redemptions; // pointsId => redemptionParams

    struct Claim {
        bytes32 pointsId;
        uint256 totalClaimable;
        uint256 amountToClaim;
        bytes32[] proof;
    }

    struct RedemptionParams {
        ERC20 rewardToken;
        uint256 rewardsPerPointToken; // Assume 18 decimals.
        bool isMerkleBased;
    }

    event Deposit(address indexed receiver, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event RootUpdated(bytes32 prevRoot, bytes32 newRoot);
    event PTokensClaimed(address indexed account, bytes32 indexed pointsId, uint256 amount);
    event RewardsClaimed(address indexed owner, address indexed receiver, bytes32 indexed pointsId, uint256 amount);
    event RewardRedemptionSet(
        bytes32 indexed pointsId, ERC20 rewardToken, uint256 rewardsPerPointToken, bool isMerkleBased
    );

    error ProofInvalidOrExpired();
    error ClaimTooLarge();
    error RewardsNotReleased();
    error PTokenAlreadyDeployed();

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Multicall_init();
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function deposit(ERC20 _token, uint256 _amount, address _receiver) public {
        _token.safeTransferFrom(msg.sender, address(this), _amount);

        balances[_receiver][_token] += _amount;

        emit Deposit(_receiver, address(_token), _amount);
    }

    function withdraw(ERC20 _token, uint256 _amount, address _receiver) public {
        balances[msg.sender][_token] -= _amount;

        _token.safeTransfer(_receiver, _amount);

        emit Withdraw(_receiver, address(_token), _amount);
    }

    /// @notice Claims point tokens after verifying the merkle proof
    /// @param _claim The claim details including the merkle proof
    /// @param _account The account to claim for
    // Adapted from Morpho's RewardsDistributor.sol (https://github.com/morpho-org/morpho-optimizers/blob/main/src/common/rewards-distribution/RewardsDistributor.sol)
    function claimPointToken(Claim calldata _claim, address _account) public {
        bytes32 pointsId = _claim.pointsId;

        bytes32 claimHash = keccak256(abi.encodePacked(_account, pointsId, _claim.totalClaimable));
        _verifyClaimAndUpdateClaimed(_claim, claimHash, _account, claimedPTokens);

        pointTokens[pointsId].mint(_account, _claim.amountToClaim);

        emit PTokensClaimed(_account, pointsId, _claim.amountToClaim);
    }

    /// @notice Redeems rewards for point tokens
    /// @param _claim Details of the claim including the amount and merkle proof
    /// @param _receiver The account that will receive the msg.sender redeemed rewards
    function redeemRewards(Claim calldata _claim, address _receiver) public {
        (bytes32 pointsId, uint256 amountToClaim) = (_claim.pointsId, _claim.amountToClaim);

        RedemptionParams memory params = redemptions[pointsId];
        (ERC20 rewardToken, uint256 rewardsPerPointToken, bool isMerkleBased) =
            (params.rewardToken, params.rewardsPerPointToken, params.isMerkleBased);

        if (address(rewardToken) == address(0)) {
            revert RewardsNotReleased();
        }

        if (isMerkleBased) {
            // If it's merkle-based, only those callers with redemption rights can redeem their point token for rewards.

            bytes32 claimHash =
                keccak256(abi.encodePacked(REDEMPTION_RIGHTS_PREFIX, msg.sender, pointsId, _claim.totalClaimable));
            _verifyClaimAndUpdateClaimed(_claim, claimHash, msg.sender, claimedRedemptionRights);
        }

        // Will fail if the user doesn't also have enough point tokens.
        pointTokens[pointsId].burn(msg.sender, amountToClaim * 1e18 / rewardsPerPointToken);
        rewardToken.safeTransfer(_receiver, amountToClaim);
        emit RewardsClaimed(msg.sender, _receiver, pointsId, amountToClaim);
    }

    function deployPToken(bytes32 _pointsId) public {
        if (address(pointTokens[_pointsId]) != address(0)) {
            revert PTokenAlreadyDeployed();
        }

        (string memory name, string memory symbol) = LibString.unpackTwo(_pointsId); // Assume the points id was created using LibString.packTwo.
        pointTokens[_pointsId] = new PToken{salt: _pointsId}(name, symbol, 18);
    }

    // Internal ---

    function _verifyClaimAndUpdateClaimed(
        Claim calldata _claim,
        bytes32 _claimHash,
        address _account,
        mapping(address => mapping(bytes32 => uint256)) storage _claimed
    ) internal {
        bytes32 candidateRoot = _claim.proof.processProof(_claimHash);
        bytes32 pointsId = _claim.pointsId;
        uint256 amountToClaim = _claim.amountToClaim;

        // Check if the root is valid.
        if (candidateRoot != currRoot && candidateRoot != prevRoot) {
            revert ProofInvalidOrExpired();
        }

        uint256 alreadyClaimed = _claimed[_account][pointsId];

        // Can claim up to the total claimable amount from the hash.
        // IMPORTANT: totalClaimable must be in the claim hash passed into this function.
        if (_claim.totalClaimable < alreadyClaimed + amountToClaim) revert ClaimTooLarge();

        // Update the total claimed amount.
        unchecked {
            _claimed[_account][pointsId] = alreadyClaimed + amountToClaim;
        }
    }

    // Admin ---

    function updateRoot(bytes32 _newRoot) external onlyRole(MERKLE_UPDATER_ROLE) {
        prevRoot = currRoot;
        currRoot = _newRoot;
        emit RootUpdated(prevRoot, currRoot);
    }

    // Can be used to unlock reward token redemption (can also modify a live redemption, so use with care).
    function setRedemption(bytes32 _pointsId, ERC20 _rewardToken, uint256 _rewardsPerPointToken, bool _isMerkleBased)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        redemptions[_pointsId] = RedemptionParams(_rewardToken, _rewardsPerPointToken, _isMerkleBased);
        emit RewardRedemptionSet(_pointsId, _rewardToken, _rewardsPerPointToken, _isMerkleBased);
    }

    // To handle arbitrary reward claiming logic.
    function execute(address _to, bytes memory _data, uint256 _txGas)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bool success)
    {
        assembly {
            success := delegatecall(_txGas, _to, add(_data, 0x20), mload(_data), 0, 0)
        }
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
