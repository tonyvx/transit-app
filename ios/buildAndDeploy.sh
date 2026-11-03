cd ios

xcodebuild \
  -project TransitApp.xcodeproj \
  -scheme TransitApp \
  -configuration Debug \
  -destination 'platform=iOS,id=00008140-0006402A3E80801C' \
  -derivedDataPath build \
  build

xcrun devicectl device install app \
  --device 00008140-0006402A3E80801C \
  build/Build/Products/Debug-iphoneos/TransitApp.app