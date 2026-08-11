# tools/video-for-roblox.ps1 — сборка ролика под страницу опыта Roblox.
#
# ЗАЧЕМ. У Roblox жёсткие рамки для ролика на витрине, и промах стоит дорого:
# ЗАГРУЗОК ВСЕГО ТРИ В МЕСЯЦ. Поэтому файл собирается и проверяется здесь, а наверх
# уходит только тот, что заведомо проходит.
#
# ТРЕБОВАНИЯ ПЛОЩАДКИ (сверено 2026-08-11 на экране загрузки):
#   формат .mp4 / .mov, СТРОГО 16:9, максимум 1920x1080, максимум 60 секунд,
#   максимум 100 МБ, рекомендуемый битрейт 15 Мбит/с.
#
# ИСПОЛЬЗОВАНИЕ
#   .\tools\video-for-roblox.ps1 -In "D:\rec\raw.mp4" -Out "D:\rec\store.mp4"
#   .\tools\video-for-roblox.ps1 -In raw.mp4 -Out store.mp4 -Segments "0:12-0:15,1:03-1:09"
#
# -Segments — куски исходника через запятую, каждый «начало-конец». Берутся именно в
# том порядке, в каком перечислены: порядок в списке = порядок в ролике. Без параметра
# берётся файл целиком.
#
# ПОЧЕМУ КУСКИ ПЕРЕКОДИРУЮТСЯ ПООТДЕЛЬНОСТИ, А НЕ РЕЖУТСЯ БЕЗ ПЕРЕКОДА. Склейка без
# перекодирования требует, чтобы куски совпадали по параметрам потока до бита, а нарезка
# по произвольным таймкодам ещё и рвётся на опорных кадрах — на стыках получаются рывки
# и рассинхрон звука. Здесь каждый кусок кодируется одинаково, и только потом склеивается
# копированием: стыки чистые.
#
# ЧЁРНЫЕ ПОЛЯ. Если исходник не 16:9, кадр вписывается целиком и добивается чёрным, а не
# обрезается: обрезка молча съела бы HUD по краям, а он в витринном ролике объясняет игру.
# Хочешь заполнить кадр без полей — кадрируй запись заранее.

param(
	[Parameter(Mandatory = $true)][string]$In,
	[Parameter(Mandatory = $true)][string]$Out,
	[string]$Segments = "",
	[int]$BitrateMbps = 15
)

$ErrorActionPreference = "Stop"

# ffmpeg ставился через winget и в PATH появляется только в новой сессии — ищем сами.
function Find-Tool([string]$name) {
	$cmd = Get-Command $name -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	$found = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet" -Filter "$name.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($found) { return $found.FullName }
	throw "$name не найден. Поставить: winget install --id Gyan.FFmpeg"
}
$ff = Find-Tool "ffmpeg"
$probe = Find-Tool "ffprobe"

if (-not (Test-Path $In)) { throw "Нет исходника: $In" }

$work = Join-Path $env:TEMP ("robloxvid_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

# Вписать в 1920x1080 без обрезки, добить чёрным, зафиксировать квадратный пиксель.
$vf = "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black,setsar=1"
# Считаем строки ЗАРАНЕЕ: выражение с конкатенацией прямо внутри массива PowerShell
# разбирает не так, как ожидаешь, и лишний элемент уезжает ffmpeg'у как имя файла.
$brate = "{0}M" -f $BitrateMbps
$bufsize = "{0}M" -f ($BitrateMbps * 2)
$vArgs = @("-c:v", "libx264", "-preset", "medium", "-b:v", $brate, "-maxrate", $brate,
	"-bufsize", $bufsize, "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k")

try {
	if ([string]::IsNullOrWhiteSpace($Segments)) {
		Write-Output "Беру файл целиком."
		& $ff -y -hide_banner -loglevel error -i $In -vf $vf @vArgs -movflags "+faststart" $Out
		if (-not $?) { throw "ffmpeg не смог обработать файл" }
	} else {
		$list = @()
		$i = 0
		foreach ($seg in ($Segments -split ",")) {
			$pair = $seg.Trim() -split "-"
			if ($pair.Count -ne 2) { throw "Кусок '$seg' не в виде начало-конец" }
			$i++
			$part = Join-Path $work ("part{0:D3}.mp4" -f $i)
			Write-Output ("Кусок {0}: {1} -> {2}" -f $i, $pair[0].Trim(), $pair[1].Trim())
			& $ff -y -hide_banner -loglevel error -ss $pair[0].Trim() -to $pair[1].Trim() -i $In -vf $vf @vArgs $part
			if (-not $?) { throw "Не вышло вырезать кусок $seg" }
			$list += "file '" + $part.Replace("\", "/") + "'"
		}
		$listFile = Join-Path $work "list.txt"
		[System.IO.File]::WriteAllLines($listFile, $list)
		& $ff -y -hide_banner -loglevel error -f concat -safe 0 -i $listFile -c copy -movflags "+faststart" $Out
		if (-not $?) { throw "Не вышло склеить куски" }
	}

	# --- приёмка по требованиям площадки ---
	$w = [int](& $probe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 $Out)
	$h = [int](& $probe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 $Out)
	$dur = [double](& $probe -v error -show_entries format=duration -of csv=p=0 $Out)
	$mb = [math]::Round((Get-Item $Out).Length / 1MB, 2)
	$ratioOk = [math]::Abs(($w / $h) - (16 / 9)) -lt 0.01

	Write-Output ""
	Write-Output "=== ПРИЁМКА ==="
	Write-Output ("Разрешение : {0}x{1}   {2}" -f $w, $h, $(if ($w -le 1920 -and $h -le 1080) { "OK" } else { "ПРЕВЫШЕНО" }))
	Write-Output ("Соотношение: {0}   {1}" -f $(if ($ratioOk) { "16:9" } else { "НЕ 16:9" }), $(if ($ratioOk) { "OK" } else { "ОТКАЖУТ" }))
	Write-Output ("Длительность: {0:N1} с   {1}" -f $dur, $(if ($dur -le 60) { "OK" } else { "ПРЕВЫШЕНО, режь" }))
	Write-Output ("Размер     : {0} МБ   {1}" -f $mb, $(if ($mb -le 100) { "OK" } else { "ПРЕВЫШЕНО, снижай -BitrateMbps" }))
	Write-Output ("Файл       : " + $Out)

	# Кадры для глазной проверки: пять точек по длине ролика.
	$shots = Join-Path (Split-Path $Out) "frames"
	New-Item -ItemType Directory -Force -Path $shots | Out-Null
	for ($k = 1; $k -le 5; $k++) {
		$t = [math]::Round($dur * $k / 6.0, 2)
		& $ff -y -hide_banner -loglevel error -ss $t -i $Out -frames:v 1 (Join-Path $shots ("shot{0}.png" -f $k))
	}
	Write-Output ("Кадры для проверки: " + $shots)
} finally {
	Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
