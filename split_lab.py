#!/usr/bin/env python3
"""Split monolithic lab Markdown into Jekyll/GitHub Pages files."""

import re

SRC = r"c:/Users/euseb/Downloads/40-505-10 TechWorkshop L400 on-demand Workforce Management.md"
OUT = r"c:/Users/euseb/OneDrive/Documents/GitHub/TWL400-Workforce-Management/lab-split-output.md"

with open(SRC, 'r', encoding='utf-8') as f:
    raw = f.read()

# Split by === on its own line (optional trailing whitespace)
parts = re.split(r'\n===[ \t]*\n', raw)
parts = [p.strip() for p in parts if p.strip()]

EXERCISE_RE = re.compile(r'^#\s+Exercise\s+(\d+):\s+(.+)$', re.MULTILINE)
TASK_RE     = re.compile(r'^##\s+Task\s+(\d+):\s+(.+)$',     re.MULTILINE)


def normalize_task_headings(content: str) -> str:
    """Normalize heading levels inside a task section.

    Rules (applied to h2+ headings):
      - ## Task NN: ...         → ## Task NN: ...   (task title, unchanged)
      - NN: ... / Part NN: ... → #### NN: ...       (numbered subtask)
      - everything else         → ### text           (structural / named subsection)
    Also fixes 'Keysteps' / 'Keytasks' spacing.
    """
    def repl(m):
        text = m.group(2).strip()

        # Task title: keep at ##
        if re.match(r'^Task\s+\d+\s*:', text, re.IGNORECASE):
            return f'## {text}'

        # Numbered subtask: 01: ..., 02: ..., Part 01: ...
        if re.match(r'^(Part\s+)?\d{2}\s*:', text):
            return f'#### {text}'

        # Structural / named subsection → h3
        text = re.sub(r'^Key\s*steps?\b', 'Key steps', text, flags=re.IGNORECASE)
        text = re.sub(r'^Key\s*tasks?\b',  'Key tasks',  text, flags=re.IGNORECASE)
        return f'### {text}'

    # Match ## or deeper (zero or more spaces after hashes, handles '###Key steps')
    return re.sub(r'^(#{2,})\s*(.*\S)', repl, content, flags=re.MULTILINE)


def fix_plain_description(content: str) -> str:
    """Replace bare 'Description' paragraph-label with a ### heading (Task 03 edge case)."""
    return re.sub(r'^Description\s*$', '### Description', content, flags=re.MULTILINE)


# ── Pass: classify each === section ──────────────────────────────────────────
current_ex_num:  int | None = None
current_ex_full: str | None = None   # e.g. "Exercise 01: Create supporting components"
ex_nav = 1   # 1 reserved for index; increments per exercise

index_chunks: list[str] = []
output_items: list[dict] = []

for part in parts:
    ex_m   = EXERCISE_RE.search(part)
    task_m = TASK_RE.search(part)

    is_exercise = ex_m and (not task_m or ex_m.start() < task_m.start())
    is_task     = bool(task_m) and not is_exercise

    if is_exercise:
        ex_num   = int(ex_m.group(1))
        ex_label = ex_m.group(2).strip()
        current_ex_num  = ex_num
        current_ex_full = f'Exercise {ex_num:02d}: {ex_label}'
        ex_nav += 1
        output_items.append({
            'filename':  f'exercise{ex_num:02d}.md',
            'type':      'exercise',
            'ex_num':    ex_num,
            'ex_title':  current_ex_full,
            'nav_order': ex_nav,
            'content':   part,
        })

    elif is_task:
        task_num   = int(task_m.group(1))
        task_label = task_m.group(2).strip()
        content = fix_plain_description(part)
        content = normalize_task_headings(content)
        output_items.append({
            'filename':   f'exercise{current_ex_num:02d}-task{task_num:02d}.md',
            'type':       'task',
            'ex_num':     current_ex_num,
            'ex_title':   current_ex_full,
            'task_num':   task_num,
            'task_title': task_label,
            'nav_order':  task_num,
            'content':    content,
        })

    else:
        index_chunks.append(part)

# ── Build index entry ─────────────────────────────────────────────────────────
index_content = '\n\n===\n\n'.join(index_chunks)
output_items.insert(0, {
    'filename': 'index.md',
    'type':     'index',
    'content':  index_content,
})


# ── Front-matter generators ───────────────────────────────────────────────────
def front_matter(item: dict) -> str:
    if item['type'] == 'index':
        return "---\ntitle: Introduction\nlayout: home\nnav_order: 1\n---"

    if item['type'] == 'exercise':
        return (
            f"---\n"
            f"title: '{item['ex_title']}'\n"
            f"layout: default\n"
            f"nav_order: {item['nav_order']}\n"
            f"has_children: true\n"
            f"---"
        )

    # task
    fm_title = f"{item['task_num']:02d}. {item['task_title']}"
    return (
        f"---\n"
        f"title: '{fm_title}'\n"
        f"layout: default\n"
        f"nav_order: {item['nav_order']}\n"
        f"parent: '{item['ex_title']}'\n"
        f"---"
    )


# ── Render combined output ────────────────────────────────────────────────────
out_lines: list[str] = []
for item in output_items:
    out_lines.append(f"<!-- ==================== FILE: {item['filename']} ==================== -->")
    out_lines.append(front_matter(item))
    out_lines.append('')
    out_lines.append(item['content'])
    out_lines.append('')
    out_lines.append('===')
    out_lines.append('')

result = '\n'.join(out_lines)

with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
    f.write(result)

# ── Summary ───────────────────────────────────────────────────────────────────
print(f"Written → {OUT}\n")
print(f"{'File':<45}  {'Type':<10}  nav_order")
print('-' * 65)
for item in output_items:
    nav = item.get('nav_order', 1)
    print(f"  {item['filename']:<43}  {item['type']:<10}  {nav}")
