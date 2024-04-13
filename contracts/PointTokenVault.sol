// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {LibString} from "solady/utils/LibString.sol";

import {PToken} from "./PToken.sol";

contract PointTokenVault is UUPSUpgradeable, OwnableUpgradeable {
    using SafeTransferLib for ERC20;
    using MerkleProof for bytes32[];

    PointTokenHub public pointTokenHub;

    // Deposit asset balancess.
    mapping(address => mapping(ERC20 => uint256)) public balances; // user => token => balance

    // Core merkle root distribution.
    mapping(address => mapping(bytes32 => uint256)) public claimedPTokens; // user => pointsId => claimed
    mapping(bytes32 => bytes32) public currRoot; // pointsId => root
    mapping(bytes32 => bytes32) public prevRoot; // pointsId => root

    // Redemption rights distribution for conditional redemptions.
    mapping(address => mapping(bytes32 => uint256)) public claimedRedemptionRights; // user => pointsId => claimed

    struct Claim {
        bytes32 pointsId;
        uint256 claimable;
        bytes32[] proof;
    }

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event RootUpdated(bytes32 indexed pointsId, bytes32 newRoot);
    event PTokensClaimed(address indexed account, bytes32 indexed pointsId, uint256 amount);
    event RewardsClaimed(address indexed owner, address indexed receiver, bytes32 indexed pointsId, uint256 amount);

    error ProofInvalidOrExpired();
    error AlreadyClaimed();
    error NotDistributed();
    error InvalidPointsId();

    constructor() {
        _disableInitializers(); // todo: do we need this?
    }

    function initialize(PointTokenHub _pointTokenHub) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        pointTokenHub = _pointTokenHub;
    }

    function deposit(ERC20 _token, uint256 _amount, address _receiver) public {
        // Need to transfer before minting or ERC777s could reenter.
        _token.safeTransferFrom(msg.sender, address(this), _amount);

        balances[_receiver][_token] += _amount;

        emit Deposit(_receiver, address(_token), _amount);
    }

    function withdraw(ERC20 _token, uint256 _amount, address _receiver) public {
        balances[msg.sender][_token] -= _amount;

        emit Withdraw(msg.sender, address(_token), _amount);

        _token.safeTransfer(_receiver, _amount);
    }

    // Assume the points id was created using LibString.packTwo for readable token names.
    function updateRoot(bytes32 _newRoot, bytes32 _pointsId) external onlyOwner {
        if (_pointsId == bytes32(0)) revert InvalidPointsId();
        prevRoot[_pointsId] = currRoot[_pointsId];
        currRoot[_pointsId] = _newRoot;
        emit RootUpdated(_pointsId, _newRoot);
    }

    function claimPointTokens(Claim[] calldata _claims, address _account) external {
        for (uint256 i = 0; i < _claims.length; i++) {
            _claimPointsToken(_claims[i], _account);
        }
    }

    // Adopted from Morpho's RewardsDistributor.sol (https://github.com/morpho-org/morpho-optimizers/blob/main/src/common/rewards-distribution/RewardsDistributor.sol)
    function _claimPointsToken(Claim calldata _claim, address _account) internal {
        (bytes32 _pointsId, uint256 _claimable) = (_claim.pointsId, _claim.claimable);

        if (!isValidProof(_claim, keccak256(abi.encodePacked(_account, _pointsId, _claimable)))) {
            revert ProofInvalidOrExpired();
        }

        uint256 alreadyClaimed = claimedPTokens[_account][_pointsId];
        if (_claimable <= alreadyClaimed) revert AlreadyClaimed();

        uint256 amount;
        unchecked {
            amount = _claimable - alreadyClaimed;
        }

        claimedPTokens[_account][_pointsId] = _claimable;

        pointTokenHub.mint(_account, _pointsId, amount);

        emit PTokensClaimed(_account, _pointsId, amount);
    }

    // Redeem points tokens for reward tokens.
    function redeemRewards(bytes32 _pointsId, address _receiver, uint256 _amount) external {
        (ERC20 rewardToken, uint256 exchangeRate, PointTokenHub.RedemptionType redemptionType) =
            pointTokenHub.redemptionParams(_pointsId);

        if (rewardToken == ERC20(address(0))) {
            revert NotDistributed();
        }

        if (redemptionType == PointTokenHub.RedemptionType.Simple) {
            pointTokenHub.burn(msg.sender, _pointsId, _amount);
            uint256 rewardAmount = _amount * exchangeRate / 1e18;
            rewardToken.safeTransfer(_receiver, rewardAmount);
            emit RewardsClaimed(msg.sender, _receiver, _pointsId, rewardAmount);
        }
    }

    // If the reward process is conditional, only address that have both the points token and redemption rights can redeem
    function redeemRewards(Claim calldata _claim, address _receiver) external {
        (bytes32 _pointsId, uint256 _claimable) = (_claim.pointsId, _claim.claimable);

        (ERC20 rewardToken, uint256 exchangeRate, PointTokenHub.RedemptionType redemptionType) =
            pointTokenHub.redemptionParams(_pointsId);

        if (rewardToken == ERC20(address(0))) {
            revert NotDistributed();
        }

        if (redemptionType == PointTokenHub.RedemptionType.Conditional) {
            // Admin overloads the merkle root with user redemption rights for conditional redemption.

            // msg.sender must have the rights
            bytes32 claimHash = keccak256(abi.encodePacked("REDEMPTION_RIGHTS", msg.sender, _pointsId, _claimable));
            if (!isValidProof(_claim, claimHash)) {
                revert ProofInvalidOrExpired();
            }

            uint256 alreadyClaimed = claimedRedemptionRights[msg.sender][_pointsId];
            if (_claimable <= alreadyClaimed) revert AlreadyClaimed();

            uint256 amount;
            unchecked {
                amount = _claimable - alreadyClaimed;
            }

            claimedRedemptionRights[msg.sender][_pointsId] = _claimable;

            // Will fail if the user doesn't also have enough point tokens.
            pointTokenHub.burn(msg.sender, _pointsId, amount);
            uint256 rewardAmount = amount * exchangeRate / 1e18;
            rewardToken.safeTransfer(_receiver, rewardAmount);

            emit RewardsClaimed(msg.sender, _receiver, _pointsId, rewardAmount);
        }
    }

    function isValidProof(Claim calldata _claim, bytes32 _claimHash) internal view returns (bool) {
        bytes32 candidateRoot = _claim.proof.processProof(_claimHash);

        return candidateRoot == currRoot[_claim.pointsId] || candidateRoot == prevRoot[_claim.pointsId];
    }

    // To handle arbitrary reward claiming logic.
    // TODO: can we restrict what the admin can do here?
    function execute(address _to, bytes memory _data, uint256 _txGas) external onlyOwner returns (bool success) {
        assembly {
            success := delegatecall(_txGas, _to, add(_data, 0x20), mload(_data), 0, 0)
        }
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}

