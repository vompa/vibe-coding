import type { ClientModule } from 'claude-code'

/** How long the pointer rests on a name before its details appear, like a tooltip of the app. */
const DELAY_MS = 600

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
    // The timer runs only while the pointer rests on this name and stops once the details show: a list of names with a
    // timer each, ticking all the time, kept a busy surface from drawing them at all.
    let stopWaiting: (() => void) | null = null
    const stop = () => {
      stopWaiting?.()
      stopWaiting = null
    }
    surface.onPointer(event => {
      const state = now()
      if (event.type === 'enter') {
        stop()
        surface.setState({ ...state, isOver: true, waited: 0 })
        stopWaiting = surface.every(DELAY_MS, () => {
          stop()
          surface.setState({ ...now(), waited: DELAY_MS, isShown: true })
        })
      } else if (event.type === 'leave') {
        stop()
        surface.setState({ ...state, isOver: false, waited: 0, isShown: false })
      } else if (event.type === 'down' && event.button === 'left') {
        surface.setState({ ...state, isPinned: !state.isPinned })
      }
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
