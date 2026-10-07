# Native test build

Final build-for-testing exit: 0.
Full log: `/tmp/atoll-next-version-fixes/build-for-testing-verified.log`.

```text
    Signing Identity:     "Apple Development: yichen.lin.2004@gmail.com (5AGX9CFNPL)"

    /usr/bin/codesign --force --sign 68E2393709CD7141C4791351A029F486D4E7E60E -o runtime --timestamp\=none --generate-entitlement-der /Users/yichenlin/Desktop/Tester/Atoll/Build/Debug/Atoll.app/Contents/MacOS/Atoll.debug.dylib

CodeSign /Users/yichenlin/Desktop/Tester/Atoll/Build/Debug/Atoll.app/Contents/MacOS/__preview.dylib (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll

    Signing Identity:     "Apple Development: yichen.lin.2004@gmail.com (5AGX9CFNPL)"

    /usr/bin/codesign --force --sign 68E2393709CD7141C4791351A029F486D4E7E60E -o runtime --timestamp\=none --generate-entitlement-der /Users/yichenlin/Desktop/Tester/Atoll/Build/Debug/Atoll.app/Contents/MacOS/__preview.dylib
/Users/yichenlin/Desktop/Tester/Atoll/Build/Debug/Atoll.app/Contents/MacOS/__preview.dylib: replacing existing signature

CodeSign /Users/yichenlin/Desktop/Tester/Atoll/Build/Debug/Atoll.app (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll

    Signing Identity:     "Apple Development: yichen.lin.2004@gmail.com (5AGX9CFNPL)"

    /usr/bin/codesign --force --sign 68E2393709CD7141C4791351A029F486D4E7E60E -o runtime --entitlements /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/DynamicIsland.build/Debug/DynamicIsland.build/Atoll.app.xcent --timestamp\=none --generate-entitlement-der /Users/yichenlin/Desktop/Tester/Atoll/Build/Debug/Atoll.app

Validate /Users/yichenlin/Desktop/Tester/Atoll/Build/Debug/Atoll.app (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll
    builtin-validationUtility /Users/yichenlin/Desktop/Tester/Atoll/Build/Debug/Atoll.app -no-validate-extension -infoplist-subpath Contents/Info.plist

RegisterWithLaunchServices /Users/yichenlin/Desktop/Tester/Atoll/Build/Debug/Atoll.app (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll
    builtin-lsregisterurl --record-path /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/XCBuildData/registered-launchservices.txt -- /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Users/yichenlin/Desktop/Tester/Atoll/Build/Debug/Atoll.app

PruneExplicitPrecompiledModules /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules

PruneExplicitPrecompiledModules /Users/yichenlin/Desktop/Tester/Atoll/Build/SDKExplicitPrecompiledModules

PruneExplicitPrecompiledModules /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/ExplicitPrecompiledModules

** TEST BUILD SUCCEEDED **

```
