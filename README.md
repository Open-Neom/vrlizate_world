# vrlizate_world

Render-neutral local coordinates, entity placement, indexed place packages and region caching for the VRlizate SDK.
No Flutter, Firebase, renderer, authentication, or networking dependency.

```dart
import 'package:vrlizate_world/vrlizate_world.dart';

final plaza = VrWorldAddress(worldId: 'vrlizate.plaza', instanceId: 'local');
final world = VrWorldRegistry(world: plaza);
world.add(VrWorldEntity(
  id: 'plaza-tree-1',
  prototypeId: 'tree.plaza',
  world: plaza,
  transform: VrWorldTransform(position: VrWorldPosition(-6, 0, 24)),
));
final nearby = world.queryRadius(
  center: VrWorldPosition(0, 1.6, 22),
  radiusMeters: 15,
);
```

Coordinates are meters, +X right, +Y up, -Z forward. A world ID and instance ID
jointly select one coordinate space. Positions are finite and bounded to ±10
million meters per axis. Rotation is Y-axis yaw in radians and scale is positive
and uniform (maximum 1000). Prototypes are stable, explicitly registered IDs;
they are not URLs, downloaded code, account identities, or GPS locations.

`VrWorldRegistry` rejects duplicate IDs, updates missing entities, different-world
placements, and capacity overflow. `update` replaces an immutable entity snapshot;
`remove` removes it from the spatial index. The X/Z grid uses floor for negative
coordinates, then filters by exact 3D distance to the entity origin. It does not
test mesh bounds or replace collision detection. Radius queries enumerate at
most 4096 cells or scan the bounded registry instead. Default capacity is 10,000,
with an explicit maximum of 100,000 entities. These are data limits, not a promise
that a phone can render that many objects. Returned lists are immutable snapshots.

## Rendering and efficiency

The renderer consumes placements and maps each prototype to reusable geometry,
materials, collision shapes, and optional level of detail. Injecting a tree by
ID and transform separates content from world construction and permits later
updates without rewriting the world. It still has to be drawn when visible.

The existing Home combines geometry by zone/material; the OpenWorld harbor uses
Flutter Scene `InstancedMeshComponent` for repeated architecture and vegetation.
Keep those optimizations when consuming entities. One mesh/material allocation
and one draw call per tree can perform worse than the existing implementation.
Use shared prototypes, instancing/batching, culling, bounded active regions, and
device-quality budgets. This package provides spatial queries and bounded region
data streaming. GPU instancing, frustum culling and presentation belong to the
renderer; no FPS improvement is claimed without device measurements.

## Region streaming and disposable cache

`VrRegionGrid` maps X/Z meters to bounded neighborhoods. Its `gridId` must identify
origin, axes, cell resolution and content revision. `VrRegionCache<T>` prefetches
nearby cells with a provider callback, bounded concurrency, byte/count budgets,
retention hysteresis, TTL/LRU and stale-response rejection. It enumerates nearby
cells, not a whole-planet catalog. Use `updatePosition`, `changes`/`snapshot`, and
periodic `prune`; stop a session with `dispose`. Provider failures are not retried
every frame; a host can explicitly call `retryFailures`.

Native hosts can separately import `package:vrlizate_world/vrlizate_world_io.dart`
for `VrRegionDiskCache`. It stores encoded regions across launches, prunes by age,
count and physical bytes, validates accidental corruption, and serializes writes.
Use one owner per app-private directory and include a content revision in each key.
The core barrel remains web-compatible; browser persistence requires another adapter.
User saves and authored changes are never disposable region cache data.

See the SDK's `docs/world_streaming_cache.md` for the OpenWorld integration and
limitations. Run `dart run tool/region_walk_example.dart` for a bounded 1,000-region
walk with cache reuse on a nearby return.

## Experimental `.vrlw` place packages

