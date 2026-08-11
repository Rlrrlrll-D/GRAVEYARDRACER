# tools/make-badge-icons.ps1 — иконки значков из вектора черепа.
#
# ЗАЧЕМ. Значки на Creator Dashboard просят картинку, а залить её из моей сессии нельзя
# (upload отвечает 401). Рисуем файлы на диске напрямую через System.Drawing, минуя
# Roblox совсем: ни Studio, ни скриншотов, ни авторизации.
#
# ПОЧЕМУ НЕ СКРИНШОТ ИЗ ИГРЫ. Roblox обрезает значок В КРУГ и показывает мелким. Кадр
# ночного кладбища в круге 150 пикселей превращается в тёмное месиво. Иконкам нужен
# жирный глиф на плоской заливке — тот же язык, что у иконок магазина.
#
# ОТКУДА ФОРМА. ReplicatedStorage/SkullOutline.lua — тот самый вектор из D:\VECTOR\skull.ai,
# которым живут и объёмные черепа-чекпоинты, и глифы в UI (см. SkullBadge). Поэтому
# значки выглядят родными, а не приклеенными со стороны. Три контура: две глазницы и
# силуэт с зубами; глазницы вырезаются правилом чётности (FillMode.Alternate), руками
# дырки делать не нужно.
#
# ЦВЕТА взяты из UITheme.lua и UIController (SKULL_COLOR). Золото 252,213,62 — цвет
# черепов-чекпоинтов, в игре он уже означает «цель достигнута», поэтому им отмечены
# значки за победы.
#
# ИСПОЛЬЗОВАНИЕ
#   .\tools\make-badge-icons.ps1        — перерисовать все четыре в art\badges\
#
# Захочешь поправить вид — правь таблицу $badges ниже: цвет черепа, цвет и толщина
# ободка, число меток по кромке. Метки не украшение: 10 у «Known by the Dead» это
# число побед, 20 у «Hundred Down» — намёк на сотню зомби.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$repo = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repo "art\badges"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# --- разбор контуров --------------------------------------------------------
# Формат в .lua: строки вида {{x,y},{x,y},...}, нормировано (ширина 1, центр в нуле, Y вверх).
$lua = Get-Content (Join-Path $repo "ReplicatedStorage\SkullOutline.lua") -Raw
$loops = @()
foreach ($line in ($lua -split "`n")) {
  if ($line -notmatch '^\s*\{\{') { continue }
  $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
  foreach ($m in [regex]::Matches($line, '\{(-?[0-9.]+),(-?[0-9.]+)\}')) {
    $pts.Add((New-Object System.Drawing.PointF([single]$m.Groups[1].Value, [single]$m.Groups[2].Value)))
  }
  if ($pts.Count -gt 2) { $loops += ,$pts }
}
if ($loops.Count -ne 3) { Write-Error ("Ожидалось 3 контура, разобрано " + $loops.Count) }
Write-Output ("Контуров: " + $loops.Count + ", точек: " + (($loops | ForEach-Object { $_.Count }) -join ", "))

$SIZE = 512
$CX = $SIZE / 2.0
$CY = $SIZE / 2.0
$SKULL_H = 300.0   # высота черепа в пикселях
$ASPECT = 1.139    # отношение сторон рисунка, из габарита контуров
$SCALE = $SKULL_H / $ASPECT

function Hex([string]$h) { return [System.Drawing.ColorTranslator]::FromHtml($h) }

$MOSS = "#16211B"   # UITheme.PanelBg   22,33,27
$BONE = "#E0D6AA"   # Palette.Bone     224,214,170
$GOLD = "#FCD53E"   # SKULL_COLOR      252,213,62
$RED  = "#961E1E"   # Palette.Red      150,30,30

$badges = @(
  @{ file = "first_ride.png";        skull = $BONE; ring = $BONE; ringW = 9;  marks = 0;  markCol = $BONE },
  @{ file = "gravedigger.png";       skull = $GOLD; ring = $GOLD; ringW = 18; marks = 0;  markCol = $GOLD },
  @{ file = "known_by_the_dead.png"; skull = $GOLD; ring = $GOLD; ringW = 10; marks = 10; markCol = $GOLD },
  @{ file = "hundred_down.png";      skull = $BONE; ring = $RED;  ringW = 10; marks = 20; markCol = $RED }
)

foreach ($b in $badges) {
  $bmp = New-Object System.Drawing.Bitmap($SIZE, $SIZE)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.Clear([System.Drawing.Color]::Transparent)

  # Подложка КРУГОМ, а не квадратом: Roblox всё равно обрежет в круг, и так углы не мешают.
  $bg = New-Object System.Drawing.SolidBrush (Hex $MOSS)
  $g.FillEllipse($bg, 0, 0, $SIZE - 1, $SIZE - 1)

  # Ободок. Отступ 14 px держит его внутри круга обрезки с запасом.
  $pen = New-Object System.Drawing.Pen((Hex $b.ring), [single]$b.ringW)
  $inset = 14.0 + $b.ringW / 2.0
  $g.DrawEllipse($pen, $inset, $inset, $SIZE - 1 - 2 * $inset, $SIZE - 1 - 2 * $inset)

  # Метки по кромке.
  if ($b.marks -gt 0) {
    $mb = New-Object System.Drawing.SolidBrush (Hex $b.markCol)
    $r = ($SIZE / 2.0) - $inset - $b.ringW - 12.0
    $dot = 9.0
    for ($i = 0; $i -lt $b.marks; $i++) {
      $a = (-[Math]::PI / 2) + ($i / [double]$b.marks) * 2 * [Math]::PI
      $mx = $CX + [Math]::Cos($a) * $r
      $my = $CY + [Math]::Sin($a) * $r
      $g.FillEllipse($mb, [single]($mx - $dot), [single]($my - $dot), [single]($dot * 2), [single]($dot * 2))
    }
    $mb.Dispose()
  }

  # Череп. Y инвертируется: в контурах ось вверх, в растре вниз.
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.FillMode = [System.Drawing.Drawing2D.FillMode]::Alternate
  foreach ($loop in $loops) {
    $arr = New-Object 'System.Drawing.PointF[]' $loop.Count
    for ($i = 0; $i -lt $loop.Count; $i++) {
      $p = $loop[$i]
      $arr[$i] = New-Object System.Drawing.PointF([single]($CX + $p.X * $SCALE), [single]($CY - $p.Y * $SCALE))
    }
    $path.AddPolygon($arr)
  }
  $sb = New-Object System.Drawing.SolidBrush (Hex $b.skull)
  $g.FillPath($sb, $path)

  $out = Join-Path $outDir $b.file
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  Write-Output ("Готово: " + $out)

  $sb.Dispose(); $path.Dispose(); $pen.Dispose(); $bg.Dispose(); $g.Dispose(); $bmp.Dispose()
}
