import 'dart:async';
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
    required this.device,
    required this.rxc,
    required this.txc,
  }) : super(ddata: ddata) {
    stateSub = device.state.listen(_onStateChanged);
  }

  final BleChannel channel;
  final BluetoothDevice device;
  final BluetoothCharacteristic rxc;
  final BluetoothCharacteristic txc;

  StreamSubscription<BluetoothDeviceState>? stateSub;

  _onStateChanged(BluetoothDeviceState state) {
    if (state == BluetoothDeviceState.disconnected) {
      channel.removeDevice(this);
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    await txc.write(data.toList());
  }

  @override
  Future<void> remove() async {
    channel.removeDevice(this);
  }
}

/// BLE comm implementation
class BleChannel extends Channel {
  BleChannel();

  static const serviceUUID = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const charTxUUID  = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
  static const charRxUUID  = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

  final FlutterBluePlus flutterBlue = FlutterBluePlus.instance;

  StreamSubscription? _scanSub;

  @override
  Future<void> init() async {
    close(); // close old if open

    // Listen to scan results
    _scanSub = flutterBlue.scanResults.listen((results) {
        for (ScanResult r in results) {
          _onBtDeviceFound(r.device);
        }
    });
  }

  @override
  close() {
    flutterBlue.stopScan();
    _scanSub?.cancel();
    _scanSub = null;
  }

  final Set<String> _scannedDevices = { };

  _onBtDeviceFound(BluetoothDevice dev) async {
    log('BleChannel._onBtDeviceFound: ${dev.id} - "${dev.name}"');

    // check if allready found
    if (_scannedDevices.contains(dev.id.id)) return;
    _scannedDevices.add(dev.id.id);

    // util function
    Future<bool> Function() checkIsConnected =  () async => (await flutterBlue.connectedDevices).contains(dev);

    // iOS leaves connections open for some reason, so disconnect first
    if (Platform.isIOS && await checkIsConnected()) {
      await dev.disconnect();
    }

    if (! await checkIsConnected()) {
      await dev.connect();
    }

    // find uart service
    BluetoothService? uartService;

    // TODO: known issue (paired device)
    // https://github.com/pauldemarco/flutter_blue/issues/760
    try {
      List<BluetoothService> services = await dev.discoverServices();
      for (BluetoothService s in services) {
        if (s.uuid == Guid(serviceUUID)) {
          uartService = s;
          break;
        }
      }
    } on Exception {
      log('discovery err for device: ${dev.toString()}');
    }

    log('device: "${dev.name}"');

    log('uartService: ${uartService?.uuid.toString()}');

    if (uartService == null) {
      await dev.disconnect();
      return;
    }

    BluetoothCharacteristic? rxc, txc;
    for (BluetoothCharacteristic c in uartService.characteristics) {
      if (c.uuid == Guid(charRxUUID)) {
        rxc = c;
      } else if (c.uuid == Guid(charTxUUID)) {
        txc = c;
      }
    }

    if (rxc == null || txc == null) {
      await dev.disconnect();
      return;
    }

    int mtu = 512;
    if (Platform.isAndroid) mtu = 512;
    if (Platform.isIOS) mtu = 185;
    // ios does not support setting MTU
    if (!Platform.isIOS) await dev.requestMtu(mtu);
    mtu = await dev.mtu.first;
    log('BT MTU: $mtu');
    // minimum MTU is 64, so that discovery does not fail
    if (mtu < 64) {
      await dev.disconnect();
      return;
    }

    final completer = Completer<List<int>?>();
    await rxc.setNotifyValue(true);
    var sub = rxc.value.listen((value) {
      if (value.isNotEmpty) completer.complete(value);
    });

    await txc.write([0]);

    List<int>? res = await completer.future.timeout(const Duration(seconds: 2), onTimeout: () => null);

    await sub.cancel();

    if (res == null) {
      await dev.disconnect();
      return;
    }

    PacketType packetType = PacketType(res[0]);

    if (packetType != PacketType.discoveryHelo) {
      await dev.disconnect();
      return;
    }

    DiscoveryData ddata = DiscoveryData(Uint8List.fromList(res));

    devices[ddata.devId] = BleDevice(
      ddata: ddata,
      channel: this,
      device: dev,
      rxc: rxc,
      txc: txc,
    );

    // set callback
    rxc.value.listen(_onMsg);

    onDeviceListChanged?.call();
  }

  _onMsg(List<int> data) {
    // header is 9 bytes long
    if (data.length < 9) return null;

    // call callback
    client?.onMsg(
      channel: this,
      data: Uint8List.fromList(data),
    );
  }

  Future<void> removeDevice(BleDevice dev, {callCallback=true}) async {
    if (devices.containsKey(dev.ddata.devId)) devices.remove(dev.ddata.devId);
    if (_scannedDevices.contains(dev.device.id.id)) _scannedDevices.remove(dev.device.id.id);

    await dev.stateSub?.cancel();
    await dev.device.disconnect();

    if (callCallback) onDeviceListChanged?.call();
  }

  @override
  Future<void> clearDevices() async {
    _scannedDevices.clear(); // to allow re-scanning

    var _devIds = List.from(devices.keys);

    List<Future> futures = [];

    for (String devId in _devIds) {
      futures.add(removeDevice(devices[devId] as BleDevice, callCallback: false));
    }

    for (Future f in futures) {
      await f;
    }

    await onDeviceListChanged?.call();

    // re-init
    await init();
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

    // (re)Start scanning
    await flutterBlue.stopScan();
    flutterBlue.startScan(timeout: const Duration(seconds: 8));
  }
}