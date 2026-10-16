# Fruit Catcher – hứng trái cây bằng khuôn mặt

Game Flutter dùng **Google ML Kit** (chạy on-device, không cần mạng) để điều khiển bằng nét mặt.

| Hành động | Kết quả | API ML Kit |
|---|---|---|
| Nghiêng đầu trái/phải | Giỏ di chuyển | Face Detection: `headEulerAngleZ` |
| Cười | Điểm x2 | Face Detection: `smilingProbability` |
| Nhắm mắt > 0.8s | Tạm dừng | Face Detection: `left/rightEyeOpenProbability` |
| Há miệng | Skill: ăn hết trái, nổ hết bom (hồi 12s) | Face Mesh: khoảng cách môi trên-dưới / chiều cao mặt |
| Mất mặt | Tự tạm dừng, thấy lại thì đếm ngược | Face Detection |

Luật: 🍎🍊🍌🍇 +10, 🍉 +20, ❤️ +1 mạng, 💣🌶️ mất 1 mạng. 3 mạng, tốc độ tăng theo điểm, top 5 điểm cao lưu trên máy.

## Âm thanh và hiệu ứng

- **Âm thanh** (không cần mạng, toàn bộ tự tổng hợp bằng `tools/gen_audio.py`, chạy lại để tạo lại file trong `assets/audio/`):
  tiếng hứng trái có **cao độ tăng dần theo combo** (thang ngũ cung), dưa hấu "ka-ching", bom nổ, ớt "rít", tim lấp lánh,
  skill "whoosh + nom nom", mốc combo, lên level, "wah-wah" khi thua, nhạc chiến thắng khi phá kỷ lục, đếm ngược, bấm nút.
  Nhạc nền chiptune lặp, **nhanh dần theo level** (tối đa +25%). Có công tắc riêng cho âm thanh và nhạc nền trong menu.
- **Hiệu ứng**: giỏ nảy (squash & stretch) và nghiêng theo hướng chạy, mặt cảm xúc trên giỏ (😋 hứng, 😵 trúng bom, 🤩 skill, 😁 cười),
  nước ép và bản sao emoji bắn tung khi hứng, bom bốc tia lửa, chữ điểm nảy, banner COMBO / LEVEL / NOM NOM,
  pháo giấy khi lên level và phá kỷ lục, chế độ **FEVER** (combo ≥ 10: hào quang vàng và sao lấp lánh quanh giỏ),
  bầu trời đổi **ngày → hoàng hôn → chiều tối → đêm** (mặt trời thành trăng, sao nhấp nháy) theo level.

## Chạy

```bash
flutter pub get
flutter run -d <pixel_7>          # emulator đã gắn webcam Mac (webcam0)
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
flutter test                      # 26 test: luật chơi, sự kiện âm thanh, bộ xử lý tín hiệu
python3 tools/gen_audio.py        # (tuỳ chọn) tạo lại toàn bộ file âm thanh
```

Emulator: AVD Pixel 7 cần `hw.camera.front=webcam0` (Extended controls → Camera, hoặc sửa `config.ini`).
Face Mesh chỉ có trên Android. Nếu Face Mesh lỗi, app tự chuyển sang Face Detection + contours để đo miệng.

## Hiệu năng (để game mượt)

- **Emulator phải dùng GPU thật**: AVD đặt `hw.gpu.mode=host`. Nếu để `auto`, emulator có thể rơi về `lavapipe` (vẽ bằng CPU):
  giao diện chỉ ~30 FPS, ML Kit 7–20 FPS. Với GPU host: **60 FPS giao diện, ML 30 FPS, Detect ~5ms, Mesh ~9ms**.
- **Chạy bản release khi demo**: chọn cấu hình *Fruit Catcher (release - mượt)* trong Android Studio, hoặc `flutter run --release`.
  Bản debug (JIT) chậm hơn đáng kể.
- Trong app: emoji và chữ được vẽ sẵn thành sprite một lần (không dàn chữ mỗi khung), không dùng `saveLayer`/`drawShadow`,
  giới hạn 220 hạt, `RepaintBoundary` tách lớp game/camera, camera giới hạn 30 FPS, Face Mesh tự giãn tần suất theo thời gian xử lý.
- Thanh hiệu năng trong game hiện `🎮 FPS giao diện · 🧠 FPS ML Kit · Detect · Mesh`.
  Đo chi tiết: `flutter run --release --dart-define=PERF_LOG=true` rồi xem log `PERF`.

## Cấu trúc

```
lib/core/face_controller.dart  camera → ML Kit (Detection mỗi khung, Mesh tự giãn tần suất) → FaceState
lib/core/input_hub.dart        hiệu chỉnh mốc 0, làm mượt 4 khung, vùng chết ±5°, há miệng/nhắm mắt
lib/game/game_engine.dart      luật chơi thuần Dart (có test)
lib/game/game_painter.dart     vẽ game bằng Canvas (bầu trời, giỏ, hạt, banner)
lib/core/audio_service.dart    âm thanh + nhạc nền (audioplayers)
lib/ui/                        menu, hiệu chỉnh, game, Face Lab, lưới mặt
```

## Kịch bản demo (~5 phút)

1. **Giới thiệu (30s)**: ML Kit là bộ SDK máy học chạy trực tiếp trên máy: nhanh, riêng tư, không cần internet.
2. **Chứng minh on-device (30s)**: bật chế độ máy bay, mở app, vẫn nhận diện bình thường. Chỉ vào dòng `⚡ FPS · Detect ms · Mesh ms`.
3. **Face Lab (1.5 phút)**: bật lưới, giải thích 468 điểm 3D và các đường viền (mắt, môi, lông mày, oval). Nghiêng đầu, cười, nhắm mắt, há miệng để thanh số liệu nhảy theo.
   Nói rõ: *Face Detection* cho góc đầu và biểu cảm (nhanh, ổn định, dùng để điều khiển); *Face Mesh* cho lưới và đo miệng (chính xác hơn nhưng nặng hơn nên chạy cách khung).
4. **Chơi (2 phút)**: mời giảng viên hoặc bạn lên chơi. Hiệu chỉnh 2 giây, chơi một ván, cho cả lớp xem bảng xếp hạng.
5. **Kết luận (30s)**: ứng dụng thật: trợ năng cho người khuyết tật tay, game, AR filter, phát hiện buồn ngủ.

## Xử lý sự cố khi demo

- Giỏ đi ngược hướng đầu → menu → bật **Đảo chiều nghiêng**.
- Giỏ quá nhạy/chậm → chỉnh thanh **Độ nhạy**.
- Camera không lên → nút **Thử lại**; hoặc tắt **Điều khiển bằng khuôn mặt** để chơi bằng cảm ứng.
- Mất khung hình/lệch lưới → Face Lab → **Xoay ảnh +90°**.
