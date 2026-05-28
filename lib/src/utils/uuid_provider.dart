import 'package:uuid/uuid.dart';

class UuidProvider {
  static const Uuid _uuid = Uuid();
  static String next() => _uuid.v4();
}
