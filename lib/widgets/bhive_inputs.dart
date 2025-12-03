// lib/widgets/bhive_inputs.dart
import 'package:flutter/material.dart';

/// Global B-Hive styled input decoration.
///
/// Use this everywhere instead of duplicating InputDecoration code.
InputDecoration bhiveInputDecoration(
  String label, {
  String? hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white38),
    labelStyle: const TextStyle(color: Colors.white70),
    filled: true,
    fillColor: Colors.black.withOpacity(0.4),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.white24),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.white70, width: 1.5),
    ),
  );
}
