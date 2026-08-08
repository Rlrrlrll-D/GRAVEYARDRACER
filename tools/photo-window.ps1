# tools/photo-window.ps1 — размер окна Studio под съёмку кадров.
#
# ЗАЧЕМ. Кнопка Studio «View -> Screenshot» сохраняет ровно то, что отрисовал вьюпорт,
# и ленту редактора в снимок НЕ включает. Значит разрешение кадра упирается только в
# размер вьюпорта, а тот тем больше, чем больше окно. Окну при этом НЕ обязательно
# помещаться на экране: часть с лентой и панелями спокойно уезжает за край монитора —
# на содержимое снимка это не влияет, рендерится вьюпорт целиком.
#
# ПРО МАСШТАБ WINDOWS. Roblox пишет файл в ФИЗИЧЕСКИХ пикселях, а Camera.ViewportSize
# рапортует ЛОГИЧЕСКИЕ. На этой машине масштаб 125% (AppliedDPI = 120), поэтому
# логический вьюпорт 1920x1080 даёт на диске 2400x1350 — выше Full HD, и это к лучшему:
# уменьшение такого кадра до 1920x1080 даёт более чёткую картинку, чем рендер сразу
# в 1080.
#
# ИСПОЛЬЗОВАНИЕ
#   .\tools\photo-window.ps1            — съёмочный размер (файл выйдет 2400x1350)
#   .\tools\photo-window.ps1 -Restore   — развернуть окно обратно
#
# ЕСЛИ ЦИФРЫ ПЕРЕСТАЛИ СХОДИТЬСЯ. Запас ниже — не формула, а замер: 487 по ширине и
# 421 по высоте это лента, вкладки и боковые панели В ТОМ СОСТАВЕ, в каком они были
# открыты при подборе. Откроешь/закроешь Explorer, Properties или Output — запас
# поедет. Проверка одной строкой в командной строке Studio:
#     print(workspace.CurrentCamera.ViewportSize)
# Должно быть ровно 1920, 1080. Не сходится — добавь разницу к $ChromeWidth/$ChromeHeight.

param(
	[switch]$Restore,
	[int]$ViewportWidth = 1920,   # ЛОГИЧЕСКИЙ размер вьюпорта, не размер файла
	[int]$ViewportHeight = 1080,
	# Замер сделан В РЕЖИМЕ PLAY с открытой панелью Output — то есть ровно в том
	# состоянии, в котором и снимают кадры. В Edit с закрытым Output запас другой.
	[int]$ChromeWidth = 505,      # окно 2425 при вьюпорте 1920
	[int]$ChromeHeight = 468      # окно 1548 при вьюпорте 1080
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class PhotoWin {
	[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
	[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
	public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$proc = Get-Process | Where-Object { $_.MainWindowTitle -like '*Roblox Studio*' } | Select-Object -First 1
if (-not $proc) {
	Write-Error 'Окно Roblox Studio не найдено.'
	exit 1
}
$hwnd = $proc.MainWindowHandle

if ($Restore) {
	[void][PhotoWin]::ShowWindow($hwnd, 3) # SW_MAXIMIZE
	Write-Output 'Окно Studio развёрнуто обратно.'
	exit 0
}

# ДВА УСЛОВИЯ, И ОБА ОБЯЗАТЕЛЬНЫ — по отдельности размер режется до размеров монитора.
#
# 1) SW_RESTORE. Развёрнутое окно Windows держит ровно в рабочей области (1938x1038 на
#    этой машине), и никакой SetWindowPos его оттуда не выпустит.
# 2) SWP_NOSENDCHANGING (0x400). Без него окно получает WM_WINDOWPOSCHANGING и режет
#    запрошенный размер по ptMaxTrackSize, то есть по границе монитора (1942x1102).
#    С флагом сообщение не посылается и запрошенный размер проходит целиком.
[void][PhotoWin]::ShowWindow($hwnd, 9)
Start-Sleep -Milliseconds 500

$w = $ViewportWidth + $ChromeWidth
$h = $ViewportHeight + $ChromeHeight
# 0x14 = SWP_NOZORDER | SWP_NOACTIVATE (не выдёргиваем окно вперёд), 0x400 = см. выше.
[void][PhotoWin]::SetWindowPos($hwnd, [IntPtr]::Zero, 0, 0, $w, $h, 0x414)
Start-Sleep -Milliseconds 500

$rect = New-Object PhotoWin+RECT
[void][PhotoWin]::GetWindowRect($hwnd, [ref]$rect)
Write-Output ('Окно Studio: {0} x {1}' -f ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top))
Write-Output ('Вьюпорт должен стать {0} x {1}, снимок на диске {2} x {3}.' -f $ViewportWidth, $ViewportHeight, [int]($ViewportWidth * 1.25), [int]($ViewportHeight * 1.25))
Write-Output 'Проверка: print(workspace.CurrentCamera.ViewportSize) в командной строке Studio.'
