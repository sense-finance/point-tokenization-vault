export function packTwo(a: string, b: string): `0x${string}` {
  const aLength = a.length;
  const bLength = b.length;

  const totalLength = aLength + bLength;
  if (totalLength === 0 || totalLength > 30) {
    return "0x00";
  }

  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);

  const resultBytes = new Uint8Array(32);
  resultBytes[0] = aLength;
  resultBytes.set(aBytes, 1);

  resultBytes.set([bLength], 1 + aLength);
  resultBytes.set(bBytes, 2 + aLength);

  const hexString = Array.from(resultBytes)
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

  return `0x${hexString}`;
}

export const POINTS_ID_KINETIQ_S1 = packTwo("Rumpel Pt: Kinetiq S1", "pKINTQ-1");

export const POINTS_ID_HYPERBEAT_S1 = packTwo("Rumpel Pt: Hyprbeat S1", "pHBEAT-1");
