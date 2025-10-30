methods {
    function allowance(address,address) external returns (uint256) envfree;
    function balanceOf(address) external returns (uint256) envfree;
    function totalSupply() external returns (uint256) envfree;
}

//===============
// Definitions
//===============

definition canIncreaseAllowance(method f) returns bool = 
	f.selector == sig:approve(address,uint256).selector ||
    f.selector == sig:permit(address,address,uint256,uint256,uint8,bytes32,bytes32).selector;

definition canDecreaseAllowance(method f) returns bool = 
	f.selector == sig:approve(address,uint256).selector || 
	f.selector == sig:transferFrom(address,address,uint256).selector ||
    f.selector == sig:permit(address,address,uint256,uint256,uint8,bytes32,bytes32).selector;

definition canIncreaseBalance(method f) returns bool = 
	f.selector == sig:mint(address,uint256).selector || 
	f.selector == sig:transfer(address,uint256).selector ||
	f.selector == sig:transferFrom(address,address,uint256).selector;

definition canDecreaseBalance(method f) returns bool = 
	f.selector == sig:burn(address,uint256).selector || 
	f.selector == sig:transfer(address,uint256).selector ||
	f.selector == sig:transferFrom(address,address,uint256).selector;

definition canIncreaseTotalSupply(method f) returns bool = 
	f.selector == sig:mint(address,uint256).selector;

definition canDecreaseTotalSupply(method f) returns bool = 
	f.selector == sig:burn(address,uint256).selector;

//==========
// Ghosts
//==========

ghost mathint sumOfBalances {
    init_state axiom sumOfBalances == 0;
}

ghost mathint numberOfChangesOfBalances {
	init_state axiom numberOfChangesOfBalances == 0;
}

//=========
// Hooks
//=========

// Initially individual user can not have balance greater than total supply
hook Sload uint256 balance balanceOf[KEY address addr] {
    require sumOfBalances >= balance;
}

hook Sstore balanceOf[KEY address addr] uint256 newValue (uint256 oldValue) {
    sumOfBalances = sumOfBalances - oldValue + newValue;
    numberOfChangesOfBalances = numberOfChangesOfBalances + 1;
}

//==============
// Invariants
//==============

// Total supply is sum of all balances
invariant totalSupplyIsSumOfBalances()
    totalSupply() == sumOfBalances;

//======================
// Rules (high level)
//======================

// Total supply never overflows
rule totalSupplyNeverOverflow(env e, method f, calldataarg args) filtered {f -> canIncreaseTotalSupply(f) }{
	uint256 totalSupplyBefore = totalSupply();

	f(e, args);

	uint256 totalSupplyAfter = totalSupply();

	assert totalSupplyBefore <= totalSupplyAfter;
}

// Max number of balace changes in a single call is 2
rule noMethodChangesMoreThanTwoBalances() {
	env e;
    method f;
    calldataarg args;
	
    mathint numberOfChangesOfBalancesBefore = numberOfChangesOfBalances;
	
	f(e,args);

	mathint numberOfChangesOfBalancesAfter = numberOfChangesOfBalances;

	assert numberOfChangesOfBalancesAfter <= numberOfChangesOfBalancesBefore + 2;
}

// Only `approve()` and `transferFrom()` can change allowance
rule onlyAllowedMethodsMayChangeAllowance() {
    env e;
    method f;
    calldataarg args;

	address user1;
	address user2;

	uint256 allowanceBefore = allowance(user1, user2);
	
    f(e, args);
	
    uint256 allowanceAfter = allowance(user1, user2);
	
    assert allowanceAfter > allowanceBefore => canIncreaseAllowance(f), "Only allowed methods can increase allowance";
	assert allowanceAfter < allowanceBefore => canDecreaseAllowance(f), "Only allowed methods can decrease allowance";
}

// User balance may be changed only by:
// - `mint()`
// - `burn()`
// - `transfer()`
// - `transferFrom()`
rule onlyAllowedMethodsMayChangeBalance() {
    env e;
    method f;
    calldataarg args;

    address user;

    requireInvariant totalSupplyIsSumOfBalances();

    uint256 balanceBefore = balanceOf(user);

    f(e, args);

    uint256 balanceAfter = balanceOf(user);
    
    assert balanceAfter > balanceBefore => canIncreaseBalance(f);
    assert balanceAfter < balanceBefore => canDecreaseBalance(f);
}

