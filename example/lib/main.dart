import 'package:example/device_card.dart';
import 'package:flutter/material.dart';
import 'package:multicom_flutter/multicom_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MultiCom example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  final String title = 'MultiCom example';

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  List<Device> devices = [];

  Client client = Client(
    channels: [
    UdpChannel(targetPort: 5021),
  ]);

  @override
  initState() {
    client.init(
      onDeviceListChanged: () {
        setState(() {
          devices = client.getDeviceList();
        });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: ListView.builder(
          itemCount: devices.length,
          itemBuilder: (context, i) => DeviceCard(
            client: client,
            device: devices[i],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          client.sendDiscover();
        },
        tooltip: 'Discover',
        child: const Icon(Icons.search),
      ),
    );
  }
}
