# Nhân vật người chơi (GLB/glTF)

`QBOCharacterRig` tự động dùng model trong thư mục này nếu có **đủ khung xương + animation**:

- `player.glb` / `player.gltf` (ưu tiên)
- `anime_girl.glb` / `anime_girl.gltf` (dự phòng)

Nếu không tìm thấy file hợp lệ, game quay về rig procedural cũ
(`game/scripts/player/character_rig.gd`).

## Model đang dùng

**Low Poly Girl** — Sketchfab

- Tác giả: `manoeldarochadeoliveira`
- UID: `4cb87c1d3c3c4b9ea3b4c61ab407500a`
- Giấy phép: **CC Attribution 4.0 (CC-BY 4.0)** — được dùng thương mại, bắt buộc ghi công
- 1.769 vertex, 89 xương, 35 animation (idle, walk, run, jump, sit, nhìn quanh, biểu cảm…)
- File: `player.gltf` + `scene.bin` + `textures/` (baseColor đã hạ về 1024×1024 cho nhẹ VRAM)
- URL: https://sketchfab.com/3d-models/low-poly-girl-4cb87c1d3c3c4b9ea3b4c61ab407500a

### Ghi công bắt buộc

> This work is based on "Low Poly Girl"
> (https://sketchfab.com/3d-models/low-poly-girl-4cb87c1d3c3c4b9ea3b4c61ab407500a)
> by manoeldarochadeoliveira (https://sketchfab.com/manoeldarochadeoliveira)
> licensed under CC-BY-4.0 (http://creativecommons.org/licenses/by/4.0/)

## Quy ước khi thay model

- Hướng nhìn: model quay mặt về `+Z` của file gốc. Nếu model quay ngược,
  sửa `MODEL_YAW` trong `character_rig.gd` (`PI` ↔ `0`).
- Chiều cao: tự chuẩn hóa về `MODEL_TARGET_HEIGHT` (1.78 m), chân đặt ở `y = 0`.
- Animation: khớp theo tên (không phân biệt hoa thường, bỏ `_`, `-`, `|`).
  Từ khóa cho từng trạng thái nằm ở `STATE_CLIP_KEYS`:
  `idle`, `walk`, `run`, `jump`, `sit`, `dance`, `dj`, `drink`, `computer`.
- Model này không có clip dance/DJ riêng: game dùng `walk_fast` + nhún/lắc root
  cho `dance`, `cycle_talking` cho `dj`/`drink`, `action_button_click` cho `computer`.

## Tự động tải lại từ Sketchfab

```
powershell -ExecutionPolicy Bypass -File tools\asset_import\fetch_sketchfab_character.ps1 -Token <API_TOKEN> -Uid 4cb87c1d3c3c4b9ea3b4c61ab407500a
```

Sau khi đổi model, chạy import:

```
tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path game --editor --quit
```
