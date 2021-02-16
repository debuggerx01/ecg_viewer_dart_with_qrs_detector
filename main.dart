import 'dart:io';
import 'qrs_detector.dart';

const SAMPLING_RATE = 250;

/// https://www.zealseeker.com/archives/find-peak/

Future sendData(WebSocket webSocket) {
  QRSDetector detector = QRSDetector(
      signalFrequency: SAMPLING_RATE,
      handleDetection: () {
        webSocket.add("beat");
      });

  var file = File('data.txt');
  return file.readAsLines().then((value) {
    return value.forEach((ele) {
      webSocket.add(ele);
      detector.addPoint(0, double.tryParse(ele));
      sleep(Duration(milliseconds: 1000 ~/ SAMPLING_RATE));
    });
  });
}

main() async {
  HttpServer server = await HttpServer.bind('127.0.0.1', 9988);
  server.transform(new WebSocketTransformer()).listen((WebSocket webSocket) {
    print('WebSocket opened.');
    webSocket.listen(print, onDone: () {
      print('WebSocket closed.');
    });
    sendData(webSocket);
  });
  print('Listening..');
}
