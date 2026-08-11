# tools/make-game-icon.ps1 — иконка опыта 512x512.
#
# ЗАЧЕМ ОТДЕЛЬНО ОТ ЗНАЧКОВ. У иконки другая работа. Значок обрезается в КРУГ и стоит
# рядом с названием, которое всё объясняет. Иконка живёт в ленте среди сотен чужих,
# показывается квадратом и должна за долю секунды сказать и «кладбище», и «гонка» —
# одним черепом тут не обойтись, им подписан каждый второй хоррор.
#
# ПОЧЕМУ НЕ КАДР ИЗ ИГРЫ. По той же причине, что и у значков: в ленте иконка мелкая,
# а ночное кладбище в мелком размере превращается в тёмное месиво. Нужен крупный
# силуэт на плоской заливке.
#
# ЧТО НА НЕЙ. Золотой череп из твоего вектора (D:\VECTOR\skull.ai, тот же SkullOutline,
# что кормит чекпоинты и значки) и три неоновых шеврона под ним. Оба цвета ВЗЯТЫ ИЗ
# ИГРЫ, а не подобраны: золото 252,213,62 — цвет черепов-чекпоинтов, зелёный
# 110,255,170 — цвет неоновых стрелок старта (BuildTemplates). Шевроны гаснут кверху,
# читаются как «вперёд» и дают жанр, которого черепу самому не хватает.
#
# ЗАЗОР МЕЖДУ ЗУБАМИ И ШЕВРОНАМИ ВАЖЕН. В первой версии верхний шеврон наезжал на зубы
# и низ картинки мазался. Череп поднят и уменьшен, шевроны опущены, пик уменьшен с 56
# до 42 — между нижним краем зубов (~355) и верхним пиком (~374) остаётся воздух.
# Тронешь SKULL_H или ряды — проверь этот зазор глазами в мелком размере.
#
# ИСПОЛЬЗОВАНИЕ
#   .\tools\make-game-icon.ps1     — перерисовать art\icon\game_icon.png

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$repo = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $repo "art\icon"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# --- контуры черепа ---------------------------------------------------------
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

$SIZE = 512
$ASPECT = 1.139
$SKULL_H = 310.0
$SKULL_CY = 200.0

function Hex([string]$h) { return [System.Drawing.ColorTranslator]::FromHtml($h) }
function ARGB([int]$a, [string]$h) {
  $c = Hex $h
  return [System.Drawing.Color]::FromArgb($a, $c.R, $c.G, $c.B)
}

$MOSS  = "#16211B"   # UITheme.PanelBg  22,33,27
$GOLD  = "#FCD53E"   # SKULL_COLOR     252,213,62
$ARROW = "#6EFFAA"   # стрелки старта  110,255,170

$bmp = New-Object System.Drawing.Bitmap($SIZE, $SIZE)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.Clear((Hex $MOSS))

# --- шевроны ----------------------------------------------------------------
# Рисуем ДО черепа: если зазор всё же съедется, череп ляжет поверх, а не наоборот.
$pen = New-Object System.Drawing.Pen((Hex $ARROW), 26)
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
# 494, а не 500: при толщине пера 26 нижний ряд иначе вылезает за край холста на пиксель.
$rows = @(494, 452, 410)
$alpha = @(255, 145, 65)
$peak = 42
for ($i = 0; $i -lt 3; $i++) {
  $pen.Color = (ARGB $alpha[$i] $ARROW)
  $y = $rows[$i]
  $pts = New-Object 'System.Drawing.Point[]' 3
  $pts[0] = New-Object System.Drawing.Point(132, $y)
  $pts[1] = New-Object System.Drawing.Point(256, ($y - $peak))
  $pts[2] = New-Object System.Drawing.Point(380, $y)
  $g.DrawLines($pen, $pts)
}
$pen.Dispose()

# --- череп ------------------------------------------------------------------
# Y инвертируется: в контурах ось вверх, в растре вниз. Глазницы вырезает
# правило чётности (FillMode.Alternate), руками дырки делать не нужно.
$scale = $SKULL_H / $ASPECT
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.FillMode = [System.Drawing.Drawing2D.FillMode]::Alternate
foreach ($loop in $loops) {
  $arr = New-Object 'System.Drawing.PointF[]' $loop.Count
  for ($i = 0; $i -lt $loop.Count; $i++) {
    $p = $loop[$i]
    $arr[$i] = New-Object System.Drawing.PointF([single](256 + $p.X * $scale), [single]($SKULL_CY - $p.Y * $scale))
  }
  $path.AddPolygon($arr)
}
$sb = New-Object System.Drawing.SolidBrush (Hex $GOLD)
$g.FillPath($sb, $path)

$out = Join-Path $outDir "game_icon.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output ("Готово: " + $out)

# Зазор для проверки: нижний край зубов и верхний пик шеврона.
$bounds = $path.GetBounds()
Write-Output ("Низ черепа: {0:N0}, верхний пик шеврона: {1:N0}, зазор: {2:N0} px" -f $bounds.Bottom, ($rows[2] - $peak), (($rows[2] - $peak) - $bounds.Bottom))

$sb.Dispose(); $path.Dispose(); $g.Dispose(); $bmp.Dispose()
