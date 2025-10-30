using PointTokenVaultHarness as pointTokenVault;
using PToken as pToken;
using MockERC20 as mockERC20;

methods {
    // PToken
    function _.PAUSE_ROLE() external => DISPATCHER(true);
    function _.approve(address, uint256) external => DISPATCHER(true);
    function _.balanceOf(address) external => DISPATCHER(true);
    function _.burn(address, uint256) external => DISPATCHER(true);
    function _.decimals() external => DISPATCHER(true);
    function _.mint(address, uint256) external => DISPATCHER(true);
    function _.pause() external => DISPATCHER(true);
    function _.renounceRole(bytes32, address) external => DISPATCHER(true);
    function _.totalSupply() external => DISPATCHER(true);
    function _.transfer(address, uint256) external => DISPATCHER(true);
    function _.transferFrom(address, address, uint256) external => DISPATCHER(true);
    function _.unpause() external => DISPATCHER(true);
    // LibString
    function _.unpackTwo(bytes32 packed) internal => cvlUnpackTwo(packed) expect (string memory, string memory);
}

function applySafeAssumptions(env e) {
    require e.msg.sender != currentContract;
}

function cvlUnpackTwo(bytes32 packed) returns (string, string) {
    return ("TKN", "TKN");
}

//===========
// High
//===========

// Methods are called by expected roles
rule high_accessControl(method f) filtered {
    f -> f.selector != sig:deployPToken(bytes32).selector
} {
    env e;
    
    calldataarg args;

    f(e, args);

    assert
        f.selector == sig:updateRoot(bytes32).selector 
        =>
        hasRole(e, currentContract.MERKLE_UPDATER_ROLE(e), e.msg.sender);

    assert
        (
            f.selector == sig:setCap(address,uint256).selector ||
            f.selector == sig:setRedemption(bytes32,address,uint256,bool).selector ||
            f.selector == sig:setMintFee(uint256).selector ||
            f.selector == sig:setRedemptionFee(uint256).selector ||
            f.selector == sig:pausePToken(bytes32).selector ||
            f.selector == sig:unpausePToken(bytes32).selector ||
            f.selector == sig:renouncePauseRole(bytes32).selector
        )
        =>
        hasRole(e, currentContract.OPERATOR_ROLE(e), e.msg.sender);
    
    assert
        f.selector == sig:setFeeCollector(address).selector
        =>
        hasRole(e, currentContract.DEFAULT_ADMIN_ROLE(e), e.msg.sender);
}

//===========
// Unit
//===========

// `deposit()` updates storage as expected
rule unit_deposit_integrity() {
    env e;
    
    address token; 
    uint256 amount; 
    address receiver;

    applySafeAssumptions(e);

    uint256 receiverBalanceBefore = balances(e, receiver, token);
    uint256 totalDepositedBefore = totalDeposited(e, token);
    uint256 contractBalanceBefore = token.balanceOf(e, currentContract);

    deposit(e, token, amount, receiver);

    uint256 receiverBalanceAfter = balances(e, receiver, token);
    uint256 totalDepositedAfter = totalDeposited(e, token);
    uint256 contractBalanceAfter = token.balanceOf(e, currentContract);

    assert receiverBalanceAfter == require_uint256(receiverBalanceBefore + amount);
    assert totalDepositedAfter == require_uint256(totalDepositedBefore + amount);
    assert contractBalanceAfter == require_uint256(contractBalanceBefore + amount);
}

// `deposit()` reverts when expected
rule unit_deposit_revertConditions() {
    env e;
    
    address token; 
    uint256 amount; 
    address receiver;

    applySafeAssumptions(e);

    require token == mockERC20;

    bool isEtherSent = e.msg.value > 0;
    bool isCapReach = (caps(e, token) < max_uint256) && (totalDeposited(e, token) + amount > caps(e, token));
    bool isBalanceOverflow = balances(e, receiver, token) + amount > max_uint256;
    bool isTotalDepositedOverflow = totalDeposited(e, token) + amount > max_uint256;
    bool hasEnoughBalance = token.balanceOf(e, e.msg.sender) >= amount;
    bool hasEnoughAllowance = token.allowance(e, e.msg.sender, currentContract) >= amount;

    bool isExpectedToRevert = 
        isEtherSent ||
        isCapReach ||
        isBalanceOverflow ||
        isTotalDepositedOverflow ||
        !hasEnoughBalance ||
        !hasEnoughAllowance;

    deposit@withrevert(e, token, amount, receiver);

    assert lastReverted <=> isExpectedToRevert;
}

