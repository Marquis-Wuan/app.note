import pathlib

# 1) Izin dan receiver notifikasi di AndroidManifest
m = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = m.read_text()
perms = '''<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    '''
recv = '''<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
            </intent-filter>
        </receiver>
    '''
s = s.replace('<application', perms + '<application', 1)
s = s.replace('</application>', recv + '</application>', 1)
m.write_text(s)

# 2) Java 17, minSdk 24, dan desugaring (syarat flutter_local_notifications)
g = pathlib.Path('android/app/build.gradle.kts')
t = g.read_text()
t = t.replace('VERSION_11', 'VERSION_17')
t = t.replace('minSdk = flutter.minSdkVersion', 'minSdk = 24')
t = t.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
t += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
g.write_text(t)
