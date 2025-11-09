import { Interface } from "ethers";

export const SIGN_MESSAGE_LIB = "0x98FFBBF51bb33A056B08ddf711f289936AafF717";
export const HYPEREVM_ADMIN_SAFE = "0x3ffd3d3695Ee8D51A54b46e37bACAa86776A8CDA";
export const HYPEREVM_MODULE = "0xa1804146617bFDb81dF7bf35a1dCC02f922559Fe";

export const RUMPEL_MODULE_INTERFACE = new Interface([
  "function exec((address safe, address to, bytes data, uint8 operation)[] calls) external",
]);

export const SIGN_MESSAGE_LIB_INTERFACE = new Interface([
  "function signMessage(bytes calldata _data)",
]);

// EIP-712 domain for Kinetiq terms signing
export const KINETIQ_DOMAIN = {
  name: "Kinetiq",
  version: "1",
  chainId: 999, // HyperEVM chain ID
  salt: "0x0456c9c833dd04de820193e57bcdec9d1c2b033be28b67d37c162a78aa223af1",
} as const;

// EIP-712 types for AcceptTerms (ordered to match Kinetiq portal prompt)
export const ACCEPT_TERMS_TYPES = {
  AcceptTerms: [
    { name: "hyperliquidChain", type: "string" },
    { name: "message", type: "string" },
    { name: "cid", type: "string" },
    { name: "time", type: "uint256" },
  ],
} as const;

export const TERMS_MESSAGE = "I acknowledge and agree to the Terms of Use at https://kinetiq-foundation.org/terms.";
export const TERMS_CID = "bafkreiheqihimggxn2kuh6zugih3fxwxgrshfwvvjxsc3cizjwbzmtxrfq";
export const HYPERLIQUID_CHAIN = "Mainnet";
