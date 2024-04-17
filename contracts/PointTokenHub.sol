// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {PToken} from "./PToken.sol";

contract PointTokenHub is UUPSUpgradeable, OwnableUpgradeable {
    mapping(address => bool) isTrusted; // user => isTrusted
    mapping(bytes32 => PToken) public pointTokens; // pointsId => pointTokens
    mapping(bytes32 => RedemptionParams) public redemptionParams; // pointsId => redemptionParams

    struct RedemptionParams {
        ERC20 rewardToken;
        uint256 exchangeRate; // Rate from point token to reward token (pToken/rewardToken). 18 decimals.
        bool isMerkleBased;
    }

    event Trusted(address indexed user, bool isTrusted);
    event RewardRedemptionSet(bytes32 indexed pointsId, ERC20 rewardToken, uint256 exchangeRate, bool isMerkleBased);

    error OnlyTrusted();

    modifier onlyTrusted() {
        if (!isTrusted[msg.sender]) revert OnlyTrusted();
        _;
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
            (string memory name, string memory symbol) = LibString.unpackTwo(_pointsId); // Assume the points id was created using LibString.packTwo.
            pointTokens[_pointsId] = new PToken{salt: _pointsId}(name, symbol, 18);
        }

        pointTokens[_pointsId].mint(_account, _amount);
    }

    function burn(address _account, bytes32 _pointsId, uint256 _amount) external onlyTrusted {
        pointTokens[_pointsId].burn(_account, _amount);
    }

    // Admin ---

    // Can be used to unlock reward token redemption (can also be used to modify a live redemption).
    // Should only be used after rewards have been claimed.
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
