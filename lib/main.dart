import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:flutter/services.dart'; // we need this for the vibrations
import 'package:sms/sms.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_mqtt/mqtt.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proje',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Düşme tespit sistemi'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  bool _fall = false; //number of recorded falls
  bool _status = false; //detection off
  bool _sleep = false; //detection off
  double _fall_value = 0;
  SmsSender sender = SmsSender();
  String acil_numara = "+905550026195";
  String _message;
  String _address;
  bool isConnected;

  void onMessage(List<MqttReceivedMessage<MqttMessage>> event) {
    final MqttPublishMessage recMess = event[0].payload as MqttPublishMessage;
    final String message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

    setState(() {
      _fall_value = double.parse(message);
    });
    print(_fall_value);
      if (_fall_value == 1.0) {
        //Fall detected
        alarm();
      }
  }


  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
          child: Container(
              child: Column(children: [
        Container(
          height: 50.0,
          child: Text(
            _fall
                ? "Düşme algılandı"
                : _status
                    ? "Sistem Aktif [" + _fall_value.toString() + "]"
                    : "Uyku Modu [" + _fall_value.toString() + "]",
            maxLines: 2,
            style: TextStyle(
                fontStyle: FontStyle.normal,
                fontWeight: FontWeight.bold, // regular weight
                color: _fall
                    ? hexToColor("#f53737")
                    : !_status
                        ? hexToColor("#76BAE2")
                        : hexToColor("#62c57b"),
                fontFamily: 'Poppins',
                fontSize: 25.0),
          ),
        ),
        Container(
          child: SizedBox(
            child: _fall
                ? Image.asset(
                    "assets/images/falling.png",
                    height: 250,
                  )
                : _status
                    ? Image.asset(
                        "assets/images/normal.png",
                        height: 260,
                      )
                    : Image.asset(
                        "assets/images/sleep.png",
                        height: 260,
                      ),
          ),
        ),
      ]))),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if(_status){
            Broker().client.disconnect();
            setState(() {
              _status = false;
            });
          } else {
            Broker().brokerSetup(onMessage);
            setState(() {
              _status = true;
              _fall = false;
            });
          }
          },
        tooltip: _status ? 'Durdur' : 'Aktifleştir',
        child: _status
            ? Icon(Icons.cancel_rounded)
            : Icon(Icons.accessibility_rounded),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void alarm() {
    HapticFeedback.heavyImpact();
    _fall = true;
    _status = false;
    print("fall detected");

    _determinePosition().then((position) async {
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      // this is all you need
      Placemark placeMark  = placemarks[0];
      String name = placeMark.name;
      String subLocality = placeMark.subLocality;
      String locality = placeMark.locality;
      String administrativeArea = placeMark.administrativeArea;
      String postalCode = placeMark.postalCode;
      String country = placeMark.country;
      String street = placeMark.street;
      String subadmin = placeMark.subAdministrativeArea;
      String throughfare = placeMark.thoroughfare;

      String address = "${name}, ${throughfare}, ${street} Mahallesi, ${subadmin}, ${administrativeArea} ${postalCode}, ${country}";

      print(Uri.encodeFull(address));
      SmsMessage message = new SmsMessage(acil_numara,
          "Düşme alarmı acil durumu algılandı!");
      SmsMessage message2 = new SmsMessage(acil_numara,
          "https://www.google.com/maps/search/?api=1&query=" + Uri.encodeQueryComponent(address));
      sender.sendSms(message).then((value) => sender.sendSms(message2));

    });
  }


  /// Determine the current position of the device.
  ///
  /// When the location services are not enabled or permissions
  /// are denied the `Future` will return an error.
  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  /// Construct a color from a hex code string, of the format #RRGGBB.
  Color hexToColor(String code) {
    return new Color(int.parse(code.substring(1, 7), radix: 16) + 0xFF000000);
  }
}
