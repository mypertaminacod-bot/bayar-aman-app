# BAYAR AMAN — aktivasi otomatis dan penyiapan Supabase

Keputusan final: pendaftaran langsung aktif tanpa persetujuan Admin. Setelah transaksi berhasil, User melihat loading 10 detik dan pesan persis:

> Pendaftaran anggota telah aktif. Anda dapat menggunakan layanan COD.

Migrasi di PR ini BELUM diterapkan ke produksi. Tidak ada deployment atau merge oleh perubahan ini.

## Kontrak aplikasi

- Empat halaman User: HP → nomor pesanan → detail/pilihan pembayaran/rute → pendaftaran bila belum menjadi anggota dan memilih COD.
- Halaman 3 membaca status anggota dari server saat dibuka dan saat konfirmasi. COD nonanggota menampilkan dialog final; OK membuka halaman 4. COD anggota aktif dikonfirmasi tanpa mendaftar ulang. LinkAja adalah pilihan pembayaran manual, tidak mewajibkan pendaftaran dan tidak menjalankan transfer dana.
- Pendaftaran menyimpan identitas, mengaktifkan anggota, memberi tiga kuota awal dan membuat satu event pendaftaran untuk Admin dalam satu transaksi database. Tidak ada persetujuan Admin. Status/kuota tidak berasal dari nilai yang dikirim browser.
- Kuota disimpan di `bayar_aman_members.free_shipping_quota`, bukan dihitung ulang setiap tombol ditekan. Pemakaian kuota saat pengiriman bukan bagian dari PR ini; tidak ada pemotongan ongkir fiktif.
- Satu anggota per auth user, satu per kunci nomor HP. Variasi Indonesia `08…`, `628…`, `00628…` menggunakan kunci unik yang sama; tampilan/event tetap menyimpan nomor asli yang dikirim. Pengulangan dari sesi yang sama mengembalikan anggota lama tanpa menambah kuota atau event. Permintaan bersamaan diserialisasi dengan advisory transaction lock dan constraint unik.
- Respons jaringan yang hilang setelah commit tidak menghasilkan klaim sukses di browser. Retry aman dan mengembalikan data anggota yang sudah tersimpan. Kegagalan pencatatan event Admin membatalkan keanggotaan dan kuota dalam transaksi yang sama.
- Setelah respons server mengonfirmasi anggota aktif, loading berlangsung 10 detik. Tombol/kembali dinonaktifkan selama proses. Sesudahnya ada tombol Kembali ke Pesanan; COD akan diperiksa lagi di server.
- Login User tetap anonim tanpa OTP. Ini bukan verifikasi kepemilikan nomor telepon. Nomor yang sudah terdaftar pada sesi lain tidak boleh mengambil alih anggota atau kuotanya. Pemulihan sesi lintas perangkat membutuhkan prosedur identitas terverifikasi terpisah; jangan menghubungkan akun hanya berdasarkan nomor HP.
- Data pendaftaran lama di `user_data` tidak otomatis membuktikan keanggotaan baru. UI Admin menyebutnya Pendaftaran lama sampai ada event aktivasi server. Migrasi tidak memberi kuota massal atau mengubah kepemilikan data lama.
- Rute tetap daftar titik dari Admin, bukan peta jalan/GPS. Alamat, koordinat, status verifikasi dan sumber dipisahkan; titik merah berkedip satu detik, diam dengan reduced motion. Editor Admin mendukung form titik pada HP serta JSON lanjutan.
- Dua tampilan Admin: login email/password dan dashboard dengan empat ringkasan, tab data masuk/editor/riwayat, pencarian, nilai asli, status dan aksi. Tidak ada tombol persetujuan anggota.

## Migrasi yang harus ditinjau di staging

