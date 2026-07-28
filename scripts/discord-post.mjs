const [channelId, ...messageParts] = process.argv.slice(2)
const message = messageParts.join(' ')
const token = process.env.POST_AS_TOKEN

if (!token) {
  console.error('[ERROR] POST_AS_TOKEN이 비어 있습니다.')
  process.exit(1)
}

if (!channelId || !/^\d+$/.test(channelId)) {
  console.error('[ERROR] 올바른 Discord 채널 ID가 필요합니다.')
  process.exit(1)
}

if (!message) {
  console.error('[ERROR] 메시지가 비어 있습니다.')
  process.exit(1)
}

const content = Array.from(message).slice(0, 1900).join('')
const response = await fetch(
  `https://discord.com/api/v10/channels/${channelId}/messages`,
  {
    method: 'POST',
    headers: {
      Authorization: `Bot ${token}`,
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: JSON.stringify({
      content,
      allowed_mentions: { parse: [] },
    }),
  },
)

if (!response.ok) {
  const errorText = await response.text()
  console.error(`[ERROR] HTTP ${response.status}`)
  console.error(errorText)
  process.exit(1)
}

const result = await response.json()
console.log(`[OK] Discord 게시 완료 (HTTP ${response.status}, id=${result.id})`)
