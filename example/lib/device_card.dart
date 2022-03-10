import 'dart:typed_data';

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
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: Column(children: [
            Text(widget.device.ddata.devId),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [

              Padding(
                padding: const EdgeInsets.all(4.0),
                child: ElevatedButton(
                  child: const Text('ping'),
                  onPressed: () async {
                    if (session == null) return;
                    Stopwatch stopwatch = Stopwatch()..start();
                    bool? res = await session!.ping();
                    if (res != null && res) {
                      Fluttertoast.showToast(msg: 'pong (${stopwatch.elapsed.inMilliseconds}ms)');
                    } else {
                      Fluttertoast.showToast(msg: 'ping failed!');
                    }
                    stopwatch.stop();
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(4.0),
                child: ElevatedButton(
                  child: const Text('get'),
                  onPressed: () async {
                    if (session == null) return;
                    Uint8List? res = await session!.get('getval');
                    if (res != null) {
                      String response = String.fromCharCodes(res.toList());
                      Fluttertoast.showToast(msg: 'response: "$response"');
                    } else {
                      Fluttertoast.showToast(msg: 'get failed!');
                    }
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(4.0),
                child: ElevatedButton(
                  child: const Text('send 1'),
                  onPressed: () async {
                    if (session == null) return;
                    await session!.send('setval', data: '1');
                    
                    Fluttertoast.showToast(msg: 'sent "1"');
                  },
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(4.0),
                child: ElevatedButton(
                  child: const Text('post 2'),
                  onPressed: () async {
                    if (session == null) return;
                    Stopwatch stopwatch = Stopwatch()..start();
                    bool? res = await session!.post('setval', data: '2');
                    if (res != null && res) {
                      Fluttertoast.showToast(msg: 'posted "2"');
                    } else {
                      Fluttertoast.showToast(msg: 'post failed');
                    }
                    stopwatch.stop();
                  },
                ),
              ),
            ],)
          ],),
        ),
      ),
    );
  }
}
