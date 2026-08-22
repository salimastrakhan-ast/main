# =============================================================================
#  Прописывает адрес сервера в system\l2.ini клиента Lineage 2
#  и проверяет, что сервер с этой машины виден.
#
#  Запускать через setup-client.bat (двойной клик).
#  Адрес и порты подставлены генератором на сервере.
# =============================================================================
param([string]$ClientDir = "")

$ErrorActionPreference = "Stop"

$Addr  = "@ADDR@"
$Login = [int]"@LOGIN_PORT@"
$Game  = [int]"@GAME_PORT@"
# Штамп сборки: без него по пересланному скриншоту не понять, какая версия
# патча у человека на руках, и разговор превращается в гадание.
$Built = "@BUILT@"

function Head($t) { Write-Host ""; Write-Host "==> $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "  ok  $t" -ForegroundColor Green }
function Bad($t)  { Write-Host "  !!  $t" -ForegroundColor Red }
function Warn($t) { Write-Host "  !!  $t" -ForegroundColor Yellow }

# --- Где клиент ---------------------------------------------------------------
# Архив можно распаковать в корень клиента, в папку system или куда угодно:
# ищем l2.ini рядом со скриптом, а если не нашли — спрашиваем путь.
function Find-Ini([string]$base) {
    if (-not $base) { return $null }
    # Путь собираем через Join-Path по кускам, а не строкой с обратными
    # слэшами: так же скрипт можно прогнать тестами под pwsh на Linux.
    foreach ($rel in @("system/l2.ini", "l2.ini", "../system/l2.ini")) {
        $candidate = $base
        foreach ($part in $rel.Split("/")) { $candidate = Join-Path $candidate $part }
        if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return $null
}

Head "клиент Lineage 2"
Write-Host "  патч от $Built, сервер $Addr" -ForegroundColor DarkGray

$ini = Find-Ini $ClientDir
if (-not $ini) { $ini = Find-Ini $PSScriptRoot }

$tries = 0
while (-not $ini -and $tries -lt 3) {
    $tries++
    Write-Host "  Не нашёл system\l2.ini рядом со скриптом."
    $answer = Read-Host "  Укажи папку клиента (там, где лежит system) или пустую строку для выхода"
    if (-not $answer) { break }
    $ini = Find-Ini ($answer.Trim('"').TrimEnd('\'))
    if (-not $ini) { Bad "в '$answer' клиента нет" }
}

if (-not $ini) {
    Bad "клиент не найден — адрес не прописан."
    Write-Host "     Распакуй архив в папку клиента (рядом с system) и запусти ещё раз."
    exit 1
}

$systemDir = Split-Path -Parent $ini
Ok "нашёл $ini"

# --- Кодировка l2.ini ---------------------------------------------------------
# Определяем, а не назначаем: файл бывает однобайтовым, UTF-8 и UTF-16, причём
# UTF-16 часто без BOM. Прочитать UTF-16 как ANSI и записать обратно значит
# перемолоть конфиг в мусор — клиент после такого не стартует вообще.
function Read-Ini([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return @{ Text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
                  Enc  = New-Object System.Text.UnicodeEncoding($false, $true) }
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return @{ Text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
                  Enc  = New-Object System.Text.UnicodeEncoding($true, $true) }
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return @{ Text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
                  Enc  = New-Object System.Text.UTF8Encoding($true) }
    }

    # BOM нет. UTF-16 выдают нулевые байты на чётных или нечётных позициях:
    # в ASCII-тексте ("ServerAddr=...") половина каждой пары — ноль.
    $probe = [Math]::Min($bytes.Length, 512)
    $zeroOdd = 0; $zeroEven = 0
    for ($i = 0; $i -lt $probe; $i++) {
        if ($bytes[$i] -eq 0) { if ($i % 2) { $zeroOdd++ } else { $zeroEven++ } }
    }
    if ($zeroOdd -gt $probe / 8 -and $zeroEven -eq 0) {
        return @{ Text = [System.Text.Encoding]::Unicode.GetString($bytes)
                  Enc  = New-Object System.Text.UnicodeEncoding($false, $false) }
    }
    if ($zeroEven -gt $probe / 8 -and $zeroOdd -eq 0) {
        return @{ Text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes)
                  Enc  = New-Object System.Text.UnicodeEncoding($true, $false) }
    }

    return @{ Text = [System.Text.Encoding]::Default.GetString($bytes)
              Enc  = [System.Text.Encoding]::Default }
}

# Ранние версии патча читали UTF-16 как однобайтовый текст и дописывали в
# конец секцию [Server] однобайтовыми буквами. Внутри UTF-16 такой хвост —
# однозначная подпись поломки: в честном UTF-16 у ASCII каждый второй байт
# нулевой, а тут подряд идут обычные буквы. Ищем её по сырым байтам, потому
# что после разбора хвост выглядит безобидными иероглифами.
function Find-ForeignTail([byte[]]$bytes, $enc) {
    if (-not ($enc -is [System.Text.UnicodeEncoding])) { return -1 }
    $needle = [System.Text.Encoding]::ASCII.GetBytes("[Server]")
    for ($i = 0; $i -le $bytes.Length - $needle.Length; $i++) {
        $hit = $true
        for ($j = 0; $j -lt $needle.Length; $j++) {
            if ($bytes[$i + $j] -ne $needle[$j]) { $hit = $false; break }
        }
        if ($hit) {
            # Отступаем назад через перевод строки, чтобы не оставить огрызок.
            while ($i -gt 0 -and ($bytes[$i - 1] -eq 13 -or $bytes[$i - 1] -eq 10)) { $i-- }
            return $i
        }
    }
    return -1
}

$backup = "$ini.orig"

$parsed = Read-Ini $ini
$text = $parsed.Text
$enc  = $parsed.Enc

$foreign = Find-ForeignTail ([System.IO.File]::ReadAllBytes($ini)) $enc
$damaged = ($foreign -ge 0 -or $text.Contains([char]0) -or $text.Contains([char]0xFFFD) -or
            ([regex]::Matches($text, '(?im)^[ \t]*\[Server\][ \t]*$').Count -gt 1))

if ($damaged) {
    if (Test-Path -LiteralPath $backup) {
        # Копия снята до всех правок — вернуть её точнее, чем чинить по кускам.
        Copy-Item -LiteralPath $backup -Destination $ini -Force
        $parsed = Read-Ini $ini
        $text = $parsed.Text
        $enc  = $parsed.Enc
        Ok "l2.ini был испорчен прошлым патчем — восстановлен из l2.ini.orig"
    } elseif ($foreign -ge 0) {
        # Копии нет: отрезаем чужой хвост, остальное в файле не пострадало.
        $bytes = [System.IO.File]::ReadAllBytes($ini)
        [System.IO.File]::WriteAllBytes($ini, $bytes[0..($foreign - 1)])
        $parsed = Read-Ini $ini
        $text = $parsed.Text
        $enc  = $parsed.Enc
        Ok "убран мусор, дописанный прошлым патчем"
    }
}

# Нули в тексте после разбора = это не текст, который мы понимаем.
# Лучше честно отказаться, чем испортить рабочий клиент.
if ($text.Contains([char]0)) {
    Bad "не понял кодировку l2.ini — не трогаю файл."
    Write-Host "     Открой system\l2.ini в Блокноте и впиши сам:"
    Write-Host "     [Server]"
    Write-Host "     ServerAddr=$Addr"
    # Первые байты однозначно называют кодировку. Пусть человек их пришлёт:
    # по ним видно, что за файл, вместо переписки вслепую.
    $head = [System.IO.File]::ReadAllBytes($ini) | Select-Object -First 16
    Write-Host ""
    Write-Host "     Пришли эту строку тому, кто собирал патч:"
    Write-Host ("     байты: " + (($head | ForEach-Object { $_.ToString("x2") }) -join " "))
    Write-Host "     версия патча: $Built"
    exit 1
}

if (-not (Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $ini -Destination $backup
    Ok "старый l2.ini сохранён как l2.ini.orig"
}

$before = $text
if ($text -match '(?m)^[ \t]*ServerAddr[ \t]*=') {
    # [^\r\n]* специально: конец строки не трогаем, чтобы CRLF файла выжил.
    $text = $text -replace '(?m)^[ \t]*ServerAddr[ \t]*=[^\r\n]*', "ServerAddr=$Addr"
} elseif ($text -match '(?im)^[ \t]*\[Server\][ \t]*\r?$') {
    $text = $text -replace '(?im)^([ \t]*\[Server\][ \t]*)(\r?\n)', "`$1`$2ServerAddr=$Addr`$2"
} else {
    $text = $text.TrimEnd() + "`r`n[Server]`r`nServerAddr=$Addr`r`n"
}

if ($text -notmatch [regex]::Escape("ServerAddr=$Addr")) {
    Bad "не смог прописать адрес в l2.ini — впиши руками:"
    Write-Host "     [Server]"
    Write-Host "     ServerAddr=$Addr"
    exit 1
}

if ($text -ne $before) {
    [System.IO.File]::WriteAllText($ini, $text, $enc)
    Ok "адрес сервера прописан: $Addr"
} else {
    Ok "адрес уже был правильный: $Addr"
}

# --- Видим ли сервер ----------------------------------------------------------
# Проверяем оба порта: логин пускает в список серверов, игровой — в мир.
# Открыт только логин — классическое вечное "Connecting..." при входе.
function Test-Port([string]$host_, [int]$port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($host_, $port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(3000)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch { return $false } finally { $client.Close() }
}

# Открытый порт ещё не значит живой L2: в него может смотреть что угодно.
# Логин-сервер здоровается первым — шлёт пакет Init сразу после соединения.
# Молчание в ответ отличает "сервер не тот" от "сервер не отвечает".
function Test-L2Login([string]$host_, [int]$port) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($host_, $port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(3000)) { return $false }
        $client.EndConnect($async)

        $stream = $client.GetStream()
        $stream.ReadTimeout = 5000
        $head = New-Object byte[] 2
        if ($stream.Read($head, 0, 2) -lt 2) { return $false }
        # Первые два байта — длина пакета вместе с ними. У Init она заметно
        # больше пустого ответа, но в разумных пределах.
        $size = [BitConverter]::ToUInt16($head, 0)
        return ($size -gt 20 -and $size -lt 4096)
    } catch { return $false } finally { $client.Close() }
}

Head "связь с сервером $Addr"

$loginOk = Test-Port $Addr $Login
$gameOk  = Test-Port $Addr $Game

if ($loginOk) { Ok "логин-сервер (порт $Login) отвечает" }
else          { Bad "логин-сервер (порт $Login) не отвечает" }

if ($gameOk) { Ok "игровой сервер (порт $Game) отвечает" }
else         { Bad "игровой сервер (порт $Game) не отвечает" }

if ($loginOk) {
    if (Test-L2Login $Addr $Login) {
        Ok "это настоящий логин-сервер L2 (прислал пакет Init)"
    } else {
        Write-Host ""
        Warn "порт $Login открыт, но по-русски L2 оттуда не отвечают."
        Write-Host "     Похоже, на этом адресе слушает не логин-сервер L2."
        Write-Host "     На сервере проверь:  make status"
    }
}

if (-not ($loginOk -and $gameOk)) {
    Write-Host ""
    Warn "адрес прописан, но сервер отсюда не виден. Что проверить:"
    Write-Host "     1. Сервер запущен?  На сервере:  make status"
    Write-Host "     2. Сеть виртуалки — 'сетевой мост' (bridged), а не"
    Write-Host "        'только хост' (host-only): в host-only режиме сервер"
    Write-Host "        отдаст клиенту адрес $Addr, а он оттуда недоступен."
    Write-Host "     3. Файрвол на сервере:  sudo ufw allow $Login/tcp"
    Write-Host "                             sudo ufw allow $Game/tcp"
    Write-Host "     Подробнее — в README.txt рядом с этим файлом."
}

# --- Куда ещё может смотреть клиент -------------------------------------------
# Репаки с чужих серверов держат адрес мимо l2.ini: во втором .ini, в файле
# сборки или в лаунчере, который переписывает l2.ini при каждом запуске.
# Патч тогда отрабатывает честно, а игрок попадает на чужой сервер.
$clientRoot = Split-Path -Parent $systemDir

Head "не уведёт ли клиент на чужой сервер"

# Другие конфиги с адресом. Ищем и ключ ServerAddr, и голый IP: в сборках
# встречается и то, и другое, под разными именами файлов.
$suspects = @()
Get-ChildItem -LiteralPath $clientRoot -Recurse -File -Include *.ini, *.cfg, *.txt, *.xml `
              -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $ini -and $_.Length -lt 1MB } |
    ForEach-Object {
        # Читаем тем же определителем кодировки, что и l2.ini: конфиги сборок
        # тоже бывают в UTF-16, а как ANSI они выглядят текстом без совпадений.
        $body = (Read-Ini $_.FullName).Text
        if (-not $body) { return }
        foreach ($m in [regex]::Matches($body, '(?im)^[ \t]*ServerAddr[ \t]*=[ \t]*(\S+)')) {
            $found = $m.Groups[1].Value
            if ($found -ne $Addr) { $suspects += [pscustomobject]@{ File = $_.FullName; Addr = $found } }
        }
    }

if ($suspects) {
    Warn "адрес сервера прописан ещё и здесь:"
    foreach ($s in $suspects) { Write-Host "     $($s.File)  ->  $($s.Addr)" }
    Write-Host ""
    $fix = Read-Host "  Прописать в них наш адрес тоже? [д/N]"
    if ($fix -match '^[дdyY]') {
        foreach ($s in $suspects | Select-Object -ExpandProperty File -Unique) {
            $p = Read-Ini $s
            if ($p.Text.Contains([char]0)) { Warn "$s — не понял кодировку, пропускаю"; continue }
            if (-not (Test-Path -LiteralPath "$s.orig")) { Copy-Item -LiteralPath $s -Destination "$s.orig" }
            # ${1}, а не $1: иначе "$1" склеится с адресом и превратится
            # в номер несуществующей группы — в файл уедет мусор.
            $new = $p.Text -replace '(?im)^([ \t]*ServerAddr[ \t]*=)[^\r\n]*', "`${1}$Addr"
            [System.IO.File]::WriteAllText($s, $new, $p.Enc)
            Ok "поправлен $s"
        }
    }
} else {
    Ok "других файлов с адресом сервера нет"
}