1. Cadangkan dan periksa tipe kolom, primary key/default/sequence ID, trigger, policy, grant, `is_admin()`, RPC lama, dan publikasi pada database yang sebenarnya. Metadata REST produksi terakhir mengembalikan 401; itu tidak membuktikan penyebabnya atau isi skema.
2. Terapkan berurutan `202611060001_secure_user_data.sql`, lalu `202611060002_automatic_membership.sql` pada staging. Jangan menjalankan ulang migrasi yang sudah tercatat. Jangan menjalankan file bootstrap/test pada Supabase atau database berisi data nyata.
3. Migrasi pertama secara sengaja mengganti SEMUA policy `user_data`, mencabut UPDATE/DELETE browser, mengganti `is_admin()`, dan menambahkan RPC editor Admin. Audit konsumen lama dan tabel lain seperti profiles secara terpisah; migrasi ini tidak memperbaiki seluruh akses proyek secara otomatis.
4. Migrasi kedua membuat `bayar_aman_members`, kunci telepon unik, RLS pemilik/Admin, RPC registrasi otomatis, pembacaan status anggota, pembuatan event, serta pagination Admin. Trigger mencegah COD tanpa anggota aktif dan mencegah pemalsuan event pendaftaran langsung dari browser.
5. `id` user_data dapat UUID/integer/bigint/text; data=jsonb, user_id=uuid, timestamp=timestamptz. Skema tak cocok membatalkan transaksi. RPC event dan daftar Admin mengembalikan ID sebagai teks di server, termasuk bigint di atas batas angka aman JavaScript. Browser menolak ID numerik tidak aman.
6. Isi `bayar_aman_admins(user_id)` dengan UUID satu akun Admin resmi melalui pengelola terpercaya. Akun berbasis metadata lama tidak otomatis mendapatkan akses. Tidak ada kredensial Admin atau service_role key di klien.
7. Aktifkan Anonymous Sign-ins pada proyek yang benar setelah verifikasi konfigurasi URL/publishable key. Pemeriksaan baca-saja sebelumnya mendapatkan `anonymous_users=false`; perubahan PR ini tidak mengaktifkannya pada produksi.
8. Pastikan `user_data` terdaftar di `supabase_realtime`. Aktivasi menghasilkan INSERT `pendaftaran` sehingga Admin menerima event melalui kanal yang sama. Keanggotaan tidak memerlukan persetujuan atau publikasi tabel anggota tambahan. Polling User 7 detik / Admin 10 detik hanya cadangan.
9. Migrasi dan klien baru harus dirilis secara terkoordinasi: klien lama mengirim pendaftaran langsung/ID angka dan akan ditolak setelah kontrak baru berlaku. Jangan deploy klien baru sebelum RPC tersedia.

## Pengujian yang dapat diulang

`npm ci`, lalu `CHROMIUM_PATH=/path/to/chromium npm run test:all`.

- `npm test`: sintaks semua skrip publik, pemindaian key privileged, validasi koordinat dan sumber rute.
- `npm run test:db`: dua database PGlite disposable, skema UUID baru dan bigserial lama. Menjalankan bootstrap Auth palsu, kedua migrasi, RLS, spoofing, RPC Admin, aktivasi, kuota, retry, constraint telepon termasuk alias awalan, rollback saat event gagal, penolakan COD nonanggota, isolasi User/Admin, ID > MAX_SAFE_INTEGER pada User dan Admin. Dua pemanggilan registrasi yang diantrekan mengembalikan event yang sama; PGlite tidak membuktikan race dua koneksi PostgreSQL sungguhan.
- `npm run test:browser`: backend simulasi, bukan Supabase asli. Memeriksa dialog nonanggota, COD aktif, LinkAja, gagal baca/tulis, respons hilang setelah commit, double submit, durasi tepat 10 detik, pesan aktivasi, kuota tidak diisi ulang, event Admin, editor rute form/JSON, XSS, konflik edit, lebar 320/360/412/1024 pada empat halaman User, lebar Admin, reduced motion, tab, password toggle, logout/penolakan Admin, dan ID numerik tidak aman.

## Gerbang sebelum produksi

- Uji dua koneksi PostgreSQL serentak untuk UID sama, nomor sama pada UID berbeda, alias nomor, dan respons putus sesudah commit. Hanya satu anggota/kuota/event boleh terbentuk. Ulangi setelah kuota pernah berkurang.
- Dua browser User terisolasi dan Admin resmi: buktikan RLS melalui REST langsung, bukan UI saja. User B tidak boleh membaca anggota, alamat, pesanan atau rute A, walau mengetahui HP/ID A.
- Rekam INSERT pendaftaran diterima Admin dan UPDATE detail/rute diterima User melalui WebSocket tanpa menunggu polling. Uji publikasi mati, JWT habis, koneksi putus, grant Admin dicabut, CDN gagal dan tab background.
- Periksa desain enam tampilan di HP Android sebenarnya, termasuk ikon SVG, keyboard, dialog, loading dan pengguliran tabel. Pemeriksaan browser lokal tidak menggantikan uji perangkat nyata.
