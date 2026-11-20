import React from 'react';
import {Easing, interpolate, useCurrentFrame} from 'remotion';

// A fingertip moving over the screen (screen points) and tapping.
// [path]: where it is at which frame; between two stops it glides.
// [taps]: frames of a tap (a press and a ripple). [show]: [in, out] frames.
export type FingerStop = {f: number; x: number; y: number};

export const Finger: React.FC<{path: FingerStop[]; taps: number[]; show: [number, number]}> = ({
  path,
  taps,
  show,
}) => {
  const frame = useCurrentFrame();
  const opacity = interpolate(frame, [show[0], show[0] + 8, show[1] - 8, show[1]], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  if (opacity <= 0) return null;
  const frames = path.map((p) => p.f);
  const ease = {easing: Easing.inOut(Easing.cubic), extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const};
  const x = interpolate(frame, frames, path.map((p) => p.x), ease);
  const y = interpolate(frame, frames, path.map((p) => p.y), ease);
  const tap = taps.find((t) => frame >= t - 4 && frame <= t + 14);
  const press = tap === undefined ? 1 : interpolate(frame, [tap - 4, tap, tap + 6], [1, 0.78, 1], {extrapolateRight: 'clamp'});
  const ripple = tap === undefined ? 0 : interpolate(frame, [tap, tap + 14], [0, 1], {extrapolateRight: 'clamp'});
  return (
    <div style={{position: 'absolute', left: x, top: y, opacity, pointerEvents: 'none'}}>
      {tap !== undefined && (
        <div
          style={{
            position: 'absolute',
            width: 70,
            height: 70,
            left: -35,
            top: -35,
            borderRadius: 35,
            border: '3px solid rgba(25, 118, 210, 0.7)',
            transform: `scale(${0.4 + ripple})`,
            opacity: 1 - ripple,
          }}
        />
      )}
      <div
        style={{
          position: 'absolute',
          width: 34,
          height: 34,
          left: -17,
          top: -17,
          borderRadius: 17,
          background: 'rgba(255,255,255,0.85)',
          border: '2px solid rgba(25, 118, 210, 0.55)',
          boxShadow: '0 4px 12px rgba(0,0,0,0.25)',
          transform: `scale(${press})`,
        }}
      />
    </div>
  );
};
