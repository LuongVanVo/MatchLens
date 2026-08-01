# Kiến thức toàn tập về AWS Glue & Ứng dụng trong MatchLens

Tài liệu này tổng hợp lý thuyết, khái niệm cốt lõi và cách ứng dụng thực tế dịch vụ AWS Glue vào luồng Data & Analytics của dự án phân tích bóng đá.

---

## 1. Bản chất AWS Glue là gì?

**AWS Glue** là một dịch vụ tích hợp dữ liệu (Data Integration) và ETL (Extract, Transform, Load) **hoàn toàn Serverless** (phi máy chủ).
- **Serverless:** Bạn không cần cấp phát hay quản lý máy chủ (như EC2). Glue tự động cung cấp tài nguyên để chạy ngầm và tính tiền theo giây chạy thực tế.
- **Mục đích chính:** Giúp khám phá, chuẩn bị, làm sạch, biến đổi và kết hợp dữ liệu từ nhiều nguồn khác nhau phục vụ cho việc phân tích (Analytics) hoặc Học máy (Machine Learning).

## 2. Các Khái niệm & Thành phần cốt lõi

1. **Data Store / Data Source (Nguồn dữ liệu):** Nơi chứa dữ liệu thô ban đầu (VD: Amazon S3, RDS, DynamoDB).
2. **Crawler (Trình thu thập thông tin):**
   - **Bản chất:** Là một chương trình tự động đọc lướt qua dữ liệu thô.
   - **Lưu ý quan trọng:** Crawler **KHÔNG** copy hay di chuyển dữ liệu. Nó chỉ quét để nhận diện cấu trúc (Schema - ví dụ: file này có cột gì, kiểu dữ liệu là số hay chữ) và định dạng file (JSON, CSV, Parquet).
3. **Data Catalog (Danh mục dữ liệu):**
   - **Bản chất:** Nơi lưu trữ Metadata (dữ liệu mô tả dữ liệu) do Crawler tạo ra.
   - **Vai trò:** Hoạt động như một cuốn từ điển trung tâm. Các dịch vụ khác (như Glue Job, Amazon Athena) sẽ nhìn vào Catalog này để biết cách truy vấn dữ liệu thô đang nằm ở đâu và có cấu trúc thế nào trên S3.
4. **Job / Script (Công việc xử lý):**
   - **Bản chất:** Là các đoạn mã (thường viết bằng PySpark hoặc Scala) thực thi logic biến đổi dữ liệu (Transform).
   - **Vai trò:** Thực hiện làm sạch dữ liệu, tính toán các chỉ số phức tạp, gom nhóm, hoặc thay đổi định dạng file (ví dụ: từ JSON sang Parquet).
5. **Data Target (Đích đến):** Nơi lưu trữ dữ liệu sau khi đã được Job xử lý sạch sẽ, chuẩn hóa.
6. **Trigger / Schedule / Workflow (Trình kích hoạt & Điều phối):** Dùng để lập lịch chạy các Job (vd: mỗi đêm lúc 12h) hoặc liên kết nhiều Job lại với nhau thành một dây chuyền tuần tự (Workflow).

---

## 3. Ứng dụng AWS Glue vào MatchLens

Trong dự án của chúng ta, luồng xử lý AI (YOLOv11) sẽ sinh ra một lượng khổng lồ dữ liệu tracking thô (Tọa độ X, Y của 22 cầu thủ và bóng trong mỗi khung hình). AWS Glue đóng vai trò là "Nhà máy tinh chế" biến đống tọa độ vô tri này thành các chỉ số chiến thuật phục vụ HLV.

### Bối cảnh & Bài toán
- Hàng ngàn file JSON/CSV chứa tọa độ thô đổ về S3 sau mỗi trận đấu. Hệ thống Dashboard không thể đọc và tính toán trực tiếp đống JSON này một cách nhanh chóng và rẻ tiền được.
- Cần một hệ thống tính toán (để suy ra tổng quãng đường, tốc độ bứt tốc, vùng hoạt động) mà không phải duy trì cấu hình máy chủ 24/7 gây lãng phí.

