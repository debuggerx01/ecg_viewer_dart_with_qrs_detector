import 'dart:collection';
import 'package:iirjdart/butterworth.dart';
import 'package:scidart/numdart.dart';
import 'package:scidart/scidart.dart' hide findPeaks;

const NUMBER_OF_SAMPLES_STORED = 200;

const FILTER_LOW_CUT = 0.001;
const FILTER_HIGH_CUT = 15.0;

const INTEGRATION_WINDOW = 15;
const DETECTION_WINDOW = 40;

const FIND_PEAKS_SPACING = 50;

const REFRACTORY_PERIOD = 120;

const QRS_PEAK_FILTERING_FACTOR = 0.125;
const NOISE_PEAK_FILTERING_FACTOR = 0.125;
const QRS_NOISE_DIFF_WEIGHT = 0.25;

class QRSDetector {
  final int signalFrequency;
  final double findPeaksLimit;
  final Function handleDetection;
  Butterworth butter;

  QRSDetector({
    this.signalFrequency = 250,
    this.findPeaksLimit = 0.04,
    this.handleDetection,
  }) {
    double nyquistFreq = signalFrequency / 2;
    butter = Butterworth();
    butter.lowPass(1, 2, FILTER_LOW_CUT / nyquistFreq);
    butter.highPass(1, 2, FILTER_HIGH_CUT / nyquistFreq);
  }

  Queue<double> _mostRecentMeasurements = Queue();

  void _addToMostRecentMeasurements(double val) {
    _mostRecentMeasurements.add(val);
    if (_mostRecentMeasurements.length > NUMBER_OF_SAMPLES_STORED)
      _mostRecentMeasurements.removeFirst();
  }

  int _lastDetectedTimeStamp = 0;

  void addPoint(int timeStamp, double point) {
    var _start = DateTime.now().microsecondsSinceEpoch;
    _addToMostRecentMeasurements(point);
    var detected = _detectPeaks();
    if (detected) {
      print(DateTime.now().microsecondsSinceEpoch - _start);

      print(
          'Heart beat rate: ${60 * 1000 * 1000 ~/ (timeStamp - _lastDetectedTimeStamp)}/min');
      _lastDetectedTimeStamp = timeStamp;
    }
  }

  bool _detectPeaks() {
    /// Measurements filtering - 0-15 Hz band pass filter.
    List<double> filteredEcgMeasurements = _bandPassFilter();

    /// Derivative - provides QRS slope information.
    /// quaring - intensifies values received in derivative.
    List<double> squaredEcgMeasurements = List.generate(
        filteredEcgMeasurements.length - 1,
        (index) => pow(
              filteredEcgMeasurements[index + 1] -
                  filteredEcgMeasurements[index],
              2,
            ));

    /// Moving-window integration.
    Array integratedEcgMeasurements =
        convolution(Array(squaredEcgMeasurements), ones(INTEGRATION_WINDOW));
    List<int> detectedPeaksIndices = _findPeaks(integratedEcgMeasurements);

    List<double> detectedPeaksValues = List.generate(
        detectedPeaksIndices.length,
        (index) => integratedEcgMeasurements[detectedPeaksIndices[index]]);

    return _detectQrs(detectedPeaksValues);
  }

  List<double> _bandPassFilter() => List.generate(
      _mostRecentMeasurements.length,
      (index) => butter.filter(_mostRecentMeasurements.elementAt(index)));

  List<int> _findPeaks(Array data) {
    int len = data.length;
    List<double> x = List.generate(len + 2 * FIND_PEAKS_SPACING, (index) {
      if (index < FIND_PEAKS_SPACING) return data.first - 1e-6;
      if (index >= len + FIND_PEAKS_SPACING) return data.last - 1e-6;
      return data[index - FIND_PEAKS_SPACING];
    });
    List<bool> peakCandidate = List.filled(len, true);

    List<int> ind = [];
    for (var s = 0; s < FIND_PEAKS_SPACING; s++) {
      var startHb = FIND_PEAKS_SPACING - s - 1;
      var startHc = FIND_PEAKS_SPACING;
      var startHa = FIND_PEAKS_SPACING + s + 1;

      for (var i = 0; i < len; i++) {
        peakCandidate[i] = peakCandidate[i] &&
            (x.elementAt(startHc + i) > x.elementAt(startHb + i)) &&
            (x.elementAt(startHc + i) > x.elementAt(startHa + i));
        if (s == FIND_PEAKS_SPACING - 1 &&
            peakCandidate[i] &&
            data[i] > findPeaksLimit &&
            i >= NUMBER_OF_SAMPLES_STORED - DETECTION_WINDOW) {
          ind.add(i);
        }
      }
    }
    return ind;
  }

  double _qrsPeakValue = 0.0;
  double _noisePeakValue = 0.0;
  int _samplesSinceLastDetectedQrs = 0;
  double _thresholdValue = 0.0;

  bool _detectQrs(List<double> detectedPeaksValues) {
    bool detected = false;
    _samplesSinceLastDetectedQrs += 1;
    if (_samplesSinceLastDetectedQrs > REFRACTORY_PERIOD &&
        detectedPeaksValues.length > 0) {
      if (detectedPeaksValues.last > _thresholdValue) {
        handleDetection?.call();
        detected = true;
        _samplesSinceLastDetectedQrs = 0;
        _qrsPeakValue = QRS_PEAK_FILTERING_FACTOR * detectedPeaksValues.last +
            (1 - QRS_PEAK_FILTERING_FACTOR) * _qrsPeakValue;
      } else {
        _noisePeakValue =
            NOISE_PEAK_FILTERING_FACTOR * detectedPeaksValues.last +
                (1 - NOISE_PEAK_FILTERING_FACTOR) * _noisePeakValue;
      }
      _thresholdValue = _noisePeakValue +
          QRS_NOISE_DIFF_WEIGHT * (_qrsPeakValue - _noisePeakValue);
    }
    return detected;
  }
}