contract PointTokenHub is UUPSUpgradeable, OwnableUpgradeable {
    mapping(bytes32 => PToken) public pointTokens; // pointsId => pointTokens

    // Trust ---
    mapping(address => bool) isTrusted;
    mapping(bytes32 => RedemptionParams) public redemptionParams; // pointsId => redemptionParams

    modifier onlyTrusted() {
        require(isTrusted[msg.sender], "PTHub: Only trusted can call this function");
        _;
    }

    event Trusted(address indexed user, bool trusted);
    event RewardRedemptionSet(
        bytes32 indexed pointsId, ERC20 rewardToken, uint256 exchangeRate, RedemptionType redemptionType
    );

    enum RedemptionType {
        Simple,
        Conditional
    }

    struct RedemptionParams {
        ERC20 rewardToken;
        uint256 exchangeRate; // Exchange rate from point token to reward token (pToken/rewardToken)
        RedemptionType redemptionType;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function mint(address _account, bytes32 _pointsId, uint256 _amount) external onlyTrusted {
        if (address(pointTokens[_pointsId]) == address(0)) {
            (string memory name, string memory symbol) = LibString.unpackTwo(_pointsId);
            pointTokens[_pointsId] = new PToken{salt: _pointsId}(name, symbol, 18);
        }

        pointTokens[_pointsId].mint(_account, _amount);
    }

    function burn(address _account, bytes32 _pointsId, uint256 _amount) external onlyTrusted {
        pointTokens[_pointsId].burn(_account, _amount);
    }

    // Admin ---

    // Can be used to unlock reward token redemption (can also be used to lock a live redemption)
    function setRewardRedemption(
        bytes32 _pointsId,
        ERC20 _rewardToken,
        uint256 _exchangeRate,
        RedemptionType _redemptionType
    ) external onlyOwner {
        redemptionParams[_pointsId] = RedemptionParams(_rewardToken, _exchangeRate, _redemptionType);
        emit RewardRedemptionSet(_pointsId, _rewardToken, _exchangeRate, _redemptionType);
    }

    function grantTokenOwnership(address _newOwner, bytes32 _pointsId) external onlyOwner {
        pointTokens[_pointsId].transferOwnership(_newOwner);
    }

    function setTrusted(address _user, bool _isTrusted) external onlyOwner {
        isTrusted[_user] = _isTrusted;
        emit Trusted(_user, _isTrusted);
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
