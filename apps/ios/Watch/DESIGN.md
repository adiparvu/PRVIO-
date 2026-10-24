# PRVIO Watch — design brief (award level)

The bar: an Apple Design Award. Juries reward a distinctive, cohesive theme
carried through color and motion (Tide Guide, 2026 Visuals), effortless
platform-native controls (Moonlitt, 2026 Interaction; Crouton, 2024),
an encouraging tone instead of pressure (Gentler Streak, 2024 Social
Impact), and accessibility from the first line (Guitar Wiz, 2026
Inclusivity). Complexity stays behind calm surfaces.

This brief governs everything the person sees and feels. The plumbing in
`Core/` (store, connector, actions, frozen contract — see ARCHITECTURE.md)
stays; the experience layer (`Design/`, `Features/`, `Widgets/` views) is
rebuilt against this brief.

## The idea: "the sky of the house"

PRVIO's iPhone app already paints a live sky behind every screen. On the
wrist that sky becomes the household's state: the page ground is the
house's sky (payload `skyTop`/`skyBottom`), and its warmth says how the
home is doing — calm when all is clear, a warmer amber dawn when something
waits, a red signal only for real alarms. One theme, carried through
color, motion, haptics and words.

## Signature moments

1. **Home Pulse (Today).** A dial: the house glyph at the center inside the
   pulse ring (health score), the headline sentence under it, four corner
   readouts (tasks, plants, deliveries, session/timer) that jump to their
   page. The house glyph *breathes* when all is clear and *wiggles* once
   when something new needs attention (Reduce Motion: static). Below the
   dial: Next Up and the day's cards.
2. **Next Up.** One card with the single most useful thing right now
   (overdue task → thirsty plant → parcel out for delivery → next task),
   with its one-tap action. Never a list of guilt.
3. **The brief.** A one-sentence, warm headline of the day ("Two things
   today — the basil is thirsty and a parcel arrives by 6"), generated on
   the iPhone by the on-device model where available (rule-based
   fallback), shipped in the payload. The watch never waits for it.
4. **All clear celebration.** Clearing the last task, plant or shopping
   item draws a checkmark on (`drawOn`), plays `.success`, and shows a
   rotating encouraging line. Once per clear, never repeated on reload.
5. **Crown as the instrument.** Pantry quantities adjust with the Digital
   Crown in detents (click haptic per step) and commit on idle; the work
   session clock scrubs nothing — it simply runs, large and calm.
6. **Words that encourage.** "3 open" not "3 OVERDUE"; streaks are
   celebrated ("21 days of a calm home"); overdue is stated plainly with
   a symbol, never shouted.
7. **Smart Stack that earns its place.** A relevance widget ("Now at
   home") appears only when it matters — arriving home, morning water
   window, parcel out for delivery — and stays away otherwise.

## Haptic vocabulary (HIG meanings, nothing else)

| moment | haptic |
|---|---|
| task done, plant watered, delivery received | `.success` |
| shopping item checked, Crown detent | `.click` |
| session start / stop | `.start` / `.stop` |
| command failed, phone unreachable | `.retry` / `.failure` |
| critical sensor alarm | `.notification` |
| all clear celebration | `.success` (once) |

## Motion

Purposeful and brief (≤ 0.35 s, `.snappy`/`.smooth`). Symbol effects
carry meaning: `breathe` = calm, `wiggle` = needs you, `bounce` = done,
`drawOn` = celebration, `pulse` = live session. Reduce Motion replaces all
of it with cross-fades. Always On: animations stop, fills become strokes,
seconds disappear, private text redacts.

## Layout rules

- One list of sections; the app opens on Today. Back is always the system
  button top leading (one level up; the list from a section root). Today's
  top is a dial, list sections are lists, details are infographics.
- Primary list actions in `.bottomBar`; no double tap in lists; double tap only on the fixed work-session screen.
- Text styles only (Dynamic Type), SF Rounded for numerals.
- Every state readable without color: symbol + word.
- VoiceOver: every control has a label and value; the dial reads as one
  summary sentence.

## Accessibility checklist

Dynamic Type to AX sizes without truncating actions; VoiceOver order and
labels; Differentiate Without Color; Reduce Motion; Increase Contrast
(stronger strokes); Always On redaction of chat, emergency and budget.
