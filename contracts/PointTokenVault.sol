// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

// infra
// - oracle
// - defender updater

// 4626 auto compounder

// gearbox to lever up on points
// list point selling marketsX

// integrate with trusted dashboards/aggregators like jupyter and definitive

// audits
// - infra audit (oracle audit)

// daily or weekly delay vs instanteous and forward looking

// module
// - swappable multisig for avs
// - canonical points token addresses across chains
// - script runs a zk proof?
// - verifiable script

//  proxy
// make sure the same tokens can be minted in the future
// multicall?
// need to map token to the points (probably admin function in the hub)
// need a way to associate all points relative to some total that won't shrink after ppl burn

// the scripte will need to generate merkle trees, and put in the exchange rate as soon as TGE occurs
// put in exchange rate at the end and pause new merkle trees
// permit?
// add storage slots for proxy upgradable
// handle rebasing tokens?

// future:
// - allownaces
// - pausable?

contract PToken is ERC20, Ownable {
    constructor(string memory _name, string memory _symbol, uint8 _decimals)
        ERC20(_name, _symbol, _decimals)
        Ownable(msg.sender)
    {}

    function mint(address to, uint256 value) public virtual onlyOwner {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual onlyOwner {
        _burn(from, value);
    }
}

contract PointTokenVault is UUPSUpgradeable, OwnableUpgradeable {
    using SafeTransferLib for ERC20;

    PointTokenMinter public pointTokenMinter;

    // Deposit asset balances
    mapping(address user => mapping(ERC20 token => uint256 balance)) public balances;

    // Merkle root distribution
    mapping(address user => mapping(bytes32 pointsId => uint256 claimed)) public claimed;
    mapping(bytes32 pointsId => bytes32 root) public currRoot;
    mapping(bytes32 pointsId => bytes32 root) public prevRoot;

    mapping(bytes32 pointsId => uint256 totalSupply) public totalSupply;

    struct Claim {
        address _account;
        bytes32 _pointsId;
        uint256 _claimable;
        bytes32[] _proof;
    }

    enum Operation {
        Call,
        DelegateCall
    }

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event RootUpdated(bytes32 indexed pointsId, bytes32 newRoot);
    event RewardsClaimed(address indexed user, bytes32 indexed pointsId, uint256 amount);

    error AlreadyClaimed();
    error ProofInvalidOrExpired();
    error NotDistributed();

    function initialize(PointTokenMinter _pointTokenMinter) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        pointTokenMinter = _pointTokenMinter;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function deposit(ERC20 token, uint256 amount, address receiver) public virtual returns (uint256 shares) {
        // Need to transfer before minting or ERC777s could reenter.
        token.safeTransferFrom(msg.sender, address(this), amount);

        balances[receiver][token] += amount;

        emit Deposit(receiver, address(token), amount);
    }

    function withdraw(ERC20 token, uint256 amount, address receiver) public virtual returns (uint256 shares) {
        balances[msg.sender][token] -= amount;

        emit Withdraw(msg.sender, address(token), amount);

        token.safeTransfer(receiver, amount);
    }

    function updateRoot(bytes32 _newRoot, bytes32 _pointsId) external onlyOwner {
        // Points id will be converted into a string for the token name, so it should make sense in that context
        prevRoot[_pointsId] = currRoot[_pointsId];
        currRoot[_pointsId] = _newRoot;
        emit RootUpdated(_pointsId, _newRoot); // todo: emit string version of id
    }

    function claimPointsTokens(Claim[] calldata claims) external {
        for (uint256 i = 0; i < claims.length; i++) {
            Claim memory claim = claims[i];
            _claimPointsToken(claim._account, claim._pointsId, claim._claimable, claim._proof);
        }
    }

    function _claimPointsToken(address _account, bytes32 _pointsId, uint256 _claimable, bytes32[] memory _proof)
        internal
    {
        bytes32 candidateRoot =
            MerkleProof.processProof(_proof, keccak256(abi.encodePacked(_account, _pointsId, _claimable)));

        if (candidateRoot != currRoot[_pointsId] && candidateRoot != prevRoot[_pointsId]) {
            revert ProofInvalidOrExpired();
        }

        uint256 alreadyClaimed = claimed[_account][_pointsId];
        if (_claimable <= alreadyClaimed) revert AlreadyClaimed();

        uint256 amount;
        unchecked {
            amount = _claimable - alreadyClaimed;
        }

        claimed[_account][_pointsId] = _claimable;

        pointTokenMinter.mint(_account, _pointsId, amount);

        emit RewardsClaimed(_account, _pointsId, amount);
    }

    // function _getRedemptionRights(address _account, bytes32 _pointsId, uint256 _rights, bytes32[] memory _proof)
    //     internal
    // {
    //     bytes32 candidateRoot = MerkleProof.processProof(
    //         _proof, keccak256(abi.encodePacked("redemption_rights", _account, _pointsId, _rights))
    //     );

    //     // verify this works with two things
    //     if (candidateRoot != currRoot[_pointsId] && candidateRoot != prevRoot[_pointsId]) {
    //         revert ProofInvalidOrExpired();
    //     }

    //     uint256 alreadyClaimed = claimed[_account][_pointsId];
    //     if (_claimable <= alreadyClaimed) revert AlreadyClaimed();

    //     uint256 amount;
    //     unchecked {
    //         amount = _claimable - alreadyClaimed;
    //     }

    //     claimed[_account][_pointsId] = _claimable;

    //     pointTokenMinter.mint(_account, _pointsId, amount);

    //     emit RewardsClaimed(_account, _pointsId, amount);
    // }

    // To handle arbitrary claiming logic for the rewards
    function execute(address to, uint256 value, bytes memory data, Operation operation, uint256 txGas)
        external
        onlyOwner
        returns (bool success)
    {
        if (operation == Operation.DelegateCall) {
            assembly {
                success := delegatecall(txGas, to, add(data, 0x20), mload(data), 0, 0)
            }
        } else {
            assembly {
                success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
            }
        }
    }

    enum RewardState {
        PreDistribution,
        RightsBased,
        Final
    }

    struct RewardParams {
        ERC20 reward;
        uint256 exchangeRate;
        RewardState rewardState;
    }

    mapping(bytes32 pointsId => RewardParams rewardParams) public rewards;

    function claimRewardToken(bytes32 _pointsId, address _receiver, uint256 _amount) external onlyOwner {
        if (rewards[_pointsId].rewardState == RewardState.PreDistribution) {
            revert NotDistributed();
        }

        if (rewards[_pointsId].rewardState == RewardState.RightsBased) {
            // process proof for how many points tokens this address has a right to still redeem, and then give the rewards accordingly
        }

        if (rewards[_pointsId].rewardState == RewardState.Final) {
            rewards[_pointsId].reward.safeTransfer(_receiver, _amount * rewards[_pointsId].exchangeRate / 1e18);
            pointTokenMinter.burn(_receiver, _pointsId, _amount);
        }
    }

    // will the reward always be erc20?
    function unlockRewards(bytes32 _pointsId, ERC20 _reward, uint256 _exchangeRate, RewardState _rewardState)
        external
        onlyOwner
    {
        // exchange rate from point token to reward (POINT_TOKEN/REWARD_TOKEN)
        rewards[_pointsId] = RewardParams(_reward, _exchangeRate, _rewardState);
    }

    function setPointTokenMinter(PointTokenMinter _pointTokenMinter) external onlyOwner {
        pointTokenMinter = _pointTokenMinter;
    }
}

contract PointTokenMinter is UUPSUpgradeable, OwnableUpgradeable {
    mapping(bytes32 pointsId => PToken token) public pointsTokens;
    mapping(address user => bool isTrusted) isTrusted;

    event Trusted(address indexed user, bool trusted);

    modifier onlyTrusted() {
        require(isTrusted[msg.sender], "PTMinter: Only trusted can call this function");
        _;
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function mint(address _account, bytes32 _pointsId, uint256 _amount) external onlyTrusted {
        if (address(pointsTokens[_pointsId]) == address(0)) {
            pointsTokens[_pointsId] =
                new PToken(string(abi.encodePacked(_pointsId)), string(abi.encodePacked(_pointsId)), 18); // owns tokens
        }

        pointsTokens[_pointsId].mint(_account, _amount);
    }

    function burn(address _account, bytes32 _pointsId, uint256 _amount) external onlyTrusted {
        pointsTokens[_pointsId].burn(_account, _amount);
    }

    function grantTokenOwnership(address _newOwner, bytes32 _pointsId) external onlyOwner {
        pointsTokens[_pointsId].transferOwnership(_newOwner);
    }

    function setTrusted(address _user, bool _isTrusted) external onlyOwner {
        isTrusted[_user] = _isTrusted;
        emit Trusted(_user, _isTrusted);
    }
}
