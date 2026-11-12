# SerFix — Layanan Servis AC dan Elektronik Rumah Tangga

SerFix adalah konsep aplikasi mobile multi-role untuk menyatukan pengajuan servis, penugasan teknisi, work order, estimasi biaya, pencatatan sparepart, pembayaran, dan garansi. Layanan yang sebelumnya dikelola manual menjadi lebih mudah dipantau oleh pelanggan dan lebih terstruktur bagi tim operasional.

## Peran

- **Pelanggan** mengajukan servis, memilih jadwal, melihat status, estimasi, riwayat, dan garansi.
- **Teknisi** melihat penugasan dan work order serta mencatat diagnosis dan sparepart.
- **Admin** mengelola jadwal, penugasan, area layanan, dan stok sparepart.
- **Manajer** memantau ringkasan operasional dan transparansi biaya.

Penugasan teknisi dirancang berdasarkan keahlian dan area layanan. Pemeriksaan jadwal mendeteksi tumpang tindih sebelum penugasan dikonfirmasi.

## Struktur

```text
database/   Skema database
api/        REST API PHP dan autentikasi
frontend/   Aplikasi mobile Flutter
```

## Menjalankan aplikasi mobile

```powershell
cd frontend
flutter pub get
flutter test
flutter run
```

## Status implementasi

Antarmuka Flutter SerFix saat ini menyediakan alur demonstrasi untuk empat peran, pengajuan servis, jadwal, estimasi, sparepart, dan garansi. Data permintaan pada antarmuka demonstrasi disimpan sementara di memori aplikasi; data tersebut belum tersinkron ke server.

Autentikasi masih menggunakan API PHP yang ada. Skema `database/schema.sql` dan endpoint operasional PHP belum dimigrasikan dari domain aplikasi sebelumnya ke layanan SerFix. Karena itu, fitur multi-role dan alur servis dalam demo belum merupakan kontrol akses atau workflow produksi. Integrasi API, penyimpanan permanen, pembayaran, penugasan berdasarkan keahlian/area, dan pengelolaan sparepart perlu diselesaikan pada migrasi backend sebelum dipakai sebagai layanan nyata.
