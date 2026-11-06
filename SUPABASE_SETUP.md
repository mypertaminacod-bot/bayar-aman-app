# BAYAR AMAN — penyiapan dan verifikasi sebelum merge

Belum siap dinyatakan final. Migrasi dalam PR ini **belum diterapkan ke Supabase**.

## Temuan audit main

Seluruh index.html (termasuk skrip dan gambar tertanam) dan admin.html dibaca. Versi awal memiliki enam screen, aktivasi anggota otomatis setelah 10 detik, pendaftaran dianggap keanggotaan aktif, quota promo diberikan oleh browser, pembaruan Admin tanpa konfirmasi jumlah baris, sesi User/Admin memakai storage yang sama, dan status subscribe Realtime tidak diperiksa. Tidak ada berkas skema/RLS dalam main. HTML hanya berisi publishable key, tidak ditemukan kredensial admin atau secret key.

Perubahan mempertahankan empat halaman, marun/putih dan identitas BAYAR AMAN. User menyimpan HP, nomor pesanan, pilihan pembayaran, dan pengajuan anggota sebagai entri terpisah dengan user_id. Pilihan pembayaran dan pengajuan merujuk id entri pesanan milik sesi yang sama. Tidak ada pencarian lintas pemilik berdasarkan HP/nomor pesanan: nomor HP bukan bukti identitas. Admin harus memverifikasi pemilik melalui proses operasional sebelum mengisi detail. Sesi anonim yang hilang tidak boleh dipulihkan hanya dengan mengetik HP; pemulihan lintas perangkat memerlukan autentikasi terverifikasi tersendiri.

Rute adalah daftar titik berurutan dari Admin, **bukan navigasi jalan atau GPS kurir**. Setiap alamat tetap diberi label sebagai input. Hanya koordinat dengan verified=true dan sumber verifikasi yang ditampilkan sebagai terverifikasi oleh Admin. Titik merah berkedip dengan periode 1 detik, atau diam jika pengguna memilih reduced motion. Status pesanan hanya bersumber dari detail yang diisi Admin; aplikasi tidak membuktikan kebenaran sumber operasional itu.

## Hasil pemeriksaan Supabase read-only, 6 November 2026

- GET /auth/v1/settings berhasil menggunakan publishable key aplikasi: external.anonymous_users=false, disable_signup=false. Anonymous sign-in perlu diaktifkan.
- GET /rest/v1/ dengan publishable key mendapat HTTP 401. Tidak membaca isi user_data. Skema, policy RLS, is_admin(), publikasi Realtime, dan hak Admin di server **belum terverifikasi**. Periksa key/project/API configuration di dashboard; HTTP 401 saja tidak membuktikan penyebabnya.
- Tidak menjalankan migrasi, membuat akun, atau memasukkan data uji ke produksi.

## Urutan penerapan oleh pengelola Supabase

1. Backup data/skema; inspeksi kolom, tipe, primary key/default id, trigger, policy, grant, fungsi RPC, serta publikasi yang sudah ada. Review SQL di supabase/migrations/202611060001_secure_user_data.sql pada staging dahulu. SQL sengaja mengganti semua policy user_data: policy lama yang permissive dapat membuka akses walaupun policy baru aman. Sesuaikan konsumen lain sebelum penerapan. RPC lama yang punya hak luas juga harus diaudit/dicabut secara terpisah.
2. Migrasi mendukung id uuid/integer/bigint/text dengan representasi string untuk RPC. data harus jsonb, user_id uuid, created_at/updated_at timestamptz. Kolom yang tidak cocok menyebabkan rollback, bukan konversi diam-diam. Audit default id untuk tabel lama. Bila memakai sequence/serial, migrasi memberi USAGE hanya pada sequence yang terikat ke kolom id user_data. Record lama tanpa pemilik tetap tersimpan tetapi tidak terlihat oleh User; jangan menghubungkan berdasarkan nomor HP/pesanan. Admin masih dapat melihatnya.
3. Terapkan migrasi ter-review. Migrasi membuat tabel allowlist baru bayar_aman_admins, RLS pemilik, trigger validasi insert, is_admin() SECURITY DEFINER dengan search_path kosong, dan RPC admin_update_order. Tidak ada UPDATE/DELETE langsung dari browser; RPC memeriksa Admin, tipe pesanan, format data/rute, dan updated_at untuk mencegah penimpaan edit bersamaan. Jangan menjalankan ulang migrasi yang sudah tercatat; gunakan migrasi lanjutan bila perlu.
4. Buat akun Admin melalui Supabase Auth dan isi public.bayar_aman_admins(user_id) dengan UUID akun tersebut dari SQL Editor terpercaya. Tidak ada signup/grant Admin dari UI. Audit is_admin() lama dan konsumen lain karena definisinya diganti; akun berbasis metadata lama tidak otomatis mendapat akses.
5. Aktifkan Anonymous Sign-ins di Authentication. Pertimbangkan CAPTCHA dan batas request sesuai trafik; jika diaktifkan, tambahkan pengiriman captchaToken sebelum membuka layanan publik. Pastikan URL dan publishable key menunjuk proyek yang benar dan API menerima key tersebut. Jangan mengganti dengan secret/service role key. Sesi menggunakan storageKey berbeda; sesi lama tidak otomatis digunakan.
6. Pastikan user_data terdaftar dalam supabase_realtime (migrasi menambahkan bila belum ada). Verifikasi publication, websocket, SELECT RLS dan JWT menggunakan proyek staging. Polling 7 detik User / 10 detik Admin adalah fallback, bukan bukti Realtime berhasil.

