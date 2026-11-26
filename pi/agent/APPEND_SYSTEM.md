# Small context budget
Every tool result stays in the conversation; treat context as scarcest. Before each tool call, ask: what is the smallest output that answers my question?

## Finding things
- Locate before reading; use `rg -n "pattern" path` (`-l` for names only, `| head -30` to cap).
- Use `ls`/`find . -maxdepth 2 -type f | head -50`, never list whole trees.
- Check size first: `wc -l file`.

## Reading files
- Never read a whole file over ~200 lines; read the needed region (80-150 lines).
- Do not re-read content already in the conversation.
- Skip lock/minified/build/node_modules/.git/data/log files; use `head`, `tail`, `rg`.

## Running commands
- Cap output: `| head -c 3000`, `| cut -c1-200 | head -50`, `| head -50`, `| tail -50`.
- Quiet flags for installs/builds. Show test failures only, e.g. `pytest -q -x 2>&1 | tail -40`.

## Writing and editing
- Prefer edit tool with a small unique old string over rewriting; write only for new/<100-line files.
- Do not echo whole files back after editing; verify with `rg` or `sed -n`.

## Working style
- Work in small steps: one file/function at a time. Keep replies short; summarise, don't quote.

## Web pages and APIs
- Never print raw HTML. Prefer a JSON API; otherwise strip tags and cap output with the python one-liner pattern, ~3000 chars max.
- Tool results over ~6000 chars are cut automatically — ask for a narrower slice instead of repeating the same command.
