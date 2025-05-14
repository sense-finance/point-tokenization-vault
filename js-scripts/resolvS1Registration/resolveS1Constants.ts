import { Interface } from "ethers";

export const SIGN_MESSAGE_LIB = "0xA65387F16B013cf2Af4605Ad8aA5ec25a2cbA3a2";
export const RUMPEL_ADMIN_SAFE = "0x9D89745fD63Af482ce93a9AdB8B0BbDbb98D3e06";
export const RUMPEL_MODULE = "0x28c3498B4956f4aD8d4549ACA8F66260975D361a";

export const RUMPEL_MODULE_INTERFACE = new Interface([
  "function exec((address safe, address to, bytes data, uint8 operation)[] calls) external",
]);
export const SIGN_MESSAGE_LIB_INTERFACE = new Interface([
  "function signMessage(bytes calldata _data)",
]);

export const START_REGISTER_MESSAGE = `I confirm that I have read, understood, and agree to the $RESOLV Token Airdrop Terms (Last Revised on May 8, 2025), available at https://docs.resolv.xyz/litepaper/legal/airdrop-terms

I acknowledge that I am not a U.S. resident or a Prohibited Person, and I am participating with my own Digital Wallet.

I understand that I have no guarantee or entitlement to receive Tokens and that all participation is at the sole discretion of Resolv Foundation.

I accept all associated risks and responsibilities, including regulatory and tax obligations.

Wallet Address: `;

export const END_REGISTER_MESSAGE = `

Timestamp: 14 May 2025 UTC

Sign this message to participate in the $RESOLV Airdrop.`;
