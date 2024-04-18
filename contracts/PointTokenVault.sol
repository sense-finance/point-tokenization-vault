// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {PointTokenHub} from "./PointTokenHub.sol";

contract PointTokenVault is UUPSUpgradeable, AccessControlUpgradeable {
    using SafeTransferLib for ERC20;
    using MerkleProof for bytes32[];

    bytes32 public constant MERKLE_UPDATER_ROLE = keccak256("MERKLE_UPDATER_ROLE");
    bytes32 public constant REDEMPTION_RIGHTS_PREFIX = keccak256("REDEMPTION_RIGHTS");

    PointTokenHub public pointTokenHub;

    // Deposit asset balancess.
    mapping(address => mapping(ERC20 => uint256)) public balances; // user => point-earning token => balance

    // Merkle root distribution.
    mapping(address => mapping(bytes32 => uint256)) public claimedPTokens; // user => pointsId => claimed
    bytes32 public currRoot;
    bytes32 public prevRoot;
    mapping(address => mapping(bytes32 => uint256)) public claimedRedemptionRights; // user => pointsId => claimed

    struct Claim {
        bytes32 pointsId;
        uint256 totalClaimable;
        uint256 amountToClaim;
        bytes32[] proof;
    }

    event Deposit(address indexed receiver, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event RootUpdated(bytes32 prevRoot, bytes32 newRoot);
    event PTokensClaimed(address indexed account, bytes32 indexed pointsId, uint256 amount);
    event RewardsClaimed(address indexed owner, address indexed receiver, bytes32 indexed pointsId, uint256 amount);

    error ProofInvalidOrExpired();
    error ClaimTooLarge();
    error RewardsNotReleased();

    constructor() {
        _disableInitializers();
    }

    function initialize(PointTokenHub _pointTokenHub) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        pointTokenHub = _pointTokenHub;
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

    function claimPointTokens(Claim[] calldata _claims, address _account) external {
        for (uint256 i = 0; i < _claims.length; i++) {
            _claimPointsToke(_claims[i], _account);
        }
    }

    // Adapted from Morpho's RewardsDistributor.sol (https://github.com/morpho-org/morpho-optimizers/blob/main/src/common/rewards-distribution/RewardsDistributor.sol)
    function _claimPointsToke(Claim calldata _claim, address _account) internal {
        bytes32 pointsId = _claim.pointsId;

        bytes32 claimHash = keccak256(abi.encodePacked(_account, pointsId, _claim.totalClaimable));
        _verifyClaimAndUpdateClaimed(_claim, claimHash, _account, claimedPTokens);

        pointTokenHub.mint(_account, pointsId, _claim.amountToClaim);

        emit PTokensClaimed(_account, pointsId, _claim.amountToClaim);
    }

    function redeemRewards(Claim calldata _claim, address _receiver) external {
        (bytes32 pointsId, uint256 amountToClaim) = (_claim.pointsId, _claim.amountToClaim);

        (ERC20 rewardToken, uint256 exchangeRate, bool isMerkleBased) = pointTokenHub.redemptionParams(pointsId);

        if (address(rewardToken) == address(0)) {
            revert RewardsNotReleased();
        }

        if (isMerkleBased) {
            // Only those with redemption rights can redeem their point tokens for rewards.

            bytes32 claimHash =
                keccak256(abi.encodePacked(REDEMPTION_RIGHTS_PREFIX, msg.sender, pointsId, _claim.totalClaimable));
            _verifyClaimAndUpdateClaimed(_claim, claimHash, msg.sender, claimedRedemptionRights);

            // Will fail if the user doesn't also have enough point tokens.
            pointTokenHub.burn(msg.sender, pointsId, amountToClaim * 1e18 / exchangeRate);
            rewardToken.safeTransfer(_receiver, amountToClaim);
            emit RewardsClaimed(msg.sender, _receiver, pointsId, amountToClaim);
        } else {
            // Anyone can redeem their point tokens for rewards.

            pointTokenHub.burn(msg.sender, pointsId, amountToClaim * 1e18 / exchangeRate);
            rewardToken.safeTransfer(_receiver, amountToClaim);
            emit RewardsClaimed(msg.sender, _receiver, pointsId, amountToClaim);
        }
    }

    function _verifyClaimAndUpdateClaimed(
        Claim calldata _claim,
        bytes32 _claimHash,
        address _account,
        mapping(address => mapping(bytes32 => uint256)) storage _claimed
    ) internal {
        bytes32 candidateRoot = _claim.proof.processProof(_claimHash);
        bytes32 pointsId = _claim.pointsId;
        uint256 totalClaimable = _claim.totalClaimable; // IMPORTANT: Must be in the claim hash.
        uint256 amountToClaim = _claim.amountToClaim;

        if (candidateRoot != currRoot && candidateRoot != prevRoot) {
            revert ProofInvalidOrExpired();
        }

        uint256 alreadyClaimed = _claimed[_account][pointsId];

        if (totalClaimable < alreadyClaimed + amountToClaim) revert ClaimTooLarge();

        _claimed[_account][pointsId] = alreadyClaimed + amountToClaim;
    }

    // Admin ---

    function updateRoot(bytes32 _newRoot) external onlyRole(MERKLE_UPDATER_ROLE) {
        prevRoot = currRoot;
        currRoot = _newRoot;
        emit RootUpdated(prevRoot, currRoot);
    }

    // To handle arbitrary reward claiming logic.
    // TODO: kinda scary, can we restrict what the admin can do here?
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