## Gerbang pengujian staging / end-to-end

- Dua browser terisolasi A/B masing-masing signInAnonymously. A memasukkan empat tahap, Admin melihat nilai persis; B tidak dapat SELECT entri A, termasuk jika mengetahui UUID, HP atau nomor pesanan A. Uji request REST langsung, tidak hanya UI.
- Tanpa sesi, akses tabel ditolak. A tidak dapat UPDATE/DELETE, menyisipkan detail_pesanan/route/kuota/status aktif, menyamar dengan user_id B, merujuk order B, atau memanggil RPC Admin. Uji akun biasa non-anonim dan admin yang haknya dicabut.
- Admin login resmi dan is_admin()=true; akun lain false. Edit detail dan rute untuk pesanan A. User A menerima perubahan lewat WebSocket **tanpa menunggu polling**; User B tidak menerima data. Catat timestamp dan frame/event Realtime. Ulangi dari User ke Admin. Dua Admin mengedit versi yang sama: simpan kedua ditolak dengan konflik.
- Cabut allowlist, expiry JWT, logout, putus jaringan, publikasi dinonaktifkan, key salah, schema tidak cocok, CDN gagal, serta tab di-background harus menghasilkan kegagalan yang terlihat dan tidak menyatakan data tersimpan. Periksa juga cache DOM sesudah logout.
- Verifikasi koordinat dari sumber operasional sah. Uji rute kosong, koordinat 0, titik di luar batas, status dihapus, serta penghapusan data route. Tidak boleh ada posisi/status otomatis.
- Pengajuan anggota tersimpan tanpa klaim aktif atau alokasi kuota. Promo 3 kali gratis ongkir menunggu verifikasi; pembayaran hanya setelah barang tiba dan diperiksa.

## Pemeriksaan lokal

`node --test tests/app.test.cjs` memeriksa sintaks inline, key publik, dan validasi rute. `node tests/browser.cjs` membutuhkan Playwright dan Chromium (`CHROMIUM_PATH` opsional). Browser test memakai server localhost dan **backend simulasi**, tidak membuktikan RLS/Auth/Realtime Supabase. Keduanya telah lulus, termasuk kedua metode pembayaran, kegagalan tulis, konflik edit, XSS pada alamat rute, label koordinat, animasi 1 detik, lebar 320/360/412, penolakan Admin dan pembersihan logout.


Migrasi juga berhasil dijalankan pada PostgreSQL 16 sementara dengan interface auth.uid()/auth.jwt() simulasi. tests/security.sql lulus untuk isolasi dua pemilik, penolakan anon tanpa sesi, pemalsuan pemilik/field Admin, larangan UPDATE/DELETE langsung, RPC Admin, koordinat, konflik edit, dan pencabutan Admin. Ini **bukan** pengujian Auth atau Realtime Supabase. PostgreSQL lokal memberi warning wal_level belum logical; tidak ada subscription/logical replication yang diuji.

Untuk mengulang SQL test gunakan database PostgreSQL disposable, jalankan tests/sql-bootstrap.sql, migrasi, lalu tests/security.sql dengan psql ON_ERROR_STOP=1. Bootstrap membuat role/schema palsu, jangan jalankan di Supabase atau database yang berisi data nyata.

Uji migrasi tambahan pada tabel lama dengan id bigserial juga lulus: insert otomatis memakai sequence berhasil dan policy lama unsafe_legacy telah diganti. Fixture ada di tests/legacy-schema.sql dan tests/legacy-assert.sql; gunakan database disposable kedua, bootstrap Auth tanpa membuat role yang sudah ada, lalu fixture skema, migrasi, dan assertion.