### Giải pháp với Glue
Sử dụng **AWS Glue ETL Pipeline** để chuyển đổi `raw-tracking-data` thành `curated-data` (Parquet) và tự động tính toán các chỉ số nâng cao ngay khi có trận đấu mới.

---

## 4. Flow thực tế trong dự án (End-to-End ETL Pipeline)

Dưới đây là luồng xử lý (Workflow) từng bước khi dữ liệu chảy qua Glue trong dự án:

### Bước 1: Lấy dữ liệu thô (Ingestion)
- Khi AI Worker (ECS) xử lý xong một video trận đấu, nó ghi các file `tracking_match_123.json` chứa tọa độ từng frame vào bucket đích là `S3://raw-tracking-data`.

### Bước 2: Khám phá cấu trúc (Crawler & Catalog)
- **AWS Glue Crawler** được kích hoạt. Nó bò vào bucket `S3://raw-tracking-data`.
- Nó nhận diện ra cấu trúc file JSON gồm: `match_id (string)`, `player_id (int)`, `frame_index (int)`, `x (float)`, `y (float)`.
- Crawler ghi thông tin này vào **AWS Glue Data Catalog** tạo thành một bảng ảo tên là `tbl_raw_tracking`.

### Bước 3: Nhào nặn và Tính toán (Glue ETL Job)
- Một **Glue Job (PySpark)** được Trigger (kích hoạt). Nó tra cuốn sổ Data Catalog (`tbl_raw_tracking`) để biết cấu trúc, sau đó kéo dữ liệu thật từ S3 lên vùng nhớ của các node Spark để xử lý.
- **Logic Transform (Xử lý trong mã nguồn Job):**
  - **Làm sạch:** Xóa các frame bị lỗi (vd x, y bị null).
  - **Tính quãng đường:** Dùng công thức toán học tính khoảng cách di chuyển (Euclid) giữa 2 tọa độ (x,y) liên tiếp của cùng một `player_id`.
  - **Tính tốc độ:** Lấy khoảng cách chia cho delta thời gian giữa các frame (Dựa trên FPS của video).
  - **Tạo Heatmap data:** Gom nhóm (Aggregate) tần suất xuất hiện của cầu thủ theo từng khu vực tọa độ lưới (grid) trên sân.
- Trước khi xuất ra, Job tự động chuyển đổi định dạng dữ liệu từ JSON sang **Parquet** (định dạng nén lưu trữ theo cột, cực kỳ tối ưu cho việc truy vấn phân tích).

### Bước 4: Lưu trữ dữ liệu chuẩn (Load)
- Kết quả của Job (dữ liệu sạch đã tính toán tổng quãng đường, tốc độ, heatmap data) được ghi vào bucket đích: `S3://curated-data`.

### Bước 5: Tiêu thụ dữ liệu (Consumption)
- Dịch vụ **Amazon Athena** sử dụng Data Catalog làm kim chỉ nam. Backend hoặc QuickSight có thể bắn các câu SQL (VD: `SELECT player_id, sum(distance) FROM curated_data GROUP BY player_id`) thẳng vào Amazon Athena.
- Athena đọc dữ liệu Parquet từ bucket `curated-data` siêu tốc và trả kết quả để vẽ biểu đồ trực quan lên Dashboard cho HLV xem.

---

## 5. Tổng kết Lợi ích khi dùng Glue cho dự án
1. **Serverless & Tiết kiệm chi phí:** Chỉ trả tiền cho 5-10 phút Glue Job được bật lên để tính toán sau mỗi trận đấu. Không mất phí duy trì Server EC2 khi không có ai upload video.
2. **Hiệu năng truy vấn (Performance):** Định dạng Parquet do Glue tạo ra giúp Athena query dữ liệu nhanh gấp hàng chục lần và rẻ hơn đáng kể so với query text/JSON thô.
3. **Thích ứng với thay đổi (Schema Evolution):** Nếu ở Version 2, mô hình AI bổ sung thêm thông số dáng chạy (`pose_estimation`), Crawler sẽ tự động phát hiện và thêm cột mới vào Catalog mà không làm hỏng (crash) hệ thống pipeline hiện tại.

