import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Адресная книга устройства.
///
/// Именно по ней мессенджер понимает, кто из ваших знакомых уже
/// зарегистрирован. Без этого список контактов пуст, пока кто-то не напишет
/// первым, — и человек справедливо решает, что поиск сломан.
///
/// Наружу уходят номера и имена. Имена — чтобы вернуть их вам же: в списке
/// видно ту подпись, которую вы дали человеку сами, а не ту, что он
/// поставил себе.
abstract final class DeviceContacts {
  /// Спрашивает разрешение и читает книгу.
  ///
  /// Возвращает пары «номер — имя», годные для отправки на сервер. Пустой
  /// список означает либо отказ, либо пустую книгу: различать их здесь
  /// незачем — показывать в обоих случаях нужно одно и то же.
  static Future<List<Map<String, String>>> read() async {
    if (!supported) return const [];
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      return const [];
    }

    final raw = await FlutterContacts.getContacts(
      withProperties: true,
      // Фотографии не нужны: они тяжёлые, а нам нужны только номера.
      withPhoto: false,
    );

    // Один человек часто записан с несколькими номерами, и один и тот же
    // номер попадается в книге дважды — например, из синхронизации с
    // почтой. Отправлять дубли значит гонять лишнее по сети и получать в
    // ответ повторы.
    final byPhone = <String, String>{};
    for (final contact in raw) {
      final name = contact.displayName.trim();
      for (final phone in contact.phones) {
        final digits = _digits(phone.number);
        if (digits.length < 7) continue;
        byPhone.putIfAbsent(digits, () => name);
      }
    }

    return [
      for (final entry in byPhone.entries)
        {'phone': entry.key, 'name': entry.value},
    ];
  }

  /// Только цифры: в книге номера записаны как попало — со скобками,
  /// дефисами, пробелами и плюсом. Сервер приводит их к своему виду сам,
  /// но мусор до него довозить незачем.
  static String _digits(String raw) {
    final buffer = StringBuffer();
    for (final code in raw.codeUnits) {
      if (code >= 0x30 && code <= 0x39) buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  /// Книга есть только на телефоне. В вебе и на настольных системах её нет,
  /// и предлагать её там — обещать то, чего не будет.
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}
