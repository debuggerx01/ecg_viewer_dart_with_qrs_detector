import 'dart:async';
import 'dart:io';
import 'qrs_detector.dart';

const SAMPLING_RATE = 250;

Future sendData(WebSocket webSocket) {
  QRSDetector detector = QRSDetector(
      signalFrequency: SAMPLING_RATE,
      handleDetection: () {
        webSocket.add("beat");
      });

  var file = File('data.txt');
  var timeStamp = 0;
  var lineIndex = 0;
  return file.readAsLines().then((value) {
    Timer.periodic(Duration(milliseconds: 1000 ~/ SAMPLING_RATE), (timer) {
      if (webSocket.closeCode != null || lineIndex > value.length)
        return timer.cancel();

      webSocket.add(value[lineIndex]);
      timeStamp += 4000;
      detector.addPoint(timeStamp, double.tryParse(value[lineIndex]));
      lineIndex++;
    });
  });
}

main() async {
  HttpServer server = await HttpServer.bind('127.0.0.1', 9988);
  server
      .transform(new WebSocketTransformer())
      .listen((WebSocket webSocket) async {
    print('WebSocket opened.');
    webSocket.listen(print, onDone: () {
      print('WebSocket closed.');
    });
    sendData(webSocket);
  });
  print('Listening..');
}
