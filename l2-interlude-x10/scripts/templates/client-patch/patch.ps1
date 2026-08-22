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

# --- Правим ServerAddr --------------------------------------------------------
# Кодировку определяем, а не назначаем: l2.ini бывает и однобайтовым, и
# UTF-16 (официальные сборки). Прочитать UTF-16 как ANSI и записать обратно
# значит перемолоть файл в мусор — клиент после такого не стартует вообще.
$reader = New-Object System.IO.StreamReader($ini, [System.Text.Encoding]::Default, $true)
try {
    $text = $reader.ReadToEnd()
    $enc  = $reader.CurrentEncoding
} finally { $reader.Close() }

# Нулевые байты в тексте = кодировку мы не угадали (UTF-16 без BOM или файл
# вообще не текстовый). Лучше честно отказаться, чем испортить рабочий клиент.
if ($text.Contains([char]0)) {
    Bad "не понял кодировку l2.ini — не трогаю файл."
    Write-Host "     Открой system\l2.ini в Блокноте и впиши сам:"
    Write-Host "     [Server]"
    Write-Host "     ServerAddr=$Addr"
    exit 1
}

$backup = "$ini.orig"
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

Head "связь с сервером $Addr"

$loginOk = Test-Port $Addr $Login
$gameOk  = Test-Port $Addr $Game

if ($loginOk) { Ok "логин-сервер (порт $Login) отвечает" }
else          { Bad "логин-сервер (порт $Login) не отвечает" }

if ($gameOk) { Ok "игровой сервер (порт $Game) отвечает" }
else         { Bad "игровой сервер (порт $Game) не отвечает" }

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
Write-Host "  1. Запусти игру как обычно — своим ярлыком или system\l2.exe."
Write-Host "  2. Логин и пароль — любые: аккаунт создастся сам при первом входе."
Write-Host "     Запомни их — со второго раза это уже обычный пароль."
Write-Host "  3. Права ГМ выдаются на сервере:  make gm CHAR=ИмяПерсонажа"
