import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hap_nav/services/comm_service.dart';
import 'package:hap_nav/utils/device_manager.dart';
import 'package:hap_nav/views/lineDetails.dart';
import 'package:hap_nav/views/navigation_buttons.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mapTools;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../utils/helper.dart';

extension on mapTools.LatLng {
  LatLng toGoogleLatLng() {
    return LatLng(latitude, longitude);
  }
}

extension on LatLng {
  mapTools.LatLng toMapToolsLatLng() {
    return mapTools.LatLng(latitude, longitude);
  }
}

class ParticipantPosition {
  final double latitude;
  final double longitude;
  ParticipantPosition(this.latitude, this.longitude);

  @override
  String toString() {
    return "${latitude.toStringAsFixed(8)}, ${longitude.toStringAsFixed(8)}";
  }
}

class BoundaryLine {
  final LatLng start;
  final LatLng end;
  final BoundaryColor color;
  final String id;
  BoundaryLine(this.start, this.end, this.color, this.id);

  Map toJson() =>
      {'start': start, 'end': end, 'color': color.toString(), 'id': id};

  BoundaryLine.fromJson(Map<String, dynamic> json)
      : start = parseLatLng(List<double>.from(json['start'])),
        end = parseLatLng(List<double>.from(json['end'])),
        color = BoundaryColor.fromString(json['color']),
        id = json['id'];

  static LatLng parseLatLng(List<double> input) {
    return LatLng(input[0], input[1]);
  }
}

enum BoundaryColor {
  red,
  blue,
  green,
  black,
  yellow;

  Color toColor() {
    switch (this) {
      case red:
        return Colors.red;
      case blue:
        return Colors.blue;
      case green:
        return Colors.green;
      case black:
        return Colors.black;
      case yellow:
        return Colors.yellow;
    }
  }

  static BoundaryColor fromString(String input) {
    return BoundaryColor.values
        .firstWhere((element) => element.toString() == input);
  }
}

class Navigation extends StatefulWidget {
  const Navigation({Key? key}) : super(key: key);

  @override
  State<Navigation> createState() => _NavigationState();
}

class _NavigationState extends State<Navigation> {
  static const CameraPosition _kGooglePlex = CameraPosition(
    target: LatLng(42.385548, -71.221619),
    zoom: 18,
  );

  final Completer<GoogleMapController> _controller =
      Completer<GoogleMapController>();

  late final Uint8List? _participantIcon;
  late final Uint8List? _originIcon;

  final Set<Marker> _markers = {};
  final Set<Polyline> _lines = {};
  final Set<Circle> _circles = {};

  LatLng? _tmpLineStart;
  LatLng? _tmpLineEnd;

  LatLng? _participantLocation;
  LatLng? _originLocation = const LatLng(42.3823856667, -71.2201560000);
  LatLng? _targetLocation = const LatLng(42.3828970000, -71.2215493333);

  Timer? timer;

  final DeviceManager _deviceManager = GetIt.instance<DeviceManager>();
  final CommService _commService = GetIt.instance<CommService>();

  final LocationSettings locationSettings = const LocationSettings(
    accuracy: LocationAccuracy.best,
  );

  final ValueNotifier<int> plotRefreshThreshold = ValueNotifier(1);

  bool isAnimating = false;

  double _mapZoomLevel = 22;
  double _bearing = 0;

  ValueNotifier<double?> secondsSinceLastPosition = ValueNotifier(null);

  List<BoundaryLine> boundaryLines = [];

  BoundaryColor newLineColor = BoundaryColor.red;

  final String _tmpLineId = "tmp_line_id";

  ValueNotifier<String?> currentLineDetails = ValueNotifier(null);

  String participantPositionTitle = "";

  late double targetCircleRadius = 1;
  late TextEditingController _textEditingController;

