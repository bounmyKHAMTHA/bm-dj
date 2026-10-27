# BM DJ - Cross-Platform YouTube Music DJ Deck

BM DJ คือโปรแกรม DJ Deck อัตโนมัติและแมนนวลที่รองรับการเปลี่ยนเพลงแบบไร้รอยต่อ (Seamless Crossfade) ด้วยสถาปัตยกรรม **Independent Dual Audio Engine (Deck A & Deck B)** พัฒนาด้วย Flutter (Dart) สำหรับ Desktop (Windows) และ Mobile (Android) ทำงานร่วมกับ Backend Python/Django REST Framework + yt-dlp สำหรับถอดรหัส YouTube Audio CDN Streams โดยไม่ต้องดาวน์โหลดไฟล์ลงเครื่อง

---

## สถาปัตยกรรมระบบ (Architecture)

```
┌──────────────────────────────────────────────────────────────┐
│        CLIENT: Flutter (Dart) - Desktop (Windows) & Mobile   │
│  ┌────────────────────────┐      ┌────────────────────────┐  │
│  │   Deck A (just_audio)  │      │   Deck B (just_audio)  │  │
│  └───────────┬────────────┘      └───────────┬────────────┘  │
│              │ (Vol: 1.0 -> 0.0)             │ (Vol: 0.0 -> 1.0)
│              └────────────┐      ┌───────────┘               │
│                           ▼      ▼                           │
│                 [ DJ Engine Controller ]                     │
│                 - Equal-Power Crossfader (cos & sin curves)  │
│                 - Speed & Pitch (Key Lock)                   │
│                 - Automated Preload Queue Manager            │
└──────────────────────────────▲───────────────────────────────┘
                               │ HTTP GET (JSON)
┌──────────────────────────────┴───────────────────────────────┐
│        BACKEND: Python (Django REST Framework)               │
│  - Endpoint: /api/v1/stream/resolve?video_id={ID}            │
│  - Endpoint: /api/v1/stream/search?q={query}&limit=10        │
│  - Engine: yt-dlp (Direct m4a/opus CDN audio URLs)           │
└──────────────────────────────────────────────────────────────┘
```

---

## คุณสมบัติเด่น (Core Features)

1. **Dual Audio Engine (Deck A & Deck B):**
   - ใช้งานอินสแตนซ์ `AudioPlayer` แยกอิสระ 2 ชุด ทำงานคู่ขนาน
   - สลับสถานะ Audible Deck และ Standby Deck โดยอัตโนมัติ

2. **Equal-Power Crossfading:**
   - ใช้สูตร Equal-Power Curve:
     $$V_A(t) = \cos\left(\frac{t}{T} \times \frac{\pi}{2}\right)$$
     $$V_B(t) = \sin\left(\frac{t}{T} \times \frac{\pi}{2}\right)$$
   - มั่นใจได้ว่าพลังงานเสียงรวมจะไม่ดรอปหรือเบาลงช่วงกึ่งกลางรอยต่อเพลง ($V_A^2 + V_B^2 = 1.0$)

3. **Smooth Skip & Auto-Fade:**
   - ปุ่ม **Smooth Skip** ขนาดใหญ่ พร้อมแสงนีออนเคลื่อนไหว สลับเพลงลื่นไหลใน 2-10 วินาที
   - ระบบ Auto Crossfade เมื่อเพลงใกล้จบ เพื่อเล่นเพลงต่อเนื่อง 24 ชั่วโมงแบบไม่มี dead air

4. **Automated Pre-buffering:**
   - เมื่อ Deck A กำลังเล่น เพลงถัดไปจะถูก preload เข้าสู่ Standby Deck B ล่วงหน้าที่ระดับเสียง 0.0 ทันที

5. **Pitch & Key Lock:**
   - ปรับ Tempo / Playback Speed ได้ตั้งแต่ `0.75x` ถึง `1.5x` โดยล็อก Pitch คงที่ที่ `1.0` ไม่ให้เสียงแหลม (Chipmunk effect)

