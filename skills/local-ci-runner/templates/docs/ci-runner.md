# Chạy CI trên máy mình (runner tự host trong Docker)

<!-- Mẫu từ skill local-ci-runner. Sửa mục 1, 6, 7 theo repo; xóa ghi chú này. -->

Repo riêng tư chỉ có 2.000 phút GitHub Actions mỗi tháng (gói Free). Vì vậy
**mọi check của PR** chạy trên máy của chủ repo. Máy GitHub chỉ còn chạy job
cần Linux x64 (khi PR có nhãn `__HOSTED_LABEL__`) và workflow có secret thật.

## 1. Cái gì chạy ở đâu

| Job | Chạy ở | Ghi chú |
|---|---|---|
| `<tên job>` | Máy mình | |
| `<job chỉ chạy được trên x64>` | GitHub | Chỉ khi PR có nhãn `__HOSTED_LABEL__` (hoặc Run workflow). Không phải check bắt buộc |

- Merge vào `main` không chạy lại CI.
- Muốn chạy lại cho một nhánh: tab Actions → CI → Run workflow.

## 2. Cách hoạt động

- `__RUN_CMD__` hỏi GitHub xem có job nào đang chờ nhãn `__LABEL__`.
- Có thì bật container (`docker/ci-runner/compose.yml`):
  - `runner`: runner chính thức của GitHub, đăng ký kiểu dùng một lần (ephemeral);
  - `postgres` (nếu có): DB trống, dữ liệu nằm trong RAM, dùng chung mạng với
    runner nên test gọi `localhost:5432` như trên GitHub.
- Runner nhận **một** job, chạy xong tự gỡ đăng ký. Script tắt container, rồi
  bật lại cho job kế tiếp. Mỗi job có môi trường sạch.
- Không còn lượt CI nào trong 3 phút thì script thoát. Không có gì chạy nền.
- Container runner **không** có Docker socket, không thấy thư mục nào của máy,
  không mở cổng nào. Nó chỉ có 2 volume cache: gói npm và trình duyệt Playwright.

## 3. Cài đặt (một lần)

1. **Repo phải riêng tư.** Xem mục 6. Script từ chối chạy với repo công khai.
2. Docker Desktop → Settings → Resources: đủ RAM cho build + test (thường 8–12 GB).
3. `gh auth status`: tài khoản chủ repo phải đăng nhập, có scope `repo`.
   Script tự chọn tài khoản trùng tên chủ repo khi máy đăng nhập nhiều tài khoản.
4. Cài hook để mỗi lần `git push` từ máy này tự chạy CI:

   ```bash
   __HOOK_CMD__
   ```

5. Lần đầu build image mất vài phút.

## 4. Dùng hằng ngày

- Đẩy code từ máy này: hook tự bật runner chạy nền. Xem tiến độ:

  ```bash
  tail -f ~/Library/Logs/__REPO_NAME__-ci-runner.log
  ```

- PR đẩy từ nơi khác (phiên Claude trên cloud, nút trên GitHub, Dependabot,
  commit do workflow đẩy): job nằm chờ trên GitHub tối đa 24 giờ. Khi muốn chạy:

  ```bash
  __RUN_CMD__
  ```

- Gọi lệnh hai lần không sao: lần sau thấy lần trước đang chạy thì thoát.
- Docker Desktop đang tắt thì script tự mở (macOS).
- Dừng giữa chừng: `Ctrl+C`, hoặc `docker compose -p __SLUG__-ci-runner down`.

## 5. Khi có trục trặc

| Hiện tượng | Cách xử lý |
|---|---|
| PR đứng ở "Waiting for a runner" | Chạy `__RUN_CMD__` |
| "không lấy được mã đăng ký runner" | `gh auth switch` sang tài khoản chủ repo; token cần scope `repo` |
| GitHub báo phiên bản runner quá cũ | Nâng `FROM` trong `docker/ci-runner/Dockerfile`, chạy lại |
| "Check the runner image's Node" đỏ | File phiên bản Node đã đổi: chạy lại lệnh (image tự build lại) |
| Build hoặc trình duyệt bị kill | Tăng Memory của Docker Desktop |
| Muốn xóa cache | `docker volume rm __SLUG__-ci-runner_npm-cache __SLUG__-ci-runner_playwright-cache` |
| Runner cũ còn hiện trong Settings → Actions → Runners | Xóa tay; runner ephemeral ngoại tuyến GitHub cũng tự dọn sau 1 ngày |

## 6. An toàn

- **Chỉ dùng khi repo riêng tư.** Với repo công khai, người lạ mở PR từ fork có
  thể sửa file workflow để chạy mã của họ trên máy này.
- Job chạy mã của PR (kể cả PR Dependabot) trong container. Container không có
  secret production: CI chỉ dùng mật khẩu và khóa mẫu ghi sẵn trong workflow.
- Mã đăng ký runner hết hạn sau 1 giờ và chỉ truyền qua biến môi trường của container.
- Workflow có secret thật (deploy, backup, job theo lịch đụng dữ liệu thật)
  **không** chạy trên runner này. Giữ `runs-on: ubuntu-latest`.

## 7. Ước tính phút GitHub mỗi tháng

| Phần | Phút |
|---|---|
| Check của PR | 0 |
| Job chỉ chạy trên GitHub (nhãn `__HOSTED_LABEL__`) | … |
| Job theo lịch, deploy | … |
| **Tổng** | **…** |
