# ============================================================
#  研修環境 一括セットアップ(Python と VS Code)
#   setup.bat から管理者として実行される
#   インストール済みのツールは自動でスキップする
# ============================================================

# ---------- 設定(資材の名前や場所が変わったらここを直す) ----------
$ToolsDir     = $PSScriptRoot                          # インストーラーを置いたフォルダ(このファイルと同じ場所)

$VSCodeExe     = 'VSCodeSetup-x64-*.exe'              # 全ユーザー用(システム)インストーラー
$PythonExe     = 'python-3.*-amd64.exe'

# インストーラーが無いときの自動ダウンロード元(Python 公式 / VS Code 公式)
$DownloadMap = @{
    $PythonExe   = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe'
    $VSCodeExe   = 'https://update.code.visualstudio.com/latest/win32-x64/stable'
}
$MaterialDir = Join-Path $ToolsDir '資材'                   # ダウンロードした資材の保存先
$DownloadDir = $MaterialDir
try {
    New-Item -ItemType Directory -Force -Path $MaterialDir | Out-Null
    $probe = Join-Path $MaterialDir '.write_test'
    Set-Content -LiteralPath $probe -Value 'x' -ErrorAction Stop
    Remove-Item -LiteralPath $probe -Force
} catch {
    # 読み取り専用の場所(サンドボックスなど)のときは一時フォルダに保存する
    $DownloadDir = Join-Path $env:TEMP 'setup_downloads'
}

# ---------- 共通処理 ----------
$ErrorActionPreference = 'Stop'

# ---------- インストール対象のユーザーを調べる ----------
# 別の管理者アカウントのパスワードを入力して実行された場合でも、
# 「実際にログインしているユーザー」の領域(VS Code の拡張機能、ログなど)に設定する
$TargetUser    = $env:USERNAME
$TargetProfile = $env:USERPROFILE
try {
    $cu = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
    if ($cu) {
        $sid = (New-Object Security.Principal.NTAccount($cu)).Translate([Security.Principal.SecurityIdentifier]).Value
        $pp  = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction Stop).ProfileImagePath
        $pp  = [Environment]::ExpandEnvironmentVariables($pp)
        if ($pp -and (Test-Path -LiteralPath $pp)) { $TargetUser = $cu; $TargetProfile = $pp }
    }
} catch { }
$SameProfile  = ($TargetProfile -ieq $env:USERPROFILE)
$TargetDesktop = Join-Path $TargetProfile 'Desktop'
if (-not (Test-Path -LiteralPath $TargetDesktop)) { $TargetDesktop = [Environment]::GetFolderPath('Desktop') }
$PublicDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')   # 全ユーザー共通のデスクトップ
$LogFile = Join-Path $TargetDesktop 'setup_log.txt'
Start-Transcript -Path $LogFile -Append | Out-Null
$Results = [ordered]@{}

function Write-Step($msg) { Write-Host ''; Write-Host "==== $msg ====" -ForegroundColor Cyan }
function Write-Info($msg) { Write-Host "  $msg" }
function Write-Warn($msg) { Write-Host "  [注意] $msg" -ForegroundColor Yellow }

function Get-Download($pattern) {
    $url = $DownloadMap[$pattern]
    if (-not $url) { return $null }
    New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    $name = if ($pattern -eq $VSCodeExe) { 'VSCodeSetup-x64-latest.exe' } else { [IO.Path]::GetFileName($url) }
    $dest = Join-Path $DownloadDir $name
    if (Test-Path -LiteralPath $dest) { return $dest }
    Write-Info "ダウンロード中: $name(ファイルが大きいと数分〜十数分かかります)"
    $tmp = $dest + '.part'
    try {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if ($curl) {
            & $curl.Source -L -f --retry 3 -o $tmp $url
            if ($LASTEXITCODE -ne 0) { throw "curl 終了コード $LASTEXITCODE" }
        } else {
            Start-BitsTransfer -Source $url -Destination $tmp
        }
        Move-Item -LiteralPath $tmp -Destination $dest -Force
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw "ダウンロードに失敗しました: $url ($($_.Exception.Message))"
    }
    return $dest
}

