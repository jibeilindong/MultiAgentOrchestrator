function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function deepSortKeys<T>(value: T): T {
  if (Array.isArray(value)) {
    return value.map((entry) => deepSortKeys(entry)) as T;
  }

  if (!isPlainObject(value)) {
    return value;
  }

  const sortedEntries = Object.keys(value)
    .sort((left, right) => left.localeCompare(right))
    .map((key) => [key, deepSortKeys(value[key])]);

  return Object.fromEntries(sortedEntries) as T;
}

export function stableStringify(value: unknown, space = 2): string {
  return `${JSON.stringify(deepSortKeys(value), null, space)}\n`;
}
