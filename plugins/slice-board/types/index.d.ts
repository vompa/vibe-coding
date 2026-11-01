export type SliceState = 'done' | 'active' | 'ready' | 'blocked'

/** The Claude session that works on a slice, matched by its title "Slice NN …". */
export type SliceSession = { id: string; title: string; link: string; isRunning: boolean }

/** What the loop wrote about a finished slice: .slice-loop/slice-NN.report.json. */
export type SliceReport = {
  title: string
  summary: string
  /** UTC times; `started` is empty for a slice no loop started. */
  started: string
  ended: string
  /** The how-manieth finished slice of the round, of `total`. */
  position: number
  total: number
  commit: string
  files: number
  checks: number
  /** The slice's manual test: start, steps, expected result. */
  manual: string[]
}

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
  report: SliceReport | null
  /** Why the loop parked or left this slice, while that still holds. */
  problem: string | null
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
      /** Which finished slices show their report. */
      openReports: string[]
      /** Whether this session asked for the pane. */
      isWanted: boolean
    }
  }
}