// Only `mint()` and `burn()` can change total supply
rule onlyAllowedMethodsMayChangeTotalSupply() {
    env e;
    method f;
    calldataarg args;

    requireInvariant totalSupplyIsSumOfBalances();

    uint256 totalSupplyBefore = totalSupply();

    f(e, args);

    uint256 totalSupplyAfter = totalSupply();

    assert totalSupplyAfter > totalSupplyBefore => canIncreaseTotalSupply(f);
    assert totalSupplyAfter < totalSupplyBefore => canDecreaseTotalSupply(f);
}

// Account's balance can be reduced only by:
// - token holder
// - approved 3rd party
rule onlyAuthorizedCanTransfer(method f) filtered { f -> canDecreaseBalance(f) } {
    env e;
    calldataarg args;

    address user;

    requireInvariant totalSupplyIsSumOfBalances();

    uint256 allowanceBefore = allowance(user, e.msg.sender);
    uint256 balanceBefore = balanceOf(user);

    f(e, args);

    uint256 balanceAfter = balanceOf(user);

    assert (
        balanceAfter < balanceBefore
    ) => (
        f.selector == sig:burn(address,uint256).selector ||
        e.msg.sender == user ||
        balanceBefore - balanceAfter <= allowanceBefore
    );
}

// Only token holder can increase allowance, spender can decrease it by using it
rule onlyHolderOrSpenderCanChangeAllowance() {
    env e;
    method f;
    calldataarg args;

    address holder;
    address spender;

    uint256 allowanceBefore = allowance(holder, spender);
    
    f(e, args);
    
    uint256 allowanceAfter = allowance(holder, spender);

    assert (
        allowanceAfter > allowanceBefore
    ) => (
        (f.selector == sig:approve(address,uint256).selector && e.msg.sender == holder) ||
        (f.selector == sig:permit(address,address,uint256,uint256,uint8,bytes32,bytes32).selector)
    );

    assert (
        allowanceAfter < allowanceBefore
    ) => (
        (f.selector == sig:transferFrom(address,address,uint256).selector && e.msg.sender == spender) ||
        (f.selector == sig:approve(address,uint256).selector && e.msg.sender == holder ) ||
        (f.selector == sig:permit(address,address,uint256,uint256,uint8,bytes32,bytes32).selector)
    );
}

//=====================
// Rules (unit test)
//=====================

// `mint()` integrity
rule mintIntegrity() {
    env e;
    address to;
    uint256 amount;

    requireInvariant totalSupplyIsSumOfBalances();

    uint256 toBalanceBefore = balanceOf(to);
    uint256 totalSupplyBefore = totalSupply();

    mint(e, to, amount);

    assert balanceOf(to) == toBalanceBefore + amount;
    assert totalSupply() == totalSupplyBefore + amount;
}

// `mint()` revert conditions
rule mintRevertConditions() {
    env e;
	address account;
    uint256 amount;

	require totalSupply() + amount <= max_uint;

	bool isPayable = e.msg.value != 0;
    bool isPaused = paused(e);
    bool hasSupplyAdminRole = hasRole(e, SUPPLY_ADMIN_ROLE(e), e.msg.sender);

    bool isExpectedToRevert = isPayable || isPaused || !hasSupplyAdminRole;

    mint@withrevert(e, account, amount);
    
    assert lastReverted <=> isExpectedToRevert;
}

// `mint()` does not affect 3rd party
rule mintDoesNotAffectThirdParty(env e) {
	address user1;
	address user2;
    uint256 amount;
    
    require user1 != user2;
	
	uint256 before = balanceOf(user2);
	
    mint(e, user1, amount);

    assert balanceOf(user2) == before;
}

// `burn()` integrity
rule burnIntegrity() {
    env e;
    address from;
    uint256 amount;

    requireInvariant totalSupplyIsSumOfBalances();

    uint256 fromBalanceBefore = balanceOf(from);
    uint256 totalSupplyBefore = totalSupply();

    burn(e, from, amount);

    assert balanceOf(from) == fromBalanceBefore - amount;
    assert totalSupply() == totalSupplyBefore - amount;
}

