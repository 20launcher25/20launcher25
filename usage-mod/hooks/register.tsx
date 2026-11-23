import type { EngineInterface, Register } from 'claude-code'

// Пишет текущую модель и окна лимитов в файл, который показывает Claude Code Launcher:
// %LOCALAPPDATA%\ClaudeCodeLauncher\usage.json

type Limit = { kind: string; percentUsed: number; resetsAt?: string }

let limits: Limit[] = []
let model = ''

// "claude-opus-5-5[1m]" -> "Opus 5.5 1M"
function modelName(id: string): string {
  const wide = /\[1m\]/i.test(id)
  const parts = id.replace(/\[.*?\]/g, '').replace(/^claude-/, '').replace(/-\d{8}$/, '').split('-').filter(Boolean)
  const words = parts.filter(p => !/^\d+$/.test(p)).map(p => p.charAt(0).toUpperCase() + p.slice(1))
  const version = parts.filter(p => /^\d+$/.test(p)).join('.')
  const name = [words.join(' '), version].filter(Boolean).join(' ')
  return (name || id) + (wide ? ' 1M' : '')
}

async function outPath($: EngineInterface): Promise<string | undefined> {
  const base = await $.env.get('LOCALAPPDATA')
  return base ? `${base}\\ClaudeCodeLauncher\\usage.json` : undefined
}

async function refreshModel($: EngineInterface): Promise<void> {
  try {
    model = await $.session.model()
  } catch {
    // модель недоступна: оставляем прежнюю
  }
}

async function save($: EngineInterface): Promise<void> {
  try {
    const out = await outPath($)
    if (!out) return
    const data = {
      model,
      modelName: model ? modelName(model) : '',
      limits: limits.map(l => ({ kind: l.kind, percentUsed: l.percentUsed, resetsAt: l.resetsAt ?? null })),
      updatedAt: new Date().toISOString(),
    }
    await $.fs.write(out, JSON.stringify(data, null, 2))
  } catch {
    // нет доступа к файлу: лаунчер покажет прежние данные
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    try {
      limits = (await $.session.usage()).rateLimits
    } catch {
      // лимиты появятся после первого ответа
    }
    await refreshModel($)
    await save($)
    // раз в минуту: модель могли сменить через /model
    $.clock.every(60_000, () => {
      void refreshModel($).then(() => save($))
    })
    return result
  })

  on('session.measure', async ($, e, next) => {
    if (e.changed.includes('rateLimits')) limits = e.rateLimits
    await refreshModel($)
    await save($)
    return next(e)
  })

  on('prompt.submit', ($, e, next) => {
    void refreshModel($)
      .then(() => save($))
      .catch(() => {})
    return next(e)
  })
}
