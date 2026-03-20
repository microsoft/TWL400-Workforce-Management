$src = "c:\Users\euseb\Downloads\40-505-10 TechWorkshop L400 on-demand Workforce Management.md"
$out = "c:\Users\euseb\OneDrive\Documents\GitHub\TWL400-Workforce-Management\lab-split-output.md"

$raw = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)

# Split by === on its own line
$parts = $raw -split '(?m)\r?\n===[ \t]*\r?\n'
$parts = @($parts | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

# ── Heading normalizer for task sections ──────────────────────────────────────
function Normalize-TaskHeadings([string]$content) {
    $lines  = $content -split '\r?\n'
    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line -match '^(#{2,})\s*(.*\S)') {
            $text = $Matches[2].Trim()
            if ($text -match '^Task\s+\d+\s*:') {
                $result.Add("## $text")
            } elseif ($text -match '^(Part\s+)?\d{2}\s*:') {
                $result.Add("#### $text")
            } else {
                $text = [regex]::Replace($text, '^Key\s*steps?\b',  'Key steps',  'IgnoreCase')
                $text = [regex]::Replace($text, '^Key\s*tasks?\b',  'Key tasks',  'IgnoreCase')
                $result.Add("### $text")
            }
        } else {
            $result.Add($line)
        }
    }
    return $result -join "`n"
}

# Fix bare "Description" paragraph label (Task 03 edge case)
function Fix-PlainDescription([string]$content) {
    return [regex]::Replace($content, '(?m)^Description\s*$', '### Description')
}

# ── Classify sections ─────────────────────────────────────────────────────────
$exRe   = [regex]'(?m)^#\s+Exercise\s+(\d+):\s+(.+)$'
$taskRe = [regex]'(?m)^##\s+Task\s+(\d+):\s+(.+)$'

$currentExNum  = $null
$currentExFull = $null
$exNav         = 1        # 1 = index; increments per exercise

$indexChunks = [System.Collections.Generic.List[string]]::new()
$outputItems = [System.Collections.Generic.List[hashtable]]::new()

foreach ($part in $parts) {
    $exM   = $exRe.Match($part)
    $taskM = $taskRe.Match($part)

    $isExercise = $exM.Success -and (-not $taskM.Success -or $exM.Index -lt $taskM.Index)
    $isTask     = $taskM.Success -and (-not $isExercise)

    if ($isExercise) {
        $exNum        = [int]$exM.Groups[1].Value
        $exLabel      = $exM.Groups[2].Value.Trim()
        $currentExNum  = $exNum
        $currentExFull = 'Exercise {0:D2}: {1}' -f $exNum, $exLabel
        $exNav++
        $exFilename = ('exercise{0:D2}.md' -f $exNum)
        $outputItems.Add(@{
            filename  = $exFilename
            type      = 'exercise'
            ex_num    = $exNum
            ex_title  = $currentExFull
            nav_order = $exNav
            content   = $part
        })
    } elseif ($isTask) {
        $taskNum      = [int]$taskM.Groups[1].Value
        $taskLabel    = $taskM.Groups[2].Value.Trim()
        $content      = Fix-PlainDescription $part
        $content      = Normalize-TaskHeadings $content
        $taskFilename = ('exercise{0:D2}-task{1:D2}.md' -f $currentExNum, $taskNum)
        $outputItems.Add(@{
            filename   = $taskFilename
            type       = 'task'
            ex_num     = $currentExNum
            ex_title   = $currentExFull
            task_num   = $taskNum
            task_title = $taskLabel
            nav_order  = $taskNum
            content    = $content
        })
    } else {
        $indexChunks.Add($part)
    }
}

# Prepend index entry
$indexContent = $indexChunks -join "`n`n===`n`n"
$allItems = [System.Collections.Generic.List[hashtable]]::new()
$allItems.Add(@{
    filename = 'index.md'
    type     = 'index'
    content  = $indexContent
})
foreach ($i in $outputItems) { $allItems.Add($i) }

# ── Front-matter builder ──────────────────────────────────────────────────────
function Get-FrontMatter([hashtable]$item) {
    switch ($item.type) {
        'index' {
            return "---`ntitle: Introduction`nlayout: home`nnav_order: 1`n---"
        }
        'exercise' {
            $exTitle = $item.ex_title
            $exNav   = $item.nav_order
            return "---`ntitle: '$exTitle'`nlayout: default`nnav_order: $exNav`nhas_children: true`n---"
        }
        'task' {
            $fmTitle = ('{0:D2}. {1}' -f $item.task_num, $item.task_title)
            $fmNav = $item.nav_order
            $fmParent = $item.ex_title
            return "---`ntitle: '$fmTitle'`nlayout: default`nnav_order: $fmNav`nparent: '$fmParent'`n---"
        }
    }
}

# ── Render combined output ────────────────────────────────────────────────────
$sb = [System.Text.StringBuilder]::new()
foreach ($item in $allItems) {
    [void]$sb.AppendLine("<!-- ==================== FILE: $($item.filename) ==================== -->")
    [void]$sb.AppendLine($(Get-FrontMatter $item))
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine($item.content)
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('===')
    [void]$sb.AppendLine('')
}

[System.IO.File]::WriteAllText($out, $sb.ToString(), [System.Text.Encoding]::UTF8)

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "Written -> $out`n"
Write-Host ('  {0,-44}  {1,-10}  {2}' -f 'File', 'Type', 'nav_order')
Write-Host ('  ' + '-'*62)
foreach ($item in $allItems) {
    $nav = if ($item.ContainsKey('nav_order')) { $item.nav_order } else { 1 }
    Write-Host ('  {0,-44}  {1,-10}  {2}' -f $item.filename, $item.type, $nav)
}
