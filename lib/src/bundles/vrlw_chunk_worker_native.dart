import 'dart:isolate';

import '../world_entity.dart';
import 'vrlw_chunk_decode_request.dart';

// Sending a bound method on this data-only request avoids accidentally copying
// the provider and its source/cache closures into the worker isolate.
Future<List<VrWorldEntity>> decodeVrlwChunkInBackground(
  VrlwChunkDecodeRequest request,
) => Isolate.run(request.decode, debugName: 'vrlw-region-decode');
