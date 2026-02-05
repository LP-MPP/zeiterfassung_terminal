import 'dart:io';
import '../lib/core/security.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run tool/hash_pin.dart <EMP_ID> <PIN>');
    exit(2);
  }

  final empId = args[0];
  final pin = args[1];

  final hash = hashPin(empId, pin);
  stdout.writeln(hash);
}