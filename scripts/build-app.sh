#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

configuration="${1:-debug}"
if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    print -u2 "Usage: scripts/build-app.sh [debug|release] [SwiftPM options]"
    exit 1
fi

swift_options=("${@:2}")
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift -module-cache-path "$PWD/.build/module-cache" scripts/generate-assets.swift "$PWD"
swift build -c "$configuration" "${swift_options[@]}" --cache-path /private/tmp/luma-swift-cache
binary_directory="$(swift build -c "$configuration" "${swift_options[@]}" --show-bin-path --cache-path /private/tmp/luma-swift-cache)"
final_app_path="$PWD/dist/Luma.app"
staging_root="$(mktemp -d "$PWD/dist/.luma-build.XXXXXX")"
trap 'rm -rf "$staging_root"' EXIT
app_path="$staging_root/Luma.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp dist/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
cp "$binary_directory/Luma" "$app_path/Contents/MacOS/Luma"
# SwiftPM locates copied resources beside the executable in an app bundle.
for resource_bundle in "$binary_directory"/*.bundle(N); do
    ditto "$resource_bundle" "$app_path/Contents/Resources/${resource_bundle:t}"
done

cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Luma</string>
  <key>CFBundleIdentifier</key><string>local.luma.reader</string>
  <key>CFBundleName</key><string>Luma</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDisplayName</key><string>Luma</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.9.0</string>
  <key>CFBundleVersion</key><string>16</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Luma contributors</string>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>local.luma.reader.sidebar-item</string>
    <key>UTTypeDescription</key><string>Luma Sidebar Item</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string></array>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Local documents</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>Alternate</string>
    <key>LSItemContentTypes</key><array><string>public.data</string><string>public.folder</string></array>
  </dict></array>
</dict></plist>
PLIST

codesign --force --deep --sign - "$app_path"
# Replace the bundle without overwriting an executable that may still be running.
if [[ -e "$final_app_path" ]]; then
    mv "$final_app_path" "$staging_root/Previous.app"
fi
mv "$app_path" "$final_app_path"
print "Built: $final_app_path"
