import type { ClientModule } from 'claude-code'

/** How long the pointer rests on a name before its details appear, like a tooltip of the app. */
const DELAY_MS = 600
const TICK_MS = 100

export type NameLine = { text: string; tone: 'strong' | 'dim' | 'subtle' }
export type NameProps = { label: string; isDim: boolean; lines: NameLine[] }
type NameState = { isOver: boolean; waited: number; isShown: boolean; isPinned: boolean }

const resting: NameState = { isOver: false, waited: 0, isShown: false, isPinned: false }

/**
 * A slice's name in the pane: its details appear under it once the pointer has rested on it for a moment and go
 * when it leaves, so moving across the list stays calm; a click keeps them open until the next click.
 */
const SliceName: ClientModule<NameProps, NameState> = (props, surface) => {
  const { Box, Text } = surface.elements
  if (surface.state === undefined) {
    const now = () => surface.state ?? resting
    surface.onPointer(event => {
      const state = now()
      if (event.type === 'enter') surface.setState({ ...state, isOver: true, waited: 0 })
      else if (event.type === 'leave') surface.setState({ ...state, isOver: false, waited: 0, isShown: false })
      else if (event.type === 'down' && event.button === 'left') surface.setState({ ...state, isPinned: !state.isPinned })
    })
    surface.every(TICK_MS, () => {
      const state = now()
      if (!state.isOver || state.isShown) return
      const waited = state.waited + TICK_MS
      surface.setState({ ...state, waited, isShown: waited >= DELAY_MS })
    })
    surface.setState(resting)
  }
  const state = surface.state ?? resting
  const isOpen = state.isShown || state.isPinned
  return Box({
    flexDirection: 'column',
    children: [
      Text({ dimColor: props.isDim, wrap: 'truncate-end', children: props.label }),
      ...(isOpen
        ? props.lines.map(line =>
            Text({
              dimColor: line.tone === 'dim',
              color: line.tone === 'subtle' ? 'subtle' : undefined,
              wrap: 'wrap',
              children: line.text,
            }),
          )
        : []),
    ],
  })
}

export default SliceName
