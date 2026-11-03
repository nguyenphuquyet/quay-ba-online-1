# Asset import

Thư mục làm việc cho tài nguyên 3D/audio bên thứ ba.

## Quy trình

1. Tải asset vào `incoming/` (đã gitignore; không commit).
2. Ghi license vào `docs/ASSET_LICENSES.md` theo mẫu.
3. Kiểm tra:
   - Model: GLB/GLTF ưu tiên, scale mét, pivot đúng, poly budget (mobile < 50k tam giác/asset).
   - Texture: ≤ 2K PC, ≤ 1K mobile, nén KTX/Basis.
   - Audio: OGG/MP3 có giấy phép; không nhạc thương mại.
4. Copy vào `game/assets/<category>/`.
5. Mở Godot import, kiểm tra `.import`, chạy `tools/development/verify.sh`.
6. Xóa bản trong `incoming/`.

## Gợi ý nguồn CC0

- Poly Haven: https://polyhaven.com (HDRi/texture CC0)
- ambientCG: https://ambientcg.com (CC0)
- Kenney: https://kenney.nl (CC0)
- Sketchfab: lọc CC0/CC-BY, kiểm tra từng model.

## Không commit

- File > 20 MB (dùng Git LFS).
- Asset không rõ license.
- Nhạc/video tải từ nền tảng streaming.
