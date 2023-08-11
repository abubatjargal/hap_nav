import 'package:flutter/material.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({Key? key}) : super(key: key);

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async => false,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: InkWell(
              child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text("Screen is locked. Hold to unlock",
                      style: TextStyle(color: Colors.white))),
              onLongPress: () {
                Navigator.of(context).pop();
              },
            ),
          ),
        ));
  }
}
