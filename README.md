# SerFix — Layanan Servis AC dan Elektronik Rumah Tangga

SerFix adalah aplikasi mobile multi-role untuk menyatukan pengajuan servis, penugasan teknisi, work order, estimasi biaya, pencatatan sparepart, pembayaran, dan garansi. Pengguna dapat masuk sebagai tamu untuk menjelajahi aplikasi; login atau pendaftaran diperlukan untuk mengajukan servis dan menggunakan fitur akun. Pelanggan dapat memantau progres dan biaya, sementara teknisi dan pengelola menangani pekerjaan serta operasional dari satu platform.

## Peran dan fitur

- **Pelanggan:** daftar/masuk, mengajukan servis dan jadwal, melihat status serta estimasi, menyetujui biaya, mengirim catatan pembayaran, dan mengajukan klaim garansi.
- **Tamu:** membuka aplikasi tanpa akun dengan akses terbatas; sesi tamu hanya berlaku sampai aplikasi ditutup.
- **Teknisi:** melihat penugasan, mencatat diagnosis dan pekerjaan, mengelola sparepart yang dipakai, dan menyelesaikan work order.
- **Admin:** mengelola permintaan dan penugasan, akun staf, stok sparepart, verifikasi pembayaran, dan klaim garansi.
- **Manajer:** memantau ringkasan operasional serta mengelola keputusan pembayaran dan garansi.

Penugasan memeriksa area layanan, keahlian teknisi, ketersediaan, dan tumpang tindih jadwal. Persetujuan pelanggan diperlukan sebelum teknisi memulai pekerjaan setelah estimasi tersedia.

## Struktur proyek

```text
database/schema.sql   Skema MySQL dan katalog layanan awal
api/                  REST API PHP, autentikasi, dan panel operasional admin
frontend/             Aplikasi mobile Flutter
```

## Persiapan backend (PHP, Apache, MySQL)

1. Pasang lingkungan PHP dengan ekstensi PDO MySQL, Apache, dan MySQL (misalnya Laragon).
2. Salin proyek ke direktori web sebagai `serfix` (contoh Laragon: `C:\laragon\www\serfix`).
3. Sesuaikan host, nama database, pengguna, dan kata sandi MySQL di `api/config/database.php` bila konfigurasi lokal bukan `localhost`, `serfix_db`, `root`, dan kata sandi kosong.
4. Impor `database/schema.sql` melalui phpMyAdmin atau MySQL CLI. Skema membuat database `serfix_db`, seluruh tabel, dan katalog layanan/sparepart awal. Impor ini **tidak** mengonversi atau menghapus data AutoLog.
5. Impor migrasi `database/migrations/001_user_sessions.sql` dan `database/migrations/002_serfix_additional_features.sql` secara berurutan agar tabel sesi serta fitur chat, lokasi, lampiran, notifikasi, dan ulasan tersedia.
6. Untuk fitur lanjutan, impor `database/migrations/003_serfix_ten_features.sql`. Migrasi ini menambahkan perangkat push, aset pelanggan, usulan penjadwalan ulang, transaksi payment gateway, antrean sinkronisasi offline, serta indeks pendukung laporan dan pencarian.
7. Impor `database/migrations/004_serfix_security_inventory_areas.sql` untuk OTP/reset password, area layanan, dan transaksi riwayat stok.
8. Buat login untuk panel web admin dari terminal di folder proyek:

   ```powershell
   php api\admin\create_admin.php
   ```

   Skrip meminta email dan kata sandi admin (minimal 12 karakter). Buka `http://localhost/serfix/api/admin/` dan masuk dengan kredensial itu. Panel digunakan untuk membuat akun admin/manajer/teknisi serta mengelola operasional. Pendaftaran publik di aplikasi hanya membuat akun pelanggan.
9. Aplikasi memakai endpoint `/serfix/api`; jika nama folder atau host berbeda, ubah Base URL pada halaman login atau **Pengaturan** setelah masuk.

Panel admin mengelola sesi login secara terpisah dari akun peran aplikasi. Akun admin awal dari skrip diperlukan untuk masuk ke panel; akun staf yang dibuat di panel digunakan untuk masuk melalui aplikasi mobile.

## Menjalankan aplikasi Flutter

```powershell
cd frontend
flutter pub get
flutter test
flutter run
```

Alamat API default:

- Windows atau web: `http://localhost/serfix/api`
- iOS Simulator: `http://localhost/serfix/api`
- Android Emulator: `http://10.0.2.2/serfix/api`
- Perangkat Android fisik: atur Base URL ke alamat IP LAN komputer yang menjalankan Apache, misalnya `http://192.168.1.10/serfix/api`.

Pastikan perangkat dan komputer berada di jaringan yang dapat saling menjangkau, Apache menerima koneksi dari jaringan tersebut, dan firewall mengizinkan akses. Gunakan HTTPS dan konfigurasi server yang sesuai sebelum pemakaian di luar lingkungan pengembangan.

## Alur operasional dan batasan

- Pelanggan mengirim permintaan; admin/manajer menugaskan teknisi yang memenuhi keahlian, area, serta jadwal.
- Teknisi mencatat diagnosis dan estimasi pada work order. Pelanggan harus menyetujui estimasi sebelum pekerjaan dimulai; perubahan estimasi saat pekerjaan berlangsung memerlukan persetujuan ulang.
- Pemakaian sparepart memperbarui stok. Servis selesai mengunci nilai akhir dan menerbitkan garansi bila kategori layanan memiliki masa garansi.
- Pembayaran saat ini **belum** terhubung ke payment gateway. Pelanggan mencatat metode dan referensi pembayaran; admin/manajer wajib memeriksa dana secara terpisah sebelum memverifikasinya di sistem.
- Pengujian end-to-end memerlukan server PHP dan MySQL yang berjalan serta skema SerFix sudah diimpor. Kredensial database dan server lokal adalah konfigurasi pengembangan, bukan konfigurasi produksi.
