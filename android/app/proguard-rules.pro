# Flutter-specific ProGuard rules

# Keep Flutter wrapper classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep just_audio / audio_service
-keep class com.google.android.exoplayer2.** { *; }

# Keep drift / sqlite3
-keep class org.sqlite.** { *; }

# Keep Dio
-keep class io.flutter.plugins.** { *; }

# Keep flutter_secure_storage (EncryptedSharedPreferences)
-keep class androidx.security.crypto.** { *; }
# The plugin's own classes live in `com.it_nomads.fluttersecurestorage` (verified
# against flutter_secure_storage 9.2.4 in the pub cache: every file under
# android/src/main/java/com/it_nomads/fluttersecurestorage/). This line used to
# read `com.tobsef.**`, which matches no package in this project's dependency
# graph at all — i.e. it kept nothing while the plugin the comment names was
# left unkept. The plugin ships no consumer ProGuard rules, so the keep has to
# live here. Reverting to a non-existent package name silently reintroduces the
# gap, which is exactly the class of mistake that only shows up as a
# release-only crash of the session/credential path.
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Flutter's Android embedding references Play Core split-install classes for
# optional deferred components. This app does not define deferred components,
# so release minification can safely ignore those optional classes.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