// `deposit` does not affect other entities
rule unit_deposit_doesNotAffectOtherEntities() {
    env e;
    
    address token; 
    uint256 amount; 
    address receiver;
    address otherUser;

    require receiver != otherUser;

    applySafeAssumptions(e);

    uint256 otherUserBalanceBefore = balances(e, otherUser, token);

    deposit(e, token, amount, receiver);

    uint256 otherUserBalanceAfter = balances(e, otherUser, token);

    assert otherUserBalanceBefore == otherUserBalanceAfter;
}

// `withdraw()` updates storage as expected
rule unit_withdraw_integrity() {
    env e;
    
    address token; 
    uint256 amount; 
    address receiver;

    applySafeAssumptions(e);

    require receiver != currentContract;

    uint256 receiverBalanceBefore = token.balanceOf(e, receiver);
    uint256 totalDepositedBefore = totalDeposited(e, token);
    uint256 contractBalanceBefore = token.balanceOf(e, currentContract);

    withdraw(e, token, amount, receiver);

    uint256 receiverBalanceAfter = token.balanceOf(e, receiver);
    uint256 totalDepositedAfter = totalDeposited(e, token);
    uint256 contractBalanceAfter = token.balanceOf(e, currentContract);

    assert receiverBalanceAfter == require_uint256(receiverBalanceBefore + amount);
    assert totalDepositedAfter == require_uint256(totalDepositedBefore - amount);
    assert contractBalanceAfter == require_uint256(contractBalanceBefore - amount);
}

// `withdraw()` reverts when expected
rule unit_withdraw_revertConditions() {
    env e;
    
    address token; 
    uint256 amount; 
    address receiver;

    applySafeAssumptions(e);

    require token == mockERC20;

    bool isEtherSent = e.msg.value > 0;
    bool hasUserDepositedEnough = balances(e, e.msg.sender, token) >= amount;
    bool isBalanceUnderflow = balances(e, e.msg.sender, token) - amount < 0;
    bool isTotalDepositedUnderflow = totalDeposited(e, token) - amount < 0;
    bool hasContractEnoughBalance = token.balanceOf(e, currentContract) >= amount;

    bool isExpectedToRevert = 
        isEtherSent ||
        !hasUserDepositedEnough ||
        isBalanceUnderflow ||
        isTotalDepositedUnderflow ||
        !hasContractEnoughBalance;

    withdraw@withrevert(e, token, amount, receiver);

    assert lastReverted <=> isExpectedToRevert;
}

// `withdraw` does not affect other entities
rule unit_withdraw_doesNotAffectOtherEntities() {
    env e;
    
    address token; 
    uint256 amount; 
    address receiver;
    address otherUser;

    require otherUser != receiver && otherUser != e.msg.sender;

    applySafeAssumptions(e);

    uint256 otherUserBalanceBefore = balances(e, otherUser, token);

    withdraw(e, token, amount, receiver);

    uint256 otherUserBalanceAfter = balances(e, otherUser, token);

    assert otherUserBalanceBefore == otherUserBalanceAfter;
}

// `claimPTokens()` updates storage as expected
rule unit_claimPTokens_integrity() {
    env e;
    
    PointTokenVault.Claim claim;
    address account; 
    address receiver;

    applySafeAssumptions(e);

    uint256 totalFeeBefore = pTokenFeeAcc(e, claim.pointsId);
    uint256 receiverBalanceBefore = pTokens(e, claim.pointsId).balanceOf(e, receiver);

    require receiverBalanceBefore + claim.amountToClaim < max_uint256;

    claimPTokens(e, claim, account, receiver);

    uint256 totalFeeAfter = pTokenFeeAcc(e, claim.pointsId);
    uint256 receiverBalanceAfter = pTokens(e, claim.pointsId).balanceOf(e, receiver);

    assert totalFeeAfter >= totalFeeBefore;
    assert receiverBalanceAfter >= receiverBalanceBefore;
}

