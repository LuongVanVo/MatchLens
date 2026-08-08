# Kiến Trúc và Luồng Xử Lý Của Module Messaging

Module `messaging` mà bạn vừa triển khai chính là "Hệ thần kinh giao tiếp" của toàn bộ dự án MatchLens. Nó hoàn toàn hoạt động theo cơ chế **Event-Driven (Hướng sự kiện)** và **Bất đồng bộ (Asynchronous)**.

Dưới đây là bức tranh toàn cảnh về 3 luồng công việc (Workflows) cốt lõi đang chạy thực tế trong module này.

---

## 1. Luồng 1: Xử Lý Video Gốc (Job Dispatcher Flow)
Luồng này được kích hoạt ngay khi người dùng (hoặc Backend) tải thành công một file video gốc lên bucket `raw-videos`.

```mermaid
sequenceDiagram
    participant User as 👤 Người dùng
    participant S3 as 🪣 S3 (raw-videos)
    participant Lambda as ⚡ Lambda (job-dispatcher)
    participant SQS_Jobs as 📨 SQS (video-processing-jobs)
    participant SQS_Status as 📨 SQS (status-callbacks)
    
    User->>S3: 1. Upload file (VD: original.mp4)
    S3-->>Lambda: 2. S3 Event (ObjectCreated) tự kích hoạt Lambda
    activate Lambda
    Lambda->>SQS_Jobs: 3. Đẩy lệnh "Hãy phân tích AI video này!"
    Lambda->>SQS_Status: 4. Đẩy lệnh "Báo cho DB là đang processing nhé!"
    deactivate Lambda
```

**Chi tiết các Service:**
- **S3 Event Trigger:** Theo dõi bucket. Cứ có file rớt vào là gọi Lambda dậy ngay lập tức.
- **Lambda `job-dispatcher`:** Đóng vai trò làm "Người điều phối". Nó không tự phân tích AI (vì rất nặng), nó chỉ tóm lấy thông tin file vừa upload và nhét thành một tin nhắn (Message) rồi ném vào hàng đợi. Nó hoàn toàn không biết kết nối tới Database.
- **SQS `video_processing_jobs`:** Hàng đợi chứa các tờ lệnh. Nó cứ giữ lệnh ở đó cho đến khi con AI Worker (thuộc module `compute` sắp làm tới) rảnh rỗi chạy đến bốc ra xử lý.

---

## 2. Luồng 2: Cập Nhật Trạng Thái (Status Updater Flow)
Bởi vì Job Dispatcher và AI Worker không có quyền chọc vào Database (để bảo mật), mọi hành động muốn đổi trạng thái của Match đều phải gửi thư qua luồng này.

```mermaid
sequenceDiagram
    participant Any as 🤖 AI Worker / Dispatcher
    participant SQS_Status as 📨 SQS (status-callbacks)
    participant Lambda as ⚡ Lambda (status-updater)
    participant RDS as 🗄️ PostgreSQL (RDS)
    
    Any->>SQS_Status: 1. Ném tin nhắn "{status: processing/completed/failed}"
    SQS_Status-->>Lambda: 2. SQS tự động mớm tin nhắn cho Lambda
    activate Lambda
    Lambda->>RDS: 3. Lấy DB Secret, chui qua VPC, chạy lệnh UPDATE
    deactivate Lambda
```

**Chi tiết các Service:**
- **SQS `status-callbacks`**: Hòm thư chuyên nhận báo cáo tiến độ. Bất cứ ai muốn update DB đều thả thư vào đây. Nó đi kèm một **DLQ (Dead Letter Queue)** - nếu thư bị lỗi không đọc được, nó sẽ bị ném vào DLQ để không làm kẹt hàng đợi.
- **Lambda `status-updater`**: Đây là **Thành phần Compute duy nhất ngoài Backend** có quyền lấy Mật khẩu Database (SecretManager) và có dây mạng chọc thẳng vào vùng Kín (Private Subnet) của RDS. Nhiệm vụ của nó là bóc thư từ SQS ra và chạy lệnh UPDATE SQL.

---

## 3. Luồng 3: Tự Động Transcode Video (MediaConvert Trigger Flow)
Luồng này phục vụ cho việc tạo ra những đoạn cắt highlight nhẹ, mượt để có thể phát trực tiếp trên Web/App.

```mermaid
sequenceDiagram
    participant Worker as 🤖 AI Worker
    participant S3 as 🪣 S3 (processed-highlights)
    participant Lambda as ⚡ Lambda (mediaconvert-trigger)
    participant MC as 🎬 AWS MediaConvert
    
    Worker->>S3: 1. Cắt xong, ném file thô vào thư mục "raw-clips/"
    S3-->>Lambda: 2. S3 Event (Chỉ filter "raw-clips/") kích hoạt Lambda
    activate Lambda
    Lambda->>MC: 3. Gọi API CreateJob ra lệnh: "Ép xung file này thành HLS!"
    deactivate Lambda
    MC->>S3: 4. MediaConvert ép xong, ném file xịn vào thư mục "clips/"
```

**Chi tiết các Service:**
- **S3 Event Trigger (có `filter_prefix = "raw-clips/"`)**: Ở đây sự thiên tài của kiến trúc bộc lộ. Bucket này chứa cả file thô và file xịn. Nhờ cái filter này, Lambda chỉ thức dậy khi có file thô rơi vào thư mục `raw-clips/`.
- **Lambda `mediaconvert-trigger`**: Đóng vai trò cầm cái remote bấm nút khởi động máy MediaConvert.
- **AWS MediaConvert**: Cỗ máy ép xung xịn xò của AWS. Nó sẽ lấy file thô từ `raw-clips/`, làm phép thuật, và nhả file xịn ra thư mục `clips/`. Vì file xịn rớt vào thư mục `clips/`, nó không vi phạm cái filter của S3 Event, nên Lambda không bị gọi dậy nữa (tránh được vòng lặp vô hạn gây cháy túi tiền).

---

### 💡 Tổng kết
Module `messaging` này chính là đỉnh cao của thiết kế **Decoupling** (Tách rời các thành phần). Không ai phải đợi ai. Bạn vừa thiết lập xong một hệ thống băng chuyền tự động hoàn hảo, nơi mỗi con Lambda chỉ làm đúng 1 việc nhanh gọn rồi đi ngủ, đảm bảo hiệu suất cực cao và chi phí cực rẻ (gần như miễn phí theo AWS Free Tier)!
