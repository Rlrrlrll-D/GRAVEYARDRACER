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
# Череп и шевроны — ОДНА ГРУППА, и центрируется она целиком (2026-08-11, по замечанию
# юзера). Раньше числа стояли на глаз: сверху оставалось 45 пикселей воздуха, снизу 5, и
# композиция кренилась вниз. Теперь положение считается — задаются только размеры и
# зазор, а сдвиг выводится из настоящих габаритов, поэтому поменяешь размер черепа и
# центровка не поедет.
$SKULL_H = 270.0
$GAP = 16.0          # воздух между зубами и верхним шевроном
$ROW_STEP = 40.0     # расстояние между шевронами
$PEAK = 36.0         # насколько шеврон поднимается к вершине
$PEN_W = 24.0        # толщина шеврона. НЕ называть $PEN: имена в PowerShell
                     # регистронезависимы, и объект пера $pen ниже затирал бы это число.

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

# --- где что лежит -----------------------------------------------------------
# Череп строим пробно в центре холста, чтобы узнать НАСТОЯЩИЕ габариты: контур не
# симметричен относительно своей середины, на глаз их не угадать.
$scale = $SKULL_H / $ASPECT
function Build-Skull([double]$cy) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.FillMode = [System.Drawing.Drawing2D.FillMode]::Alternate
  foreach ($loop in $loops) {
    $arr = New-Object 'System.Drawing.PointF[]' $loop.Count
    for ($i = 0; $i -lt $loop.Count; $i++) {
      $p = $loop[$i]
      $arr[$i] = New-Object System.Drawing.PointF([single](256 + $p.X * $scale), [single]($cy - $p.Y * $scale))
    }
    $path.AddPolygon($arr)
  }
  return $path
}

$probePath = Build-Skull 256.0
$pb = $probePath.GetBounds()
$probePath.Dispose()

# Шевроны считаем от низа черепа. Нижний ряд — самый нижний пиксель группы.
# Каждое значение считаем отдельной строкой: арифметика прямо внутри литерала массива
# в PowerShell разбирается не так, как ожидаешь (запятая связывает крепче, чем плюс).
$rowTop = $pb.Bottom + $GAP + $PEAK + $PEN_W / 2.0   # центр ВЕРХНЕГО ряда
$rowMid = $rowTop + $ROW_STEP
$rowBottom = $rowTop + 2 * $ROW_STEP
$rows = @($rowBottom, $rowMid, $rowTop)            # порядок = по убыванию яркости
$groupTop = $pb.Top                                 # у черепа обводки нет, край = контур
$groupBottom = $rowBottom + $PEN_W / 2.0

# Один сдвиг на всю группу: её середину совмещаем с серединой холста.
$shift = ($SIZE - ($groupBottom - $groupTop)) / 2.0 - $groupTop
Write-Output ("Группа: {0:N0}..{1:N0}, высота {2:N0}, сдвиг {3:N0}, поля сверху/снизу {4:N0}" -f `
  $groupTop, $groupBottom, ($groupBottom - $groupTop), $shift, ($groupTop + $shift))

# --- шевроны ----------------------------------------------------------------
# Рисуем ДО черепа: если зазор всё же съедется, череп ляжет поверх, а не наоборот.
$pen = New-Object System.Drawing.Pen((Hex $ARROW), [single]$PEN_W)
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$alpha = @(255, 145, 65) # нижний ярче: шевроны гаснут кверху, читается как «вперёд»
for ($i = 0; $i -lt 3; $i++) {
  $pen.Color = (ARGB $alpha[$i] $ARROW)
  $y = [single]($rows[$i] + $shift)
  $pts = New-Object 'System.Drawing.PointF[]' 3
  $pts[0] = New-Object System.Drawing.PointF(132, $y)
  $pts[1] = New-Object System.Drawing.PointF(256, [single]($y - $PEAK))
  $pts[2] = New-Object System.Drawing.PointF(380, $y)
  $g.DrawLines($pen, $pts)
}
$pen.Dispose()

# --- череп ------------------------------------------------------------------
# Y инвертируется: в контурах ось вверх, в растре вниз. Глазницы вырезает
# правило чётности (FillMode.Alternate), руками дырки делать не нужно.
$path = Build-Skull (256.0 + $shift)
$sb = New-Object System.Drawing.SolidBrush (Hex $GOLD)
$g.FillPath($sb, $path)

$out = Join-Path $outDir "game_icon.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output ("Готово: " + $out)

# Контроль: зазор между зубами и шевроном плюс поля сверху и снизу — по ним видно,
# что группа действительно по центру, а не «примерно».
$bounds = $path.GetBounds()
$topGap = $bounds.Top
$bottomGap = $SIZE - (($rows[0] + $shift) + $PEN_W / 2.0)
Write-Output ("Зазор зубы/шеврон: {0:N0} px" -f ((($rows[2] + $shift) - $PEAK) - $bounds.Bottom))
Write-Output ("Поле сверху: {0:N0} px, снизу: {1:N0} px — расхождение {2:N0}" -f $topGap, $bottomGap, [math]::Abs($topGap - $bottomGap))

$sb.Dispose(); $path.Dispose(); $g.Dispose(); $bmp.Dispose()
