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

const refractoryPeriod = 120;

const QRS_PEAK_FILTERING_FACTOR = 0.125;
const NOISE_PEAK_FILTERING_FACTOR = 0.125;
const QRS_NOISE_DIFF_WEIGHT = 0.25;

class QRSDetector {
  final int signalFrequency;
  final double findPeaksLimit;
  final Function handleDetection;

  QRSDetector({
    this.signalFrequency = 250,
    this.findPeaksLimit = 0.04,
    this.handleDetection,
  });

  DoubleLinkedQueue<double> _mostRecentMeasurements = DoubleLinkedQueue();

  void addToMostRecentMeasurements(double val) {
    _mostRecentMeasurements.add(val);
    if (_mostRecentMeasurements.length > NUMBER_OF_SAMPLES_STORED)
      _mostRecentMeasurements.removeFirst();
  }

  int timeStamp;

  void addPoint(int timeStamp, double point) {
    this.timeStamp = timeStamp;
    addToMostRecentMeasurements(point);
    detectPeaks();
  }

  void detectPeaks() async {
    /// Measurements filtering - 0-15 Hz band pass filter.
    List<double> filteredEcgMeasurements = bandPassFilter();

    /// Derivative - provides QRS slope information.
    List<double> differentiatedEcgMeasurements = List.generate(
        filteredEcgMeasurements.length - 1,
        (index) =>
            filteredEcgMeasurements[index + 1] -
            filteredEcgMeasurements[index]);

    /// quaring - intensifies values received in derivative.
    List<double> squaredEcgMeasurements =
        differentiatedEcgMeasurements.map((data) => data * data).toList();

    /// Moving-window integration.
    Array integratedEcgMeasurements =
        convolution(Array(squaredEcgMeasurements), ones(INTEGRATION_WINDOW));
    List<int> detectedPeaksIndices = findPeaks(integratedEcgMeasurements);

    detectedPeaksIndices.removeWhere(
        (ele) => ele < (NUMBER_OF_SAMPLES_STORED - DETECTION_WINDOW));

    List<double> detectedPeaksValues = List.generate(
        detectedPeaksIndices.length,
        (index) => integratedEcgMeasurements[detectedPeaksIndices[index]]);

    detectQrs(detectedPeaksValues);
  }

  List<double> bandPassFilter() {
    double nyquistFreq = signalFrequency / 2;
    Butterworth butter = Butterworth();
    butter.lowPass(1, 2, FILTER_LOW_CUT / nyquistFreq);
    butter.highPass(1, 2, FILTER_HIGH_CUT / nyquistFreq);
    return List.generate(_mostRecentMeasurements.length,
        (index) => butter.filter(_mostRecentMeasurements.elementAt(index)));
  }

  List<int> findPeaks(Array data) {
    int len = data.length;
    List<double> x = List.generate(len + 2 * FIND_PEAKS_SPACING, (index) {
      if (index < FIND_PEAKS_SPACING) return data.first - 1e-6;
      if (index >= len + FIND_PEAKS_SPACING) return data.last - 1e-6;
      return data[index - FIND_PEAKS_SPACING];
    });
    List<bool> peakCandidate = List.filled(len, true);

    List<int> ind = [];
    for (var s = 0; s < FIND_PEAKS_SPACING; s++) {
      var start = FIND_PEAKS_SPACING - s - 1;
      var hb = x.getRange(start, start + len);
      start = FIND_PEAKS_SPACING;
      var hc = x.getRange(start, start + len);
      start = FIND_PEAKS_SPACING + s + 1;
      var ha = x.getRange(start, start + len);

      for (var i = 0; i < len; i++) {
        peakCandidate[i] = peakCandidate[i] &&
            (hc.elementAt(i) > hb.elementAt(i)) &&
            (hc.elementAt(i) > ha.elementAt(i));
        if (s == FIND_PEAKS_SPACING - 1 &&
            peakCandidate[i] &&
            data[i] > findPeaksLimit) {
          ind.add(i);
        }
      }
    }
    return ind;
  }

  int detectedQrs = 0;
  double qrsPeakValue = 0.0;
  double noisePeakValue = 0.0;
  int samplesSinceLastDetectedQrs = 0;
  double thresholdValue = 0.0;

  void detectQrs(List<double> detectedPeaksValues) {
    samplesSinceLastDetectedQrs += 1;
    if (samplesSinceLastDetectedQrs > refractoryPeriod) {
      if (detectedPeaksValues.length > 0) {
        if (detectedPeaksValues.last > thresholdValue) {
          handleDetection?.call();
          samplesSinceLastDetectedQrs = 0;
          detectedQrs = 1;
          qrsPeakValue = QRS_PEAK_FILTERING_FACTOR * detectedPeaksValues.last +
              (1 - QRS_PEAK_FILTERING_FACTOR) * qrsPeakValue;
        } else {
          noisePeakValue =
              NOISE_PEAK_FILTERING_FACTOR * detectedPeaksValues.last +
                  (1 - NOISE_PEAK_FILTERING_FACTOR) * noisePeakValue;
        }
        thresholdValue = noisePeakValue +
            QRS_NOISE_DIFF_WEIGHT * (qrsPeakValue - noisePeakValue);
      }
    }
  }
}
