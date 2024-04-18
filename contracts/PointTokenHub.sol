// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {PToken} from "./PToken.sol";

contract PointTokenHub is UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant MINT_BURN_ROLE = keccak256("MINT_BURN_ROLE");

    mapping(bytes32 => PToken) public pointTokens; // pointsId => pointTokens
    mapping(bytes32 => RedemptionParams) public redemptionParams; // pointsId => redemptionParams

    struct RedemptionParams {
        ERC20 rewardToken;
        uint256 exchangeRate; // Rate from point token to reward token (pToken/rewardToken). 18 decimals.
        bool isMerkleBased;
    }

    event RewardRedemptionSet(bytes32 indexed pointsId, ERC20 rewardToken, uint256 exchangeRate, bool isMerkleBased);

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Mint and burn ---

    function mint(address _account, bytes32 _pointsId, uint256 _amount) external onlyRole(MINT_BURN_ROLE) {
        if (address(pointTokens[_pointsId]) == address(0)) {
            (string memory name, string memory symbol) = LibString.unpackTwo(_pointsId); // Assume the points id was created using LibString.packTwo.
            pointTokens[_pointsId] = new PToken{salt: _pointsId}(name, symbol, 18);
        }

        pointTokens[_pointsId].mint(_account, _amount);
    }

    function burn(address _account, bytes32 _pointsId, uint256 _amount) external onlyRole(MINT_BURN_ROLE) {
        pointTokens[_pointsId].burn(_account, _amount);
    }

    // Admin ---

    // Can be used to unlock reward token redemption (can also be used to modify a live redemption).
    // Should only be used after rewards have been claimed.
    function setRedemption(bytes32 _pointsId, ERC20 _rewardToken, uint256 _exchangeRate, bool _isMerkleBased)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        redemptionParams[_pointsId] = RedemptionParams(_rewardToken, _exchangeRate, _isMerkleBased);
        emit RewardRedemptionSet(_pointsId, _rewardToken, _exchangeRate, _isMerkleBased);
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
