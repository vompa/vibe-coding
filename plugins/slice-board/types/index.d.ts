export type SliceState = 'done' | 'active' | 'ready' | 'blocked'

/** The Claude session that works on a slice, matched by its title "Slice NN …". */
export type SliceSession = { id: string; title: string; link: string; isRunning: boolean }

export type SliceRow = {
  nr: string
  slug: string
  name: string
  state: SliceState
  /** Ticks of the five checklist columns (Plan, Tests red, Green, Checks, Commit), from the slice's worktree when it has one. */
  ticks: boolean[]
  /** Dependencies that are not done yet. */
  waitingFor: string[]
  /** Commits on slice-NN ahead of the integration branch. */
  ahead: number
  hasPlan: boolean
  session: SliceSession | null
  /** Started from the pane, its session not found yet. */
  isStarting: boolean
}

export type Board = {
  root: string
  round: string
  integration: string
  rows: SliceRow[]
  updatedAt: number
  problem: string | null
}

declare module 'claude-code' {
  interface PluginState {
    'slice-board': {
      board: Board | null
      /** Which groups of the pane are unfolded. */
      expanded: Record<SliceState, boolean>
    }
  }
}
