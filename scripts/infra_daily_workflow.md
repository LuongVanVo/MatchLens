# Sổ Tay Vận Hành Hạ Tầng (Dev Daily Workflow)

Vì dự án của bạn sử dụng kiến trúc Hạ tầng dưới dạng Code (IaC - Terraform) kết hợp với các Script tự động, đây là "Quy trình chuẩn" (SOP) để bạn vận hành hệ thống hàng ngày. Tuân thủ quy trình này sẽ giúp bạn **tiết kiệm 100% tiền hạ tầng khi không dùng** mà **không bao giờ bị mất dữ liệu**.

---

## 🌙 QUY TRÌNH CUỐI NGÀY (TRƯỚC KHI TẮT MÁY)

Hãy làm theo thứ tự từ 1 đến 2 để gói ghém toàn bộ dữ liệu an toàn trước khi "nhấn nút nổ bom" hạ tầng.

### Bước 1: Kéo toàn bộ dữ liệu S3 về máy (Backup)
Mở Terminal, cd vào thư mục gốc của dự án (`D:\MatchLens\`) và chạy script backup bạn vừa viết:

```bash
# Lệnh chạy trên PowerShell
.\scripts\backup-dev-s3.ps1
```
> [!NOTE]  
> Màn hình sẽ hiện log màu vàng báo đang kéo dữ liệu của từng Bucket (raw-videos, tracking, v.v...) về thư mục `./s3-backup/`. Đợi đến khi có dòng chữ màu xanh báo **"Backup toàn bộ S3 hoàn tất!"**.

### Bước 2: Phá hủy Hạ tầng (Destroy)
Lúc này dữ liệu đã an toàn trong ổ cứng máy tính. Bạn tiến hành xóa tài nguyên trên AWS:

```bash
cd infra/environments/dev
terraform destroy -auto-approve
```
> [!TIP]
> Lệnh này sẽ mất khoảng 3-5 phút để AWS xóa sạch sẽ S3, RDS, NAT Gateway,... Bạn có thể đi pha một tách trà, khi quay lại thấy chữ **"Destroy complete!"** là yên tâm tắt máy đi ngủ.

---

## ☀️ QUY TRÌNH SÁNG HÔM SAU (KHI BẮT ĐẦU CODE)

Sáng hôm sau, môi trường AWS của bạn đang hoàn toàn trống rỗng. Hãy làm theo 2 bước sau để "hồi sinh" lại hệ thống.

### Bước 1: Dựng lại Hạ tầng (Apply)
Mở Terminal và vào đúng thư mục môi trường dev:

```bash
cd infra/environments/dev
terraform apply -auto-approve
```
> [!NOTE]  
> AWS sẽ mất khoảng vài phút để xây lại toàn bộ các Buckets mới toanh và các tài nguyên khác. Đợi đến khi báo **"Apply complete!"**.

### Bước 2: Bơm dữ liệu cũ trở lại S3 (Restore)
Lúc này S3 Buckets đang trống rỗng. Mở Terminal khác đứng ở thư mục gốc (`D:\MatchLens\`) và chạy script:

```bash
# Lệnh chạy trên PowerShell
.\scripts\restore-dev-s3.ps1
```
> [!TIP]
> Script sẽ đọc các thư mục bên trong `./s3-backup/` và bơm đúng dữ liệu vào đúng 5 cái Buckets tương ứng trên AWS. Cấu trúc file, đường dẫn Video (VD: `match_id/original.mp4`) sẽ được giữ nguyên 100%.

🎉 **Hoàn tất!** Giờ đây Backend của bạn có thể query lấy URL, và Frontend có thể hiển thị Video y chang như tối hôm qua bạn vừa để lại!
