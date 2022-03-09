library multicom_flutter;

export 'src/udp.dart' show UdpChannel;

import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:multicom_flutter/packet.dart';

/// multicom client wrapper for various backends/clients
class Client {
  Client({
    required this.channels
  });

  final List<Channel> channels;
  final sessions = { };

  /// Initialize all communications channels
  Future<void> init() async {
    List<Future> futures = [];
    for (Channel ch in channels) {
      futures.add(ch.init());
    }

    for (Future f in futures) {
      await f;
    }
  }

  /// Adds a new backend communication channel implementation to the client
  void addChannel({
    required Channel channel
  }) {
    // prevent duplicate channel types
    for (Channel ch in channels) {
      if (channel.runtimeType == ch.runtimeType) return;
    }
    channels.add(channel);
  }

  /// internal callback function (called from a channel implementation when a new packet arrives)
  _onMsg({
    required Channel channel,
    required Uint8List data,
  }) {
    if (data.isEmpty) return null;
    // packet type
    PacketType pcktType = PacketType(data[0]);

    // TODO: implement
  }

  Future<void> sendDiscover() async {

    final futures = <Future>[];

    for (Channel ch in channels) {
      futures.add(ch.startDiscovery(newDevCallback: (_){}));
    }

    for (Future f in futures) {
      await f;
    }
  }

  /// Get a device object from one of the backends
  Device getDevice(String devId){
    // TODO: implement getDevice
    throw UnimplementedError();
  }

  /// Open a new session
  Session open(String devId) {
    // TODO: implement open
    throw UnimplementedError();
  }
}

/// Session class (manages nonce counters and message queues)
class Session {
  Session({
    required this.client,
    required this.devId,
  }) {
    final random = math.Random();
    id = random.nextInt((math.pow(2, 32)-1).toInt());
  }

  final Client client;
  final String devId;

  int nonce = 1;
  int id = 0;

  /// internal callback function (called by the channel implementation)
  void _onMsg({
    required Uint8List data,
  }) {
    // TODO: implement
  }

  // TODO: implement: ping, get, send, post
}


/// Base class to implement for various backends/communicaton channels
abstract class Channel {
  Channel();

  final Map<String, Device> devices = { };

  /// Initialize communications channel
  Future<void> init();

  /// Start the discovery of compatible devices
  Future<void> startDiscovery({
    required Function(DiscoveryData) newDevCallback,
  });

  /// Clears list of devices and closes connections if needed
  Future<void> clearDevices();
}

/// Base class for implementation-specific device objects
abstract class Device {
  Device();

  /// Send data to the device
  Future<void> send(Uint8List data);
}

/// Discovery packet data parser
class DiscoveryData {
  DiscoveryData(Uint8List data) {
    var _decoded = String.fromCharCodes(data, 1).split('\x00');
    log(_decoded.toString());
    fwId = _decoded[0];
    devId = _decoded[1];
    apiVer = int.parse(_decoded[2]);
  }

  late final String fwId;
  late final String devId;
  late final int apiVer;
}
