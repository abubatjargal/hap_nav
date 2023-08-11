import 'package:flutter/material.dart';

void showConfirmationDialog(
    BuildContext context, Function() onContinue, String title, String msg) {
  // set up the buttons
  Widget cancelButton = TextButton(
    child: const Text("Cancel"),
    onPressed: () {
      Navigator.of(context).pop();
    },
  );
  Widget continueButton = TextButton(
    onPressed: () {
      onContinue();
      Navigator.of(context).pop();
    },
    child: const Text("Continue"),
  );
  // set up the AlertDialog
  AlertDialog alert = AlertDialog(
    title: Text(title),
    content: Text(msg),
    actions: [
      cancelButton,
      continueButton,
    ],
  );
  // show the dialog
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
  );
}

void showAlertDialog(
    BuildContext context, Function() onOk, String title, String msg) {
  Widget okButton = TextButton(
    onPressed: () {
      onOk();
      Navigator.of(context).pop();
    },
    child: const Text("Continue"),
  );
  // set up the AlertDialog
  AlertDialog alert = AlertDialog(
    title: Text(title),
    content: Text(msg),
    actions: [
      okButton,
    ],
  );
  // show the dialog
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
  );
}


void showScaffoldMessage(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}