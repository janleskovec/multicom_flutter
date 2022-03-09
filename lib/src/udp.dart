import 'dart:io';
import 'dart:developer';
import 'dart:typed_data';

import 'package:multicom_flutter/packet.dart';
import 'package:udp/udp.dart';

import 'package:multicom_flutter/multicom_flutter.dart';

/// Udp device implementation
class UdpDevice extends Device {
  UdpDevice({
    required this.channel,
  });

  final UdpChannel channel;
  // TODO: othr

  @override
  Future<void> send(Uint8List data) {
    // TODO: implement send
    throw UnimplementedError();
  }
}

/// Udp comm implementation
class UdpChannel extends Channel {
  UdpChannel({
    required this.targetPort,
  });

  final int targetPort;

  UDP? socket;

  @override
  Future<void> init() async {
    socket = await UDP.bind(Endpoint.any());
    socket!.asStream().listen(_onMsg);
  }

  _onNewDevice(DiscoveryData ddata, Datagram datagram) {
    // TODO: implement
    log(ddata.devId);
  }

  _onMsg(Datagram? dat) {
    if (dat == null) return null;

    PacketType packetType = PacketType(dat.data[0]);

    if (packetType == PacketType.discoveryHelo) {
      _onNewDevice(DiscoveryData(dat.data), dat);
    }
  }

  @override
  Future<void> clearDevices() async {
    for (String devId in devices.keys) {
      devices.remove(devId);
    }
  }

  @override
  Future<void> startDiscovery({
    required Function(DiscoveryData p1) newDevCallback,
  }) async {
    for (int i = 0; i < 5; i++) {
      socket?.send('\x00'.codeUnits, Endpoint.broadcast(port: Port(targetPort)));
      await Future.delayed(const Duration(milliseconds: 250));
    } 
  }
}