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

    bytes32 public constant REDEMPTION_RIGHTS_PREFIX = keccak256(abi.encodePacked("REDEMPTION_RIGHTS"));

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

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event RootUpdated(bytes32 prevRoot, bytes32 newRoot);
    event PTokensClaimed(address indexed account, bytes32 indexed pointsId, uint256 amount);
    event RewardsClaimed(address indexed owner, address indexed receiver, bytes32 indexed pointsId, uint256 amount);

    error ProofInvalidOrExpired();
    error ClaimTooLarge();
    error NotDistributed();
    error InvalidPointsId();

    constructor() {
        _disableInitializers();
    }

    function initialize(PointTokenHub _pointTokenHub) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        pointTokenHub = _pointTokenHub;
    }

    function deposit(ERC20 _token, uint256 _amount, address _receiver) public {
        _token.safeTransferFrom(msg.sender, address(this), _amount);

        balances[_receiver][_token] += _amount;

        emit Deposit(_receiver, address(_token), _amount);
    }

    function withdraw(ERC20 _token, uint256 _amount, address _receiver) public {
        balances[msg.sender][_token] -= _amount;

        emit Withdraw(msg.sender, address(_token), _amount);

        _token.safeTransfer(_receiver, _amount);
    }

    function claimPointTokens(Claim[] calldata _claims, address _account) external {
        for (uint256 i = 0; i < _claims.length; i++) {
            _claimPointsToken(_claims[i], _account);
        }
    }

    // Adapted from Morpho's RewardsDistributor.sol (https://github.com/morpho-org/morpho-optimizers/blob/main/src/common/rewards-distribution/RewardsDistributor.sol)
    function _claimPointsToken(Claim calldata _claim, address _account) internal {
        bytes32 pointsId = _claim.pointsId;

        bytes32 claimHash = keccak256(abi.encodePacked(_account, pointsId, _claim.totalClaimable));
        _verifyClaimAndUpdateClaimed(_claim, claimHash, _account, claimedPTokens);

        pointTokenHub.mint(_account, pointsId, _claim.amountToClaim);

        emit PTokensClaimed(_account, pointsId, _claim.amountToClaim);
    }

    function redeemRewards(Claim calldata _claim, address _receiver) external {
        (bytes32 pointsId, uint256 amountToClaim) = (_claim.pointsId, _claim.amountToClaim);

        (ERC20 rewardToken, uint256 exchangeRate, bool isMerkleBased) = pointTokenHub.redemptionParams(pointsId);

        if (rewardToken == ERC20(address(0))) {
            revert NotDistributed();
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

        _claimed[_account][pointsId] = amountToClaim + alreadyClaimed;
    }

    // Admin ---

    // Assume the points id was created using LibString.packTwo for readable token names.
    function updateRoot(bytes32 _newRoot) external onlyOwner {
        emit RootUpdated(prevRoot, _newRoot);
        prevRoot = currRoot;
        currRoot = _newRoot;
    }

    // To handle arbitrary reward claiming logic.
    // TODO: kinda scary, can we restrict what the admin can do here?
    function execute(address _to, bytes memory _data, uint256 _txGas) external onlyOwner returns (bool success) {
        assembly {
            success := delegatecall(_txGas, _to, add(_data, 0x20), mload(_data), 0, 0)
        }
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}

contract PointTokenHub is UUPSUpgradeable, OwnableUpgradeable {
    error OnlyTrusted();
    // Trust ---

    mapping(address => bool) public isTrusted; // user => isTrusted

    mapping(bytes32 => PToken) public pointTokens; // pointsId => pointTokens
    mapping(bytes32 => RedemptionParams) public redemptionParams; // pointsId => redemptionParams

    struct RedemptionParams {
        ERC20 rewardToken;
        uint256 exchangeRate; // Rate from point token to reward token (pToken/rewardToken). 18 decimals.
        bool isMerkleBased;
    }

    modifier onlyTrusted() {
        if (!isTrusted[msg.sender]) revert OnlyTrusted();
        _;
    }

    event Trusted(address indexed user, bool trusted);
    event RewardRedemptionSet(bytes32 indexed pointsId, ERC20 rewardToken, uint256 exchangeRate, bool isMerkleBased);

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function mint(address _account, bytes32 _pointsId, uint256 _amount) external onlyTrusted {
        if (address(pointTokens[_pointsId]) == address(0)) {
            (string memory name, string memory symbol) = LibString.unpackTwo(_pointsId); // Assume the points id was created using LibString.packTwo.
            pointTokens[_pointsId] = new PToken{salt: _pointsId}(name, symbol, 18);
        }

        pointTokens[_pointsId].mint(_account, _amount);
    }

    function burn(address _account, bytes32 _pointsId, uint256 _amount) external onlyTrusted {
        pointTokens[_pointsId].burn(_account, _amount);
    }

    // Admin ---

    // Can be used to unlock reward token redemption (can also be used to modify a live redemption)
    // Should be used after claiming rewards.
    function setRedemption(bytes32 _pointsId, ERC20 _rewardToken, uint256 _exchangeRate, bool _isMerkleBased)
        external
        onlyOwner
    {
        redemptionParams[_pointsId] = RedemptionParams(_rewardToken, _exchangeRate, _isMerkleBased);
        emit RewardRedemptionSet(_pointsId, _rewardToken, _exchangeRate, _isMerkleBased);
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