// `claimPTokens()` reverts when expected
rule unit_claimPTokens_revertConditions() {
    env e;
    
    PointTokenVault.Claim claim;
    address account; 
    address receiver;

    applySafeAssumptions(e);

    uint256 mintFee = mintFee(e);
    uint256 expectedFee = getClaimPTokenFee(e, claim.amountToClaim);

    bool isEtherSent = e.msg.value > 0;
    bool isPTokenDeployed = pTokens(e, claim.pointsId) != 0;
    bool isReceiverTrusted = account == receiver || trustedReceivers(e, account, receiver);
    bool isPTokenFeeOverflow = claim.amountToClaim * mintFee > max_uint256;
    bool isPTokenFeeAccOverflow = pTokenFeeAcc(e, claim.pointsId) + expectedFee > max_uint256;
    bool isPTokenTotalSupplyOverflow = pTokens(e, claim.pointsId).totalSupply(e) + claim.amountToClaim - expectedFee > max_uint256;
    bool isTokenFeeGreaterThanAmountToClaim = expectedFee > claim.amountToClaim;
    bool isClaimTooLarge = claimedPTokens(e, account, claim.pointsId) + claim.amountToClaim > claim.totalClaimable;
    bool isMerkleRootValid = getMerkleRootFromClaim(e, claim, account) == currRoot(e) || getMerkleRootFromClaim(e, claim, account) == prevRoot(e);
    bool isPTokenPaused = pTokens(e, claim.pointsId).paused(e);
    bool hasSupplyAdminRole = pTokens(e, claim.pointsId).hasRole(e, pTokens(e, claim.pointsId).SUPPLY_ADMIN_ROLE(e), currentContract);

    bool isExpectedToRevert = 
        isEtherSent ||
        !isPTokenDeployed ||
        !isReceiverTrusted ||
        isPTokenFeeOverflow ||
        isPTokenFeeAccOverflow ||
        isPTokenTotalSupplyOverflow ||
        isTokenFeeGreaterThanAmountToClaim ||
        isClaimTooLarge ||
        !isMerkleRootValid ||
        isPTokenPaused ||
        !hasSupplyAdminRole;

    claimPTokens@withrevert(e, claim, account, receiver);

    assert lastReverted <=> isExpectedToRevert;
}

// `claimPTokens()` does not affect other entities
rule unit_claimPTokens_doesNotAffectOtherEntities() {
    env e;
    
    PointTokenVault.Claim claim;
    address account; 
    address receiver;
    address otherUser;

    require otherUser != receiver;

    applySafeAssumptions(e);

    uint256 otherUserBalanceBefore = pTokens(e, claim.pointsId).balanceOf(e, otherUser);

    claimPTokens(e, claim, account, receiver);

    uint256 otherUserBalanceAfter = pTokens(e, claim.pointsId).balanceOf(e, otherUser);

    assert otherUserBalanceBefore == otherUserBalanceAfter;
}

// `redeemRewards` updates storage as expected
rule unit_redeemRewards_integrity() {
    env e;

    PointTokenVault.Claim claim;
    address receiver;

    applySafeAssumptions(e);

    address rewardToken;
    rewardToken, _, _ = redemptions(e, claim.pointsId);

    require rewardToken == mockERC20;

    uint256 pTokensBalanceBefore = pTokens(e, claim.pointsId).balanceOf(e, e.msg.sender);
    uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(e, receiver);

    require rewardTokenBalanceBefore + claim.amountToClaim < max_uint256;

    redeemRewards(e, claim, receiver);

    uint256 pTokensBalanceAfter = pTokens(e, claim.pointsId).balanceOf(e, e.msg.sender);
    uint256 rewardTokenBalanceAfter = rewardToken.balanceOf(e, receiver);

    assert pTokensBalanceAfter <= pTokensBalanceBefore;
    assert rewardTokenBalanceAfter >= rewardTokenBalanceBefore;
}

