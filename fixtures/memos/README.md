# Memo fixtures

Inputs for the memo bullet locator (SN-302): the locator finds the `- ` line before `![...](<file>)` and rewrites that line only, leaving every other byte untouched. Each file names what it exercises. `placeholders.md` is a memo as an evidence script first drafts it, every caption still `description`; `assets-subbullets.md` is a synthetic memo in a shape real memos have, captures in an `assets/` sub-folder and sub-bullets under a caption, which the locator must accept. `crlf.md` is stored with CRLF on purpose; `.gitattributes` keeps it that way.
