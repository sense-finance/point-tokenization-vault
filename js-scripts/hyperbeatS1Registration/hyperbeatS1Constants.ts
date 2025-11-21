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

export const HYPERBEAT_TERMS_MESSAGE = "I accept the Hyperbeat Foundation Terms of Use";
