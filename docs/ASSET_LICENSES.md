# ASSET LICENSES — QUẨY BAR ONLINE

Cập nhật: 2026-11-03

## 1. Nguyên tắc

1. Không đưa vào repo tài nguyên không rõ nguồn gốc hoặc không cho phép dùng thương mại.
2. Mỗi asset bên thứ ba phải ghi: tên, tác giả, URL nguồn, giấy phép, ngày tải, đường dẫn trong repo.
3. Ưu tiên CC0 / CC-BY / giấy phép cho phép dùng trong game thương mại.
4. Không dùng nhạc thương mại, soundtrack phim, hay nội dung YouTube tải xuống.
5. Không commit file > 20 MB trực tiếp; dùng Git LFS hoặc script tải trong `tools/asset_import/`.
6. Không để đường dẫn asset chết: mọi `res://` phải tồn tại và được import bởi Godot.

## 2. Tài nguyên hiện có trong repo

Phần lớn tài nguyên là **tác phẩm gốc của dự án**, sinh bằng code hoặc hình học procedural. Ngoại lệ duy nhất là model nhân vật GLB tải từ Sketchfab dưới giấy phép CC-BY 4.0 (xem bảng bên dưới và `game/assets/models/characters/README.md`).

| Tài nguyên | Loại | Nguồn | Giấy phép | Ghi chú |
| --- | --- | --- | --- | --- |
| Nightclub The Chrome Lotus | Hình học 3D procedural | `game/scripts/world/nightclub.gd` | Gốc dự án | Box/cylinder/sphere mesh + PBR material; không dùng mesh mặc định làm thành phẩm |
| Đá marble, gỗ, thảm, kim loại | Texture PBR procedural | `game/scripts/world/procedural_textures.gd` | Gốc dự án | Sinh bằng FastNoiseLite; albedo + roughness |
| Nhân vật người chơi | Mesh + rig procedural | `game/scripts/player/character_rig.gd` | Gốc dự án | Rig tay/chân/đầu, animation code; dùng khi không có GLB |
| Nhân vật người chơi (GLB) | Model có rig + animation | manoeldarochadeoliveira — https://sketchfab.com/3d-models/low-poly-girl-4cb87c1d3c3c4b9ea3b4c61ab407500a | CC-BY 4.0 | `game/assets/models/characters/player.gltf`; 89 xương, 35 animation; bắt buộc ghi công khi phát hành |
| Nhạc demo “Chrome Lotus” | Audio tổng hợp | `game/scripts/systems/demo_track.gd` | Gốc dự án | 124 BPM, 12 giây loop, tổng hợp sin/noise; không lấy mẫu từ bản thu nào |
| Icon | SVG | `game/icon.svg` | Gốc dự án | |
| Game Menu Kit Lite | Addon UI Godot | Ryan — https://github.com/GameMenuKit/game-menu-kit-lite (vendored tại `tools/game-menu-kit-lite`, bản dùng trong game ở `game/addons/game_menu_kit`) | MIT | Menu chính/options; giữ nguyên `LICENSE` |
| Font UI | System font | Thiết bị người dùng | Font hệ điều hành | Dùng `SystemFont` (Segoe UI / Noto Sans / Roboto / Microsoft YaHei) — không phân phối lại font |
| Logo chữ “QUẨY BAR ONLINE”, “The Chrome Lotus” | Text/Label3D | Dự án | Gốc dự án | Tên sản phẩm, không phải nhãn hiệu bên thứ ba |

> Lưu ý: “The Chrome Lotus” là tên hư cấu của club trong game. Nếu trùng tên doanh nghiệp thật, cần đổi trước khi phát hành thương mại.

## 3. Nguồn dự kiến khi bổ sung asset thật

Chỉ dùng sau khi kiểm tra giấy phép và ghi lại vào bảng dưới:

- Poly Haven (CC0) — HDRi, PBR texture.
- ambientCG (CC0) — PBR texture.
- Kenney (CC0) — UI/audio placeholder.
- Sketchfab (lọc CC0 / CC-BY, kiểm tra từng model).
- OpenGameArt (CC0/CC-BY).
- Quixel Megascans (chỉ khi tài khoản/điều khoản cho phép dùng trong game thương mại; không commit raw).

### Mẫu ghi nhận asset mới

```
| <Tên file> | Model/Texture/Audio | <Tác giả> | <Giấy phép + URL> | <Ngày tải> | <Dùng ở đâu> |
```

## 4. Quy trình import asset

1. Tải asset về `tools/asset_import/incoming/` (không commit).
2. Kiểm tra license, ghi vào file này.
3. Chuẩn hóa: GLB/GLTF ưu tiên; scale về mét; pivot đúng; texture ≤ 2K cho PC, ≤ 1K cho mobile; nén KTX/Basis khi export mobile.
4. Đặt vào `game/assets/<category>/`.
5. Import bằng Godot, kiểm tra `.import` được commit.
6. Cập nhật cảnh/builder tương ứng, chạy smoke test.
7. Xóa bản gốc trong `incoming/`.

## 5. Âm thanh và nhạc

- Track demo trong game là bản tổng hợp gốc, an toàn để phân phối.
- Người chơi có thể tải nhạc từ URL **nếu họ có quyền sử dụng**; game không đóng gói nhạc đó và không lưu trữ lâu dài.
- Không tải/nhúng nội dung YouTube trái chính sách; chỉ dùng chế độ nhúng chính thức trên nền tảng có WebView.
- Không vượt DRM dưới bất kỳ hình thức nào.

## 6. Giấy phép mã nguồn

Mã nguồn dự án chưa được cấp giấy phép phát hành công khai. Trước khi publish repository, chủ dự án cần chọn giấy phép (ví dụ MIT cho code và CC-BY cho asset) và thêm file `LICENSE`. Không tự ý gán giấy phép khi chưa có quyết định của chủ sở hữu.
