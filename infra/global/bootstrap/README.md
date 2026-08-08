# Bootstrap — Terraform Remote State

Chạy **thủ công 1 lần duy nhất** trước khi bất kỳ environment nào (`dev`/`staging`/`prod`) có thể dùng remote backend. Không có `backend.tf` — cố tình dùng local state tạm vì bản thân module này tạo ra nơi lưu remote state.

Sau khi apply xong, ghi lại `state_bucket_name` và `lock_table_name` để điền vào `backend.tf` của từng environment (xem `docs/terraform-structure.md` mục 5.1).