// `burn()` revert conditions
rule burnRevertConditions() {
    env e;
	address account;
    uint256 amount;

	bool isPayable = e.msg.value != 0;
    bool hasNotEnoughBalance = balanceOf(account) < amount;
    bool hasSupplyAdminRole = hasRole(e, SUPPLY_ADMIN_ROLE(e), e.msg.sender);
    bool isPaused = paused(e);

    bool isExpectedToRevert = isPayable || hasNotEnoughBalance || !hasSupplyAdminRole || isPaused;

    burn@withrevert(e, account, amount);

    assert lastReverted <=> isExpectedToRevert;
}

// `burn()` does not affect 3rd party
rule burnDoesNotAffectThirdParty( env e) {
	address user1;
    address user2;
	uint256 amount;

    require user1 != user2;

    uint256 before = balanceOf(user2);

	burn(e, user1, amount);
    
    assert balanceOf(user2) == before;
}

// `transfer()` integrity
rule transferIntegrity() {
    env e;
    address holder = e.msg.sender;
    address recipient;
    uint256 amount;

    requireInvariant totalSupplyIsSumOfBalances();

    uint256 holderBalanceBefore  = balanceOf(holder);
    uint256 recipientBalanceBefore = balanceOf(recipient);

    transfer(e, recipient, amount);
   
    assert balanceOf(holder) == holderBalanceBefore - (holder == recipient ? 0 : amount);
    assert balanceOf(recipient) == recipientBalanceBefore + (holder == recipient ? 0 : amount);
}

// `transfer()` additivity
// i.e. `transfer(10) == (transfer(5) + transfer(5))`
rule transferIsOneWayAdditive() {
    env e;
	address recipient;
	uint256 amount_a;
    uint256 amount_b;
	mathint sum_amount = amount_a + amount_b;

	require sum_amount < max_uint256;
	
    storage init = lastStorage;
	
	transfer(e, recipient, assert_uint256(sum_amount));
	
    storage after1 = lastStorage;

	transfer@withrevert(e, recipient, amount_a) at init; // restores storage
	assert !lastReverted; // if the transfer passed with sum, it should pass with both summands individually
	transfer@withrevert(e, recipient, amount_b);
	assert !lastReverted;
	storage after2 = lastStorage;

	assert after1[currentContract] == after2[currentContract];
}

// `transfer()` revert conditions
rule transferRevertConditions() {
    env e;
	uint256 amount;
	address account;

	bool isPayable = e.msg.value != 0;
    bool hasNotEnoughBalance = balanceOf(e.msg.sender) < amount;
    bool isPaused = paused(e);

    bool isExpectedToRevert = isPayable || hasNotEnoughBalance || isPaused;

    transfer@withrevert(e, account, amount);

    assert lastReverted <=> isExpectedToRevert;
}

// `transfer()` does not affect 3rd party
rule transferDoesNotAffectThirdParty() {
    env e;
	address user1;
	address user2;
    uint256 amount;

    require user1 != user2 && user2 != e.msg.sender;

    uint256 before = balanceOf(user2);

	transfer(e, user1, amount);

    assert balanceOf(user2) == before;
}

// `transferFrom()` integrity
rule transferFromIntegrity() {
    env e;
    address spender = e.msg.sender;
    address holder;
    address recipient;
    uint256 amount;
    
    requireInvariant totalSupplyIsSumOfBalances();

    uint256 allowanceBefore = allowance(holder, spender);
    uint256 holderBalanceBefore = balanceOf(holder);
    uint256 recipientBalanceBefore = balanceOf(recipient);

    transferFrom(e, holder, recipient, amount);

    // allowance is valid & updated
    assert allowanceBefore >= amount;
    assert allowance(holder, spender) == (allowanceBefore == max_uint256 ? max_uint256 : allowanceBefore - amount);

    // balances of holder and recipient are updated
    assert balanceOf(holder) == holderBalanceBefore - (holder == recipient ? 0 : amount);
    assert balanceOf(recipient) == recipientBalanceBefore + (holder == recipient ? 0 : amount);
}

