import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:multicom_flutter/packet.dart';
import 'package:multicom_flutter/multicom_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

/// BLE device implementation
class BleDevice extends Device {
  BleDevice({
    required ddata,
    required this.channel,
  }) : super(ddata: ddata);

  final BleChannel channel;

  @override
  Future<void> send(Uint8List data) async {
    // TODO: implement
  }
}

/// BLE comm implementation
class BleChannel extends Channel {
  BleChannel();

  static const serviceUUID = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const charTxUUID  = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
  static const charRxUUID  = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

  final FlutterBluePlus flutterBlue = FlutterBluePlus.instance;

  @override
  Future<void> init() async {
    // Listen to scan results
    var subscription = flutterBlue.scanResults.listen((results) {
        // do something with scan results
        for (ScanResult r in results) {
            log('${r.device.name} found! rssi: ${r.rssi}');
        }
    });
  }

  @override
  Future<void> clearDevices() async {
    // TODO: implement
  }

  @override
  Future<void> startDiscovery({
    required Function()? onDeviceListChanged,
  }) async {
    super.startDiscovery(onDeviceListChanged: onDeviceListChanged);

    if (Platform.isAndroid) {
      await Permission.locationWhenInUse.request();
      await Permission.bluetooth.request();
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
    }

    // Start scanning
    flutterBlue.startScan(timeout: const Duration(seconds: 4));
  }
}