// `redeemRewards` reverts when expected
rule unit_redeemRewards_revertConditions() {
    env e;

    PointTokenVault.Claim claim;
    address receiver;

    address rewardToken;
    bool isMerkleBased;
    uint256 rewardsPerPToken;
    rewardToken, rewardsPerPToken, isMerkleBased = redemptions(e, claim.pointsId);
    uint256 expectedPTokensBurned = getPTokensForRewards(e, claim.pointsId, claim.amountToClaim, true);

    applySafeAssumptions(e);
    require rewardToken == mockERC20;
    require claim.amountToClaim * 1000000000000000000 < max_uint256;
    require rewardToken.decimals(e) == 18;
    require expectedPTokensBurned * rewardsPerPToken < max_uint256;
    require rewardToken.balanceOf(e, currentContract) >= claim.amountToClaim;
    require redemptionFee(e) == 0;
    require expectedPTokensBurned <= 100 * 1000000000000000000;
    require rewardTokenFeeAcc(e, claim.pointsId) < max_uint256;
    require rewardsPerPToken <= 10 * 1000000000000000000;

    bool isEtherSent = e.msg.value > 0;
    bool isRewardTokenZero = rewardToken == 0;
    bool isMerkleRootValid = getMerkleRootForRedemption(e, claim, e.msg.sender) == currRoot(e) || getMerkleRootForRedemption(e, claim, e.msg.sender) == prevRoot(e);
    bool isClaimTooLarge = claimedRedemptionRights(e, e.msg.sender, claim.pointsId) + claim.amountToClaim > claim.totalClaimable;
    bool isRewardsPerPTokenZero = rewardsPerPToken == 0;
    bool isPTokenPaused = pTokens(e, claim.pointsId).paused(e);
    bool hasSupplyAdminRole = pTokens(e, claim.pointsId).hasRole(e, pTokens(e, claim.pointsId).SUPPLY_ADMIN_ROLE(e), currentContract);
    bool isFeelesslyRedeemedGreaterThanClaimed = feelesslyRedeemedPTokens(e, e.msg.sender, claim.pointsId) > claimedPTokens(e, e.msg.sender, claim.pointsId);
    bool hasUserEnoughPTokensBalance = pTokens(e, claim.pointsId).balanceOf(e, e.msg.sender) >= expectedPTokensBurned;

    bool isExpectedToRevert = 
        isEtherSent ||
        isRewardTokenZero ||
        (isMerkleBased && (!isMerkleRootValid || isClaimTooLarge)) ||
        isRewardsPerPTokenZero ||
        isPTokenPaused ||
        !hasSupplyAdminRole ||
        isFeelesslyRedeemedGreaterThanClaimed ||
        !hasUserEnoughPTokensBalance;

    redeemRewards@withrevert(e, claim, receiver);

    assert lastReverted <=> isExpectedToRevert;
}

// `redeemRewards` does not affect other entities
rule unit_redeemRewards_doesNotAffectOtherEntities() {
    env e;

    PointTokenVault.Claim claim;
    address receiver;
    address otherUser;

    applySafeAssumptions(e);

    require e.msg.sender != otherUser && receiver != otherUser && currentContract != otherUser;

    address rewardToken;
    rewardToken, _, _ = redemptions(e, claim.pointsId);

    uint256 pTokensBalanceBefore = pTokens(e, claim.pointsId).balanceOf(e, otherUser);
    uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(e, otherUser);

    redeemRewards(e, claim, receiver);

    uint256 pTokensBalanceAfter = pTokens(e, claim.pointsId).balanceOf(e, otherUser);
    uint256 rewardTokenBalanceAfter = rewardToken.balanceOf(e, otherUser);

    assert pTokensBalanceAfter == pTokensBalanceBefore;
    assert rewardTokenBalanceAfter == rewardTokenBalanceBefore;
}

// `convertRewardsToPTokens` updates storage as expected
rule unit_convertRewardsToPTokens_integrity() {
    env e;

    address receiver; 
    bytes32 pointsId; 
    uint256 amount;

    address rewardToken;
    rewardToken, _, _ = redemptions(e, pointsId);
    uint256 expectedPTokensMinted = getPTokensForRewards(e, pointsId, amount, false);

    applySafeAssumptions(e);
    require receiver != currentContract;
    require rewardToken == mockERC20;

    uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(e, e.msg.sender);
    uint256 pTokensBalanceBefore = pTokens(e, pointsId).balanceOf(e, receiver);

    require pTokensBalanceBefore + expectedPTokensMinted < max_uint256;

    convertRewardsToPTokens(e, receiver, pointsId, amount);

    uint256 rewardTokenBalanceAfter = rewardToken.balanceOf(e, e.msg.sender);
    uint256 pTokensBalanceAfter = pTokens(e, pointsId).balanceOf(e, receiver);

    assert rewardTokenBalanceBefore >= rewardTokenBalanceAfter;
    assert pTokensBalanceBefore <= pTokensBalanceAfter;
}