  void updateParticipantLocation(ParticipantPosition position) async {
    setState(() {
      _participantLocation = LatLng(position.latitude, position.longitude);
      _markers.add(Marker(
          zIndex: 1,
          markerId: const MarkerId("participant"),
          position: _participantLocation!,
          icon: _participantIcon != null
              ? BitmapDescriptor.fromBytes(_participantIcon!)
              : BitmapDescriptor.defaultMarker));
    });
    // if (_tmpLineStart != null) {
    //   final start = LatLng(_tmpLineStart!.latitude, _tmpLineStart!.longitude);
    //   final end = LatLng(_deviceManager.lastKnownPosition.value!.latitude,
    //       _deviceManager.lastKnownPosition.value!.longitude);
    //   setState(() {
    //     _lines.add(Polyline(
    //       polylineId: PolylineId(_tmpLineId),
    //       visible: true,
    //       width: 5,
    //       points: [start, end],
    //       color: newLineColor.toColor().withOpacity(0.4),
    //       consumeTapEvents: true,
    //     ));
    //
    //     currentLineDetails.value =
    //         "${calculateDistanceBetween(start, end)}m @ ${calculateHeadingOf(start, end)} degrees";
    //   });
    // } else {
    //   setState(() {
    //     _lines.removeWhere((element) => element.polylineId.value == _tmpLineId);
    //   });
    // }

    final GoogleMapController controller = await _controller.future;

    controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: _participantLocation!,
        zoom: _mapZoomLevel,
        bearing: _bearing)));

    participantPositionTitle = "${position.latitude}, ${position.longitude}";
  }

  String calculateDistanceBetween(LatLng coordinateA, LatLng coordinateB) {
    final from = coordinateA.toMapToolsLatLng();
    final to = coordinateB.toMapToolsLatLng();
    return mapTools.SphericalUtil.computeDistanceBetween(from, to)
        .toStringAsFixed(3);
  }

  String calculateHeadingOf(LatLng coordinateA, LatLng coordinateB) {
    final from = coordinateA.toMapToolsLatLng();
    final to = coordinateB.toMapToolsLatLng();
    final h1 = mapTools.SphericalUtil.computeHeading(from, to);
    final h2 = mapTools.SphericalUtil.computeHeading(to, from);
    return math.max(h1, h2).toStringAsFixed(3);
  }

  Future<void> addOriginMarker(LatLng? markerPosition) async {
    final LatLng position = markerPosition ??
        LatLng(_deviceManager.lastKnownPosition.value!.latitude,
            _deviceManager.lastKnownPosition.value!.longitude);

    setState(() {
      _originLocation = LatLng(position.latitude, position.longitude);
      _markers.add(
        Marker(
            zIndex: 0,
            onDrag: (pos) {
              setState(() {
                _originLocation = pos;
              });
            },
            markerId: const MarkerId("origin"),
            position: _originLocation!,
            icon: _originLocation != null
                ? BitmapDescriptor.fromBytes(_originIcon!)
                : BitmapDescriptor.defaultMarker),
      );
    });

    if (markerPosition == null) {
      SharedPreferences.getInstance().then((value) {
        value.setStringList("origin",
            [position.latitude.toString(), position.longitude.toString()]);
      });
    }
  }

  void removeOriginMarker() {
    setState(() {
      _originLocation = null;
      _markers
          .removeWhere((marker) => marker.markerId == const MarkerId("origin"));
    });
    SharedPreferences.getInstance().then((value) {
      value.remove("origin");
    });
  }

  Future<void> addTargetMarker(LatLng? markerPosition) async {
    final position = markerPosition ??
        LatLng(_deviceManager.lastKnownPosition.value!.latitude,
            _deviceManager.lastKnownPosition.value!.longitude);

    setState(() {
      _targetLocation = LatLng(position.latitude, position.longitude);
      _markers.add(Marker(
          zIndex: 0,
          onDrag: (pos) {
            setState(() {
              _targetLocation = pos;
            });
          },
          markerId: const MarkerId("target"),
          position: _targetLocation!));
    });

    if (markerPosition == null) {
      SharedPreferences.getInstance().then((value) {
        value.setStringList("target",
            [position.latitude.toString(), position.longitude.toString()]);
      });
    }
  }

  void removeTargetMarker() {
    setState(() {
      _targetLocation = null;
      _markers
          .removeWhere((marker) => marker.markerId == const MarkerId("target"));
    });
    SharedPreferences.getInstance().then((value) {
      value.remove("target");
    });
  }

  void startLine() {
    final lastKnownPosition = _deviceManager.lastKnownPosition.value;

    if (lastKnownPosition == null) {
      _deviceManager.errorMessage.value = "Cannot find participant location!";
      return;
    }
    _tmpLineStart =
        LatLng(lastKnownPosition.latitude, lastKnownPosition.longitude);
    _markers.add(Marker(
        markerId: const MarkerId("lineStart"),
        position:
            LatLng(lastKnownPosition.latitude, lastKnownPosition.longitude)));
  }

  void endLine() {
    newLineColor = BoundaryColor.black;

    final lastKnownPosition = _deviceManager.lastKnownPosition.value;

    if (lastKnownPosition == null) {
      _deviceManager.errorMessage.value = "Cannot find participant location!";
      return;
    }
    _tmpLineEnd =
        LatLng(lastKnownPosition.latitude, lastKnownPosition.longitude);

    addPolyline(null, "reference_line");

    _markers.removeWhere(
        (element) => element.markerId == const MarkerId("lineStart"));

    _lines
        .removeWhere((element) => element.polylineId == PolylineId(_tmpLineId));

    addConditionLines();
    // addCircle();

    _tmpLineStart = null;
    _tmpLineEnd = null;
    currentLineDetails.value = null;
  }

  void drawExperimentLines() {
    boundaryLines.clear();
    _lines.clear();
    newLineColor = BoundaryColor.black;

    _tmpLineStart = _originLocation;
    _tmpLineEnd = _targetLocation;

    addCircles();

    addPolyline(null, "reference_line");

    addConditionLines();
  }

  void addCircles() {
    setState(() {
      _circles.clear();
      _circles.add(
          Circle(
              circleId: const CircleId("originCircle"),
              center: _originLocation!,
              radius: targetCircleRadius,
              fillColor: Colors.yellow.withOpacity(0.2),
              strokeColor: Colors.yellow,
              strokeWidth: 3
          )
      );

      _circles.add(
          Circle(
              circleId: const CircleId("targetCircle"),
              center: _targetLocation!,
              radius: targetCircleRadius,
              fillColor: Colors.yellow.withOpacity(0.2),
              strokeColor: Colors.yellow,
              strokeWidth: 3
          )
      );
    });
  }

  void addConditionLines() {
    newLineColor = BoundaryColor.yellow;
    addConditionLine(1);
    newLineColor = BoundaryColor.green;
    addConditionLine(2.5);
    newLineColor = BoundaryColor.red;
    addConditionLine(4);
  }

  void addFinishLine() {
    final line1 = boundaryLines[boundaryLines.length - 1];
    final line2 = boundaryLines[boundaryLines.length - 2];

    final referenceLine = boundaryLines.first;

    final lineHeading = mapTools.SphericalUtil.computeHeading(
        referenceLine.start.toMapToolsLatLng(),
        referenceLine.end.toMapToolsLatLng()
    );

    final finishLineP1 = mapTools.SphericalUtil.computeOffset(referenceLine.end.toMapToolsLatLng(), 7, lineHeading + 90);

    _tmpLineStart = line1.end;
    _tmpLineEnd = line2.end;

    addPolyline(null, "finish_line");
  }

  void addConditionLine(num distance) {
    final referenceLine = boundaryLines.first;
    final start = referenceLine.start.toMapToolsLatLng();
    final end = referenceLine.end.toMapToolsLatLng();
    final lineDistance =
        mapTools.SphericalUtil.computeDistanceBetween(start, end);
    final lineHeading = mapTools.SphericalUtil.computeHeading(start, end);

    final midPoint = mapTools.SphericalUtil.computeOffset(
        start, lineDistance / 2, lineHeading);

    final p1 = mapTools.SphericalUtil.computeOffset(
        midPoint, distance, lineHeading + 90);
    final p2 = mapTools.SphericalUtil.computeOffset(
        midPoint, -distance, lineHeading + 90);

    final p1Start =
        mapTools.SphericalUtil.computeOffset(p1, lineDistance / 2, lineHeading);
    final p1End = mapTools.SphericalUtil.computeOffset(
        p1, -lineDistance / 2, lineHeading);

    _tmpLineStart = p1Start.toGoogleLatLng();
    _tmpLineEnd = p1End.toGoogleLatLng();

    addPolyline(null, "condition_line_$distance _1");

    final p2Start =
        mapTools.SphericalUtil.computeOffset(p2, lineDistance / 2, lineHeading);
    final p2End = mapTools.SphericalUtil.computeOffset(
        p2, -lineDistance / 2, lineHeading);

    _tmpLineStart = p2Start.toGoogleLatLng();
    _tmpLineEnd = p2End.toGoogleLatLng();

    addPolyline(null, "condition_line_$distance _ 2");
  }

  void loadMapIcons() async {
    _participantIcon = await getBytesFromAsset(
        path: 'lib/assets/dot.png', //paste the custom image path
        width: 30 // size of custom image as marker
        );

    final originIconData = await getBytesFromIcon(Icons.home);
    _originIcon = originIconData?.buffer.asUint8List();
  }

  void participantPositionListener() {
    if (_deviceManager.lastKnownPosition.value != null) {
      secondsSinceLastPosition.value = null;
      updateParticipantLocation(_deviceManager.lastKnownPosition.value!);
    }
  }

  void errorMessageListener() {
    if (_deviceManager.errorMessage.value != null) {
      showAlertDialog(context, () => {_deviceManager.errorMessage.value = null},
          "Error", _deviceManager.errorMessage.value!);
      HapticFeedback.lightImpact();
    }
  }

  void alertMessageListener() {
    if (_deviceManager.alertMessage.value != null) {
      showAlertDialog(context, () => {_deviceManager.alertMessage.value = null},
          _deviceManager.alertMessage.value!, "");
      HapticFeedback.lightImpact();
    }
  }

  void parseExistingLines() {
    SharedPreferences.getInstance().then((value) {
      final savedOriginCoordinates = value.getStringList("origin");

      if (savedOriginCoordinates != null) {
        log(savedOriginCoordinates.toString());
        addOriginMarker(LatLng(double.parse(savedOriginCoordinates[0]),
            double.parse(savedOriginCoordinates[1])));
      }

      final savedTargetCoordinates = value.getStringList("target");

      if (savedTargetCoordinates != null) {
        log(savedTargetCoordinates.toString());
        addTargetMarker(LatLng(double.parse(savedTargetCoordinates[0]),
            double.parse(savedTargetCoordinates[1])));
      }

      final jsonString = value.getString("lines");
      if (jsonString != null) {
        _lines.clear();
        List<dynamic> parsedListJson = jsonDecode(jsonString);
        List<BoundaryLine> itemsList = List<BoundaryLine>.from(parsedListJson
            .map<BoundaryLine>((dynamic i) => BoundaryLine.fromJson(i)));

        log("Item List ${itemsList.toString()}");

        log(itemsList.toString());
        boundaryLines = itemsList;

        for (var line in itemsList) {
          addPolyline(line, line.id);
        }

        final targetCoordinates = itemsList.firstWhere((element) => element.id == "reference_line");

        setState(() {
          _circles.clear();
          _circles.add(Circle(
              circleId: const CircleId("targetCircle"),
              center: targetCoordinates.end,
              fillColor: Colors.yellow.withOpacity(0.2),
              strokeColor: Colors.yellow,
              radius: targetCircleRadius,
              strokeWidth: 3
          ));

        });
      } else {
        setState(() {
          boundaryLines = [];
          _lines.clear();
        });
      }
    });
  }

  void saveExistingLines() {
    final jsonString = jsonEncode(boundaryLines);
    SharedPreferences.getInstance().then((value) {
      log("Writing $jsonString");
      value.setString("lines", jsonString);
    });
  }

  void addPolyline(BoundaryLine? line, String? id) {
    BoundaryLine lineToAdd = line ??
        BoundaryLine(_tmpLineStart!, _tmpLineEnd!, newLineColor,
            id ?? const Uuid().v4().toString());

    if (line == null) {
      boundaryLines.add(lineToAdd);
      saveExistingLines();
    }

    setState(() {
      _lines.add(Polyline(
          polylineId: PolylineId(lineToAdd.id),
          visible: true,
          width: 3,
          points: [lineToAdd.start, lineToAdd.end],
          color: lineToAdd.color.toColor().withOpacity(lineToAdd.color == BoundaryColor.black ? 0.3 : 1.0),
          patterns: id == "reference_line"
              ? ([
                  PatternItem.dash(20),
                  PatternItem.gap(15),
                ])
              : [],
      ));
    });
  }

  void setPolylineColors(PolylineId id, BoundaryColor color) {
    BoundaryLine? line =
        boundaryLines.firstWhereOrNull((element) => element.id == id.value);

    if (line == null) {
      log("Line is null!");
      return;
    }
    final newLine = BoundaryLine(line.start, line.end, color, line.id);
    setState(() {
      boundaryLines.remove(line);
      boundaryLines.add(newLine);
      parseExistingLines();
    });
  }

  void clearLines() {
    SharedPreferences.getInstance().then((value) {
      value.remove("lines");
      parseExistingLines();
      _tmpLineStart = null;
      _tmpLineEnd = null;
      currentLineDetails.value = null;
    });
    _circles.clear();
  }

  void showSelectedPolylineData(PolylineId id) {
    showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 300,
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                          "Length: ${calculateDistanceBetween(boundaryLines.firstWhere((element) => element.id == id.value).start, boundaryLines.firstWhere((element) => element.id == id.value).end)}m \nHeading: ${calculateHeadingOf(boundaryLines.firstWhere((element) => element.id == id.value).start, boundaryLines.firstWhere((element) => element.id == id.value).end)} degrees"),
                    ],
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  SizedBox(
                    height: 50,
                    width: double.infinity,
                    child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            shadowColor: Colors.red),
                        onPressed: () {
                          showConfirmationDialog(context, () {
                            setState(() {
                              BoundaryLine? line =
                                  boundaryLines.firstWhereOrNull(
                                      (element) => element.id == id.value);
                              boundaryLines.remove(line);
                              _lines.removeWhere(
                                  (element) => element.polylineId == id);
                              saveExistingLines();
                              _tmpLineStart = null;
                              currentLineDetails.value = null;
                            });
                          }, "Delete Line", "Delete this line?");
                        },
                        child: Row(
                          children: const [
                            Spacer(),
                            Icon(Icons.delete),
                            SizedBox(width: 16),
                            Text("Delete"),
                            Spacer()
                          ],
                        )),
                  ),
                  const Spacer()
                ],
              ),
            ),
          );
        });
  }

  @override
  void initState() {
    loadMapIcons();
    _lines.clear();

    super.initState();

    _deviceManager.lastKnownPosition.addListener(participantPositionListener);
    _deviceManager.errorMessage.addListener(errorMessageListener);
    _deviceManager.alertMessage.addListener(alertMessageListener);

    Future.delayed(const Duration(milliseconds: 500), () {
      // parseExistingLines();
      drawExperimentLines();
    });

    timer ??= Timer.periodic(const Duration(seconds: 1), (timer) async {
      secondsSinceLastPosition.value =
          (secondsSinceLastPosition.value ?? -1) + 1;

      final history = _deviceManager.updateIntervalHistory;

      if (history.length > 10) {
        _deviceManager.updateIntervalHistory.removeAt(0);
      }
      _deviceManager.updateIntervalHistory
          .add(secondsSinceLastPosition.value!.round());

      final avg = _deviceManager.updateIntervalHistory.reduce((a, b) => a + b) /
          history.length;
      _commService.connectionQuality.value = avg.toStringAsFixed(2);
    });

    // TODO:  REMOVE THIS~!!!
    _deviceManager.lastKnownPosition.value = ParticipantPosition(_originLocation!.latitude, _originLocation!.longitude);
  }

  @override
  void dispose() {
    timer?.cancel();
    timer = null;
    _deviceManager.lastKnownPosition
        .removeListener(participantPositionListener);
    _deviceManager.errorMessage.removeListener(errorMessageListener);
    _deviceManager.alertMessage.removeListener(alertMessageListener);
    super.dispose();
  }

  Widget _startStopButton() {
    return ValueListenableBuilder(
        valueListenable: _deviceManager.isSessionActive,
        builder: (BuildContext context, bool isActive, Widget? widget) {
          return TextButton(
            onPressed: () {
              if (isActive) {
                _deviceManager.stopSession();
              } else {
                _deviceManager.startSession();
              }
            },
            child: Row(
              children: [
                Icon(isActive ? Icons.stop : Icons.play_arrow,
                    color: Colors.white),
                Text(isActive ? "Stop" : "Start",
                    style: const TextStyle(color: Colors.white))
              ],
            ),
          );
        });
  }

  Widget _addMarkerButton() {
    return IconButton(
        onPressed: () {
          showModalBottomSheet<dynamic>(
              isScrollControlled: true,
              context: context,
              builder: (BuildContext context) {
                return StatefulBuilder(
                    builder: (BuildContext context, StateSetter setState) {
                  return SingleChildScrollView(
                    child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 16, 16,
                            MediaQuery.of(context).viewInsets.bottom),
                        child: Column(
                          children: [
                            // Row(
                            //   children: [
                            //     Expanded(
                            //       child: SizedBox(
                            //           width: double.infinity,
                            //           child: ElevatedButton(
                            //             style: ElevatedButton.styleFrom(
                            //                 minimumSize: const Size.fromHeight(
                            //                     50), // NEW
                            //                 backgroundColor:
                            //                     _originLocation == null
                            //                         ? Colors.blue
                            //                         : Colors.red),
                            //             onPressed: () {
                            //               if (_originLocation == null) {
                            //                 addOriginMarker(null);
                            //                 Navigator.of(context).pop();
                            //               } else {
                            //                 showConfirmationDialog(context, () {
                            //                   removeOriginMarker();
                            //                   Navigator.of(context).pop();
                            //                 }, "Remove Origin",
                            //                     "Are you sure you want to remove this marker?");
                            //               }
                            //             },
                            //             child: Row(
                            //               children: [
                            //                 const Icon(Icons.home),
                            //                 const Spacer(),
                            //                 Text(
                            //                   _originLocation == null
                            //                       ? 'Place Origin'
                            //                       : 'Remove Origin',
                            //                   style:
                            //                       const TextStyle(fontSize: 14),
                            //                 )
                            //               ],
                            //             ),
                            //           )),
                            //     ),
                            //     const SizedBox(width: 8),
                            //     Expanded(
                            //       child: SizedBox(
                            //           width: double.infinity,
                            //           child: ElevatedButton(
                            //             style: ElevatedButton.styleFrom(
                            //               backgroundColor:
                            //                   _targetLocation == null
                            //                       ? Colors.blue
                            //                       : Colors.red,
                            //               minimumSize:
                            //                   const Size.fromHeight(50), // NEW
                            //             ),
                            //             onPressed: () {
                            //               if (_targetLocation == null) {
                            //                 addTargetMarker(null);
                            //                 Navigator.of(context).pop();
                            //               } else {
                            //                 showConfirmationDialog(context, () {
                            //                   removeTargetMarker();
                            //                   Navigator.of(context).pop();
                            //                 }, "Remove Target",
                            //                     "Are you sure you want to remove this marker?");
                            //               }
                            //             },
                            //             child: Row(
                            //               children: [
                            //                 const Icon(Icons.location_on),
                            //                 const Spacer(),
                            //                 Text(
                            //                   _targetLocation == null
                            //                       ? 'Place Target'
                            //                       : 'Remove Target',
                            //                   style:
                            //                       const TextStyle(fontSize: 14),
                            //                 )
                            //               ],
                            //             ),
                            //           )),
                            //     )
                            //   ],
                            // ),
                            // const SizedBox(height: 16),
                            // Row(
                            //   children: [
                            //     Expanded(
                            //       child: SizedBox(
                            //           width: double.infinity,
                            //           child: ElevatedButton(
                            //               style: ElevatedButton.styleFrom(
                            //                   minimumSize:
                            //                       const Size.fromHeight(50),
                            //                   foregroundColor:
                            //                       _tmpLineStart == null
                            //                           ? Colors.blueGrey
                            //                           : Colors.white, // NEW
                            //                   backgroundColor:
                            //                       _tmpLineStart == null
                            //                           ? Colors.white
                            //                           : Colors.blue),
                            //               onPressed: () {
                            //                 if (_tmpLineStart == null) {
                            //                   showConfirmationDialog(context,
                            //                       () {
                            //                     startLine();
                            //                     Navigator.of(context).pop();
                            //                   }, "Start line here?", "");
                            //                 } else {
                            //                   showConfirmationDialog(context,
                            //                       () {
                            //                     endLine();
                            //                     Navigator.of(context).pop();
                            //                   }, "End line here?", "");
                            //                 }
                            //               },
                            //               child: Center(
                            //                 child: Text(
                            //                   _tmpLineStart == null
                            //                       ? "Start Line"
                            //                       : " - End Line",
                            //                   style:
                            //                       const TextStyle(fontSize: 14),
                            //                 ),
                            //               ))),
                            //     ),
                            //   ],
                            // ),
                            // Row(
                            //   children: [
                            //     Expanded(
                            //       child: SizedBox(
                            //         width: double.infinity,
                            //         child: OutlinedButton(
                            //             style: OutlinedButton.styleFrom(
                            //               foregroundColor: Colors.red,
                            //             ),
                            //             onPressed: () {
                            //               showConfirmationDialog(context, () {
                            //                 clearLines();
                            //               }, "Clear Lines?",
                            //                   "Are you sure you want to remove all lines? This cannot be undone");
                            //             },
                            //             child: const Text("Clear Lines")),
                            //       ),
                            //     )
                            //   ],
                            // ),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.grey,
                                        ),
                                        onPressed: () {
                                          boundaryLines.isEmpty
                                              ? null
                                              : showLineDetails();
                                        },
                                        child: const Text("View Line Details")),
                                  ),
                                )
                              ],
                            )
                          ],
                        )),
                  );
                });
              });
        },
        icon: const Icon(Icons.add));
  }

  void showLineDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => LineDetailsView(lines: boundaryLines)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          actions: [_startStopButton(), _addMarkerButton()],
        ),
        body: Stack(
          children: [
            (() {
              if (_participantLocation == null) {
                return const Center(child: CircularProgressIndicator());
              } else {
                return map();
              }
            }()),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // const Spacer(),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              NavigationButton(type: NavigationButtonType.left, action: () {
                                _commService.sendMessage("LEFT, ${_deviceManager.lastKnownPosition.value?.latitude}, ${_deviceManager.lastKnownPosition.value?.longitude}");
                                HapticFeedback.lightImpact();
                              }),
                              const SizedBox(width: 16),
                              NavigationButton(type: NavigationButtonType.right, action: () {
                                _commService.sendMessage("RIGHT, ${_deviceManager.lastKnownPosition.value?.latitude}, ${_deviceManager.lastKnownPosition.value?.longitude}");
                                HapticFeedback.lightImpact();
                              })
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ValueListenableBuilder(
                                  valueListenable:
                                      _deviceManager.lastKnownPosition,
                                  builder: (BuildContext context,
                                      ParticipantPosition? position,
                                      Widget? widget) {
                                    if (position != null) {
                                      return Text(
                                          "Current Position: ${position.toString()}");
                                    }
                                    return const SizedBox();
                                  })
                            ],
                          ),
                          // const SizedBox(height: 8),
                          // Row(
                          //   children: [
                          //     ValueListenableBuilder(
                          //         valueListenable: currentLineDetails,
                          //         builder: (BuildContext context,
                          //             String? lineDetails, Widget? widget) {
                          //           if (lineDetails != null) {
                          //             return Text("Drawing Line: $lineDetails");
                          //           }
                          //           return const SizedBox();
                          //         })
                          //   ],
                          // ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ValueListenableBuilder(
                                  valueListenable: secondsSinceLastPosition,
                                  builder: (BuildContext context,
                                      double? seconds, Widget? widget) {
                                    if (seconds != null && seconds > 10) {
                                      return Text(
                                          "Participant last seen ${seconds}s ago");
                                    }
                                    return const SizedBox();
                                  })
                            ],
                          ),
                          Row(
                            children: [
                              ValueListenableBuilder(
                                  valueListenable:
                                      _commService.connectionQuality,
                                  builder: (BuildContext context,
                                      String? quality, Widget? widget) {
                                    if (quality != null && quality != "0.00") {
                                      return Text(
                                          "Connection quality is: $quality");
                                    }
                                    return const SizedBox();
                                  })
                            ],
                          )
                        ],
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ));
  }

  Widget map() {
    return GoogleMap(
      polylines: _lines,
      markers: _markers,
      circles: _circles,
      mapType: MapType.hybrid,
      initialCameraPosition: _kGooglePlex,
      onMapCreated: (GoogleMapController controller) async {
        _controller.complete(controller);
        final ctrl = await _controller.future;
        changeMapMode(ctrl);
      },
      onCameraMove: (CameraPosition position) {
        _mapZoomLevel = position.zoom;
        _bearing = position.bearing;
      },
      // // TODO: Remove THIS!!!
      // onTap: (LatLng position) {
      //   _deviceManager.lastKnownPosition.value =
      //       ParticipantPosition(position.latitude, position.longitude);
      // },
    );
  }

  //this is the function to load custom map style json
  void changeMapMode(GoogleMapController mapController) {
    getJsonFile("lib/assets/map_style.txt")
        .then((value) => setMapStyle(value, mapController));
  }

  //helper function
  void setMapStyle(String mapStyle, GoogleMapController mapController) {
    mapController.setMapStyle(mapStyle);
  }

  //helper function
  Future<String> getJsonFile(String path) async {
    ByteData byte = await rootBundle.load(path);
    var list = byte.buffer.asUint8List(byte.offsetInBytes, byte.lengthInBytes);
    return utf8.decode(list);
  }

  Future<Uint8List?> getBytesFromAsset(
      {required String path, required int width}) async {
    ByteData data = await rootBundle.load(path);
    ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
        targetWidth: width);
    ui.FrameInfo fi = await codec.getNextFrame();
    return (await fi.image.toByteData(format: ui.ImageByteFormat.png))
        ?.buffer
        .asUint8List();
  }

  Future<ByteData?> getBytesFromIcon(IconData iconData) async {
    final pictureRecorder = PictureRecorder();
    final canvas = Canvas(pictureRecorder);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final iconStr = String.fromCharCode(iconData.codePoint);
    textPainter.text = TextSpan(
        text: iconStr,
        style: TextStyle(
          letterSpacing: 0.0,
          fontSize: 100.0,
          fontFamily: iconData.fontFamily,
          color: Colors.yellow,
        ));
    textPainter.layout();
    textPainter.paint(canvas, const Offset(0.0, 0.0));
    final picture = pictureRecorder.endRecording();
    final image = await picture.toImage(50, 50);
    return image.toByteData(format: ImageByteFormat.png);
  }
}