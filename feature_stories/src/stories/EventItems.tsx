import React from 'react';
import {AbsoluteFill, Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Background} from '../components/Background';
import {Finger} from '../components/Finger';
import {Phone, PhonePose} from '../components/Phone';
import {Screens} from '../components/Screens';
import {loadRubik} from '../fonts';
import {theme} from '../theme';
import points from '../../public/event_items/points.json';

// Story: "מה יש באירוע" on the admin event cards (V5.6.7, managers only).
// No text, no sound.
// 1. The events screen, cards as they were.
// 2. Each card gets its row of emojis under the Drive / constraints icons.
// 3. Push in on the first card; a long press on an emoji shows its name.
// Screens: shavtzak/tool/story_capture/event_items_capture_test.dart (the
// real EventListScreen with made-up events), coordinates from its points.json.
export const EVENT_ITEMS_FRAMES = 330;

const clamp = {extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const};
type Box = {x: number; y: number; left: number; top: number; width: number; height: number};
const P = points as Record<string, Box>;
const item = (prefix: string) => P[Object.keys(P).find((k) => k.startsWith(prefix))!];

// The first card's row of items (union of its marked rects).
const row0 = Object.keys(P)
  .filter((k) => k.startsWith('row0_'))
  .map((k) => P[k]);
const ROW = {
  left: Math.min(...row0.map((b) => b.left)) - 6,
  top: Math.min(...row0.map((b) => b.top)) - 3,
  right: Math.max(...row0.map((b) => b.left + b.width)) + 6,
  bottom: Math.max(...row0.map((b) => b.top + b.height)) + 3,
};
const donut = item('row0_item1_');

// A pose that puts screen point (fx, fy) at the canvas centre.
const focus = (fx: number, fy: number, scale: number): PhonePose => ({
  x: 540 - (fx - 195) * scale,
  y: 960 - (fy - 422) * scale,
  scale,
});
const WIDE = {fx: 195, fy: 430, scale: 2.15};
const CLOSE = {fx: 175, fy: 318, scale: 3.2};

export const EventItems: React.FC = () => {
  loadRubik();
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  const rise = spring({frame, fps, config: {damping: 16}});
  // Push in after the rows appear, back out at the end.
  const zin = interpolate(frame, [95, 130], [0, 1], {...clamp, easing: Easing.inOut(Easing.cubic)});
  const zout = interpolate(frame, [270, 305], [0, 1], {...clamp, easing: Easing.inOut(Easing.cubic)});
  const z = zin * (1 - zout);
  const p = focus(
    WIDE.fx + (CLOSE.fx - WIDE.fx) * z,
    WIDE.fy + (CLOSE.fy - WIDE.fy) * z,
    WIDE.scale + (CLOSE.scale - WIDE.scale) * z,
  );
  const pose: PhonePose = {...p, y: p.y + (1 - rise) * 500, opacity: rise};

  // The new rows glow as they appear (every card), then the first one again
  // once zoomed in.
  const appear = interpolate(frame, [48, 58, 82, 94], [0, 1, 1, 0], clamp);
  const glowClose = interpolate(frame, [132, 142, 160, 170], [0, 1, 1, 0], clamp);
  const rows = ['row0_', 'row1_', 'row2_'].map((prefix) => {
    const boxes = Object.keys(P).filter((k) => k.startsWith(prefix)).map((k) => P[k]);
    return {
      left: Math.min(...boxes.map((b) => b.left)) - 6,
      top: Math.min(...boxes.map((b) => b.top)) - 3,
      right: Math.max(...boxes.map((b) => b.left + b.width)) + 6,
      bottom: Math.max(...boxes.map((b) => b.top + b.height)) + 3,
    };
  });
  const glowBox = (r: typeof ROW, opacity: number, key: string) =>
    opacity > 0 ? (
      <div
        key={key}
        style={{
          position: 'absolute',
          left: r.left,
          top: r.top,
          width: r.right - r.left,
          height: r.bottom - r.top,
          borderRadius: 10,
          border: `2px solid ${theme.primary}`,
          boxShadow: `0 0 14px ${theme.primary}`,
          opacity,
        }}
      />
    ) : null;

  // The long press: a ring fills around the fingertip, then the name shows.
  const PRESS = 192;
  const hold = interpolate(frame, [PRESS - 14, PRESS], [0, 1], clamp);
  const holdVisible = frame >= PRESS - 14 && frame < PRESS + 6;

  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Background />
      <Phone pose={pose}>
        <Screens
          fade={10}
          steps={[
            {src: 'event_items/01_before.png', at: 0},
            {src: 'event_items/02_after.png', at: 44},
            {src: 'event_items/03_long_press.png', at: PRESS},
            {src: 'event_items/02_after.png', at: 258},
          ]}
        />
        {rows.map((r, i) => glowBox(r, appear, `appear${i}`))}
        {glowBox(ROW, glowClose, 'close')}
        {holdVisible && (
          <svg
            width={40}
            height={40}
            viewBox="0 0 40 40"
            style={{position: 'absolute', left: donut.x - 20, top: donut.y - 20, transform: 'rotate(-90deg)'}}
          >
            <circle
              cx={20}
              cy={20}
              r={17}
              fill="none"
              stroke={theme.primary}
              strokeWidth={3}
              strokeDasharray={2 * Math.PI * 17}
              strokeDashoffset={2 * Math.PI * 17 * (1 - hold)}
              strokeLinecap="round"
            />
          </svg>
        )}
        <Finger
          show={[160, 262]}
          path={[
            {f: 160, x: 170, y: 420},
            {f: 176, x: donut.x, y: donut.y + 6},
            {f: 250, x: donut.x, y: donut.y + 6},
          ]}
          taps={[]}
        />
      </Phone>
    </AbsoluteFill>
  );
};