// `convertRewardsToPTokens` reverts when expected
rule unit_convertRewardsToPTokens_revertConditions() {
    env e;

    address receiver; 
    bytes32 pointsId; 
    uint256 amount;

    applySafeAssumptions(e);

    address rewardToken;
    uint256 rewardsPerPToken;
    bool isMerkleBased;
    rewardToken, rewardsPerPToken, isMerkleBased = redemptions(e, pointsId);
    uint256 expectedPTokensMinted = getPTokensForRewards(e, pointsId, amount, false);
    uint256 pTokensBalanceBefore = pTokens(e, pointsId).balanceOf(e, receiver);

    require rewardToken == mockERC20;
    require pTokensBalanceBefore + expectedPTokensMinted < max_uint256;

    bool isEtherSent = e.msg.value > 0;
    bool isRewardTokenZero = rewardToken == 0;
    bool isAmountTooSmall = amount == 0 || rewardsPerPToken == 0;
    bool isOverflow = amount * 1000000000000000000 > max_uint256;
    bool hasSenderEnoughBalance = rewardToken.balanceOf(e, e.msg.sender) >= amount;
    bool hasRewardTokenGreaterThan18Decimals = rewardToken.decimals(e) > 18;
    bool hasEnoughAllowance = rewardToken.allowance(e, e.msg.sender, currentContract) >= amount;
    bool isPTokenPaused = pTokens(e, pointsId).paused(e);
    bool hasSupplyAdminRole = pTokens(e, pointsId).hasRole(e, pTokens(e, pointsId).SUPPLY_ADMIN_ROLE(e), currentContract);
    bool isPTokensMintedZero = expectedPTokensMinted == 0;
    bool isPTokenTotalSupplyOverflow = pTokens(e, pointsId).totalSupply(e) + expectedPTokensMinted > max_uint256;

    bool isExpectedToRevert = 
        isEtherSent ||
        isRewardTokenZero ||
        isMerkleBased ||
        isAmountTooSmall ||
        isOverflow ||
        !hasSenderEnoughBalance ||
        hasRewardTokenGreaterThan18Decimals ||
        !hasEnoughAllowance ||
        isPTokenPaused ||
        !hasSupplyAdminRole ||
        isPTokensMintedZero ||
        isPTokenTotalSupplyOverflow;

    convertRewardsToPTokens@withrevert(e, receiver, pointsId, amount);

    assert lastReverted <=> isExpectedToRevert;
}

// `convertRewardsToPTokens` does not affect other entities
rule unit_convertRewardsToPTokens_doesNotAffectOtherEntities() {
    env e;

    address receiver; 
    bytes32 pointsId; 
    uint256 amount;
    address otherUser;

    applySafeAssumptions(e);

    require otherUser != e.msg.sender && otherUser != receiver && otherUser != currentContract;

    address rewardToken;
    rewardToken, _, _ = redemptions(e, pointsId);

    uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(e, otherUser);
    uint256 pTokensBalanceBefore = pTokens(e, pointsId).balanceOf(e, otherUser);

    convertRewardsToPTokens(e, receiver, pointsId, amount);

    uint256 rewardTokenBalanceAfter = rewardToken.balanceOf(e, otherUser);
    uint256 pTokensBalanceAfter = pTokens(e, pointsId).balanceOf(e, otherUser);

    assert rewardTokenBalanceBefore == rewardTokenBalanceAfter;
    assert pTokensBalanceBefore == pTokensBalanceAfter;
}

// `trustReceiver()` updates storage as expected
rule unit_trustReceiver_integrity() {
    env e;

    address account;
    bool isTrusted;

    trustReceiver(e, account, isTrusted);

    assert trustedReceivers(e, e.msg.sender, account) == isTrusted;
}

// `trustReceiver()` reverts when expected
rule unit_trustReceiver_revertConditions() {
    env e;

    address account;
    bool isTrusted;

    bool isEtherSent = e.msg.value > 0;

    bool isExpectedToRevert = 
        isEtherSent;

    trustReceiver@withrevert(e, account, isTrusted);

    assert lastReverted <=> isExpectedToRevert;
}

