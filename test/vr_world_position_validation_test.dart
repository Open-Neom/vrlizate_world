import 'package:test/test.dart';
import 'package:vrlizate_world/vrlizate_world.dart';

void main() {
  const limit = VrWorldPosition.maximumCoordinateMeters;
  const epsilon = 1e-8;

  test(
    'each axis rejects nonfinite and outside values with the same error',
    () {
      const names = ['x', 'y', 'z'];
      for (var axis = 0; axis < names.length; axis++) {
        for (final invalid in [
          double.nan,
          double.infinity,
          double.negativeInfinity,
          limit + epsilon,
          -limit - epsilon,
        ]) {
          final coordinates = [1.25, -2.5, 3.75];
          coordinates[axis] = invalid;
          final error = _argumentError(
            () =>
                VrWorldPosition(coordinates[0], coordinates[1], coordinates[2]),
          );
          expect(error.name, names[axis]);
          expect(error.message, VrWorldConstants.errCoordinateOutOfBounds);
          if (invalid.isNaN) {
            expect((error.invalidValue as double).isNaN, isTrue);
          } else {
            expect(error.invalidValue, invalid);
          }
        }
      }
    },
  );

  test('exact and nearby interior bounds remain inclusive', () {
    for (final value in [-limit, -limit + epsilon, limit - epsilon, limit]) {
      final position = VrWorldPosition(value, value, value);
      expect(position.x, value);
      expect(position.y, value);
      expect(position.z, value);
    }
    final opposite = VrWorldPosition(-limit, limit, -limit);
    expect(opposite, VrWorldPosition(-limit, limit, -limit));
  });

  test('multiple invalid coordinates report the first in x y z order', () {
    for (final (x, y, z, name, value) in [
      (double.infinity, double.nan, -limit - 1, 'x', double.infinity),
      (limit + 1, double.infinity, double.nan, 'x', limit + 1),
      (1.0, double.negativeInfinity, double.nan, 'y', double.negativeInfinity),
      (1.0, 2.0, -limit - 1, 'z', -limit - 1),
    ]) {
      final error = _argumentError(() => VrWorldPosition(x, y, z));
      expect(error.name, name);
      expect(error.invalidValue, value);
      expect(error.message, VrWorldConstants.errCoordinateOutOfBounds);
    }
  });

  test('signed zeros keep their fields and normal value equality', () {
    final mixed = VrWorldPosition(-0.0, 0.0, -0.0);
    expect(mixed.x.isNegative, isTrue);
    expect(mixed.y.isNegative, isFalse);
    expect(mixed.z.isNegative, isTrue);
    expect(mixed, VrWorldPosition.zero);
    expect(mixed.hashCode, VrWorldPosition.zero.hashCode);
  });

  test('finite tiny coordinates are neither clamped nor rounded away', () {
    final position = VrWorldPosition(
      -double.minPositive,
      double.minPositive,
      .123456789012345,
    );
    expect(position.x, -double.minPositive);
    expect(position.y, double.minPositive);
    expect(position.z, .123456789012345);
    expect(position, VrWorldPosition(position.x, position.y, position.z));
  });
}

ArgumentError _argumentError(void Function() create) {
  try {
    create();
  } on ArgumentError catch (error) {
    return error;
  }
  throw StateError('Expected an ArgumentError from the coordinate factory.');
}
