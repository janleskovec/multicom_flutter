import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:multicom_flutter/multicom_flutter.dart';


class DeviceCard extends StatefulWidget {
  const DeviceCard({Key? key, required this.client, required this.device}) : super(key: key);

  final Client client;
  final Device device;

  @override
  State<DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends State<DeviceCard> {

  Session? session;

  @override
  initState() {
    session = widget.client.open(widget.device.ddata.devId);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
        elevation: 8,
        child: Column(children: [
          Text(widget.device.ddata.devId),
          Row(children: [
            ElevatedButton(
              child: const Text('ping'),
              onPressed: () async {
                if (session == null) return;
                bool res = await session!.ping();
                if (res) {
                  Fluttertoast.showToast(msg: 'pong');
                } else {
                  Fluttertoast.showToast(msg: 'ping failed!');
                }
              },
            ),
          ],)
        ],),
      ),
    );
  }
}
