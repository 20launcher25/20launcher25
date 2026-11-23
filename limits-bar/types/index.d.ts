export type Limit = { kind: string; percentUsed: number; resetsAt?: string }
export type ContextFill = { tokens?: number; window: number; percent?: number }

declare module 'claude-code' {
  interface PluginState {
    'launcher-limits-bar': { limits: Limit[]; tick: number; context: ContextFill | null; model: string }
  }
}
