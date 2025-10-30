// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {PointTokenVault} from "../../contracts/PointTokenVault.sol";

contract PointTokenVaultHarness is PointTokenVault {
    using MerkleProof for bytes32[];

    function getClaimPTokenFee(uint256 amount) public view returns (uint256) {
        return FixedPointMathLib.mulWadUp(amount, mintFee);
    }

    function getMerkleRootForRedemption(Claim calldata claim, address account) public view returns (bytes32) {
        bytes32 claimHash = keccak256(abi.encodePacked(REDEMPTION_RIGHTS_PREFIX, account, claim.pointsId, claim.totalClaimable));
        bytes32 candidateRoot = claim.proof.processProof(claimHash);
        return candidateRoot;
    }

    function getMerkleRootFromClaim(Claim calldata claim, address account) public view returns (bytes32) {
        bytes32 claimHash = keccak256(abi.encodePacked(account, claim.pointsId, claim.totalClaimable));
        bytes32 candidateRoot = claim.proof.processProof(claimHash);
        return candidateRoot;
    }

    function getPTokensForRewards(bytes32 pointsId, uint256 amountToConvert, bool isRoundUp) public view returns (uint256) {
        RedemptionParams memory params = redemptions[pointsId];
        (ERC20 rewardToken, uint256 rewardsPerPToken) = (params.rewardToken, params.rewardsPerPToken);

        uint256 pTokensToMint;
        uint256 scalingFactor = 10 ** (18 - rewardToken.decimals());
        if (isRoundUp) {
            pTokensToMint = FixedPointMathLib.divWadUp(amountToConvert * scalingFactor, rewardsPerPToken);
        } else {
            pTokensToMint = FixedPointMathLib.divWadDown(amountToConvert * scalingFactor, rewardsPerPToken);
        }

        return pTokensToMint;
    }
}