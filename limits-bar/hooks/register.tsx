import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { ContextFill, Limit } from '../types'

// Строка над полем ввода Claude Code: модель, контекст и окна лимитов с временем до сброса.
// Язык берётся из переменной CCL_LANG, которую выставляет Claude Code Launcher (ru / en).

// Только символы из кодовой таблицы Windows (CP437): они есть в любом шрифте терминала.
const FULL = '█'
const EMPTY = '░'
const SEP = '│'
const BAR = 6

type Lang = 'ru' | 'en'
const TEXT = {
  ru: {
    labels: { five_hour: '5ч', seven_day: 'Неделя', spend_limit: 'Расход' } as Record<string, string>,
    context: 'Контекст', window: 'окно', now: 'сейчас', d: 'д', h: 'ч', m: 'м',
    waiting: 'Лимиты и контекст появятся после первого ответа',
  },
  en: {
    labels: { five_hour: '5h', seven_day: 'Week', spend_limit: 'Spend' } as Record<string, string>,
    context: 'Context', window: 'window', now: 'now', d: 'd', h: 'h', m: 'm',
    waiting: 'Limits and context appear after the first reply',
  },
}
let lang: Lang = 'ru'
const t = () => TEXT[lang]

const ORDER = ['five_hour', 'seven_day']

// Окно, которого нет в списке (например, отдельный лимит модели), показываем под понятным именем.
function labelOf(kind: string): string {
  const known = t().labels[kind]
  if (known) return known
  const model = /fable|opus|sonnet|haiku/i.exec(kind)?.[0]
  if (model) return model.charAt(0).toUpperCase() + model.slice(1).toLowerCase()
  return kind.replace(/_/g, ' ')
}
const rank = (kind: string) => (ORDER.includes(kind) ? ORDER.indexOf(kind) : ORDER.length)

const limitsAtom = atom({ plugin: 'launcher-limits-bar', key: 'limits' } as const, [] as Limit[])
const contextAtom = atom({ plugin: 'launcher-limits-bar', key: 'context' } as const, null as ContextFill | null)
const tickAtom = atom({ plugin: 'launcher-limits-bar', key: 'tick' } as const, 0)
const modelAtom = atom({ plugin: 'launcher-limits-bar', key: 'model' } as const, '')

// "claude-fable-5-2" или "claude-opus-5-5[1m]" -> "Fable 5.2" и "Opus 5.5 1M".
function modelName(id: string): string {
  const wide = /\[1m\]/i.test(id)
  const parts = id.replace(/\[.*?\]/g, '').replace(/^claude-/, '').replace(/-\d{8}$/, '').split('-').filter(Boolean)
  const words = parts.filter(part => !/^\d+$/.test(part)).map(part => part.charAt(0).toUpperCase() + part.slice(1))
  const version = parts.filter(part => /^\d+$/.test(part)).join('.')
  const name = [words.join(' '), version].filter(Boolean).join(' ')
  return (name || id) + (wide ? ' 1M' : '')
}

type Row = { key: string; label: string; pct?: number; note: string }

function level(pct: number): 'success' | 'warning' | 'error' {
  return pct >= 80 ? 'error' : pct >= 50 ? 'warning' : 'success'
}

function untilReset(iso?: string): string {
  if (!iso) return ''
  const ms = Date.parse(iso) - Date.now()
  const x = t()
  if (!(ms > 0)) return x.now
  const mins = Math.floor(ms / 60000)
  const d = Math.floor(mins / 1440)
  const h = Math.floor((mins % 1440) / 60)
  const m = mins % 60
  return d > 0 ? `${d}${x.d} ${h}${x.h}` : h > 0 ? `${h}${x.h} ${m}${x.m}` : `${m}${x.m}`
}

function tokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(n % 1_000_000 === 0 ? 0 : 1)}M`
  if (n >= 1000) return `${Math.round(n / 1000)}k`
  return String(n)
}

function contextRow(c: ContextFill | null): Row | null {
  if (!c) return null
  if (c.tokens === undefined || c.percent === undefined) {
    return { key: 'context', label: t().context, note: `${t().window} ${tokens(c.window)}` }
  }
  return { key: 'context', label: t().context, pct: c.percent, note: `${tokens(c.tokens)}/${tokens(c.window)}` }
}

// Отдельного события о смене модели нет, поэтому перечитываем её в нескольких местах.
async function refreshModel($: EngineInterface): Promise<void> {
  try {
    const id = await $.session.model()
    await update($, modelAtom, () => id)
  } catch {
    // модель недоступна: строку просто не показываем
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    try {
      lang = (await $.env.get('CCL_LANG')) === 'en' ? 'en' : 'ru'
    } catch {
      // остаётся русский
    }
    const { rateLimits, context } = await $.session.usage()
    await update($, limitsAtom, () => rateLimits)
    await update($, contextAtom, () => context)
    await refreshModel($)
    // раз в минуту перерисовываем «до сброса» и перечитываем модель
    $.clock.every(60_000, () => {
      void update($, tickAtom, n => n + 1)
      void refreshModel($)
    })
    return result
  })

  on('session.measure', async ($, e, next) => {
    if (e.changed.includes('rateLimits')) await update($, limitsAtom, () => e.rateLimits)
    if (e.changed.includes('context')) await update($, contextAtom, () => e.context)
    await refreshModel($)
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    await refreshModel($)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    await read($, tickAtom)

    const model = await read($, modelAtom)
    const rows: Row[] = []
    const ctx = contextRow(await read($, contextAtom))
    if (ctx) rows.push(ctx)
    for (const l of [...(await read($, limitsAtom))].sort((a, b) => rank(a.kind) - rank(b.kind))) {
      rows.push({ key: l.kind, label: labelOf(l.kind), pct: l.percentUsed, note: untilReset(l.resetsAt) })
    }

    const { Box, Text } = $.ui.resolve(e)

    if (rows.length === 0 && !model) {
      return (
        <Box paddingX={1}>
          <Text dimColor>{t().waiting}</Text>
        </Box>
      )
    }

    const bar = (pct: number | undefined, width: number) => {
      if (pct === undefined) return <Text dimColor>{EMPTY.repeat(width)}</Text>
      const filled = Math.max(0, Math.min(width, Math.round((pct / 100) * width)))
      return (
        <Text>
          <Text color={level(pct)}>{FULL.repeat(filled)}</Text>
          <Text dimColor>{EMPTY.repeat(width - filled)}</Text>
        </Text>
      )
    }

    const percent = (pct: number | undefined) => {
      if (pct === undefined) return <Text dimColor>·</Text>
      const p = Math.round(pct)
      return (
        <Text color={level(p)} weight="bold">
          {`${p}%${p >= 90 ? '!' : ''}`}
        </Text>
      )
    }

    // Одна строка без рамки; при нехватке ширины переносится по блокам
    return (
      <Box paddingX={1} columnGap={1} flexWrap="wrap">
        {model ? (
          <Text color="claude" weight="bold">
            {modelName(model)}
          </Text>
        ) : null}
        {rows.map((r, i) => (
          <Box key={r.key} gap={1}>
            {i > 0 || model ? <Text dimColor>{SEP}</Text> : null}
            <Text weight="bold">{r.label}</Text>
            {bar(r.pct, BAR)}
            {percent(r.pct)}
            {r.note ? <Text dimColor>{r.note}</Text> : null}
          </Box>
        ))}
      </Box>
    )
  })
}
