import type { SwiftDate } from "@multi-agent-flow/domain";

const SWIFT_REFERENCE_UNIX_MS = Date.UTC(2001, 0, 1, 0, 0, 0, 0);

export function toSwiftDate(value: Date | number = Date.now()): SwiftDate {
  const unixMs = value instanceof Date ? value.getTime() : value;
  return (unixMs - SWIFT_REFERENCE_UNIX_MS) / 1000;
}

export function fromSwiftDate(value: SwiftDate): Date {
  return new Date(SWIFT_REFERENCE_UNIX_MS + value * 1000);
}
