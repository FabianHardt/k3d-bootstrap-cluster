---
name: No autonomous commits
description: Never commit without explicit user instruction; user does not want unsolicited git commits
type: feedback
---

Never create git commits unless the user explicitly asks for it with a direct instruction like "commit this" or "erstelle einen Commit".

**Why:** User has stated this clearly multiple times. Committing without being asked is unwanted behavior.

**How to apply:** After completing any code change, documentation update, or file creation — do NOT run git add/commit. Always wait for an explicit commit instruction. Finishing a task (e.g. "Changelog ergänzen") does NOT imply permission to commit.
