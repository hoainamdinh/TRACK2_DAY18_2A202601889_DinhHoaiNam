# Lakehouse Reflection

- **Học viên:** Đinh Hoài Nam
- **MSSV:** 2A202601889

Trong quá trình thực hiện, tôi nhận thấy hệ thống dễ gặp phải **Anti-pattern #3: Bỏ qua OPTIMIZE (small-file problem)**.

Do các luồng dữ liệu (API calls, agent trajectories) được nạp liên tục dưới dạng micro-batch, hệ thống sẽ nhanh chóng tích tụ hàng ngàn file nhỏ (khoảng 1MB). Nếu không chạy compaction định kỳ, chi phí đọc metadata sẽ tăng vọt khiến hiệu năng truy vấn chậm đi hơn 10 lần. Để khắc phục, team cần thiết lập cron job chạy `OPTIMIZE` và `Z-ORDER` hàng ngày để tối ưu kích thước file dữ liệu.
