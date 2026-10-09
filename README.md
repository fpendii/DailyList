# Daftar Harian

Aplikasi to-do list harian berbasis PowerShell dengan popup daftar tugas dan animasi kucing.

## Menjalankan aplikasi

Klik dua kali `DailyList.exe` yang berada langsung di folder utama ini. 

Untuk menjalankan versi sumber PowerShell, gunakan perintah berikut:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File .\DailyListPopup.ps1
```

## Struktur proyek

- `Daftar Harian.exe` — aplikasi sekali-klik untuk pengguna.
- `assets/app-icon.ico` — ikon aplikasi.
- `DailyListPopup.ps1` — logika dan antarmuka aplikasi.
- `LaunchDailyListPopup.vbs` — launcher VBS lama (opsional).
- `assets/` — gambar ekspresi kucing yang dibutuhkan aplikasi.
- `data/` — penyimpanan daftar tugas pada komputer lokal.

File `data/daily-list-data.json` sengaja tidak diunggah ke GitHub agar daftar tugas pribadi tidak ikut terbuka. Aplikasi akan membuatnya otomatis saat data pertama kali disimpan.

Pengaturan **Jalankan saat masuk Windows** di aplikasi akan membuat shortcut Startup yang menunjuk ke launcher dalam folder ini.
