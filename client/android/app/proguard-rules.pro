# flutter_local_notifications serialises its persisted state with Gson, which
# reads generic type parameters at runtime. R8 erases those by default, so a
# release build throws
#
#   TypeToken must be created with a type argument
#
# the first time the plugin touches that state — which in practice is when a
# notification button is pressed while the app isn't in the foreground. Debug
# builds never hit it, because R8 doesn't run.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# Gson itself, for the same reason.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
