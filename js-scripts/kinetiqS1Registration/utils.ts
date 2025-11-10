export function packTwo(a: string, b: string): `0x${string}` {
  // Calculate lengths
  const aLength = a.length;
  const bLength = b.length;

  // Check combined length
  const totalLength = aLength + bLength;
  if (totalLength === 0 || totalLength > 30) {
    return "0x00"; // Return 0x00 for invalid lengths
  }

  // Convert strings to byte arrays
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);

  // Combine lengths and bytes into a single Uint8Array
  const resultBytes = new Uint8Array(32);
  resultBytes[0] = aLength;
  resultBytes.set(aBytes, 1);

  resultBytes.set([bLength], 1 + aLength);
  resultBytes.set(bBytes, 2 + aLength);

  // Convert Uint8Array to hex string with 0x prefix
  const hexString = Array.from(resultBytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return `0x${hexString}`;
}

export const POINTS_ID_KINETIQ_S1 = packTwo("Rumpel Pt: Kinetiq S1", "pKINTQ-1");