// `deployPToken()` reverts when expected
rule unit_deployPToken_revertConditions() {
    env e;

    bytes32 pointsId;

    bool isEtherSent = e.msg.value > 0;
    bool isAlreadyDeployed = pTokens(e, pointsId) != 0;

    bool isExpectedToRevert = 
        isEtherSent ||
        isAlreadyDeployed;

    deployPToken@withrevert(e, pointsId);

    assert lastReverted <=> isExpectedToRevert;
}

// `updateRoot()` updates storage as expected
rule unit_updateRoot_integrity() {
    env e;

    bytes32 newRoot;
    bytes32 currentRoot = pointTokenVault.currRoot;

    updateRoot(e, newRoot);

    assert pointTokenVault.currRoot == newRoot;
    assert pointTokenVault.prevRoot == currentRoot;
}

// `updateRoot()` reverts when expected
rule unit_updateRoot_revertConditions() {
    env e;

    bytes32 newRoot;

    bool isEtherSent = e.msg.value > 0;
    bool hasMerkleUpdaterRole = hasRole(e, MERKLE_UPDATER_ROLE(e), e.msg.sender);

    bool isExpectedToRevert = 
        isEtherSent ||
        !hasMerkleUpdaterRole;

    updateRoot@withrevert(e, newRoot);

    assert lastReverted <=> isExpectedToRevert;
}

// `setCap()` updates storage as expected
rule unit_setCap_integrity() {
    env e;

    address token;
    uint256 cap;

    setCap(e, token, cap);

    assert caps(e, token) == cap;
}

// `setCap()` reverts when expected
rule unit_setCap_revertConditions() {
    env e;

    address token;
    uint256 cap;

    bool isEtherSent = e.msg.value > 0;
    bool hasOperatorRole = hasRole(e, OPERATOR_ROLE(e), e.msg.sender);

    bool isExpectedToRevert = 
        isEtherSent ||
        !hasOperatorRole;

    setCap@withrevert(e, token, cap);

    assert lastReverted <=> isExpectedToRevert;
}

// `setRedemption()` updates storage as expected
rule unit_setRedemption_integrity() {
    env e;

    bytes32 pointsId;
    address rewardToken;
    uint256 rewardsPerPToken;
    bool isMerkleBased;

    setRedemption(e, pointsId, rewardToken, rewardsPerPToken, isMerkleBased);

    address newRewardToken;
    uint256 newRewardsPerPToken;
    bool newIsMerkleBased;

    newRewardToken, newRewardsPerPToken, newIsMerkleBased = redemptions(e, pointsId);

    assert newRewardToken == rewardToken;
    assert newRewardsPerPToken == rewardsPerPToken;
    assert newIsMerkleBased == isMerkleBased;
}

// `setRedemption()` reverts when expected
rule unit_setRedemption_revertConditions() {
    env e;

    bytes32 pointsId;
    address rewardToken;
    uint256 rewardsPerPToken;
    bool isMerkleBased;

    bool isEtherSent = e.msg.value > 0;
    bool hasOperatorRole = hasRole(e, OPERATOR_ROLE(e), e.msg.sender);

    bool isExpectedToRevert = 
        isEtherSent ||
        !hasOperatorRole;

    setRedemption@withrevert(e, pointsId, rewardToken, rewardsPerPToken, isMerkleBased);

    assert lastReverted <=> isExpectedToRevert;
}

// `setMintFee()` updates storage as expected
rule unit_setMintFee_integrity() {
    env e;

    uint256 mintFee;

    setMintFee(e, mintFee);

    assert mintFee(e) == mintFee;
}

// `setMintFee()` reverts when expected
rule unit_setMintFee_revertConditions() {
    env e;

    uint256 mintFee;

    bool isEtherSent = e.msg.value > 0;
    bool hasOperatorRole = hasRole(e, OPERATOR_ROLE(e), e.msg.sender);

    bool isExpectedToRevert = 
        isEtherSent ||
        !hasOperatorRole;

    setMintFee@withrevert(e, mintFee);

    assert lastReverted <=> isExpectedToRevert;
}

// `setRedemptionFee()` updates storage as expected
rule unit_setRedemptionFee_integrity() {
    env e;

    uint256 redemptionFee;

    setRedemptionFee(e, redemptionFee);

    assert redemptionFee(e) == redemptionFee;
}