function Find-Installer($pattern) {
    $f = $ToolsDir, $MaterialDir, $DownloadDir | Select-Object -Unique | Where-Object { Test-Path -LiteralPath $_ } |
         ForEach-Object { Get-ChildItem -LiteralPath $_ -Filter $pattern -File -ErrorAction SilentlyContinue } |
         Sort-Object Name -Descending | Select-Object -First 1
    if ($f) { return $f.FullName }
    $dl = Get-Download $pattern
    if ($dl) { return $dl }
    throw "インストーラーが見つかりません: $pattern($ToolsDir)"
}

function Invoke-Installer($file, $arguments) {
    Write-Info "実行中: $(Split-Path $file -Leaf)(数分かかることがあります)"
    $p = Start-Process -FilePath $file -ArgumentList $arguments -Wait -PassThru
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw "終了コード $($p.ExitCode)" }
}

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function New-Shortcut($name, $target) {
    $lnk = Join-Path $PublicDesktop "$name.lnk"      # 全ユーザー共通のデスクトップに作る
    $ws = New-Object -ComObject WScript.Shell
    $s = $ws.CreateShortcut($lnk)
    $s.TargetPath = $target
    $s.WorkingDirectory = Split-Path $target
    $s.Save()
}

# フォルダ配下からファイルを探す
# (存在しないフォルダに -Recurse を付けると親フォルダ全体を検索してしまうため、先に存在を確認する)
function Find-File($root, $name) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $null }
    Get-ChildItem -LiteralPath $root -Filter $name -Recurse -Depth 4 -File -ErrorAction SilentlyContinue | Select-Object -First 1
}

function Get-InstalledApp($namePattern) {
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like $namePattern } | Select-Object -First 1
}

# 各ツールを順に処理する。失敗しても次のツールへ進む
function Invoke-Tool($name, [scriptblock]$isInstalled, [scriptblock]$install) {
    Write-Step $name
    try {
        $found = & $isInstalled
        if ($found) {
            Write-Info "インストール済みのためスキップ($found)"
            $Results[$name] = 'スキップ(インストール済み)'
            return $false
        }
        & $install
        $Results[$name] = 'インストール完了'
        return $true
    } catch {
        Write-Host "  [失敗] $_" -ForegroundColor Red
        $Results[$name] = "失敗: $_"
        return $false
    }
}

Write-Host '研修環境のセットアップを開始します。完了までウィンドウを閉じないでください。' -ForegroundColor Green
Write-Info "資材フォルダ: $ToolsDir"
Write-Info "ログ: $LogFile"
Write-Info "対象ユーザー: $TargetUser"


# ダウンロードした資材の「インターネットから取得」の印を外し、実行時の確認画面を出さないようにする
Get-ChildItem -Path $ToolsDir -File -Recurse -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

# ---------- 1. Python ----------
Invoke-Tool 'Python' {
    # 3.12 以上が(全ユーザー版、または対象ユーザーのユーザー版で)入っていればスキップ
    $py = Get-ChildItem 'HKLM:\SOFTWARE\Python\PythonCore', 'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore' -ErrorAction SilentlyContinue |
          Where-Object { $_.PSChildName -match '^3\.(\d+)' -and [int]$Matches[1] -ge 12 } | Select-Object -First 1
    if ($py) { "Python $($py.PSChildName)" }
    else {
        $u = Get-ChildItem (Join-Path $TargetProfile 'AppData\Local\Programs\Python') -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue |
             Where-Object { [int]($_.Name -replace '\D', '') -ge 312 -and (Test-Path (Join-Path $_.FullName 'python.exe')) } | Select-Object -First 1
        if ($u) { "$($u.FullName)(ユーザー版)" }
    }
} {
    $exe = Find-Installer $PythonExe
    Invoke-Installer $exe '/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=1 Include_test=0'
} | Out-Null

