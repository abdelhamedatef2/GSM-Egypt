# GSM Egypt (Publish-ready)

## Important
This project now includes an `android/` folder so Codemagic won't fail with "android directory does not exist".

## Build on Codemagic (Recommended)
- Workflow: Flutter
- Build: Android App Bundle (AAB) for Google Play

## Signing (Release)
File: `android/key.properties` currently contains placeholders:
- storePassword=CHANGE_ME
- keyPassword=CHANGE_ME
- keyAlias=gsm_egypt
- storeFile=../keystore/release-keystore.jks

### Option A (Best): Generate keystore in Codemagic UI
Codemagic has a "Code signing identities" section where you can create/upload a keystore and map it to Gradle.
Then update `android/key.properties` accordingly (Codemagic can set these as environment variables).

### Option B: Generate locally (once)
Run:
`keytool -genkeypair -v -keystore release-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias gsm_egypt`
Put it inside `keystore/` and update passwords in `android/key.properties`.

## Build Command
`flutter pub get`
`flutter build appbundle --release`
