import 'dart:async';
import 'dart:math';
import '../app_state.dart';

class LiveSensorService {
  static int currentBpm = 72;
  static Timer? _streamTimer;

  static void startHardwareStream() {
    _streamTimer?.cancel();
    _streamTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (currentBpm > 60 && currentBpm < 150)
        currentBpm += (Random().nextBool() ? 1 : -1);
      AppState.heartRate.value = currentBpm;
    });
  }

  static void simulateHeartStep() {
    if (currentBpm < 120 && currentBpm > 0)
      currentBpm = 145;
    else if (currentBpm >= 120)
      currentBpm = 0;
    else
      currentBpm = 72;
    AppState.heartRate.value = currentBpm;
  }

  static void simulateNextScenario() {
    int nextIndex =
        (AppState.alertStatus.value.index + 1) % AlertType.values.length;
    AppState.alertStatus.value = AlertType.values[nextIndex];
  }
}