// `transferFrom()` revert conditions
rule transferFromRevertConditions() {
    env e;
    address owner;
	address spender = e.msg.sender;
	address recepient;
	uint256 allowed = allowance(owner, spender);
	uint256 transferred;

    require spender != 0, "Spender can not be zero address";

	bool isPayable = e.msg.value != 0;
	bool isAllowanceLow = allowed < transferred;
    bool hasNotEnoughBalance = balanceOf(owner) < transferred;
    bool isPaused = paused(e);

    bool isExpectedToRevert = isPayable  || isAllowanceLow || hasNotEnoughBalance || isPaused;

    transferFrom@withrevert(e, owner, recepient, transferred);   

    assert lastReverted <=> isExpectedToRevert;
}

// `transferFrom()` does not affect 3rd party
rule transferFromDoesNotAffectThirdParty() {
    env e;
	address spender = e.msg.sender;
	address owner;
	address recepient;
	address thirdParty;
    address everyUser;
    uint256 transferred;

	require thirdParty != owner && thirdParty != recepient && thirdParty != spender;

	uint256 thirdPartyBalanceBefore = balanceOf(thirdParty);
    uint256 thirdPartyAllowanceBefore = allowance(thirdParty, everyUser);
	
	transferFrom(e, owner, recepient, transferred);
    
	uint256 thirdPartyBalanceAfter = balanceOf(thirdParty);
	uint256 thirdPartyAllowanceAfter = allowance(thirdParty, everyUser);
	
	assert thirdPartyBalanceBefore == thirdPartyBalanceAfter;
    assert thirdPartyAllowanceBefore == thirdPartyAllowanceAfter;
}

// `transferFrom()` additivity
rule transferFromIsOneWayAdditive() {
    env e;
	address recipient;
    address owner;
    address spender = e.msg.sender;
	uint256 amount_a;
    uint256 amount_b;
	mathint sum_amount = amount_a + amount_b;
	
    require sum_amount < max_uint256;
	
    storage init = lastStorage; // saves storage
	
	transferFrom(e, owner, recipient, assert_uint256(sum_amount));
	
    storage after1 = lastStorage;

	transferFrom@withrevert(e, owner, recipient, amount_a) at init; // restores storage
	assert !lastReverted; // if the transfer passed with sum, it should pass with both summands individually
	transferFrom@withrevert(e, owner, recipient, amount_b);
	assert !lastReverted;
	storage after2 = lastStorage;

	assert after1[currentContract] == after2[currentContract];
}

// `approve()` integrity
rule approveIntegrity() {
    env e;
    address holder = e.msg.sender;
    address spender;
    uint256 amount;

    approve(e, spender, amount);

    assert allowance(holder, spender) == amount;
}

// `approve()` revert conditions
rule approveRevertConditions() {
    env e;
	address spender;
	address owner = e.msg.sender;
	uint256 amount;

	bool isPayable = e.msg.value != 0;

	bool isExpectedToRevert = isPayable;

	approve@withrevert(e, spender, amount);

    assert lastReverted <=> isExpectedToRevert;
}

// `approve()` does not affect 3rd party
rule approveDoesNotAffectThirdParty() {
    env e;
	address spender;
	address owner = e.msg.sender;
	address thirdParty;
    address everyUser; 
    uint amount;

    require thirdParty != owner && thirdParty != spender;
    
	uint256 thirdPartyAllowanceBefore = allowance(thirdParty, everyUser);

	approve(e, spender, amount);

	uint256 thirdPartyAllowanceAfter = allowance(thirdParty, everyUser);

    assert thirdPartyAllowanceBefore == thirdPartyAllowanceBefore;
}

// `pause()` integrity
rule pauseIntegrity() {
    env e;

    pause(e);

    assert(paused(e));
}

// `pause()` revert conditions
rule pauseRevertConditions() {
    env e;

    bool hasPauseRole = hasRole(e, PAUSE_ROLE(e), e.msg.sender);
    bool isPaused = paused(e);

    bool isExpectedToRevert = !hasPauseRole || isPaused;

    pause@withrevert(e);

    assert lastReverted <=> isExpectedToRevert;
}

// `unpause()` integrity
rule unpauseIntegrity() {
    env e;

    unpause(e);

    assert(!paused(e));
}

// `unpause()` revert conditions
rule unpauseRevertConditions() {
    env e;

    bool hasPauseRole = hasRole(e, PAUSE_ROLE(e), e.msg.sender);
    bool isPaused = paused(e);

    bool isExpectedToRevert = !hasPauseRole || !isPaused;

    unpause@withrevert(e);

    assert lastReverted <=> isExpectedToRevert;
}