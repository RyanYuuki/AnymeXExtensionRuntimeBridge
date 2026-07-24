# Disable all R8 shrinking, optimization, and obfuscation so dynamic extensions never encounter missing classes/methods
-dontobfuscate
-dontoptimize
-dontshrink

-keepattributes *

-keep class ** { *; }
-keep interface ** { *; }
-keepclassmembers class ** { *; }
-keepclassmembernames class ** { *; }
