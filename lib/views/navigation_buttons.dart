import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';

enum NavigationButtonType {
  left, right
}

extension NavigationButtonTypeExtension on NavigationButtonType {
  String name() {
    switch (this) {
      case NavigationButtonType.left:
        return "Left";
      case NavigationButtonType.right:
        return "Right";
    }
  }
}

class NavigationButton extends StatefulWidget {
  final NavigationButtonType type;
  final VoidCallback action;

  const NavigationButton({Key? key, required this.type, required this.action}) : super(key: key);

  @override
  State<NavigationButton> createState() => _NavigationButtonState();
}

class _NavigationButtonState extends State<NavigationButton> {
  Timer? _timer;

  bool _isDisabled = false;

  void startTimer() {
    setState(() {
      _isDisabled = true;
    });
    _timer = Timer(const Duration(seconds: 5), () {
      setState(() {
        _isDisabled = false;
        _timer?.cancel();
        _timer = null;
      });
    });
    widget.action();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              minimumSize:
              const Size.fromHeight(50), // NEW
            ),
            onPressed: _isDisabled ? null : startTimer,
            child: Row(
              children: [
                const Spacer(),
                (() {
                  if (widget.type == NavigationButtonType.left) {
                    return const Icon(
                        Icons.keyboard_double_arrow_left,
                        size: 40);
                  } else {
                    return const SizedBox();
                  }
                } ()),
                Text(widget.type.name(),
                    style: const TextStyle(fontSize: 24)),
                (() {
                  if (widget.type == NavigationButtonType.right) {
                    return const Icon(
                        Icons.keyboard_double_arrow_right,
                        size: 40);
                  } else {
                    return const SizedBox();
                  }
                } ()),
                const Spacer()
              ],
            ),
          )),
    );
  }
}