// `setRedemptionFee()` reverts when expected
rule unit_setRedemptionFee_revertConditions() {
    env e;

    uint256 redemptionFee;

    bool isEtherSent = e.msg.value > 0;
    bool hasOperatorRole = hasRole(e, OPERATOR_ROLE(e), e.msg.sender);

    bool isExpectedToRevert = 
        isEtherSent ||
        !hasOperatorRole;

    setRedemptionFee@withrevert(e, redemptionFee);

    assert lastReverted <=> isExpectedToRevert;
}

// `pausePToken()` updates storage as expected
rule unit_pausePToken_integrity() {
    env e;

    bytes32 pointsId;

    pausePToken(e, pointsId);

    assert pointTokenVault.pTokens[pointsId].paused(e);
}

// `pausePToken()` reverts when expected
rule unit_pausePToken_revertConditions() {
    env e;

    bytes32 pointsId;

    address currentPToken = pointTokenVault.pTokens[pointsId];

    bool isEtherSent = e.msg.value > 0;
    bool hasOperatorRole = hasRole(e, OPERATOR_ROLE(e), e.msg.sender);
    bool isPTokenPaused = currentPToken.paused(e);
    bool hasPointTokenVaultPauseRole = currentPToken.hasRole(e, currentPToken.PAUSE_ROLE(e), currentContract);

    bool isExpectedToRevert = 
        isEtherSent ||
        !hasOperatorRole ||
        isPTokenPaused ||
        !hasPointTokenVaultPauseRole;

    pausePToken@withrevert(e, pointsId);

    assert lastReverted <=> isExpectedToRevert;
}

// `unpausePToken()` updates storage as expected
rule unit_unpausePToken_integrity() {
    env e;

    bytes32 pointsId;

    unpausePToken(e, pointsId);

    assert !pointTokenVault.pTokens[pointsId].paused(e);
}

// `unpausePToken()` reverts when expected
rule unit_unpausePToken_revertConditions() {
    env e;

    bytes32 pointsId;

    address currentPToken = pointTokenVault.pTokens[pointsId];

    bool isEtherSent = e.msg.value > 0;
    bool hasOperatorRole = hasRole(e, OPERATOR_ROLE(e), e.msg.sender);
    bool isPTokenPaused = currentPToken.paused(e);
    bool hasPointTokenVaultPauseRole = currentPToken.hasRole(e, currentPToken.PAUSE_ROLE(e), currentContract);

    bool isExpectedToRevert = 
        isEtherSent ||
        !hasOperatorRole ||
        !isPTokenPaused ||
        !hasPointTokenVaultPauseRole;

    unpausePToken@withrevert(e, pointsId);

    assert lastReverted <=> isExpectedToRevert;
}

// `renouncePauseRole()` updates storage as expected
rule unit_renouncePauseRole_integrity() {
    env e;

    bytes32 pointsId;
    address currentPToken = pointTokenVault.pTokens[pointsId];

    renouncePauseRole(e, pointsId);

    assert !currentPToken.hasRole(e, currentPToken.PAUSE_ROLE(e), currentContract);
}

// `renouncePauseRole()` reverts when expected
rule unit_renouncePauseRole_revertConditions() {
    env e;

    bytes32 pointsId;

    bool isEtherSent = e.msg.value > 0;
    bool hasOperatorRole = hasRole(e, OPERATOR_ROLE(e), e.msg.sender);

    bool isExpectedToRevert = 
        isEtherSent ||
        !hasOperatorRole;

    renouncePauseRole@withrevert(e, pointsId);

    assert lastReverted <=> isExpectedToRevert;
}

