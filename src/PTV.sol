// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626} from "solmate/tokens/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

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

// future:
// - allownaces

contract PTV is Ownable, UUPSUpgradeable, Initializable {
    using SafeTransferLib for ERC20;

    error AlreadyClaimed();

    PTVHub public hub;
    mapping(address => mapping(address => uint256)) public allowance;

    mapping(address user => mapping(ERC20 token => uint256 balance)) public balances;
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

    function initialize(PTVHub _hub) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        hub = _hub;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function deposit(ERC20 token, uint256 amount, address receiver) public virtual returns (uint256 shares) {
        // Need to transfer before minting or ERC777s could reenter.
        token.safeTransferFrom(msg.sender, address(this), amount);

        balances[receiver][token] += amount;

        // emit deposit event
    }

    function withdraw(ERC20 token, uint256 amount, address receiver) public virtual returns (uint256 shares) {
        balances[msg.sender][token] -= amount;

        // emit Withdraw(msg.sender, receiver, msg.sender, amount);

        token.safeTransfer(receiver, amount);
    }

    function updateRoot(bytes32 _newRoot, bytes32 _pointsId) external onlyOwner {
        prevRoot[_pointsId] = currRoot[_pointsId];
        currRoot[_pointsId] = _newRoot;
        // emit RootUpdated(_newRoot, _pointsId);
    }

    // can we assume this will be pushed in, or should we fetch it from somewhere?

    function claimPointsTokens(Claim[] calldata claims) external {
        for (uint256 i = 0; i < claims.length; i++) {
            Claim memory claim = claims[i];
            _claimPointsToken(claim._account, claim._pointsId, claim._claimable, claim._proof);
        }
    }

    function _claimPointsToken(address _account, bytes32 _pointsId, uint256 _claimable, bytes32[] calldata _proof)
        internal
    {
        bytes32 candidateRoot =
            MerkleProof.processProof(_proof, keccak256(abi.encodePacked(_account, _pointsId, _claimable)));

        if (candidateRoot != currRoot[_pointsId] && candidateRoot != prevRoot[_pointsId]) {
            // revert ProofInvalidOrExpired();
        }

        uint256 alreadyClaimed = claimed[_account][_pointsId];
        if (_claimable <= alreadyClaimed) revert AlreadyClaimed();

        uint256 amount;
        unchecked {
            amount = _claimable - alreadyClaimed;
        }

        claimed[_account][_pointsId] = _claimable;

        // hub.mint(_account, _pointsId, amount);

        // emit RewardsClaimed(_account, _pointsId, amount);
    }

    enum Operation {
        Call,
        DelegateCall
    }

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

    function claimRewardToken(address _reward, address _receiver, uint256 _amount) external onlyOwner {
        // hub.burnAndTransfer(_account, _pointsId, amount);

        // if is final
        // burn tokens and distribute rewards
        // if not final,

        // hub.mint(_account, _pointsId, amount);

        // _reward.safeTransfer(_receiver, _amount);
    }

    // recover?
}

// todo: make the hub a proxy as well
contract PTVHub {
    mapping(bytes32 pointsId => ERC20 token) public pointsTokens;
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "PTVHub: Only owner can call this function");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

    function mint(address _account, bytes32 _pointsId, uint256 _amount) external {
        // auth only trusted
        if (pointsTokens[_pointsId] == address(0)) {
            pointsTokens[_pointsId] = new ERC20(_pointsId, _pointsId, 18); // owns tokens
        }

        pointsTokens[_pointsId].mint(_account, _amount);
    }

    function grantTokenOwnership(address _newOwner) external onlyOwner {
        pointsTokens[_pointsId].grantTokenOwnership(_newOwner);
    }

    // function auth() {
    // give auth to factories or vaults
    // }
}
