abstract final class VrWorldConstants {
  static const String identifierPattern =
      r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$';
  static const String sha256Pattern = r'^[0-9a-f]{64}$';
  static const String controlCharPattern = r'[\x00-\x1f\x7f]';
  static const String diskEntryNamePattern = r'^r-[0-9a-f]{32}\.vrregion$';
  static const String diskPendingNamePattern =
      r'^\.pending-[0-9]+-[0-9]+\.tmp$';

  static const double maximumCoordinateMeters = 10000000.0;
  static const double maximumScale = 1000.0;
  static const double defaultScale = 1.0;
  static const double defaultYawRadians = 0.0;

  static const double defaultRegistryCellSizeMeters = 16.0;
  static const double minCellSizeMeters = 0.1;
  static const int defaultRegistryMaxEntities = 10000;
  static const int maximumEntityCapacity = 100000;
  static const int maximumQueryCells = 4096;
  static const double worldDiagonalMultiplier = 4.0;

  static const int maxRegionGridIndex = 100000016;
  static const double defaultRegionGridCellSizeMeters = 64.0;
  static const int maxRegionDataBytes = 2147483647;
  static const int defaultRegionCacheMaxEntries = 32;
  static const int maxRegionCacheEntriesLimit = 4096;
  static const int defaultRegionCacheMaxBytes = 32 * 1024 * 1024;
  static const int defaultPrefetchRadiusCells = 1;
  static const int maxPrefetchRadiusCells = 8;
  static const int defaultRetentionRadiusCells = 2;
  static const int maxRetentionRadiusCells = 16;
  static const int defaultMaxConcurrentLoads = 2;
  static const int maxConcurrentLoadsLimit = 16;
  static const int defaultIdleTtlMinutes = 10;

  static const int defaultDiskCacheMaxBytes = 64 * 1024 * 1024;
  static const int maxDiskCacheBytesLimit = 2 * 1024 * 1024 * 1024;
  static const int defaultDiskCacheMaxEntries = 128;
  static const int maxDiskCacheEntriesLimit = 100000;
  static const int defaultMaxDiskEntryBytes = 8 * 1024 * 1024;
  static const int defaultDiskCacheIdleDays = 7;
  static const String diskCacheNamespace = 'vrlizate-regions-v1';
  static const List<int> diskCacheMagic = <int>[86, 82, 87, 82, 67, 48, 48, 49];
  static const int diskCachePrefixBytes = 12;
  static const int diskCacheLengthOffset = 8;
  static const int maxDiskHeaderBytes = 16384;
  static const int maxDiskKeyUtf8Bytes = 4096;

  static const int vrlwHeaderSize = 16;
  static const int vrlwMaxManifestBytes = 1024 * 1024;
  static const int vrlwMaxChunks = 1024;
  static const int vrlwMaxPackedChunkBytes = 512 * 1024;
  static const int vrlwMaxUnpackedChunkBytes = 2 * 1024 * 1024;
  static const int vrlwMaxFileBytes = 128 * 1024 * 1024;
  static const int vrlwMaxTotalUnpackedBytes = 256 * 1024 * 1024;
  static const int vrlwMaxEntitiesPerChunk = 4096;
  static const int vrlwMaxResources = 32;
  static const int vrlwMaxResourceBytes = 4 * 1024 * 1024;
  static const int vrlwMaxTotalResourceBytes = 16 * 1024 * 1024;
  static const int vrlwMaxTextureDimension = 512;
  static const int vrlwMaxCompressedTextureDimension = 2048;
  static const int vrlwMaxAudioEmitters = 64;
  static const int vrlwMaxMotions = 8;
  static const int vrlwMaxInteractions = 8;
  static const int vrlwMaxDependencies = 32;
  static const String vrlwMagic = 'VRLW0001';
  static const int vrlwMaxReadLength = 1024 * 1024;
  static const int backgroundDecodeThresholdBytes = 64 * 1024;
  static const String defaultInstanceId = 'local';
  static const int emptyRegionResidentBytes = 64;
  static const int residentUnpackedMultiplier = 4;
  static const int residentEntityOverheadBytes = 384;
  static const int residentBaseOverheadBytes = 256;

  static const double defaultPortalTriggerRadiusMeters = 2.0;
  static const double maxPortalTriggerRadiusMeters = 1000.0;
  static const int maxPortalLabelLength = 160;

  static const String sharedSpaceUriScheme = 'vrlizate';
  static const String sharedSpaceUriHost = 'space';
  static const String sharedSpaceCodePrefix = 'VRLZ-SPACE-';
  static const double minRoomDimensionMeters = 0.5;
  static const double maxRoomDimensionMeters = 500.0;
  static const double defaultRoomWidthMeters = 3.0;
  static const double defaultRoomDepthMeters = 3.0;
  static const double fullCircleDegrees = 360.0;
  static const int maxHostDisplayNameLength = 64;

