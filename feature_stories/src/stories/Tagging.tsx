import React from 'react';
import {AbsoluteFill, Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {Background} from '../components/Background';
import {Finger} from '../components/Finger';
import {Phone, PhonePose, toCanvas} from '../components/Phone';
import {Screens} from '../components/Screens';
import {loadRubik} from '../fonts';
import {theme} from '../theme';
import points from '../../public/tagging/points.json';

// Story: @-tagging in a task's updates (V5.6.0). No text, no sound.
// 1. A member opens a task's update, types "@", picks a teammate, sends.
// 2. The "@" flies to the teammate's phone: the task lands in their
//    "המשימות שלי" with the @ mark.
// 3. They tick it done.
// Screens: shavtzak/tool/story_capture/tagging_capture_test.dart (the real
// app widgets with made-up names), coordinates from its points.json.
export const TAGGING_FRAMES = 420;

const clamp = {extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const};
type Box = {x: number; y: number; left: number; top: number; width: number; height: number};
const P = points as Record<string, Box>;

// The "בליץ" button's label comes out in the test font (boxes) in the
// capture: drawn again here in Rubik. [dim]: under a dialog's shade.
const BlitzLabel: React.FC<{dim?: boolean}> = ({dim}) => (
  <div
    style={{
      position: 'absolute',
      left: 34,
      top: 151,
      width: 60,
      height: 21,
      background: dim ? 'rgb(104,111,116)' : 'rgb(227,242,253)',
      color: dim ? 'rgb(10,46,88)' : 'rgb(21,101,192)',
      fontFamily: 'Rubik',
      fontWeight: 700,
      fontSize: 15,
      lineHeight: '21px',
      textAlign: 'center',
      direction: 'rtl',
    }}
  >
    בליץ
  </div>
);

const PHONE_SCALE = 2.35;
// The rows the story is about (y ~ 250-420 pt) sit in the upper middle;
// the phone's empty bottom runs off the canvas.
const CENTER = {x: 540, y: 1120};

const leaveAt = (f: number) =>
  interpolate(f, [182, 214], [0, 1], {...clamp, easing: Easing.inOut(Easing.cubic)});
// A gentle push in while the update dialog is open.
const zoomAt = (f: number) =>
  interpolate(f, [70, 95, 172, 186], [1, 1.08, 1.08, 1], {...clamp, easing: Easing.inOut(Easing.cubic)});

// Phone A (the writer): rises in, then slides out to the left.
const poseA = (f: number, rise: number): PhonePose => {
  const leave = leaveAt(f);
  const zoom = zoomAt(f);
  return {
    x: CENTER.x - leave * 1250,
    y: CENTER.y + (1 - rise) * 500 + (zoom - 1) * 150,
    scale: PHONE_SCALE * zoom * (1 - leave * 0.12),
    opacity: rise,
    rotate: -leave * 8,
  };
};

export const Tagging: React.FC = () => {
  loadRubik();
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();

  const rise = spring({frame, fps, config: {damping: 16}});
  const a = poseA(frame, rise);

  // Phone B (the tagged teammate): slides in from the right.
  const enter = interpolate(frame, [188, 222], [0, 1], {...clamp, easing: Easing.out(Easing.cubic)});
  const settle = interpolate(frame, [372, 400], [0, 1], {...clamp, easing: Easing.inOut(Easing.cubic)});
  const b: PhonePose = {
    x: CENTER.x + (1 - enter) * 1250,
    y: CENTER.y,
    scale: PHONE_SCALE * (1 - settle * 0.06),
    rotate: (1 - enter) * 8,
  };
  const bRest: PhonePose = {x: CENTER.x, y: CENTER.y, scale: PHONE_SCALE};

  // The flying "@": from the send button to the new row.
  const from = toCanvas(poseA(182, 1), P.send.x, P.send.y);
  const to = toCanvas(bRest, P.taggedBox.x - 32, P.taggedBox.y);
  const fly = interpolate(frame, [182, 228], [0, 1], {...clamp, easing: Easing.inOut(Easing.quad)});
  const control = {x: (from.x + to.x) / 2, y: Math.min(from.y, to.y) - 520};
  const bez = (p0: number, p1: number, p2: number) =>
    (1 - fly) ** 2 * p0 + 2 * (1 - fly) * fly * p1 + fly ** 2 * p2;
  const flyVisible = frame >= 180 && frame <= 232;
  const flyScale = interpolate(frame, [180, 192, 220, 230], [0.3, 1.5, 1.2, 0.4], clamp);

  // The new row glows when it lands.
  const glow = frame < 228 ? 0 : interpolate(frame, [228, 238, 278, 290], [0, 1, 1, 0], clamp);
  const pulse = 1 + Math.sin((frame - 228) / 4) * 0.015;

  // The success burst when it is ticked.
  const burst = interpolate(frame, [334, 346], [0, 1], clamp);
  const burstOut = interpolate(frame, [362, 376], [1, 0], clamp);
  const burstAt = toCanvas(bRest, P.taggedBox.x, P.taggedBox.y);

  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <Background />

      {frame < 222 && (
        <Phone pose={a}>
          <Screens
            steps={[
              {src: 'tagging/01_writer_list.png', at: 0, overlay: <BlitzLabel />},
              {src: 'tagging/02_writer_update_open.png', at: 54, overlay: <BlitzLabel dim />},
              {src: 'tagging/03_writer_at_list.png', at: 98, overlay: <BlitzLabel dim />},
              {src: 'tagging/04_writer_at_query.png', at: 112, overlay: <BlitzLabel dim />},
              {src: 'tagging/05_writer_picked.png', at: 136, overlay: <BlitzLabel dim />},
              {src: 'tagging/06_writer_typed.png', at: 152, overlay: <BlitzLabel dim />},
            ]}
          />
          <Finger
            show={[22, 184]}
            path={[
              {f: 22, x: 230, y: 640},
              {f: 46, x: P.quickUpdate.x, y: P.quickUpdate.y},
              {f: 60, x: P.quickUpdate.x, y: P.quickUpdate.y},
              {f: 80, x: P.updateField.x + 60, y: P.updateField.y},
              {f: 118, x: P.updateField.x + 60, y: P.updateField.y},
              {f: 130, x: P.pickYossi.x + 70, y: P.pickYossi.y},
              {f: 156, x: P.pickYossi.x + 70, y: P.pickYossi.y},
              {f: 172, x: P.send.x, y: P.send.y},
            ]}
            taps={[50, 86, 132, 176]}
          />
        </Phone>
      )}

      {frame >= 186 && (
        <Phone pose={b}>
          <Screens
            steps={[
              {src: 'tagging/07_tagged_before.png', at: 0, overlay: <BlitzLabel />},
              {src: 'tagging/08_tagged_after.png', at: 226, overlay: <BlitzLabel />},
              {src: 'tagging/09_tagged_done_dialog.png', at: 298, overlay: <BlitzLabel dim />},
              {src: 'tagging/10_tagged_done.png', at: 336, overlay: <BlitzLabel />},
            ]}
          />
          {glow > 0 && (
            <div
              style={{
                position: 'absolute',
                left: P.taggedRow.left,
                top: P.taggedRow.top,
                width: P.taggedRow.width,
                height: P.taggedRow.height,
                borderRadius: 10,
                border: `3px solid ${theme.mention}`,
                boxShadow: `0 0 24px ${theme.mention}`,
                opacity: glow,
                transform: `scale(${pulse})`,
              }}
            />
          )}
          <Finger
            show={[262, 340]}
            path={[
              {f: 262, x: 250, y: 620},
              {f: 286, x: P.taggedBox.x, y: P.taggedBox.y},
              {f: 304, x: P.taggedBox.x, y: P.taggedBox.y},
              {f: 324, x: P.doneConfirm.x, y: P.doneConfirm.y},
            ]}
            taps={[292, 328]}
          />
        </Phone>
      )}

      {flyVisible && (
        <div
          style={{
            position: 'absolute',
            left: bez(from.x, control.x, to.x) - 60,
            top: bez(from.y, control.y, to.y) - 60,
            width: 120,
            height: 120,
            borderRadius: 60,
            background: theme.mention,
            boxShadow: '0 12px 40px rgba(142, 36, 170, 0.45)',
            transform: `scale(${flyScale})`,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: 'white',
            fontFamily: 'Rubik',
            fontWeight: 700,
            fontSize: 72,
            lineHeight: 1,
          }}
        >
          @
        </div>
      )}

      {burst > 0 && burstOut > 0 && (
        <div style={{position: 'absolute', left: burstAt.x, top: burstAt.y, opacity: burstOut}}>
          <div
            style={{
              position: 'absolute',
              width: 260,
              height: 260,
              left: -130,
              top: -130,
              borderRadius: 130,
              border: `6px solid ${theme.success}`,
              transform: `scale(${0.3 + burst * 0.9})`,
              opacity: 1 - burst * 0.6,
            }}
          />
          <div
            style={{
              position: 'absolute',
              width: 150,
              height: 150,
              left: -75,
              top: -75,
              borderRadius: 75,
              background: theme.success,
              boxShadow: '0 12px 40px rgba(76, 175, 80, 0.45)',
              transform: `scale(${spring({frame: frame - 334, fps, config: {damping: 9}})})`,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            <svg width="86" height="86" viewBox="0 0 24 24">
              <path d="M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4z" fill="white" />
            </svg>
          </div>
        </div>
      )}
    </AbsoluteFill>
  );
};
