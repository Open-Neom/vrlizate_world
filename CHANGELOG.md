# Changelog

## 0.1.0 — Unreleased

- Schedule large region decoding in a native isolate with bounded codec output, cancellation/close checks and inline web fallback; keep small regions inline.
- Add reproducible CPU decode benchmark and an explicitly unimplemented resource/world-dependency v2 proposal.
- Add experimental `.vrlw` place codec, front index, independent DEFLATE/STORE regions, bounded decoding and prototype validation.
- Add memory/native range sources, indexed region provider, compressed-cache reuse and offline pack/read tools with a forest fixture.
- World/instance identities, bounded coordinates, reusable entity placement and spatial queries.
- Add bounded asynchronous region demand, prefetch, hysteresis, TTL/LRU and stale-load rejection.
- Add optional native persistent region byte cache with size/entry limits, atomic writes and corruption checks.
