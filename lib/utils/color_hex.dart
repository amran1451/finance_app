import 'package:flutter/material.dart';

String? colorToHex(Color? c) {
  if (c == null) return null;
  final v = (c.value & 0x00FFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
  return '#$v';
}

Color? hexToColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}
