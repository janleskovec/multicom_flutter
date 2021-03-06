library multicom_flutter;

export 'src/udp.dart' show UdpChannel, UdpDevice;
export 'src/ble.dart' show BleChannel, BleDevice;

import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:multicom_flutter/packet.dart';

/// multicom client wrapper for various backends/clients
class Client {
  Client({
    channels,
  }) {
    if (channels != null) {
      this.channels = channels;
    } else {
      this.channels = [];
    }
  }

  late final List<Channel> channels;
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
  addChannel(Channel channel) async {
    // prevent duplicate channel types
    for (Channel ch in channels) {
      if (channel.runtimeType == ch.runtimeType) return;
    }
    channel.client = this;
    channels.add(channel);

    await channel.init();
  }

  /// Remove a channel type
  removeChannel(Type type) async {
    for (Channel ch in channels) {
      if (ch.runtimeType == type) {
        channels.remove(ch);
        await ch.clearDevices();
        ch.close();
      }
    }
  }

  /// internal callback function (called from a channel implementation when a new packet arrives)
  onMsg({
    required Channel channel,
    required Uint8List data,
  }) {
    if (data.isEmpty) return null;

    int sessionId = data.buffer.asByteData(1, 4).getInt32(0, Endian.big).toUnsigned(32);

    for (int sid in sessions.keys) {
      if (sessionId == sid) sessions[sid]?.onMsg(data: data);
    }
  }

  /// Start discovery procedures in each channel
  Future<void> sendDiscover() async {

    final futures = <Future>[];

    for (Channel ch in channels) {
      futures.add(ch.startDiscovery(onDeviceListChanged: onDeviceListChanged));
    }

    for (Future f in futures) {
      await f;
    }
  }

  /// Clear the internal device objects for a complete refresh
  Future<void> clearDevices() async {
    final futures = <Future>[];

    for (Channel ch in channels) {
      futures.add(ch.clearDevices());
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

    this.timeout=const Duration(seconds: 4),
    this.retransmitCount=4,
    this.maxFailedCount=4,
  }) {
    final random = math.Random();
    id = random.nextInt((math.pow(2, 32)-1).toInt());
  }

  final Client client;
  final String devId;

  /// timeout before considering a request failed
  /// actual timeout is shorter if retransmit is used
  final Duration timeout;

  /// number of times a packet wil be re-transmitted before failing
  final int retransmitCount;

  /// max failed packet count before considering a device failed and removing it
  final int maxFailedCount;


  final Map<int, Completer> requestCompleters = {};

  int nonce = 1;
  int id = 0;

  /// internal callback function (called by the channel implementation)
  void onMsg({
    required Uint8List data,
  }) {
    PacketType packetType = PacketType(data[0]);
    int nonce      = data.buffer.asByteData(5, 4).getInt32(0, Endian.big).toUnsigned(32);
    Uint8List msg  = Uint8List.fromList(data.skip(9).toList()); // first 9 bytes are header data

    if (packetType == PacketType.ping) {
      if (requestCompleters.containsKey(nonce)) {
        requestCompleters[nonce]?.complete(true);
        requestCompleters.remove(nonce);
      }
    } else if (packetType == PacketType.notFound) {
      // endpoint not found TODO: exception?
      // complete future with null
      if (requestCompleters.containsKey(nonce)) {
        requestCompleters[nonce]?.complete(null);
        requestCompleters.remove(nonce);
      }
    } else if (packetType == PacketType.getReply) {
      if (requestCompleters.containsKey(nonce)) {
        requestCompleters[nonce]?.complete(msg);
        requestCompleters.remove(nonce);
      }
    } else if (packetType == PacketType.ack) {
      if (requestCompleters.containsKey(nonce)) {
        requestCompleters[nonce]?.complete(true);
        requestCompleters.remove(nonce);
      }
    }
  }

  /// send ping packet
  Future<bool?> ping() async {
    final random = math.Random();
    int _nonce = random.nextInt((math.pow(2, 32)-1).toInt());

    // NOTE: getter is always used to allow backends to reconnect
    //       or to switch over to a new backend if one fails
    Device? device = client.getDevice(devId);
    if (device == null) return null;

    var completer = Completer<bool?>();
    requestCompleters[_nonce] = completer;

    var packet = Uint8List.fromList(
      [PacketType.ping.type] +
      (ByteData(4)..setUint32(0, id   )).buffer.asInt8List() +
      (ByteData(4)..setUint32(0, _nonce)).buffer.asInt8List()
    );

    bool? res;

    for (int i = 0; i < retransmitCount; i++) {
      if (i > 0) log('session.ping retransmit count: $i');

      device = client.getDevice(devId);
      if (device == null) continue;

      await device.send(packet);

      res = await completer.future.timeout(timeout~/retransmitCount, onTimeout: () => null);
      if (res != null) break;
    }

    // remove completer
    if (requestCompleters.containsKey(_nonce)) { requestCompleters.remove(_nonce); }

    if (device == null) return null;

    // failed device removal logic
    if (res == null) {
      device.failedCounter++;
    } else {
      device.failedCounter = 0;
    }

    // device is probbably offline
    if (device.failedCounter > maxFailedCount) device.remove();

    return res;
  }

