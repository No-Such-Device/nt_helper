# MCP memory connected-device build validation

This record is agent-observed build acceptance evidence for the fresh MCP memory query. It is not Neal Sanche's owner-final acceptance.

| Field | Observed value |
| --- | --- |
| Date (UTC) | 2026-09-18T14:18:22Z |
| Checkout under test | `593ac9b7c286bc6c1066c8cea0ae6c0994973c74` (includes MCP implementation commit `6fe361127270ab3106a633d83d7d2998fc18e22f`) |
| Build | nt_helper `2.52.0+334`, macOS debug build, Flutter `3.44.9` |
| Host | macOS `26.6.2` (`25G83`) |
| Connected firmware | `v1.19.0beta`, `Sep 16 2026 11:56:15` |
| Preset before and after | `Init`, slot 0 `Seymour` (`ThSy`), 19 parameters |

The firmware value and date were read from the connected build's live `DistingVersion` widget. The preset was queried immediately before and after the memory request and did not change.

## MCP request

```json
{"tool":"show_memory","arguments":{}}
```

## MCP result

```json
{
  "success": true,
  "memory_usage": {
    "sram": {"current_bytes": 3680, "total_bytes": 335872, "free_bytes": 332192},
    "dram": {"current_bytes": 76816, "total_bytes": 16777216, "free_bytes": 16700400},
    "dtc": {"current_bytes": 96, "total_bytes": 195584, "free_bytes": 195488},
    "itc": {"current_bytes": 0, "total_bytes": 12288, "free_bytes": 12288}
  }
}
```

The response contains only the four approved pools and their byte-valued current, total, and derived free fields. This call used the running app's registered MCP transport and currently connected physical Disting NT; it was not a mocked result.