`VrlwBundleCodec` compiles validated placement data into a front index and
independently compressed regions. `VrlwPlaceReader` and `VrlwRegionProvider`
connect selective decoding to the existing region cache. Core memory sources
remain portable; the IO barrel adds native file ranges, and `vrlizate_apps`
provides HTTPS ranges with version pinning. SHA-256, output budgets and explicit
host prototype registration are enforced before returning entities.

This is content compilation and decompression, not downloaded Dart execution.
Version 1 beta supports installed host prototypes and optional bounded static
GLB/RGBA8 resources with explicit prototype bindings. Apps validates the full
static model profile before rendering. Audio and executable code are not embedded.
The `vrlizate.worlds.v1` experience profile connects locally bundled places.
The OpenWorld forest uses the included 49-region fixture; Flutter loads its
small asset once, then decodes regions on demand. Native/HTTPS sources support
partial reads. No smartphone FPS improvement has been measured for this change.

Start with the [authoring and integration guide](doc/vrlw_guide.md), including a
minimal JSON place and executable Dart reader. See the
[VRLW v1 beta specification](doc/vrlw_format.md) for binary details and the
[extension naming review](doc/vrlw_naming.md) for documented `.vrz`/`.vrw` collisions.
The [VRLW v1 beta roadmap](doc/vrlw_beta_roadmap.md) separates the implemented
static-resource subset from remote dependencies, more codecs and composition
still pending in this initial unreleased beta. See the
[external authoring guide](../docs/creator_worlds_beta.md) for local world packages.
The container remains `VRLW0001` with `schemaVersion: 1`. `tool/benchmark_vrlw.dart` measures index/chunk CPU decoding separately
from rendering and I/O. Large native chunks decode outside the caller isolate;
small chunks and the web fallback remain inline. This does not budget GPU upload.

## Reuse and multiplayer boundary

Existing code audited in the same workspace:

- `VRlizate_app/lib/ecosystem/auth/vr_ecosystem_session.dart` and its root binding
  already reuse Open Neom login/profile identity, guard protected actions, and
  invalidate identity when an account/profile changes. Keep that identity in the
  host; an avatar is a VR representation attached to a profile.
- `neom_rooms/lib/data/firestore/room_firestore.dart` provides rooms, participant
  streams, reactions, join/leave, and heartbeat. Its default participant stream
  is capped at 50; heartbeat is 30 seconds and stale threshold is 90 seconds.
  These APIs are useful for membership and social events, not frame-rate poses.
  The book-tour `sync/latest` document should not become a hot shared pose slot.
- `neom_rooms/lib/data/webrtc/room_webrtc_controller.dart` provides voice with
  Firestore signaling, reconnect/device handling and Opus configuration. Its
  mesh currently caps peer connections at five. It does not expose pose data
  channels or a public per-participant gain/pan API. A spatial voice adapter can
  extend that implementation; larger public groups need a scalable audio
  transport and proximity subscriptions.
- `vrlizate_scene/lib/src/vr_spatial_audio.dart` already evaluates attenuation and
  stereo pan. Reuse that policy for distance-dependent playback. Evaluation alone
  does not spatialize a remote voice track or implement HRTF/occlusion.
- `vrlizate/lib/core/network/vr_remote_pose_predictor.dart` handles angular
  smoothing/prediction for a 3DoF controller. Its protocol has no player world
  position and should not be mislabeled as multiplayer replication.

No authenticated multiplayer service is connected by this package. Public-world
delivery still needs authenticated membership, session lifecycle, bounded pose
updates with sequence/timing validation, remote interpolation, proximity/region
subscriptions, authoritative object updates, moderation, and an audio adapter.
Rendering remains local; transmit poses/events rather than video of the world.

No VRlizate/neom_rooms backend authorization rules were found in the inspected
checkout. Existing client guards do not establish deployed server authorization.
Before public writes, verify server membership/ownership, limits and rules against
the selected backend. Do not use `neom_states`' unauthenticated random presence ID
as a player identity; it is only a lightweight experience participation counter.

Run `dart test` and `dart analyze` inside this package.
