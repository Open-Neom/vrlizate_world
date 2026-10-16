import '../world_entity.dart';
import 'vrlw_chunk_decode_request.dart';

// Web has no dart:isolate worker here. Hosts should author smaller regions and
// measure their web frame budget until a dedicated web-worker runtime exists.
Future<List<VrWorldEntity>> decodeVrlwChunkInBackground(
  VrlwChunkDecodeRequest request,
) async => request.decode();
