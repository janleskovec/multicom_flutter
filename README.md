# MultiCom Flutter

Client library implementation for [MultiCom](https://github.com/janleskovec/MultiCom)

## Features

- discover nearby compatible devices
- ping
- get
- send
- post

## Getting started

BLE notes: [link](https://pub.dev/packages/flutter_blue_plus)

Android permissions issues: [link](https://github.com/boskokg/flutter_blue_plus/issues/7)

TODO: List prerequisites and provide or point to information on how to
start using the package.

## Usage

Following is some ecample usage of this library. For more detail spin up the [example](/example/)

```dart
// create a new client object with selected backends
Client client = Client(
    channels: [
        UdpChannel(targetPort: 5021),
        BleChannel(),
    ]);

// initiate device discovery
client.sendDiscover();

//... after some devices are found

// obtain a list of discovered devices
devices = client.getDeviceList();

// open a new connection session
session = widget.client.open(devices[0].ddata.devId);

// test ping
Stopwatch stopwatch = Stopwatch()..start();
bool? res = await session.ping();
if (res != null && res) {
    log('pong (${stopwatch.elapsed.inMilliseconds}ms)');
} else {
    log('ping failed!');
}
stopwatch.stop();
```
