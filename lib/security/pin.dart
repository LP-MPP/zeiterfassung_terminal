import 'dart:convert';
import 'package:crypto/crypto.dart';

String hashPin(String employeeId, String pin) {
  // Einfacher Salt: employeeId (für MVP ok). Später: random salt pro MA.
  final bytes = utf8.encode('$employeeId::$pin');
  return sha256.convert(bytes).toString();
}