#!/usr/bin/env python3
"""Build and sign the two APKs using official Android SDK tools and JDK 17+."""
import hashlib, os, pathlib, shutil, subprocess, zipfile
root=pathlib.Path(__file__).resolve().parent.parent
sdk=pathlib.Path(os.environ['ANDROID_HOME'])
tools=sdk/'build-tools'/os.environ.get('BAYAR_BUILD_TOOLS','35.0.0')
jar=sdk/'platforms/android-35/android.jar'
key=pathlib.Path(os.environ['BAYAR_KEYSTORE']).resolve()
password=pathlib.Path(os.environ['BAYAR_KEYSTORE_PASSWORD_FILE']).resolve()
if not key.is_file() or not password.is_file(): raise SystemExit('Signing keystore and password file are required.')
build=root/'android/build';out=root/'android/output'
if build.exists(): shutil.rmtree(build)
build.mkdir();out.mkdir(exist_ok=True)
def run(*args): subprocess.run([str(a) for a in args],check=True)
for flavor in ('user','admin'):
 folder=build/flavor;folder.mkdir();assets=folder/'assets';assets.mkdir()
 for name in (('index.html','user.js') if flavor=='user' else ('admin.html','admin.js'))+('app.css','config.js','icons.svg','route.js'):
  shutil.copyfile(root/name,assets/name)
 (assets/'vendor').mkdir();shutil.copyfile(root/'vendor/supabase.min.js',assets/'vendor/supabase.min.js')
 shutil.copyfile(root/'vendor/SUPABASE_LICENSE.txt',assets/'vendor/SUPABASE_LICENSE.txt')
 label='BAYAR AMAN' if flavor=='user' else 'BAYAR AMAN Admin'
 manifest=folder/'AndroidManifest.xml'
 manifest.write_text(f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="id.bayaraman.{flavor}" android:versionCode="1" android:versionName="1.0.0"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><uses-permission android:name="android.permission.INTERNET"/><application android:label="{label}" android:icon="@drawable/ic_launcher" android:theme="@style/AppTheme" android:allowBackup="false" android:usesCleartextTraffic="false" android:supportsRtl="true"><activity android:name="id.bayaraman.app.MainActivity" android:exported="true" android:configChanges="orientation|screenSize|keyboardHidden" android:windowSoftInputMode="adjustResize"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>''')
 classes=folder/'classes';classes.mkdir();dex=folder/'dex';dex.mkdir()
 compiler = ['java','-jar',os.environ['BAYAR_ECJ_JAR'],'-proc:none','-bootclasspath',str(jar)+os.pathsep+str(tools/'core-lambda-stubs.jar')] if os.environ.get('BAYAR_ECJ_JAR') else ['javac','-classpath',jar]
 run(*compiler,'-encoding','UTF-8','-source','8','-target','8','-d',classes,*sorted((root/'android/src').rglob('*.java')))
 run(tools/'d8','--release','--min-api','23','--lib',jar,'--output',dex,*sorted(classes.rglob('*.class')))
 unsigned=folder/'unsigned.apk'
 run(tools/'aapt','package','-f','-M',manifest,'-S',root/'android/res','-A',assets,'-I',jar,'-F',unsigned)
 with zipfile.ZipFile(unsigned,'a',zipfile.ZIP_DEFLATED) as z: z.write(dex/'classes.dex','classes.dex')
 aligned=folder/'aligned.apk';run(tools/'zipalign','-f','-p','4',unsigned,aligned)
 apk=out/('BAYAR_AMAN_User_v1.0.0.apk' if flavor=='user' else 'BAYAR_AMAN_Admin_v1.0.0.apk')
 run(tools/'apksigner','sign','--ks',key,'--ks-key-alias','bayaraman','--ks-pass','file:'+str(password),'--out',apk,aligned)
 run(tools/'apksigner','verify','--verbose',apk)
 run(tools/'aapt','dump','badging',apk)
 print(hashlib.sha256(apk.read_bytes()).hexdigest(),apk.name)
