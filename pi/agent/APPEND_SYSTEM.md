# Small context budget

You run on a local model with a small context window (about 16K tokens), and every
tool result stays in the conversation for all later turns. Treat context as the scarcest
resource. Before each tool call, ask: what is the smallest output that answers my question?

## Finding things
- Locate before reading. Use `rg -n "pattern" path` (or `grep -rn`) to find the exact
  lines; add `-l` to list only file names, and `| head -30` to cap matches.
- List folders with `ls` or `find . -maxdepth 2 -type f | head -50`. Never list a whole tree.
- Check size first when unsure: `wc -l file`.

## Reading files
- Never read a whole file over about 200 lines. Read the region you need with the read
  tool's offset/limit (around 80-150 lines), or `sed -n '120,200p' file`.
- Do not re-read content that is already in the conversation.
- Skip generated or bulky files: lock files, minified code, build output, node_modules,
  .git, data files, logs. Use `head`, `tail` or `rg` on them instead.

## Running commands
- Cap output by size, not just lines: one line of HTML, JSON or minified code can be 50 KB.
  Append `| head -c 3000` (or `| cut -c1-200 | head -50`).
- Cap output: append `| head -50` or `| tail -50`. Use quiet flags (`-q`, `--quiet`,
  `--silent`) for installs and builds.
- For tests, show failures only (for example `pytest -q -x 2>&1 | tail -40`).

## Writing and editing
- Prefer the edit tool with a small, unique old string over rewriting a file.
- Use write only for new files or files under about 100 lines.
- Do not echo whole files back after editing; check with a targeted `rg` or `sed -n`.

## Working style
- Work in small steps: one file or one function at a time.
- Keep replies short. Summarise what you found instead of quoting it.

## Web pages and APIs
- Never print raw HTML. Prefer a JSON API (for Hacker News: `curl -s
  "https://hn.algolia.com/api/v1/search?tags=front_page" | python3 -c "import sys,json;[print(h['title'],'|',h['points'],'|',h['objectID']) for h in json.load(sys.stdin)['hits']]"`).
- Otherwise strip tags and cap: `curl -s URL | python3 -c "import sys,re,html;t=re.sub(r'<[^>]+>',' ',sys.stdin.read());print(html.unescape(re.sub(r'\s+',' ',t))[:3000])"`.
- Tool results longer than about 6,000 characters are cut automatically; if you see the cut
  notice, ask again for a narrower slice instead of repeating the same command.