  /// retreive data from endpoint
  Future<Uint8List?> get(String endpoint, { data='' }) async {
    final random = math.Random();
    int _nonce = random.nextInt((math.pow(2, 32)-1).toInt());

    var completer = Completer<Uint8List?>();
    requestCompleters[_nonce] = completer;

    Device? device;

    var packet = Uint8List.fromList(
      [PacketType.get.type] +
      (ByteData(4)..setUint32(0, id   )).buffer.asInt8List() +
      (ByteData(4)..setUint32(0, _nonce)).buffer.asInt8List() +
      Uint8List.fromList(endpoint.codeUnits) + Uint8List.fromList([0]) +
      Uint8List.fromList(data.codeUnits)
    );

    Uint8List? res;

    for (int i = 0; i < retransmitCount; i++) {
      if (i > 0) log('session.get retransmit count: $i');
      
      device = client.getDevice(devId);
      if (device == null) continue;

      await device.send(packet);

      res = await completer.future.timeout(timeout~/retransmitCount, onTimeout: () => null);
      if (res != null) break;
    }

    // remove completer
    if (requestCompleters.containsKey(_nonce)) { requestCompleters.remove(_nonce); }

    if (device == null) return null;

    // failed device removal logic
    if (res == null) {
      device.failedCounter++;
    } else {
      device.failedCounter = 0;
    }

    // device is probbably offline
    if (device.failedCounter > maxFailedCount) device.remove();

    return res;
  }

  /// send data to endpoint, without expecting an answer
  Future<void> send(String endpoint, { data='' }) async {
    int _nonce = nonce;
    nonce++;

    Device? device = client.getDevice(devId);
    if (device == null) return;

    var packet = Uint8List.fromList(
      [PacketType.send.type] +
      (ByteData(4)..setUint32(0, id   )).buffer.asInt8List() +
      (ByteData(4)..setUint32(0, _nonce)).buffer.asInt8List() +
      Uint8List.fromList(endpoint.codeUnits) + Uint8List.fromList([0]) +
      Uint8List.fromList(data.codeUnits)
    );

    await device.send(packet);
  }

  /// send data to endpoint and wait for ack
  Future<bool?> post(String endpoint, { data='' }) async {

    int _nonce = nonce;
    nonce++;

    var completer = Completer<bool?>();
    requestCompleters[_nonce] = completer;

    Device? device = client.getDevice(devId);
    if (device == null) return null;

    var packet = Uint8List.fromList(
      [PacketType.post.type] +
      (ByteData(4)..setUint32(0, id   )).buffer.asInt8List() +
      (ByteData(4)..setUint32(0, _nonce)).buffer.asInt8List() +
      Uint8List.fromList(endpoint.codeUnits) + Uint8List.fromList([0]) +
      Uint8List.fromList(data.codeUnits)
    );

    bool? res;

    for (int i = 0; i < retransmitCount; i++) {
      if (i > 0) log('session.post retransmit count: $i');

      device = client.getDevice(devId);
      if (device == null) continue;

      await device.send(packet);

      res = await completer.future.timeout(timeout~/retransmitCount, onTimeout: () => null);
      if (res != null) break;
    }

    // remove completer
    if (requestCompleters.containsKey(_nonce)) { requestCompleters.remove(_nonce); }

    if (device == null) return null;

    // failed device removal logic
    if (res == null) {
      device.failedCounter++;
    } else {
      device.failedCounter = 0;
    }

    // device is probbably offline
    if (device.failedCounter > maxFailedCount) device.remove();

    return res;
  }

}


/// Base class to implement for various backends/communicaton channels
abstract class Channel {
  Channel();

  Client? client;

  final Map<String, Device> devices = { };

  Function()? onDeviceListChanged;

  /// Initialize communications channel
  Future<void> init();

  /// Close any open sockets, streams...
  void close();

  /// Start the discovery of compatible devices
  /// NOTE: calling cancels previous onDeviceListChanged
  Future<void> startDiscovery({
    required Function()? onDeviceListChanged,
  }) async {
    // set callback
    this.onDeviceListChanged = onDeviceListChanged;
  }

  /// Clears list of devices and closes connections if needed
  Future<void> clearDevices();
}

/// Base class for implementation-specific device objects
abstract class Device {
  Device({
    required this.ddata,
  });

  final DiscoveryData ddata;

  int failedCounter = 0;

  /// Send data to the device
  Future<void> send(Uint8List data);

  /// Remove device from channel
  Future<void> remove();
}

/// Discovery packet data parser
class DiscoveryData {
  DiscoveryData(Uint8List data) {
    var _decoded = String.fromCharCodes(data, 1).split('\x00');
    
    if (_decoded.length < 3) {fwId = ""; devId = ""; apiVer = 0; return;}
    
    fwId = _decoded[0];
    devId = _decoded[1];
    apiVer = int.parse(_decoded[2]);
  }

  late final String fwId;
  late final String devId;
  late final int apiVer;
}
