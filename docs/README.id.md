# GoldBrain 🧠✨

**Tujuh bulan ambisi, pembelajaran, dan ruang kerja intelijen keuangan yang belum selesai.**

[English](https://github.com/FarlandGame/GoldBrain/blob/main/README.md) · [日本語](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ja.md) · [فارسی](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fa.md) · [Deutsch](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.de.md) · [Français](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.fr.md) · [Español](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.es.md) · [Português (Brasil)](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pt-BR.md) · [Italiano](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.it.md) · [Nederlands](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.nl.md) · [Polski](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.pl.md) · [Українська](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.uk.md) · [Türkçe](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.tr.md) · [Русский](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ru.md) · [简体中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-CN.md) · [繁體中文](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.zh-TW.md) · [한국어](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.ko.md) · [हिन्दी](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.hi.md) · [Bahasa Indonesia](https://github.com/FarlandGame/GoldBrain/blob/main/docs/README.id.md)

<p><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/goldbrain-brand-logo.png" width="128" alt="GoldBrain logo"></p>

GoldBrain adalah proyek eksperimen yang pengembangannya dihentikan, karya saudara kembar Bardiya dan Armiya Alizadeh (Kabir). Proyek ini memadukan antarmuka Flutter yang mengutamakan bahasa Persia dengan backend Python/FastAPI. Kode sumbernya disimpan agar pengembang lain dapat memahami pekerjaan yang sudah dilakukan, mereproduksi kondisi saat ini, dan menentukan cara melanjutkannya.

Pembuat bersama: **Bardiya Alizadeh (Kabir) · Farland_game** dan **Armiya Alizadeh (Kabir) · ArmiyaFbix**, dengan kredit setara pada layar Tentang dan catatan pengembangan terbaru proyek.

Menurut Bardiya, proyek ini dikerjakan selama kurang lebih tujuh bulan. Ia memulai dengan sedikit pengalaman pemrograman dan belajar melalui eksperimen, sumber daring, serta bantuan AI. Ambisi awalnya adalah produk Windows/Android dengan prediksi pasar jangka pendek dan panjang, lalu perdagangan otomatis di Wallex yang hanya memakai sebagian dana sesuai pilihan pengguna. Ia berhenti mengejar keseluruhan visi itu karena kebutuhan infrastruktur, biaya, kerumitan, dan risiko keuangan. Semua itu adalah tujuan, bukan kemampuan yang telah selesai atau tervalidasi.

> Si otak punya rencana besar. Tagihan infrastruktur juga punya rencananya sendiri. 🧠🧾😅

## Isi kode sumber yang disimpan

- Antarmuka Flutter khusus dengan 11 tema, 8 bahasa antarmuka yang sudah ada, animasi, grafik, pengaturan, daftar pantauan, kontrol audio, dan halaman Tentang.
- Backend FastAPI dengan kuotasi dan riwayat pasar yang dinormalisasi, asal penyedia data, pemeriksaan kebaruan dan kualitas, data ringkasan yang disimpan secara persisten, serta worker pengumpulan data.
- Mesin prediksi untuk riset dengan penghitungan fitur, evaluasi/pengujian historis secara kronologis, dan catatan bukti; ini berbeda dari sistem prediksi akhir yang belum selesai.
- API simulasi perdagangan tanpa uang sungguhan; UI portofolio yang terlihat dan perdagangan dengan uang sungguhan belum selesai.
- Alur verifikasi email dan pengaturan ulang kata sandi, pengelolaan kata sandi dengan Argon2, token akses JWT, rotasi token penyegaran, serta kontrol perangkat dan sesi.
- Berita RSS, terjemahan/ringkasan artikel dengan AI yang opsional, asisten obrolan hanya-baca dengan kewenangan terbatas, dan indikator denyut pasar enam negara.
- Kode sumber pengujian backend dan Flutter, sepuluh migrasi basis data, contoh konfigurasi, dokumen arsitektur/API, serta riwayat kemajuan dan keputusan.

## Titik berhentinya pengembangan

- Sistem prediksi langsung/dengan umpan balik mandiri yang direncanakan untuk Phase 6 belum selesai. Alat asistennya secara tegas melaporkan bahwa fitur tidak tersedia, alih-alih mengarang prediksi.
- Perdagangan otomatis dengan uang sungguhan di Wallex dan alur alokasi anggaran pengguna yang diusulkan belum diimplementasikan. Adaptor bursa hanya berupa kontrak antarmuka tiruan.
- Perjanjian data untuk penggunaan produksi, kinerja keuangan yang divalidasi secara independen, penguatan keamanan dan keandalan penerapan publik, serta akses penyedia yang andal masih menjadi pekerjaan terbuka.
- Pemrosesan pembayaran, UI portofolio lengkap, dan beberapa pengaturan yang terlihat belum selesai. Model langganan/hak akses bukan berarti sistem pembayaran telah selesai.
- Kode sumber terintegrasi saat ini memiliki kerangka Windows dan web; kerangka Android lama disimpan terpisah. Rilis Android atau web versi saat ini yang berfungsi belum diverifikasi.

## Lanjutkan proyeknya

Mulailah dari panduan melanjutkan proyek, penyiapan hasil kloning baru, matriks status terkini, dan laporan verifikasi. Dokumen historis dipertahankan beserta tanggalnya; label fase, harga penyedia, dan jumlah pengujian lama di dalamnya tidak mengesampingkan kode sumber saat ini. Gunakan konfigurasi layanan sendiri dan basis data baru. Basis data akun pribadi, kredensial API, dan identitas penandatanganan Android tidak disertakan.

[Continuation guide](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CONTINUING.md) · [Fresh-clone setup](https://github.com/FarlandGame/GoldBrain/blob/main/docs/SETUP.md) · [Current status matrix](https://github.com/FarlandGame/GoldBrain/blob/main/docs/CURRENT_STATUS.md) · [Verification report](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERIFICATION.md)

## Identitas visual dan materi historis

Poster dan logo proyek yang diberikan disertakan. Audio didistribusikan sebagai paket aset terpisah berdasarkan pernyataan pembuat bahwa distribusi ulang diizinkan; audio tidak otomatis tercakup oleh lisensi kode. Snapshot kode sumber lama adalah referensi historis, bukan komponen yang dapat saling ditukar dalam aplikasi saat ini.

<p><a href="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png"><img src="https://raw.githubusercontent.com/FarlandGame/GoldBrain/main/assets/historical-promo-poster.png" width="720" alt="Poster promosi historis: menggambarkan visi awal proyek, bukan rilis terkini yang telah diverifikasi."></a></p>

*Poster promosi historis: menggambarkan visi awal proyek, bukan rilis terkini yang telah diverifikasi.*

[Preservation release · preserved-2026-11-01](https://github.com/FarlandGame/GoldBrain/releases/tag/preserved-2026-11-01)

## Serah terima teknis

Panduan teknis terperinci tersedia dalam bahasa Inggris, bersama dokumen asli proyek berbahasa Inggris/Persia yang tetap disimpan. Pengantar portofolio ini menggunakan 18 bahasa dokumentasi yang sama dengan bagian portofolio lainnya; 8 bahasa antarmuka yang sudah ada dalam aplikasi merupakan fitur terpisah.

[Version map](https://github.com/FarlandGame/GoldBrain/blob/main/docs/VERSION_MAP.md) · [Assets and license notices](https://github.com/FarlandGame/GoldBrain/blob/main/docs/ASSETS_AND_LICENSES.md) · [MIT code license](https://github.com/FarlandGame/GoldBrain/blob/main/LICENSE)

Baca catatan publikasi/lisensi repositori dan pemberitahuan aset pihak ketiga yang terpisah sebelum menggunakan ulang kode atau media.

[Bardiya Alizadeh (Kabir) · Farland_game](https://github.com/FarlandGame)
