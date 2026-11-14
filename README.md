# claude-skills

Skill cá nhân cho Claude Code. Mỗi thư mục trong `skills/` là một skill.

| Skill | Việc |
|---|---|
| `local-ci-runner` | Chạy check PR của repo **riêng tư** trên máy mình, trong Docker, bằng runner GitHub Actions tự host dùng một lần (`npm run ci:runner` + hook `pre-push`) |

## Cài trên máy mới

```bash
gh repo clone hoanghainh1188/claude-skills ~/Projects/claude-skills
bash ~/Projects/claude-skills/link.sh
```

`link.sh` tạo symlink `~/.claude/skills/<tên>` → `skills/<tên>` cho từng skill
(bỏ qua tên đã có sẵn). Sửa skill ở đây rồi commit, đẩy lên; máy khác `git pull`.
