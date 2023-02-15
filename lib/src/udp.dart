import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:multicom_flutter/packet.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:udp/udp.dart';

import 'package:multicom_flutter/multicom_flutter.dart';

/// Udp device implementation
class UdpDevice extends Device {
  UdpDevice({
    required ddata,
    required this.channel,
    required this.addr,
    required this.port,
  }) : super(ddata: ddata);

  final UdpChannel channel;
  final InternetAddress addr;
  final int port;

  @override
  Future<void> send(Uint8List data) async {
    await channel.socket?.send(data, Endpoint.unicast(addr, port: Port(port)));
  }

  @override
  Future<void> remove() async {
    channel.removeDevice(this);
  }
}

/// Udp comm implementation
class UdpChannel extends Channel {
  UdpChannel({
    required this.targetPort,
  });

  final int targetPort;

  final info = NetworkInfo();

  RawDatagramSocket? bSocket;
  UDP? socket;

  StreamSubscription? ssOnMsg;

  @override
  Future<void> init() async {
    close(); // close old socket if exists
    bSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    bSocket!.broadcastEnabled = true;
    ssOnMsg = bSocket!.listen((evt) {
      if (evt == RawSocketEvent.read) {
        if (bSocket == null) return;
        var dat = bSocket!.receive();
        if (dat == null) return;
        _onMsg(dat);
      }
    });

    socket = await UDP.bind(Endpoint.any());
    ssOnMsg = socket!.asStream().listen(_onMsg);
  }

  @override
  close() {
    ssOnMsg?.cancel(); ssOnMsg = null;
    socket?.close(); socket = null;
    bSocket?.close(); bSocket = null;
  }

  _onNewDevice(DiscoveryData ddata, Datagram datagram) {
    for (String devId in devices.keys) {
      if (ddata.devId == devId) {
        return; // device allready found
      }
    }

    devices[ddata.devId] = UdpDevice(
      ddata: ddata,
      channel: this,
      addr: datagram.address,
      port: datagram.port,
    );

    onDeviceListChanged?.call();
  }

  _onMsg(Datagram? dat) {
    if (dat == null) return null;
    if (dat.data.length < 9) return null;

    PacketType packetType = PacketType(dat.data[0]);

    if (packetType == PacketType.discoveryHelo) {
      _onNewDevice(DiscoveryData(dat.data), dat);
    }

    // call callback
    client?.onMsg(
      channel: this,
      data: dat.data,
    );
  }

  removeDevice(UdpDevice dev) {
    if (devices.containsKey(dev.ddata.devId)) {
      devices.remove(dev.ddata.devId);
    }
  }

  @override
  Future<void> clearDevices() async {
    var _devIds = List.from(devices.keys);

    for (String devId in _devIds) {
      devices.remove(devId);
    }

    onDeviceListChanged?.call();

    // refresh socket
    // preventative
    // should help with switching networks
    await init();
  }

  @override
  Future<void> startDiscovery({
    required Function()? onDeviceListChanged,
  }) async {
    super.startDiscovery(onDeviceListChanged: onDeviceListChanged);

    final wifiBroadcast = await info.getWifiBroadcast();

    if (wifiBroadcast == null) {
      log('MultiCom -> cannot find UDP broadcast address');
      return;
    }

    try {
      // send discovery packet 5 times
      for (int i = 0; i < 5; i++) {
        bSocket?.send('\x00'.codeUnits, InternetAddress(wifiBroadcast!), targetPort);
        await Future.delayed(const Duration(milliseconds: 250));
      }
    } catch (e) {
      if (e is OSError) log('OSError: ${e.message}');
      // probs not connected to a local network
      log('MultiCom -> failed broadcasting UDP packet on local network');
    }
  }
}