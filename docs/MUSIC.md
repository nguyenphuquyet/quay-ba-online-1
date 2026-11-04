# NHẠC & TV SÂN KHẤU

Tài liệu này mô tả nguồn nhạc, định dạng được phát, cách đồng bộ và cách thêm
bài mới. Code liên quan:

- `game/scripts/systems/dj_system.gd` — tải thư viện, giải mã audio, phát và sync.
- `game/scripts/systems/tv_system.gd` — màn nhạc DJ, video MP4 và TV thông tin.
- `game/scripts/systems/url_guard.gd` — kiểm tra URL media.
- `game/scripts/autoload/app_config.gd` — cấu hình endpoint nhạc.

## 1. Nguồn nhạc

| Mục | Giá trị |
| --- | --- |
| API | `https://music.nguyenphuquyet.online/api/songs?take=1000` |
| Repo | https://github.com/nguyenphuquyet/NPQ-Music-Web |
| Host media | `https://music.nguyenphuquyet.online` |

Có thể đổi bằng biến môi trường `QBO_MUSIC_API_URL` hoặc tham số
`--music-api=https://host`. Đường dẫn API cố định trong
`AppConfig.MUSIC_SONGS_PATH` (`/api/songs?take=1000`).

## 2. Dữ liệu API

API trả về một mảng, hoặc object có `songs`/`data` là mảng. Mỗi bài có thể dùng
các trường sau (tên khác sẽ được bỏ qua an toàn):

| Trường | Bắt buộc | Ghi chú |
| --- | --- | --- |
| `id` / `_id` | không | Thiếu thì dùng chỉ số mảng; game thêm tiền tố `api_`. |
| `title` | không | Thiếu thì lấy từ tên tệp. |
| `artist` | không | Thiếu thì hiện “Không rõ nghệ sĩ”. |
| `audioUrl` / `url` | **có** | Có thể là URL tuyệt đối hoặc tương đối (`/media/audio/...`). |
| `coverUrl` | không | Ảnh bìa; tương đối cũng được. |
| `duration` | không | Giây; nếu 0 thì UI dựa vào stream thật. |
| `genre` | không | Hiện chưa dùng để lọc. |

URL tương đối được ghép với host API bằng `QBOUrlGuard.absolute_url()`.

## 3. Định dạng được phát

- **Audio:** `.mp3`, `.ogg`, `.oga`, `.wav`.
- **Video TV:** `.mp4`, `.mov`, `.m4v`, `.ogv`.

Các bài `.m4a`/AAC bị **ẩn khỏi playlist** vì Godot không giải mã AAC native.
API hiện có 96 bài, trong đó 71 bài MP3 phát được và 25 bài M4A bị ẩn.

MP4/H.264 dùng addon `native_video` (Windows/macOS/Linux) và cần renderer
Forward+ hoặc Mobile. Trên OpenGL Compatibility video vẫn tải/giải mã nhưng
không hiển thị khung hình; TV sẽ báo rõ thay vì im lặng.

## 4. Cache

| Loại | Nơi lưu | Giới hạn |
| --- | --- | --- |
| Audio đã giải mã | RAM (`_streams`) | Theo phiên chạy |
| Ảnh bìa | RAM (`_cover_cache`) | Theo phiên chạy |
| Video TV | `user://tv_video_cache` | 300 MB/tệp, tổng 1.5 GB (tự xoá tệp cũ nhất) |

Bảng TV trong máy tính của bar hiển thị dung lượng cache và có nút **Xoá cache
video**. Không cho xoá khi TV đang phát video để tránh hỏng stream.

## 5. Đồng bộ trong phòng

Trạng thái DJ được gửi qua `Net.send_dj()`; trạng thái TV qua `Net.send_tv()`.
Server giữ lại state và gửi cho người vào sau trong `cli_welcome`.

- DJ: `track_id`, `title`, `artist`, `url`, `cover_url`, `playing`, `position`,
  `volume`, `duration`, `updated_at`.
- TV: `kind` (`video`/`idle`), `url`, `title`, `playing`, `position`, `volume`,
  `status`, `by`, `updated_at`.

Người điều khiển gửi lại vị trí DJ/TV mỗi 6 giây để client khác bám theo. Khi
nhận state, game cộng thêm thời gian đã trôi qua kể từ `updated_at`; nếu đồng
hồ hai máy lệch quá 15 giây thì bỏ qua phần bù này (tránh seek sai) và trông
vào sync định kỳ.

## 6. Thêm bài hát mới

1. Thêm bài vào repo/CSDL của `NPQ-Music-Web` (upload qua trang quản trị hoặc
   theo hướng dẫn của repo đó).
2. Đảm bảo file audio là MP3/OGG/WAV và có `audioUrl` trả về trong `/api/songs`.
3. Thêm `coverUrl` nếu muốn TV/panel hiện bìa.
4. Trong game, mở **DJ booth** hoặc tab **NHẠC / DJ** của máy tính trong bar,
   bấm **Tải lại thư viện**.
5. Nếu bài mới không xuất hiện, kiểm tra `library_error` trong log
   `[QBO] DJ library: …` và thử gọi thẳng API.

## 7. Lỗi thường gặp

| Hiện tượng | Nguyên nhân / cách xử lý |
| --- | --- |
| `library=0` | API lỗi mạng, sai host, hoặc toàn bộ bài là M4A. Kiểm tra `library_error`. |
| Có bài nhưng bấm phát không ra tiếng | File không phải MP3/OGG/WAV thật, hoặc tải quá 50 MB. |
| TV báo “đã giải mã nhưng không hiển thị” | Máy không có Vulkan/D3D12; chạy Forward+ trên GPU hỗ trợ. |
| Video tải mãi | Host chặn hotlink/CORS ở tầng HTTP; thử URL trực tiếp khác. |
| TV lệch vài giây | Sync định kỳ 6 giây sẽ kéo về; kiểm tra đồng hồ hai máy nếu lệch lớn. |
