import 'package:flutter/material.dart';

enum HapticOutputTarget { vulcan, arduino }

enum HapticMotorType { lfi, lf, mf, hf }

enum HapticEffectType {
  subtle1,
  subtle2,
  subtle3,
  medium1,
  medium2,
  strong1,
  strong2,
  strong3
}

extension ParseToString on HapticEffectType {
  String toDisplayString() {
    switch (this) {
      case HapticEffectType.subtle1:
        return "Subtle 1";
      case HapticEffectType.subtle2:
        return "Subtle 2";
      case HapticEffectType.subtle3:
        return "Subtle 3";
      case HapticEffectType.medium1:
        return "Medium 1";
      case HapticEffectType.medium2:
        return "Medium 2";
      case HapticEffectType.strong1:
        return "Strong 1";
      case HapticEffectType.strong2:
        return "Strong 2";
      case HapticEffectType.strong3:
        return "Strong 3";
    }
  }

  Color buttonColor() {
    switch (this) {
      case HapticEffectType.subtle1:
      case HapticEffectType.subtle3:
        return Colors.green;
      case HapticEffectType.medium1:
      case HapticEffectType.medium2:
        return Colors.blue;
      case HapticEffectType.strong1:
      case HapticEffectType.strong2:
        return Colors.red;
      case HapticEffectType.subtle2:
        return Colors.orange;
      case HapticEffectType.strong3:
        return Colors.blueGrey;
    }
  }

  String toCommandDescription() {
    switch (this) {
      case HapticEffectType.subtle1:
        return "Friendly";
      case HapticEffectType.subtle2:
        return "Reach Target";
      case HapticEffectType.subtle3:
        return "Friendly 15m";
      case HapticEffectType.medium1:
        return "Neutral";
      case HapticEffectType.medium2:
        return "Neutral 15m";
      case HapticEffectType.strong1:
        return "Threat 60m";
      case HapticEffectType.strong2:
        return "Threat";
      case HapticEffectType.strong3:
        return "Msg from Commander";
    }
  }

  int serialOutputValue() {
    switch (this) {
      case HapticEffectType.subtle1:
        return 1;
      case HapticEffectType.subtle2:
        return 2;
      case HapticEffectType.subtle3:
        return 3;
      case HapticEffectType.medium1:
        return 4;
      case HapticEffectType.medium2:
        return 5;
      case HapticEffectType.strong1:
        return 6;
      case HapticEffectType.strong2:
        return 7;
      case HapticEffectType.strong3:
        return 8;
    }
  }
}