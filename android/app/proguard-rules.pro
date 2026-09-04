-keepattributes *Annotation*,InnerClasses,Signature,EnclosingMethod
-keepattributes SourceFile,LineNumberTable

-keep class com.telepulse.telepulse.MainActivity { *; }

# Flutter embedding references Play Core split-install classes that are
# only present on Play-installed apps — silence R8, not a real dependency.
-dontwarn com.google.android.play.core.**

-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