# Лаунчер сборки — вторая причина попасть не туда: он переписывает l2.ini
# своим адресом при каждом запуске, поэтому запускать надо мимо него.
$launchers = Get-ChildItem -LiteralPath $clientRoot -File -Filter *.exe -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notmatch '^(l2|L2)\.exe$' }
if ($launchers) {
    Write-Host ""
    Warn "в папке клиента есть свои запускалки:"
    foreach ($l in $launchers) { Write-Host "     $($l.Name)" }
    Write-Host "     Через них не запускай: лаунчер сборки может подменить адрес"
    Write-Host "     обратно на свой сервер. Запускай напрямую system\l2.exe."
}

# --- Не висит ли уже клиент ---------------------------------------------------
# L2 не поднимает второй экземпляр: если предыдущий запуск завис в памяти,
# ярлык молча не делает ничего. Симптом пугающий, причина безобидная.
$running = Get-Process -Name l2, L2, engine -ErrorAction SilentlyContinue
if ($running) {
    Write-Host ""
    Warn "клиент уже висит в памяти (процесс l2.exe)."
    Write-Host "     Пока он там, игра по ярлыку не запустится."
    Write-Host "     Сними его в диспетчере задач (Ctrl+Shift+Esc) или перезагрузи Windows."
}

# --- Что дальше ---------------------------------------------------------------
# Игру намеренно не запускаем отсюда: у клиента бывает свой ярлык с
# нужными правами и параметрами, а запуск в обход него оставляет
# зависший процесс, после которого ярлык перестаёт работать.
Head "что дальше"
Write-Host "  1. Запусти игру напрямую: $systemDir\l2.exe"
Write-Host "     Не ярлыком сборки — он может увести на чужой сервер."
Write-Host "  2. Логин и пароль — любые: аккаунт создастся сам при первом входе."
Write-Host "     Запомни их — со второго раза это уже обычный пароль."
Write-Host "  3. Права ГМ выдаются на сервере:  make gm CHAR=ИмяПерсонажа"
