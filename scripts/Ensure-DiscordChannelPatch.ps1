$ErrorActionPreference = "Stop"

$userProfilePath = [Environment]::GetFolderPath("UserProfile")
$cachePattern = Join-Path $userProfilePath ".claude\plugins\cache\claude-plugins-official\discord\*\server.ts"
$marketplacePath = Join-Path $userProfilePath ".claude\plugins\marketplaces\claude-plugins-official\external_plugins\discord\server.ts"
$targets = @(
    @(Get-ChildItem -Path $cachePattern -File -ErrorAction SilentlyContinue).FullName
    $marketplacePath
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

if ($targets.Count -eq 0) {
    throw "Discord plugin server.ts was not found."
}

$queuePatch = @'
// GY_QUEUE_PATCH_V1: serialize channel events so concurrent Discord messages
// are delivered as separate Claude turns.
type PendingInbound = {
  content: string
  meta: Record<string, string>
}

const inboundQueue: PendingInbound[] = []
let activeInbound: PendingInbound | undefined
let inboundWatchdog: ReturnType<typeof setTimeout> | undefined

function dispatchNextInbound(): void {
  if (activeInbound || inboundQueue.length === 0) return

  activeInbound = inboundQueue.shift()
  if (!activeInbound) return

  const current = activeInbound
  inboundWatchdog = setTimeout(() => {
    if (activeInbound === current) {
      activeInbound = undefined
      dispatchNextInbound()
    }
  }, 120_000)

  mcp.notification({
    method: 'notifications/claude/channel',
    params: current,
  }).catch(err => {
    process.stderr.write(`discord channel: failed to deliver inbound to Claude: ${err}\n`)
    if (activeInbound === current) {
      clearTimeout(inboundWatchdog)
      activeInbound = undefined
      dispatchNextInbound()
    }
  })
}

function enqueueInbound(content: string, meta: Record<string, string>): void {
  inboundQueue.push({ content, meta })
  dispatchNextInbound()
}

function completeInbound(chatId: string): void {
  if (!activeInbound || activeInbound.meta.chat_id !== chatId) return
  clearTimeout(inboundWatchdog)
  activeInbound = undefined
  setTimeout(dispatchNextInbound, 2_000)
}

'@

$oldInboundNotification = @'
  mcp.notification({
    method: 'notifications/claude/channel',
    params: {
      content,
      meta: {
        chat_id,
        message_id: msg.id,
        user: msg.author.username,
        user_id: msg.author.id,
        ts: msg.createdAt.toISOString(),
        ...(atts.length > 0 ? { attachment_count: String(atts.length), attachments: atts.join('; ') } : {}),
      },
    },
  }).catch(err => {
    process.stderr.write(`discord channel: failed to deliver inbound to Claude: ${err}\n`)
  })
'@

$newInboundNotification = @'
  enqueueInbound(content, {
    chat_id,
    message_id: msg.id,
    user: msg.author.username,
    user_id: msg.author.id,
    ts: msg.createdAt.toISOString(),
    ...(atts.length > 0 ? { attachment_count: String(atts.length), attachments: atts.join('; ') } : {}),
  })
'@

foreach ($target in $targets) {
    $text = [IO.File]::ReadAllText($target).Replace("`r`n", "`n")
    $changed = $false

    if (-not $text.Contains("'anthropic/alwaysLoad': true")) {
        $anchor = "      name: 'reply',`n"
        if (-not $text.Contains($anchor)) {
            throw "Reply tool anchor was not found in $target"
        }
        $text = $text.Replace(
            $anchor,
            "      name: 'reply',`n      _meta: { 'anthropic/alwaysLoad': true },`n"
        )
        $changed = $true
    }

    if (-not $text.Contains("GY_QUEUE_PATCH_V1")) {
        $handlerAnchor = "async function handleInbound(msg: Message): Promise<void> {"
        if (-not $text.Contains($handlerAnchor)) {
            throw "Inbound handler anchor was not found in $target"
        }
        $text = $text.Replace($handlerAnchor, $queuePatch + $handlerAnchor)

        if (-not $text.Contains($oldInboundNotification)) {
            throw "Inbound notification anchor was not found in $target"
        }
        $text = $text.Replace($oldInboundNotification, $newInboundNotification)

        $replyAnchor = "        return { content: [{ type: 'text', text: result }] }"
        if (-not $text.Contains($replyAnchor)) {
            throw "Reply completion anchor was not found in $target"
        }
        $text = $text.Replace(
            $replyAnchor,
            "        completeInbound(chat_id)`n$replyAnchor"
        )
        $changed = $true
    }

    if ($changed) {
        [IO.File]::WriteAllText(
            $target,
            $text,
            [Text.UTF8Encoding]::new($false)
        )
        Write-Output "PATCHED $target"
    }
    else {
        Write-Output "OK $target"
    }
}
