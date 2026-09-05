# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-keep class com.google.android.gms.internal.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}
-assumenosideeffects class kotlin.jvm.internal.Intrinsics {
    static void checkParameterIsNotNull(java.lang.Object, java.lang.String);
}

# AndroidX
-keep class androidx.** { *; }
-keep interface androidx.** { *; }
-dontwarn androidx.**

# Bluetooth
-keep class android.bluetooth.** { *; }
-keep class androidx.bluetooth.** { *; }
-dontwarn android.bluetooth.**

# Gson (JSON)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# Keep custom model classes
-keep class com.example.strusa.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
-keepclasseswithmembers class * {
    native <methods>;
}

# Camera & QR Scanner
-keep class androidx.camera.** { *; }
-keep class androidx.camera.core.** { *; }
-keep class androidx.camera.camera2.** { *; }
-keep class com.google.mlkit.** { *; }
-dontwarn androidx.camera.**

# Printer ESC/POS
-keep class com.dantsu.escposprinter.** { *; }
-keep class com.dantsu.thermalprinter.** { *; }

# PDF
-keep class com.itextpdf.** { *; }
-keep class com.tom_roush.pdfbox.** { *; }
-dontwarn com.itextpdf.**

# CSV
-keep class com.opencsv.** { *; }
-keep class au.com.bytecode.opencsv.** { *; }

# File Picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Shared Preferences
-keep class androidx.preference.** { *; }

# Google AI (Gemini)
-keep class com.google.ai.** { *; }
-keep class com.google.generativeai.** { *; }
-dontwarn com.google.ai.**

# Keep Parcelable implementations
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Keep Serializable implementations
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep annotations
-keepattributes *Annotation*
-keep @interface *

# Remove logging
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# Retrofit (if used)
-dontwarn retrofit2.**
-keep class retrofit2.** { *; }
-keepattributes Exceptions

# Crashlytics (if used)
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# General
-keepattributes LineNumberTable,SourceFile
-renamesourcefileattribute SourceFile
-repackageclasses ''
-allowaccessmodification
-optimizations !code/simplification/arithmetic
-keepparameternames