  static const String keyAnchorId = 'anchorId';
  static const String keyWorldId = 'worldId';
  static const String keyOriginX = 'ox';
  static const String keyOriginY = 'oy';
  static const String keyOriginZ = 'oz';
  static const String keyCompassHeadingDegrees = 'heading';
  static const String keyRoomWidthMeters = 'rw';
  static const String keyRoomDepthMeters = 'rd';
  static const String keyHostDisplayName = 'host';
  static const String keyCreatedAtEpochMs = 'ts';

  static const String paramWorldId = 'worldId';
  static const String paramInstanceId = 'instanceId';
  static const String paramId = 'id';
  static const String paramPrototypeId = 'prototypeId';
  static const String paramYawRadians = 'yawRadians';
  static const String paramScale = 'scale';
  static const String paramCellSizeMeters = 'cellSizeMeters';
  static const String paramMaxEntities = 'maxEntities';
  static const String paramRadiusMeters = 'radiusMeters';
  static const String paramWorld = 'world';
  static const String paramGridId = 'gridId';
  static const String paramSizeBytes = 'sizeBytes';
  static const String paramMaxEntries = 'maxEntries';
  static const String paramMaxBytes = 'maxBytes';
  static const String paramPrefetchRadiusCells = 'prefetchRadiusCells';
  static const String paramRetentionRadiusCells = 'retentionRadiusCells';
  static const String paramMaxConcurrentLoads = 'maxConcurrentLoads';
  static const String paramIdleTtl = 'idleTtl';
  static const String paramDirectoryPath = 'directoryPath';
  static const String paramMaxEntryBytes = 'maxEntryBytes';
  static const String paramKey = 'key';
  static const String paramTriggerRadiusMeters = 'triggerRadiusMeters';
  static const String paramLabel = 'label';
  static const String paramSourceWorld = 'sourceWorld';
  static const String paramTargetWorld = 'targetWorld';
  static const String paramAnchorId = 'anchorId';
  static const String paramCompassHeadingDegrees = 'compassHeadingDegrees';
  static const String paramRoomWidthMeters = 'roomWidthMeters';
  static const String paramRoomDepthMeters = 'roomDepthMeters';
  static const String paramHostDisplayName = 'hostDisplayName';
  static const String paramCreatedAtEpochMs = 'createdAtEpochMs';

  static const String errInvalidIdentifier =
      'Expected 1–128 ASCII letters/digits/dot/underscore/colon/hyphen, '
      'starting with a letter or digit.';
  static const String errCoordinateOutOfBounds =
      'Coordinate outside world bounds.';
  static const String errFinite = 'Must be finite.';
  static const String errScaleRange = 'Must be positive and <= 1000.';
  static const String errCellSizeRange =
      'Must be finite, >= 0.1 and within world bounds.';
  static const String errRadiusRange = 'Must be finite and >= 0.';
  static const String errDifferentWorldInstance = 'Different world instance.';
  static const String errEntityCapacityReached =
      'World entity capacity reached.';
  static const String errRegionIndexOutOfBounds =
      'Region index outside supported local grid bounds.';
  static const String errRegionCancelled = 'Region request cancelled.';
  static const String errRegionCacheDisposed = 'Region cache is disposed.';
  static const String errVrlwSourceClosed = 'VRLW source is closed.';
  static const String errVrlwSourceBudget =
      'VRLW source exceeds its byte budget.';
  static const String errVrlwRangeBudget =
      'VRLW range exceeds its source or read budget.';
  static const String errVrlwPlaceReaderClosed = 'VRLW place reader is closed.';
  static const String errPortalTriggerRadius =
      'Portal trigger radius must be finite, > 0, and <= 1000.';
  static const String errPortalLabel =
      'Portal label must be non-empty and <= 160 characters.';
  static const String errPortalSameWorld =
      'Portal targetWorld must differ from sourceWorld.';
  static const String errRoomDimensionRange =
      'Room dimension must be finite and between 0.5 and 500.0 meters.';
  static const String errHostDisplayName =
      'Host display name must be non-empty and <= 64 characters.';
  static const String errCreatedAtEpochMs = 'Timestamp must be >= 0.';
  static const String errInvalidSharedSpaceUri =
      'Invalid VRlizate shared space URI.';
  static const String errInvalidSharedSpaceCode =
      'Invalid VRLZ-SPACE share code.';
}
