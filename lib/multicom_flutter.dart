library multicom_flutter;

export 'src/udp.dart' show UdpChannel, UdpDevice;

import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:multicom_flutter/packet.dart';

/// multicom client wrapper for various backends/clients
class Client {
  Client({
    required this.channels,
  });

  final List<Channel> channels;
  final Map<int, Session> sessions = { };
  Function()? onDeviceListChanged;

  /// Initialize all communications channels
  Future<void> init({
    required Function()? onDeviceListChanged,
  }) async {
    this.onDeviceListChanged = onDeviceListChanged;

    List<Future> futures = [];
    for (Channel ch in channels) {
      ch.client = this;
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
    channel.client = this;
    channels.add(channel);
  }

  /// internal callback function (called from a channel implementation when a new packet arrives)
  onMsg({
    required Channel channel,
    required Uint8List data,
  }) {
    if (data.isEmpty) return null;
    //PacketType packetType = PacketType(data[0]);
    int sessionId = data.buffer.asByteData(1, 4).getInt32(0, Endian.big).toUnsigned(32);
    //int nonce      = data.buffer.asByteData(5, 4).getInt32(0, Endian.big).toUnsigned(32);
    //Uint8List msg  = Uint8List.fromList(data.skip(9).toList()); // first 9 bytes are header data

    for (int sid in sessions.keys) {
      if (sessionId == sid) sessions[sid]?.onMsg(data: data);
    }
  }

  Future<void> sendDiscover() async {

    final futures = <Future>[];

    for (Channel ch in channels) {
      futures.add(ch.startDiscovery(onDeviceListChanged: onDeviceListChanged));
    }

    for (Future f in futures) {
      await f;
    }
  }

  /// Get a list of all nareby devices
  List<Device> getDeviceList(){
    Set<String> ids = { };

    List<Device> devices = [];

    for (Channel ch in channels) {
      for (String _devId in ch.devices.keys) {
        if (!ids.contains(_devId)){
          ids.add(_devId);
          Device? dev = ch.devices[_devId];
          if (dev != null) devices.add(dev);
        }
      }
    }

    return devices;
  }

  /// Get a device object from one of the backends
  Device? getDevice(String devId){
    for (Channel ch in channels) {
      for (String _devId in ch.devices.keys) {
        if (_devId == devId) return ch.devices[devId];
      }
    }

    // not found
    return null;
  }

  /// Open a new session
  Session? open(String devId) {
    Device? dev = getDevice(devId);
    if (dev == null) return null;

    Session newSession = Session(
      client: this,
      devId: dev.ddata.devId,
    );

    sessions[newSession.id] = newSession;

    return newSession;
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

  final Map<int, Completer> requestCompleters = {};

  int nonce = 1;
  int id = 0;

  /// internal callback function (called by the channel implementation)
  void onMsg({
    required Uint8List data,
  }) {
    PacketType packetType = PacketType(data[0]);
    //int sessionId = data.buffer.asByteData(1, 4).getInt32(0, Endian.big).toUnsigned(32);
    int nonce      = data.buffer.asByteData(5, 4).getInt32(0, Endian.big).toUnsigned(32);
    Uint8List msg  = Uint8List.fromList(data.skip(9).toList()); // first 9 bytes are header data

    if (packetType == PacketType.ping) {
      if (requestCompleters.containsKey(nonce)) {
        requestCompleters[nonce]?.complete(true);
        requestCompleters.remove(nonce);
      }
    } else if (packetType == PacketType.notFound) {
      // endpoint not found TODO: exception?
    } else if (packetType == PacketType.getReply) {
      //
    } else if (packetType == PacketType.ack) {
      //
    }
  }

  Future<bool> ping() async {
    final random = math.Random();
    int nonce = random.nextInt((math.pow(2, 32)-1).toInt());

    var completer = Completer<bool>();
    requestCompleters[nonce] = completer;

    var nonceData = ByteData(4);
    nonceData.setUint32(0, nonce);

    var idData = ByteData(4);
    idData.setUint32(0, id);

    // NOTE: getter is always used to allow backends to reconnect
    //       or to switch over to a new backend if one fails
    await client.getDevice(devId)?.send(Uint8List.fromList(
      [PacketType.ping.type] +
      idData.buffer.asInt8List() +
      nonceData.buffer.asInt8List()
    ));

    bool res = await completer.future.timeout(const Duration(seconds: 4), onTimeout: () => false);

    // remove completer
    if (requestCompleters.containsKey(nonce)) { requestCompleters.remove(nonce); }

    return res;
  }

  // TODO: implement: get, send, post
}


/// Base class to implement for various backends/communicaton channels
abstract class Channel {
  Channel();

  Client? client;

  final Map<String, Device> devices = { };

  Function()? onDeviceListChanged;

  /// Initialize communications channel
  Future<void> init();

  /// Start the discovery of compatible devices
  /// NOTE: calling cancels previous onDeviceListChanged
  Future<void> startDiscovery({
    required Function()? onDeviceListChanged,
  });

  /// Clears list of devices and closes connections if needed
  Future<void> clearDevices();
}

/// Base class for implementation-specific device objects
abstract class Device {
  Device({
    required this.ddata,
  });

  final DiscoveryData ddata;

  /// Send data to the device
  Future<void> send(Uint8List data);
}

/// Discovery packet data parser
class DiscoveryData {
  DiscoveryData(Uint8List data) {
    var _decoded = String.fromCharCodes(data, 1).split('\x00');
    fwId = _decoded[0];
    devId = _decoded[1];
    apiVer = int.parse(_decoded[2]);
  }

  late final String fwId;
  late final String devId;
  late final int apiVer;
}
