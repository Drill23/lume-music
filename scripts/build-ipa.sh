#!/bin/bash
# Gera o IPA Release do Lume Music (iPhone) com assinatura ad-hoc e os entitlements EMBUTIDOS no app e na extensão
# do widget (o SideStore só cria o App Group se os entitlements vierem embutidos na assinatura).
# Saída: outputs/<versão>/ios/Lume-Music-<versão>-Claude.ipa
set -euo pipefail
cd "$(dirname "$0")/.."

VER=$(awk '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)
BUILD=$(awk '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' project.yml)
[ -n "$VER" ] && [ -n "$BUILD" ] || { echo "Não achei a versão no project.yml" >&2; exit 1; }

DD=build/ipa
OUT="outputs/$VER/ios"
IPA="$OUT/Lume-Music-$VER-Claude.ipa"

echo "==> Lume Music $VER ($BUILD): gerando projeto"
xcodegen generate -q

echo "==> Compilando Release para iphoneos (sem assinatura do Xcode; a assinatura ad-hoc vem logo depois)"
rm -rf "$DD"
# O Xcode recusa entitlements de App Group sem perfil de provisionamento; por isso compila sem assinar e assina ad-hoc
# aqui mesmo (codesign -s -), embutindo os entitlements. Mesma versão no app e na extensão, vinda do project.yml.
xcodebuild -project LumeMusic.xcodeproj -scheme LumeMusic -configuration Release -sdk iphoneos \
  -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  MARKETING_VERSION="$VER" CURRENT_PROJECT_VERSION="$BUILD" \
  build -quiet

APP="$DD/Build/Products/Release-iphoneos/LumeMusic.app"
APPEX="$APP/PlugIns/LumeWidget.appex"
[ -d "$APP" ] || { echo "App não encontrado em $APP" >&2; exit 1; }
[ -d "$APPEX" ] || { echo "Extensão do widget não encontrada em $APPEX" >&2; exit 1; }

has_group() { codesign -d --entitlements :- "$1" 2>/dev/null | grep -q "group.com.adriano.lumemusic"; }
echo "==> Assinando ad-hoc com entitlements (primeiro a extensão, depois o app)"
codesign -f -s - --entitlements LumeWidget/LumeWidget.entitlements "$APPEX"
codesign -f -s - --entitlements App/LumeMusic.entitlements "$APP"
has_group "$APPEX" || { echo "Entitlements ausentes na extensão" >&2; exit 1; }
has_group "$APP" || { echo "Entitlements ausentes no app" >&2; exit 1; }

echo "==> Empacotando o IPA"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/Payload" "$OUT"
ditto "$APP" "$STAGE/Payload/LumeMusic.app"
rm -f "$IPA"
(cd "$STAGE" && zip -qry "$OLDPWD/$IPA" Payload)

echo "==> Conferindo"
LISTA=$(unzip -l "$IPA")
case "$LISTA" in *"Payload/LumeMusic.app/PlugIns/LumeWidget.appex/"*) ;; *) echo "IPA sem a extensão do widget" >&2; exit 1 ;; esac
for target in "$APP" "$APPEX"; do
  echo "--- $(basename "$target"): $(codesign -d --entitlements :- "$target" 2>/dev/null | grep -A1 application-groups | tr -d '\n\t' | sed 's/<[^>]*>/ /g')"
done
shasum -a 256 "$IPA" | tee "$OUT/SHA256.txt"
echo "Pronto: $IPA"
