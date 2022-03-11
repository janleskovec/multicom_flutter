import 'dart:io';
import 'dart:typed_data';

import 'package:multicom_flutter/packet.dart';
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

  @override
  Future<void> clearDevices() async {
    for (String devId in devices.keys) {
      devices.remove(devId);
    }
  }

  @override
  Future<void> startDiscovery({
    required Function()? onDeviceListChanged,
  }) async {
    super.startDiscovery(onDeviceListChanged: onDeviceListChanged);

    // send discovery packet 5 times
    for (int i = 0; i < 5; i++) {
      await socket?.send('\x00'.codeUnits, Endpoint.broadcast(port: Port(targetPort)));
      await Future.delayed(const Duration(milliseconds: 250));
    } 
  }
}