# Compatibility Fixtures

These `.maoproj` files are synthetic regression fixtures used to validate the
TypeScript compatibility layer.

- `minimal-legacy.maoproj` exercises normalization from a sparse legacy-style payload.
- `workflow-complex.maoproj` exercises agent, node, edge, and Swift-date round-tripping.
- `runtime-protocol.maoproj` exercises runtime event round-tripping across message, execution, and runtime-state payloads.

When real production project files become available for testing, add sanitized
copies alongside these fixtures to extend coverage.