# ---------- 2. VS Code ----------
$codeCandidates = "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd",
                  (Join-Path $TargetProfile 'AppData\Local\Programs\Microsoft VS Code\bin\code.cmd')
Invoke-Tool 'VS Code' {
    $c = $codeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($c) { $c }
} {
    $exe = Find-Installer $VSCodeExe
    # 手順書の「追加タスク」をすべて ON にした状態で、全ユーザー版としてインストール
    Invoke-Installer $exe '/VERYSILENT /NORESTART /MERGETASKS=!runcode,desktopicon,addcontextmenufiles,addcontextmenufolders,associatewithfiles,addtopath'
} | Out-Null

# 拡張機能と日本語表示は、VS Code があれば不足分だけ追加する
$code = $codeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($code) {
    Write-Step 'VS Code 拡張機能(Python・日本語化)'
    $ErrorActionPreference = 'Continue'   # code.cmd の警告出力で止まらないように
    try {
        Update-SessionPath
        # 拡張機能は、実際にログインしているユーザーの領域に入れる
        $extArgs = @()
        if (-not $SameProfile) {
            $extDir = Join-Path $TargetProfile '.vscode\extensions'
            New-Item -ItemType Directory -Path $extDir -Force | Out-Null
            $extArgs = @('--extensions-dir', $extDir)
        }
        $installed = & $code @extArgs --list-extensions 2>$null
        foreach ($ext in 'ms-python.python', 'MS-CEINTL.vscode-language-pack-ja') {
            if ($installed -contains $ext) { Write-Info "$ext はインストール済み" }
            else { Write-Info "$ext を追加中"; & $code @extArgs --install-extension $ext --force | Out-Null }
        }
        # 別ユーザーの領域に拡張機能を入れた場合、日本語パックの登録ファイル(languagepacks.json)が
        # そのユーザー側にできず、英語のままになるため、ここで作成する
        if (-not $SameProfile) {
            try {
                $packDir = Get-ChildItem $extDir -Directory -Filter 'ms-ceintl.vscode-language-pack-ja-*' -ErrorAction Stop |
                           Sort-Object Name -Descending | Select-Object -First 1
                if ($packDir) {
                    $pkg = Get-Content (Join-Path $packDir.FullName 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                    $loc = $pkg.contributes.localizations | Where-Object { $_.languageId -eq 'ja' } | Select-Object -First 1
                    $tr = [ordered]@{}
                    foreach ($t in $loc.translations) {
                        $tr[$t.id] = Join-Path $packDir.FullName (($t.path -replace '^\./', '') -replace '/', '\')
                    }
                    $md5 = [Security.Cryptography.MD5]::Create()
                    $hash = ([BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes("ms-ceintl.vscode-language-pack-ja$($pkg.version)"))) -replace '-', '').ToLower()
                    $entry = [ordered]@{
                        hash         = $hash
                        extensions   = @([ordered]@{
                            extensionIdentifier = [ordered]@{ id = 'ms-ceintl.vscode-language-pack-ja'; uuid = '077515fe-1509-49c0-9dcc-5511b41682fc' }
                            version = $pkg.version })
                        translations = $tr
                        label        = $loc.localizedLanguageName
                    }
                    $lpFile = Join-Path $TargetProfile 'AppData\Roaming\Code\languagepacks.json'
                    New-Item -ItemType Directory -Path (Split-Path $lpFile) -Force | Out-Null
                    $all = [ordered]@{}
                    if (Test-Path -LiteralPath $lpFile) {
                        $cur = Get-Content -LiteralPath $lpFile -Raw -Encoding UTF8 | ConvertFrom-Json
                        foreach ($p in $cur.PSObject.Properties) { $all[$p.Name] = $p.Value }
                    }
                    $all['ja'] = $entry
                    [IO.File]::WriteAllText($lpFile, ($all | ConvertTo-Json -Depth 8 -Compress), (New-Object System.Text.UTF8Encoding($false)))
                    Write-Info '日本語パックの登録ファイルを作成しました'
                }
            } catch {
                Write-Warn "日本語パックの登録に失敗しました。VS Code 起動後に Ctrl+Shift+P →「Configure Display Language」→「日本語」を実行してください: $_"
            }
        }
        $argv = Join-Path $TargetProfile '.vscode\argv.json'
        if (-not (Test-Path $argv)) {
            New-Item -ItemType Directory -Path (Split-Path $argv) -Force | Out-Null
            # BOM 付きだと VS Code が読み込めないため、BOM なしの UTF-8 で書く
            [IO.File]::WriteAllText($argv, '{ "locale": "ja" }', (New-Object System.Text.UTF8Encoding($false)))
        } elseif (-not (Select-String -Path $argv -Pattern '"locale"' -Quiet)) {
            Write-Warn '表示言語は VS Code 起動後の「Change Language and Restart」で日本語にしてください'
        }
        $Results['VS Code 拡張機能'] = '確認済み'
    } catch {
        Write-Host "  [失敗] $_  (拡張機能はネット接続が必要です)" -ForegroundColor Red
        $Results['VS Code 拡張機能'] = "失敗: $_"
    }
    $ErrorActionPreference = 'Stop'
}

# ---------- 3. 作業フォルダ(C:\fellowsapp)とデータベース(SQLite) ----------
# 講義で生成した Python アプリは C:\fellowsapp に展開する(OneDrive の同期対象外、ユーザー名に依存しない場所)。
# データベースのファイル myappdb.sqlite3 は、完成済みのもの(商品関連テーブル フォルダ内)をここにコピーする(アプリを上書きしても消えない)。
Write-Step '作業フォルダ(C:\fellowsapp)'
try {
    $WorkDir = 'C:\fellowsapp'
    $DbName  = 'myappdb.sqlite3'
    $DbDest  = Join-Path $WorkDir $DbName
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    if (Test-Path -LiteralPath $DbDest) {
        Write-Info "$DbName は既にあります(上書きしません): $DbDest"
        $Results['作業フォルダ(C:\fellowsapp)'] = 'スキップ(DB は既にあり)'
    } else {
        $src = @(
            (Join-Path $ToolsDir "商品関連テーブル\$DbName"),
            (Join-Path $ToolsDir $DbName)
        ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $src) { throw "$DbName が見つかりません(①環境構築 フォルダの「商品関連テーブル」フォルダごと、ZIP から展開してください)" }
        Copy-Item -LiteralPath $src -Destination $DbDest
        Write-Info "コピーしました: $DbDest"
        $Results['作業フォルダ(C:\fellowsapp)'] = '作成完了(C:\fellowsapp に myappdb.sqlite3 を配置)'
    }
} catch {
    Write-Host "  [失敗] $_" -ForegroundColor Red
    $Results['作業フォルダ(C:\fellowsapp)'] = "失敗: $_"
}
try { New-Shortcut 'fellowsapp' 'C:\fellowsapp' } catch { Write-Warn "デスクトップのショートカットを作れませんでした: $_" }

# ---------- 結果 ----------
Write-Step '結果'
foreach ($k in $Results.Keys) {
    $color = if ($Results[$k] -like '失敗*') { 'Red' } elseif ($Results[$k] -like 'スキップ*') { 'Yellow' } else { 'Green' }
    Write-Host ('  {0,-20} {1}' -f $k, $Results[$k]) -ForegroundColor $color
}
Write-Host ''
Write-Host 'Path の変更を反映するため、開いているコマンドプロンプトや VS Code は一度閉じてから使ってください。' -ForegroundColor Green
Stop-Transcript | Out-Null
