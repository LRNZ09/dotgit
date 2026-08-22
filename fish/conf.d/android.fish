# Android development environment (React Native / Gradle).
# JAVA_HOME: Android Studio's bundled JBR 21 — the proto-managed `java`
# shim resolves to OpenJDK 26, which Gradle 8.x cannot run on.
if test -d $HOME/Library/Android/sdk
    set -gx ANDROID_HOME $HOME/Library/Android/sdk
    fish_add_path --global $ANDROID_HOME/platform-tools $ANDROID_HOME/emulator
end

set -l jbr "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
if test -d $jbr
    set -gx JAVA_HOME $jbr
end
