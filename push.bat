@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

set "REPO=https://github.com/enesboz-9/hayat_simulasyonu.git"
set "BRANCH=main"

where git >nul 2>nul
if errorlevel 1 (
  echo [HATA] Git bulunamadi. https://git-scm.com adresinden kurun.
  pause
  exit /b 1
)

if not exist ".git" (
  echo [BILGI] Git deposu olusturuluyor...
  git init
  git branch -M %BRANCH%
)

git remote get-url origin >nul 2>nul
if errorlevel 1 (
  git remote add origin %REPO%
) else (
  git remote set-url origin %REPO%
)

if not exist ".gitignore" (
  echo [BILGI] .gitignore olusturuluyor...
  > .gitignore echo .dart_tool/
  >> .gitignore echo .idea/
  >> .gitignore echo build/
  >> .gitignore echo .flutter-plugins
  >> .gitignore echo .flutter-plugins-dependencies
  >> .gitignore echo .packages
  >> .gitignore echo pubspec.lock
  >> .gitignore echo local.properties
  >> .gitignore echo *.iml
)

rem Commit mesaji: bat dosyasina arguman verilirse o kullanilir, yoksa tarih-saat
set "MSG=%*"
if "%MSG%"=="" set "MSG=Guncelleme %date% %time:~0,5%"

git add -A
git diff --cached --quiet
if errorlevel 1 (
  git commit -m "%MSG%"
  if errorlevel 1 (
    echo [HATA] Commit basarisiz. user.name ve user.email ayarli mi?
    echo   git config --global user.name "Adiniz"
    echo   git config --global user.email "mail@ornek.com"
    pause
    exit /b 1
  )
) else (
  echo [BILGI] Yeni degisiklik yok, mevcut commitler gonderilecek.
)

echo [BILGI] GitHub'a gonderiliyor...
git push -u origin %BRANCH%
if errorlevel 1 (
  echo [BILGI] Push reddedildi, uzak depodaki degisiklikler birlestiriliyor...
  git pull origin %BRANCH% --rebase --allow-unrelated-histories
  if errorlevel 1 (
    echo [HATA] Birlestirme cakismasi var. Cakismalari elle cozup tekrar calistirin.
    pause
    exit /b 1
  )
  git push -u origin %BRANCH%
  if errorlevel 1 (
    echo [HATA] Push basarisiz. GitHub girisinizi ve depo erisiminizi kontrol edin.
    pause
    exit /b 1
  )
)

echo.
echo [TAMAM] Push basarili: %REPO%
pause
endlocal
