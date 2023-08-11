import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mapTools;
import 'navigation.dart';

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

class LineDetailsView extends StatefulWidget {
  List<BoundaryLine> lines;

  LineDetailsView({Key? key, required this.lines}) : super(key: key);

  @override
  State<LineDetailsView> createState() => _LineDetailsViewState();
}

class _LineDetailsViewState extends State<LineDetailsView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(),
        body: ListView.builder(
          itemCount: widget.lines.length,
          itemBuilder: (context, index) {
            return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ListTile(
                  title: Text("Line id: ${widget.lines[index].id}"),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(color: widget.lines[index].color.toColor(), thickness: 3),
                      Text(
                          "Start: ${widget.lines[index].start.latitude.toStringAsFixed(10)}, ${widget.lines[index].start.longitude.toStringAsFixed(10)}"),
                      Text(
                          "End: ${widget.lines[index].end.latitude.toStringAsFixed(10)}, ${widget.lines[index].end.longitude.toStringAsFixed(10)}"),
                      Text("Color: ${widget.lines[index].color.name}"),
                      Text("Distance: ${mapTools.SphericalUtil.computeDistanceBetween(widget.lines[index].start.toMapToolsLatLng(), widget.lines[index].end.toMapToolsLatLng())
                          .toStringAsFixed(3)}m")
                    ],
                  ),
                ));
          },
        ));
  }
}
