/// Тип содержимого по расширению имени.
///
/// Файловый выбор его не сообщает, а сервер по нему решает, картинка это,
/// звук или документ — то есть как клиент нарисует вложение. Ошибиться
/// здесь значит показать фотографию строкой «файл».
///
/// Лежит отдельно от экрана переписки: тем же способом тип определяется при
/// смене фото профиля, а сервер там вообще отказывается принимать вложение
/// без типа картинки.
String mimeByName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'mp3' => 'audio/mpeg',
    'ogg' || 'oga' => 'audio/ogg',
    'm4a' => 'audio/mp4',
    'wav' => 'audio/wav',
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'zip' => 'application/zip',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}