// `collectFees()` updates storage as expected
rule unit_collectFees_integrity() {
    env e;

    bytes32 pointsId;

    require pointTokenVault.feeCollector != currentContract;

    address currentPToken = pointTokenVault.pTokens[pointsId];
    address rewardToken = pointTokenVault.redemptions[pointsId].rewardToken;

    uint256 pTokenFee = pointTokenVault.pTokenFeeAcc[pointsId];
    uint256 feeCollectorPTokenBalanceBefore = pointTokenVault.pTokens[pointsId].balanceOf(e, pointTokenVault.feeCollector);
    
    uint256 rewardTokenFee = pointTokenVault.rewardTokenFeeAcc[pointsId];
    uint256 feeCollectorRewardTokenBalanceBefore = pointTokenVault.redemptions[pointsId].rewardToken.balanceOf(e, pointTokenVault.feeCollector);

    collectFees(e, pointsId);

    uint256 feeCollectorPTokenBalanceAfter = pointTokenVault.pTokens[pointsId].balanceOf(e, pointTokenVault.feeCollector);
    uint256 feeCollectorRewardTokenBalanceAfter = pointTokenVault.redemptions[pointsId].rewardToken.balanceOf(e, pointTokenVault.feeCollector);

    assert currentPToken == rewardToken => 
        feeCollectorPTokenBalanceAfter == require_uint256(feeCollectorRewardTokenBalanceBefore + pTokenFee + rewardTokenFee);

    assert currentPToken != rewardToken =>
        pointTokenVault.pTokenFeeAcc[pointsId] == 0 &&
        feeCollectorPTokenBalanceAfter == require_uint256(feeCollectorPTokenBalanceBefore + pTokenFee) &&
        feeCollectorRewardTokenBalanceAfter == require_uint256(feeCollectorRewardTokenBalanceBefore + rewardTokenFee);
}

// `collectFees()` reverts when expected
rule unit_collectFees_revertConditions() {
    env e;

    bytes32 pointsId;

    uint256 pTokenFee = pointTokenVault.pTokenFeeAcc[pointsId];
    uint256 rewardTokenFee = pointTokenVault.rewardTokenFeeAcc[pointsId];
    address currentPToken = pointTokenVault.pTokens[pointsId];
    address rewardToken = pointTokenVault.redemptions[pointsId].rewardToken;

    require rewardToken == mockERC20;

    bool isEtherSent = e.msg.value > 0;
    bool isPTokenPaused = currentPToken.paused(e);
    bool hasUncollectedPTokenFee = pTokenFee > 0;
    bool hasEnoughRewardTokens = rewardTokenFee <= rewardToken.balanceOf(e, currentContract);
    bool hasSupplyAdminRole = currentPToken.hasRole(e, currentPToken.SUPPLY_ADMIN_ROLE(e), currentContract);
    bool isPTokenTotalSupplyOverflow = currentPToken.totalSupply(e) + pTokenFee > max_uint256;

    bool isExpectedToRevert = 
        isEtherSent ||
        (hasUncollectedPTokenFee && (isPTokenPaused || !hasSupplyAdminRole)) ||
        !hasEnoughRewardTokens ||
        isPTokenTotalSupplyOverflow;

    collectFees@withrevert(e, pointsId);

    assert lastReverted <=> isExpectedToRevert;
}

// `collectFees()` does not affect other entities
rule unit_collectFees_doesNotAffectOtherEntities() {
    env e;

    address otherUser;
    bytes32 pointsId;

    require otherUser != pointTokenVault.feeCollector && otherUser != currentContract;

    uint256 otherUserPTokenBalanceBefore = pointTokenVault.pTokens[pointsId].balanceOf(e, otherUser);
    uint256 otherUserRewardTokenBalanceBefore = pointTokenVault.redemptions[pointsId].rewardToken.balanceOf(e, otherUser);

    collectFees(e, pointsId);

    uint256 otherUserPTokenBalanceAfter = pointTokenVault.pTokens[pointsId].balanceOf(e, otherUser);
    uint256 otherUserRewardTokenBalanceAfter = pointTokenVault.redemptions[pointsId].rewardToken.balanceOf(e, otherUser);

    assert otherUserPTokenBalanceBefore == otherUserPTokenBalanceAfter;
    assert otherUserRewardTokenBalanceBefore == otherUserRewardTokenBalanceAfter;
}

// `setFeeCollector()` updates storage as expected
rule unit_setFeeCollector_integrity() {
    env e;

    address feeCollector;

    setFeeCollector(e, feeCollector);

    assert feeCollector(e) == feeCollector;
}

// `setFeeCollector()` reverts when expected
rule unit_setFeeCollector_revertConditions() {
    env e;

    address feeCollector;

    bool isEtherSent = e.msg.value > 0;
    bool hasDefaultAdminRole = hasRole(e, DEFAULT_ADMIN_ROLE(e), e.msg.sender);

    bool isExpectedToRevert = 
        isEtherSent ||
        !hasDefaultAdminRole;

    setFeeCollector@withrevert(e, feeCollector);

    assert lastReverted <=> isExpectedToRevert;
}