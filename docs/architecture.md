# Architecture guide

This page is a navigation guide, not a snapshot of the source tree. Read current
versions and dependencies from `pubspec.yaml`, executable structure from `lib/`,
and behavioral contracts from `test/`.

## Core boundaries

- `lib/cubit/disting_cubit.dart` is the state-management facade. Cohesive work
  belongs in its existing ops mixins or delegates.
- `lib/domain/i_disting_midi_manager.dart` separates live, offline, and mock MIDI
  behavior.
- `lib/db/database.dart` owns the Drift schema and migrations.
- `lib/core/routing/` owns routing models and discovery; routing widgets render
  that state rather than rediscovering it.
- `lib/services/mcp_server_service.dart` exposes the app's MCP integration.

## Authorities

- Repository and release rules: [`../AGENTS.md`](../AGENTS.md)
- Coding and delegate patterns:
  [`architecture/coding-standards.md`](architecture/coding-standards.md)
- Domain vocabulary: [`../CONTEXT.md`](../CONTEXT.md)
- SysEx protocol: [`SYSEX_REFERENCE.md`](SYSEX_REFERENCE.md)
- MCP API and mappings: [`mcp-api-guide.md`](mcp-api-guide.md) and
  [`mcp-mapping-guide.md`](mcp-mapping-guide.md)
- Metadata collection: [`metadata-collection-process.md`](metadata-collection-process.md)
- NTX-8CV protocol and acceptance: [`ntx_8cv_protocol.md`](ntx_8cv_protocol.md)
  and [`ntx_8cv_hardware_validation.md`](ntx_8cv_hardware_validation.md)
- Durable architectural decisions: [`adr/`](adr/)

## Maintenance rule

Do not add copied dependency lists, file counts, version inventories, or class
catalogues here. Those facts drift quickly and are cheaper to derive from their
owning files. Record only non-obvious boundaries or decisions that cannot be
recovered from code and tests.
