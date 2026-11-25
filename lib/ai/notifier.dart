import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificações locais (alerta de falha mesmo com o ecrã bloqueado).
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  static Future<void> alert(String title, String body) async {
    await init();
    await _plugin.show(
      1,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails('print_guard', 'Vigilância de impressão',
            channelDescription: 'Alertas quando a IA deteta uma falha',
            importance: Importance.max,
            priority: Priority.high),
        iOS: DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive),
      ),
    );
  }
}