6. **Studio DJ Console UI:**
   - ธีม Dark Studio Neon (Cyan สำหรับ Deck A, Magenta/Purple สำหรับ Deck B)
   - แผ่นเสียงไวนิลหมุนแบบเรียลไทม์ พร้อมโทนอาร์มและกราฟิกปกอัลบั้ม
   - VU Meter วัดระดับสัญญาณเสียงสดแบบ LED Bars
   - แถบค้นหาเพลงในตัว รองรับทั้งชื่อเพลง, ศิลปิน, และ URL / Video ID ตรงจาก YouTube
   - ปุ่มเพิ่ม Demo Playlist เพื่อทดสอบได้ทันทีในคลิกเดียว

8. **User Account & Memory Synchronization (ระบบบัญชีและความทรงจำเดิม):**
   - สมัครและเข้าสู่ระบบบัญชี BM DJ เพื่อบันทึกความทรงจำเพลง
   - บันทึกประวัติการค้นหา (Search History) ย้อนหลังและซิงก์ข้ามเครื่อง
   - บันทึกเพลงที่ชอบ (Liked Tracks) พร้อมไอคอนหัวใจบนการ์ดเพลง
   - บันทึกและกู้คืนคิวเพลง (Queue) และการตั้งค่าอัตโนมัติ

9. **YouTube Music Integration (เชื่อมต่อบัญชี YouTube Music):**
   - เชื่อมต่อบัญชี YouTube Music เพื่อดึงข้อมูลคลังเพลงของคุณ
   - ดึงประวัติการฟังล่าสุด (History) จาก YouTube Music
   - ดึงเพลงที่กดถูกใจ (Liked Songs)
   - ดึงเพลย์ลิสต์ส่วนตัว (My Playlists) และเลือกโหลดเพลงหรือเพิ่มทั้งเพลย์ลิสต์เข้าคิว DJ ได้ทันที

---

## โครงสร้างโปรเจกต์ (Project Structure)

```
d:\work bm\dj bm\
├── backend/                  # Python Django Backend
│   ├── .venv/                # Python Virtual Environment
│   ├── manage.py
│   ├── requirements.txt
│   ├── bmdj_server/          # Django Project Configuration & CORS
│   └── stream_resolver/      # Stream Resolver & Search API Views
├── bm_dj/                    # Flutter Application
│   ├── lib/
│   │   ├── main.dart         # Entrypoint, Theme, Shortcuts & Responsive Layout
│   │   ├── controllers/      # DJDeckManager (Dual Engine Controller)
│   │   ├── models/           # Track data model
│   │   ├── services/         # ApiService (Stream & Search)
│   │   └── widgets/          # Turntable, DeckPanel, Crossfader, VU Meter, Queue
│   └── test/                 # Automated Unit & Widget Tests
├── run_backend.bat           # สคริปต์เปิดรัน Backend Server
└── run_flutter_windows.bat   # สคริปต์เปิดรัน Flutter Windows App
```

---

## วิธีเปิดใช้งาน (Quick Start)

### ขั้นตอนที่ 1: เปิด Backend Server
ดับเบิลคลิกที่ไฟล์:
```
run_backend.bat
```
หรือรันผ่าน Terminal:
```powershell
cd backend
.venv\Scripts\python.exe manage.py runserver 127.0.0.1:8000
```
Backend จะทำงานที่ `http://127.0.0.1:8000`

### ขั้นตอนที่ 2: เปิดโปรแกรม DJ Deck (Flutter Windows)
ดับเบิลคลิกที่ไฟล์:
```
run_flutter_windows.bat
```
หรือรันผ่าน Terminal:
```powershell
cd bm_dj
flutter run -d windows
```

### การรันบน Android (Mobile):
```powershell
cd bm_dj
flutter run -d <android-device-id>
```
*(กรณีใช้งานบนมือถือ ให้กดปุ่ม Settings ที่มุมขวาบนในแอป แล้วระบุ IP คอมพิวเตอร์ เช่น `http://192.168.1.xxx:8000` หรือ `http://10.0.2.2:8000` สำหรับ Android Emulator)*
