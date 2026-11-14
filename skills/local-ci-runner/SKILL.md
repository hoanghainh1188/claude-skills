---
name: local-ci-runner
description: Set up PR checks of a PRIVATE GitHub repo to run on the owner's own machine, in Docker, on an ephemeral self-hosted GitHub Actions runner started on demand (npm run ci:runner + git pre-push hook), so PRs use no GitHub Actions minutes. Use when a private repo hits its free Actions minutes, when the user wants "CI chạy trên máy mình / runner local / self-hosted runner trong Docker", or when starting a new private project that should follow this pattern. Never for public repos.
origin: user (from scaffolding-erp, PR #190 and #204, 2026-11)
---

# Local CI runner (ephemeral self-hosted runner trong Docker)

Mẫu gốc: repo `scaffolding-erp` (`docker/ci-runner/`, `scripts/ci-runner/`,
`.github/workflows/ci.yml`, `visual.yml`, `docs/ops/ci-runner.md`).

## Khi nào dùng

- Repo **riêng tư** trên GitHub, gói Free (2.000 phút/tháng), CI tốn nhiều phút.
- Chủ repo có máy (Mac arm64 hoặc Linux) cài Docker và `gh` đăng nhập bằng tài
  khoản quản trị repo.

**Không dùng cho repo công khai.** Người lạ mở PR từ fork có thể sửa workflow
để chạy mã trên máy chủ repo. Kiểm tra trước:

```bash
gh repo view --json visibility --jq .visibility   # phải là PRIVATE
```

Không phải PRIVATE thì dừng, báo người dùng, không cài. (`install.sh` và
`run.sh` cũng tự từ chối.) Repo sau này chuyển sang công khai thì phải gỡ
runner: đổi `runs-on` về `ubuntu-latest` trước.

## Cách hoạt động (tóm tắt)

- `run.sh` hỏi GitHub API xem có job `queued` mang nhãn runner không.
- Có: lấy registration token (`gh api .../runners/registration-token`), bật
  `docker compose up` (runner + DB tùy chọn). Runner đăng ký `--ephemeral`,
  nhận **một** job, chạy, tự gỡ. Script tắt container, lặp lại cho job kế.
- Không còn run nào trong 3 phút: thoát. Không có daemon chạy nền.
- Kết quả job hiện ở check của PR như runner GitHub (runner tự báo về).
- Hook `pre-push` gọi `start-background.sh` (nohup, log ở
  `~/Library/Logs/<repo>-ci-runner.log`), không bao giờ chặn push.
- Khóa thư mục trong `$TMPDIR` để mỗi máy chỉ một vòng lặp.
- Container: không Docker socket, không mount thư mục máy, không mở cổng;
  chỉ volume cache npm và Playwright.

## Quyết định cho từng repo (hỏi người dùng nếu không suy ra được)

| Điểm | Mặc định | Ghi chú |
|---|---|---|
| Nhãn runner (`--label`) | `<slug>-local` | Phải riêng cho mỗi repo. Ví dụ ERP: `erp-local` |
| Slug (`--slug`) | tên ngắn | Tên compose project `<slug>-ci-runner`, file khóa, volume |
| Tên repo (`--name`) | tên thư mục | Tên file log, dấu nhận diện trong hook |
| Nguồn phiên bản Node (`--node-file`) | `.nvmrc` | `.node-version`, `.tool-versions`; rỗng = không cài Node |
| DB (`--db`) | `none` | `postgres`: container Postgres dữ liệu trong RAM, runner dùng chung mạng (`localhost:5432`). DB khác: chép `compose.postgres.yml` và sửa |
| Trình duyệt (`--browsers`) | rỗng | Ví dụ `"chromium webkit"`: cài gói hệ thống Playwright vào image, phiên bản đọc từ `@playwright/test` trong `package.json` |
| Job giữ trên GitHub | xem dưới | |

**Job phải giữ `runs-on: ubuntu-latest`:**

1. Workflow có **secret thật** (deploy, backup, job theo lịch đụng dữ liệu
   thật, ký/phát hành). Luôn luôn, không ngoại lệ: runner local chạy mã của PR.
2. Job **chỉ chạy được trên Linux x64** (máy Mac là arm64): Edge/Chrome bản
   thương hiệu, ảnh mốc chụp trên x64, binary chỉ có x64. Đặt sau nhãn PR
   (mẫu `hosted-behind-label.example.yml`, ví dụ ERP: nhãn `visual`), không
   phải check bắt buộc.
3. Workflow chạy theo `schedule` hoặc trên `push` vào `main` khi máy có thể tắt:
   cân nhắc giữ hosted (job local chờ tối đa 24 giờ rồi hủy).

Chỉ đọc workflow, không đổi job có secret. Nếu không chắc job nào có secret:
`grep -n 'secrets\.' .github/workflows/*.yml`.

## Các bước

1. **Kiểm tra**: repo riêng tư; `docker info`; `gh auth status` (scope `repo`);
   RAM Docker Desktop đủ (build + E2E thường cần 8–12 GB).
2. **Đọc workflow hiện có** (`.github/workflows/*.yml`): liệt kê job, `runs-on`,
   `services:`, `setup-node`, secret. Chốt các quyết định ở bảng trên.
3. **Chép mẫu** (không ghi đè file có sẵn):

   ```bash
   bash ~/.claude/skills/local-ci-runner/bin/install.sh --repo . \
     --label myapp-local --slug myapp --node-file .nvmrc \
     [--browsers "chromium webkit"] \
     [--db postgres --db-user app --db-password app --db-name app_test] \
     [--hosted-label visual]
   ```

   Ghi ra: `docker/ci-runner/{Dockerfile,entrypoint.sh,compose.yml}`,
   `scripts/ci-runner/{run.sh,start-background.sh,install-hook.sh}`,
   `docs/ops/ci-runner.md`. Script in ra placeholder còn sót (phải là "none").
4. **Sửa workflow** theo "Checklist workflow" dưới.
5. **Thêm lệnh**:
   - Repo Node: thêm vào `package.json` → `scripts`:
     `"ci:runner": "bash scripts/ci-runner/run.sh"`,
     `"ci:runner:hook": "bash scripts/ci-runner/install-hook.sh"`.
   - Không Node: dùng `Makefile` (`ci-runner:` / `ci-runner-hook:`) hoặc gọi
     thẳng `bash scripts/ci-runner/run.sh`. Docs dùng lệnh tương ứng
     (`install.sh` tự chọn khi không có `package.json`).
6. **Dependabot** (khuyên): thêm `package-ecosystem: docker`,
   `directory: /docker/ci-runner` vào `.github/dependabot.yml` để nâng image
   runner (GitHub từ chối runner quá cũ).
7. **Tài liệu**: hoàn thiện `docs/ops/ci-runner.md` (mục 1 bảng job, mục 7
   phút ước tính). Thêm vào `CLAUDE.md`/`README` của repo: CI chạy local, PR
   đẩy từ nơi khác (cloud session, Dependabot, commit do workflow đẩy) cần chạy
   `npm run ci:runner` vì hook không tự gọi.
8. **Nhánh + PR** theo quy trình của repo. Sau khi push, chạy
   `npm run ci:runner` (lần đầu build image vài phút) và xác nhận check xanh.
9. **Branch protection**: tên check bắt buộc giữ nguyên (dùng job gom kết quả
   như `gate` trong mẫu nếu tách job). Check hosted sau nhãn không bắt buộc.
10. **Cài hook** trên máy người dùng (chỉ khi họ đồng ý):
    `npm run ci:runner:hook`. Hook đã có từ trước thì script in dòng cần thêm tay.

## Checklist workflow

Với mỗi job chuyển sang local:

- [ ] `runs-on: [self-hosted, <label>]` (cả job nhỏ như detect changes và gate,
      để PR không tốn phút nào).
- [ ] Bỏ `actions/setup-node` (image có Node theo file phiên bản). Thêm bước
      kiểm Node của image khớp file phiên bản (xem `ci.example.yml`).
- [ ] Bỏ `services:` Postgres; DB của compose ở `localhost:5432` với
      user/mật khẩu/tên DB đã chọn. Biến `DATABASE_URL` trỏ vào đó.
- [ ] Trình duyệt: `npx playwright install <browsers>` (không `--with-deps`,
      gói hệ thống đã ở image). Edge/Chrome thương hiệu không có Linux arm64:
      dùng kênh `chromium` local, bản thương hiệu chạy hosted sau nhãn.
- [ ] Không dùng `secrets.*` (trừ `github.token`). Giá trị mẫu cho CI ghi thẳng
      trong `env:` với chú thích "throwaway, CI-only".
- [ ] `actions/cache` / `cache: npm` của setup-node: bỏ, volume cache đã lo.
- [ ] Job cần `gh`: đã có trong image, truyền `GH_TOKEN: ${{ github.token }}`.
- [ ] Cập nhật chú thích đầu workflow: job chạy ở đâu, trỏ tới `docs/ops/ci-runner.md`.

Job giữ hosted: giữ nguyên `ubuntu-latest`, `setup-node`, `services:`; nếu chỉ
x64 thì chuyển sang workflow riêng có điều kiện nhãn và tạo nhãn
(`gh label create <nhãn>`).

## Đối chiếu với scaffolding-erp

Điền như sau sẽ ra đúng bộ file của ERP (khác biệt duy nhất: template thêm
kiểm tra repo riêng tư, Node/Playwright tùy chọn, bỏ `^`/`~` khỏi phiên bản
Playwright):

```bash
install.sh --repo . --label erp-local --slug erp --name scaffolding-erp \
  --node-file .nvmrc --browsers "chromium webkit" \
  --db postgres --db-user erp --db-password erp --db-name scaffolding_erp_test \
  --db-image postgres:17-alpine --hosted-label visual
```

Phần riêng của ERP (role `erp_app`, `db:roles`, biến E2E, `PW_CHANNEL`) nằm
trong `ci.yml` của repo đó, không thuộc template.

## Sự cố hay gặp

Xem mục 5 của `templates/docs/ci-runner.md`. Thêm:
- Check đứng "Waiting for a runner": chưa ai chạy `ci:runner` (PR đẩy từ nơi
  khác, hoặc hook chưa cài).
- `gh` nhiều tài khoản: `run.sh` lấy token của tài khoản trùng chủ repo.
- Repo của tổ chức: registration token cần quyền admin repo; runner nhóm của
  tổ chức không dùng trong mẫu này.
