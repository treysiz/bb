#!/bin/sh
# Mac-only build helper. Never uploads, provisions an account, or reads credentials.
set -eu
if [ "$(uname -s)" != Darwin ]; then
    echo 'MiniBridge Camera requires macOS with Xcode. No build was performed.' >&2
    exit 2
fi
command -v xcodebuild >/dev/null 2>&1 || { echo 'Install/select Xcode first.' >&2; exit 2; }
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_project="$task_root/ios_app/MiniBridgePassword.xcodeproj"
task_output="$task_root/firmware/build/ios-camera"
task_mode=${1:-simulator}
case "$task_mode" in
    simulator)
        xcodebuild -project "$task_project" -scheme 'MiniBridge Camera' -configuration Debug \
            -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
            -derivedDataPath "$task_output/DerivedData" CODE_SIGNING_ALLOWED=NO build
        ;;
    archive)
        task_team=${2:-}
        task_bundle=${3:-}
        case "$task_team" in ''|*[!A-Z0-9]*) echo 'Provide your Apple Team ID.' >&2; exit 2;; esac
        case "$task_bundle" in ''|*[!A-Za-z0-9.-]*) echo 'Provide your unique app bundle identifier.' >&2; exit 2;; esac
        xcodebuild -project "$task_project" -scheme 'MiniBridge Camera' -configuration Release \
            -destination 'generic/platform=iOS' -archivePath "$task_output/MiniBridge-Camera.xcarchive" \
            DEVELOPMENT_TEAM="$task_team" PRODUCT_BUNDLE_IDENTIFIER="$task_bundle" archive
        echo 'Archive created. Review/sign/distribute in Xcode Organizer; nothing was uploaded.'
        ;;
    device-check)
        xcodebuild -project "$task_project" -scheme 'MiniBridge Camera' -configuration Debug \
            -sdk iphoneos -destination 'generic/platform=iOS' \
            -derivedDataPath "$task_output/DeviceCheck" CODE_SIGNING_ALLOWED=NO build
        echo 'Unsigned device compilation only. This output cannot be installed on an iPhone.'
        ;;
    *) echo 'Usage: sh scripts/build_ios_camera.sh simulator | device-check | archive TEAM_ID UNIQUE_BUNDLE_ID' >&2; exit 2;;
esac
