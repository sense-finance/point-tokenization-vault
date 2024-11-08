export const pointTokenVaultABI = [
  { type: "constructor", inputs: [], stateMutability: "nonpayable" },
  { type: "receive", stateMutability: "payable" },
  {
    type: "function",
    name: "DEFAULT_ADMIN_ROLE",
    inputs: [],
    outputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "MERKLE_UPDATER_ROLE",
    inputs: [],
    outputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "OPERATOR_ROLE",
    inputs: [],
    outputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "REDEMPTION_RIGHTS_PREFIX",
    inputs: [],
    outputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "UPGRADE_INTERFACE_VERSION",
    inputs: [],
    outputs: [{ name: "", type: "string", internalType: "string" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "balances",
    inputs: [
      { name: "", type: "address", internalType: "address" },
      { name: "", type: "address", internalType: "contract ERC20" },
    ],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "caps",
    inputs: [{ name: "", type: "address", internalType: "address" }],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "claimPTokens",
    inputs: [
      {
        name: "_claim",
        type: "tuple",
        internalType: "struct PointTokenVault.Claim",
        components: [
          { name: "pointsId", type: "bytes32", internalType: "bytes32" },
          { name: "totalClaimable", type: "uint256", internalType: "uint256" },
          { name: "amountToClaim", type: "uint256", internalType: "uint256" },
          { name: "proof", type: "bytes32[]", internalType: "bytes32[]" },
        ],
      },
      { name: "_account", type: "address", internalType: "address" },
      { name: "_receiver", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "claimedPTokens",
    inputs: [
      { name: "", type: "address", internalType: "address" },
      { name: "", type: "bytes32", internalType: "bytes32" },
    ],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "claimedRedemptionRights",
    inputs: [
      { name: "", type: "address", internalType: "address" },
      { name: "", type: "bytes32", internalType: "bytes32" },
    ],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "collectFees",
    inputs: [{ name: "_pointsId", type: "bytes32", internalType: "bytes32" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "convertRewardsToPTokens",
    inputs: [
      { name: "_receiver", type: "address", internalType: "address" },
      { name: "_pointsId", type: "bytes32", internalType: "bytes32" },
      { name: "_amountToConvert", type: "uint256", internalType: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "currRoot",
    inputs: [],
    outputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "deployPToken",
    inputs: [{ name: "_pointsId", type: "bytes32", internalType: "bytes32" }],
    outputs: [
      { name: "pToken", type: "address", internalType: "contract PToken" },
    ],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "deposit",
    inputs: [
      { name: "_token", type: "address", internalType: "contract ERC20" },
      { name: "_amount", type: "uint256", internalType: "uint256" },
      { name: "_receiver", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "execute",
    inputs: [
      { name: "_to", type: "address", internalType: "address" },
      { name: "_data", type: "bytes", internalType: "bytes" },
      { name: "_txGas", type: "uint256", internalType: "uint256" },
    ],
    outputs: [{ name: "success", type: "bool", internalType: "bool" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "feeCollector",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "feelesslyRedeemedPTokens",
    inputs: [
      { name: "", type: "address", internalType: "address" },
      { name: "", type: "bytes32", internalType: "bytes32" },
    ],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getRoleAdmin",
    inputs: [{ name: "role", type: "bytes32", internalType: "bytes32" }],
    outputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "grantRole",
    inputs: [
      { name: "role", type: "bytes32", internalType: "bytes32" },
      { name: "account", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "hasRole",
    inputs: [
      { name: "role", type: "bytes32", internalType: "bytes32" },
      { name: "account", type: "address", internalType: "address" },
    ],
    outputs: [{ name: "", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "initialize",
    inputs: [
      { name: "_admin", type: "address", internalType: "address" },
      { name: "_feeCollector", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "mintFee",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "multicall",
    inputs: [{ name: "data", type: "bytes[]", internalType: "bytes[]" }],
    outputs: [{ name: "results", type: "bytes[]", internalType: "bytes[]" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "pTokenFeeAcc",
    inputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "pTokens",
    inputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    outputs: [{ name: "", type: "address", internalType: "contract PToken" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "pausePToken",
    inputs: [{ name: "_pointsId", type: "bytes32", internalType: "bytes32" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "prevRoot",
    inputs: [],
    outputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "proxiableUUID",
    inputs: [],
    outputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "redeemRewards",
    inputs: [
      {
        name: "_claim",
        type: "tuple",
        internalType: "struct PointTokenVault.Claim",
        components: [
          { name: "pointsId", type: "bytes32", internalType: "bytes32" },
          { name: "totalClaimable", type: "uint256", internalType: "uint256" },
          { name: "amountToClaim", type: "uint256", internalType: "uint256" },
          { name: "proof", type: "bytes32[]", internalType: "bytes32[]" },
        ],
      },
      { name: "_receiver", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "redemptionFee",
    inputs: [],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "redemptions",
    inputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    outputs: [
      { name: "rewardToken", type: "address", internalType: "contract ERC20" },
      { name: "rewardsPerPToken", type: "uint256", internalType: "uint256" },
      { name: "isMerkleBased", type: "bool", internalType: "bool" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "renouncePauseRole",
    inputs: [{ name: "_pointsId", type: "bytes32", internalType: "bytes32" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "renounceRole",
    inputs: [
      { name: "role", type: "bytes32", internalType: "bytes32" },
      { name: "callerConfirmation", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "revokeRole",
    inputs: [
      { name: "role", type: "bytes32", internalType: "bytes32" },
      { name: "account", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "rewardTokenFeeAcc",
    inputs: [{ name: "", type: "bytes32", internalType: "bytes32" }],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "setCap",
    inputs: [
      { name: "_token", type: "address", internalType: "address" },
      { name: "_cap", type: "uint256", internalType: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setFeeCollector",
    inputs: [
      { name: "_feeCollector", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setMintFee",
    inputs: [{ name: "_mintFee", type: "uint256", internalType: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setRedemption",
    inputs: [
      { name: "_pointsId", type: "bytes32", internalType: "bytes32" },
      { name: "_rewardToken", type: "address", internalType: "contract ERC20" },
      { name: "_rewardsPerPToken", type: "uint256", internalType: "uint256" },
      { name: "_isMerkleBased", type: "bool", internalType: "bool" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setRedemptionFee",
    inputs: [
      { name: "_redemptionFee", type: "uint256", internalType: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "supportsInterface",
    inputs: [{ name: "interfaceId", type: "bytes4", internalType: "bytes4" }],
    outputs: [{ name: "", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "totalDeposited",
    inputs: [{ name: "", type: "address", internalType: "address" }],
    outputs: [{ name: "", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "trustReceiver",
    inputs: [
      { name: "_account", type: "address", internalType: "address" },
      { name: "_isTrusted", type: "bool", internalType: "bool" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "trustedReceivers",
    inputs: [
      { name: "", type: "address", internalType: "address" },
      { name: "", type: "address", internalType: "address" },
    ],
    outputs: [{ name: "", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "unpausePToken",
    inputs: [{ name: "_pointsId", type: "bytes32", internalType: "bytes32" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "updateRoot",
    inputs: [{ name: "_newRoot", type: "bytes32", internalType: "bytes32" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "upgradeToAndCall",
    inputs: [
      { name: "newImplementation", type: "address", internalType: "address" },
      { name: "data", type: "bytes", internalType: "bytes" },
    ],
    outputs: [],
    stateMutability: "payable",
  },
  {
    type: "function",
    name: "withdraw",
    inputs: [
      { name: "_token", type: "address", internalType: "contract ERC20" },
      { name: "_amount", type: "uint256", internalType: "uint256" },
      { name: "_receiver", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "event",
    name: "CapSet",
    inputs: [
      {
        name: "token",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "prevCap",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      { name: "cap", type: "uint256", indexed: false, internalType: "uint256" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Deposit",
    inputs: [
      {
        name: "depositor",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "receiver",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "token",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "amount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "FeeCollectorSet",
    inputs: [
      {
        name: "feeCollector",
        type: "address",
        indexed: false,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "FeesCollected",
    inputs: [
      {
        name: "pointsId",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32",
      },
      {
        name: "feeCollector",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "pTokenFee",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "rewardTokenFee",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Initialized",
    inputs: [
      {
        name: "version",
        type: "uint64",
        indexed: false,
        internalType: "uint64",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "MintFeeSet",
    inputs: [
      {
        name: "mintFee",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "PTokenDeployed",
    inputs: [
      {
        name: "pointsId",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32",
      },
      {
        name: "pToken",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "PTokensClaimed",
    inputs: [
      {
        name: "account",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "receiver",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "pointsId",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32",
      },
      {
        name: "amount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      { name: "fee", type: "uint256", indexed: false, internalType: "uint256" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "RedemptionFeeSet",
    inputs: [
      {
        name: "redemptionFee",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "RewardRedemptionSet",
    inputs: [
      {
        name: "pointsId",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32",
      },
      {
        name: "rewardToken",
        type: "address",
        indexed: false,
        internalType: "contract ERC20",
      },
      {
        name: "rewardsPerPToken",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      {
        name: "isMerkleBased",
        type: "bool",
        indexed: false,
        internalType: "bool",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "RewardsClaimed",
    inputs: [
      {
        name: "owner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "receiver",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "pointsId",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32",
      },
      {
        name: "amount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
      { name: "fee", type: "uint256", indexed: false, internalType: "uint256" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "RewardsConverted",
    inputs: [
      {
        name: "owner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "receiver",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "pointsId",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32",
      },
      {
        name: "amount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "RoleAdminChanged",
    inputs: [
      { name: "role", type: "bytes32", indexed: true, internalType: "bytes32" },
      {
        name: "previousAdminRole",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32",
      },
      {
        name: "newAdminRole",
        type: "bytes32",
        indexed: true,
        internalType: "bytes32",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "RoleGranted",
    inputs: [
      { name: "role", type: "bytes32", indexed: true, internalType: "bytes32" },
      {
        name: "account",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "sender",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "RoleRevoked",
    inputs: [
      { name: "role", type: "bytes32", indexed: true, internalType: "bytes32" },
      {
        name: "account",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "sender",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "RootUpdated",
    inputs: [
      {
        name: "prevRoot",
        type: "bytes32",
        indexed: false,
        internalType: "bytes32",
      },
      {
        name: "newRoot",
        type: "bytes32",
        indexed: false,
        internalType: "bytes32",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "TrustReceiver",
    inputs: [
      {
        name: "owner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "delegate",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      { name: "isTrusted", type: "bool", indexed: false, internalType: "bool" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Upgraded",
    inputs: [
      {
        name: "implementation",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Withdraw",
    inputs: [
      {
        name: "withdrawer",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "receiver",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "token",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "amount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  { type: "error", name: "AccessControlBadConfirmation", inputs: [] },
  {
    type: "error",
    name: "AccessControlUnauthorizedAccount",
    inputs: [
      { name: "account", type: "address", internalType: "address" },
      { name: "neededRole", type: "bytes32", internalType: "bytes32" },
    ],
  },
  {
    type: "error",
    name: "AddressEmptyCode",
    inputs: [{ name: "target", type: "address", internalType: "address" }],
  },
  { type: "error", name: "AmountTooSmall", inputs: [] },
  { type: "error", name: "CantConvertMerkleRedemption", inputs: [] },
  { type: "error", name: "ClaimTooLarge", inputs: [] },
  { type: "error", name: "DepositExceedsCap", inputs: [] },
  {
    type: "error",
    name: "ERC1967InvalidImplementation",
    inputs: [
      { name: "implementation", type: "address", internalType: "address" },
    ],
  },
  { type: "error", name: "ERC1967NonPayable", inputs: [] },
  {
    type: "error",
    name: "ExecutionFailed",
    inputs: [
      { name: "to", type: "address", internalType: "address" },
      { name: "data", type: "bytes", internalType: "bytes" },
    ],
  },
  { type: "error", name: "FailedCall", inputs: [] },
  { type: "error", name: "InvalidInitialization", inputs: [] },
  { type: "error", name: "NotInitializing", inputs: [] },
  { type: "error", name: "NotTrustedReceiver", inputs: [] },
  { type: "error", name: "PTokenAlreadyDeployed", inputs: [] },
  { type: "error", name: "PTokenNotDeployed", inputs: [] },
  { type: "error", name: "ProofInvalidOrExpired", inputs: [] },
  { type: "error", name: "RewardsNotLive", inputs: [] },
  { type: "error", name: "UUPSUnauthorizedCallContext", inputs: [] },
  {
    type: "error",
    name: "UUPSUnsupportedProxiableUUID",
    inputs: [{ name: "slot", type: "bytes32", internalType: "bytes32" }],
  },
];