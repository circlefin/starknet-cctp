// Copyright (c) 2025, Circle Internet Financial LTD. All Rights Reserved.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.


export function encode(bytes: Uint8Array | number[]): string[] {
  const byteArray = bytes instanceof Uint8Array ? Array.from(bytes) : bytes;
  const result: string[] = [];

  // 1. Split the array into 31-byte chunks
  const chunks: number[][] = [];
  let remaining: number[] = [];

  for (let i = 0; i < byteArray.length; i += 31) {
    if (i + 31 <= byteArray.length) {
      // Full 31-byte chunk
      chunks.push(byteArray.slice(i, i + 31));
    } else {
      // Remaining bytes (less than 31)
      remaining = byteArray.slice(i);
    }
  }

  // 2. First, push the number of full chunks (excluding remaining)
  result.push('0x' + chunks.length.toString(16));

  // 3. Push chunks as hex strings
  for (const chunk of chunks) {
    const hexChunk = chunk.map(b => b.toString(16).padStart(2, '0')).join('');
    result.push('0x' + hexChunk);
  }

  // 4. Push remaining chunk as hex string (or empty if no remaining)
  const remainingHex = remaining.map(b => b.toString(16).padStart(2, '0')).join('');
  result.push('0x' + remainingHex);

  // 5. Push the length of remaining chunk
  result.push('0x' + remaining.length.toString(16));

  return result;
}

export function hexToBytes(hex: string): number[] {
  const bytes: number[] = [];
  for (let i = 0; i < hex.length; i += 2) {
    bytes.push(parseInt(hex.substring(i, i + 2), 16));
  }
  return bytes;
}

export function hexToBytesArray(hex: string): string[] {
  const bytes = hexToBytes(hex);
  return encode(bytes);
}
