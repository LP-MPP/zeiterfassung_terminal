import 'dart:convert';
import 'package:crypto/crypto.dart';

String hashPin(String employeeId, String pin) {
  final bytes = utf8.encode('$employeeId:$pin');
  return sha256.convert(bytes).toString();
}