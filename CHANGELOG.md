# Changelog

## 1.0.0 - 2026-10-20

- Architecture refactor to Open Neom standard layout (`lib/utils/constants/`, `lib/utils/enums/`, `lib/domain/models/`, `lib/domain/services/`) with one class or enum per file and centralized constants (`VrWorldConstants`).
- Add `VrSharedSpaceAnchor` and `VrSharedSpaceCodec` (`vrlizate://space/...` URI and `VRLZ-SPACE:` share codes) for zero-server peer-to-peer co-located physical/virtual space alignment (`alignPeerPosition`).
- Add `VrWorldEnvironmentPreset` (`daylight`, `nightSky`, `cyberpunkNeon`, `studioNeutral`, `sunsetHorizon`, `deepSpace`) with factory converters to `VrlwEnvironmentSpec`.
- Add `VrPortalLink` for inter-world/inter-instance portal teleports with activation radius checks.
- Add `VrWorldBuilder` for fluent declarative construction of a `VrWorldRegistry` and `.vrlw` bundle metadata/chunks.
- Preserve 100% backward-compatible barrel exports under `lib/src/` and `lib/vrlizate_world.dart`.

## 0.1.0 — Unreleased

- Schedule large region decoding in a native isolate with bounded codec output, cancellation/close checks and inline web fallback; keep small regions inline.
- Add reproducible CPU decode benchmark and an explicitly unimplemented resource/world-dependency v2 proposal.
- Add experimental `.vrlw` place codec, front index, independent DEFLATE/STORE regions, bounded decoding and prototype validation.
- Add memory/native range sources, indexed region provider, compressed-cache reuse and offline pack/read tools with a forest fixture.
- World/instance identities, bounded coordinates, reusable entity placement and spatial queries.
- Add bounded asynchronous region demand, prefetch, hysteresis, TTL/LRU and stale-load rejection.
- Add optional native persistent region byte cache with size/entry limits, atomic writes and corruption checks.
