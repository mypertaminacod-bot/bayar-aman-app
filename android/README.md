# Android BAYAR AMAN

Dua paket terpisah: `id.bayaraman.user` dan `id.bayaraman.admin`. Keduanya memuat tampilan web yang sama dengan repo tanpa mengubah layout dan terhubung online ke Supabase baru. Halaman, gambar, ikon, CSS dan Supabase JS 2.119.0 dibundel di APK. Origin HTTPS lokal hanya melayani nama berkas yang diizinkan. Akses file/content, HTTP, mixed content, navigasi eksternal dan backup akun dinonaktifkan. Tidak ada native JavaScript bridge, izin kontak, SMS, lokasi, kamera atau penyimpanan.

Build memakai JDK 17+, Android platform 35 dan build-tools 35.0.0 resmi. Tidak memerlukan Gradle/dependensi Android tambahan:

```
ANDROID_HOME=/path/android-sdk \
BAYAR_KEYSTORE=/private/bayar-aman-release.jks \
BAYAR_KEYSTORE_PASSWORD_FILE=/private/password.txt \
python3 android/build.py
```

Simpan kunci penandatanganan dan password di lokasi privat. Jangan commit ke GitHub. Pembaruan APK harus memakai kunci yang sama dan versionCode lebih tinggi. Skrip saat ini menghasilkan versi 1.0.0 (versionCode 1), minimum Android 6.0, target API 35. Dua paket mempunyai penyimpanan sesi yang terpisah. Jangan hapus data aplikasi User setelah menjadi anggota: login tanpa OTP terikat sesi anonim, dan nomor yang sama tidak otomatis mengambil alih akun lama.

Hasil: `android/output/BAYAR_AMAN_User_v1.0.0.apk` dan `BAYAR_AMAN_Admin_v1.0.0.apk`. Internet dan Android System WebView yang diperbarui diperlukan untuk layanan online.

Verifikasi binary: `apksigner verify --verbose` dan `aapt dump badging` untuk kedua APK. Verifikasi UI/alur: `npm run test:all`. Browser terotomasi menguji transport simulasi; pengujian APK pada HP dan Auth/Realtime nyata adalah pemeriksaan terpisah. Jangan menyebutnya lulus sebelum dilakukan.
