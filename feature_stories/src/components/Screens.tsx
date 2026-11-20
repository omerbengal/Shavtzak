import React from 'react';
import {Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {SCREEN} from '../theme';

// Captured app screens, one after another: each fades in over the previous
// one at its frame [at]. [overlay] draws on top of that screen only (fixes,
// highlights), in screen points.
export type ScreenStep = {src: string; at: number; overlay?: React.ReactNode};

export const Screens: React.FC<{steps: ScreenStep[]; fade?: number}> = ({steps, fade = 6}) => {
  const frame = useCurrentFrame();
  return (
    <>
      {steps.map((step, i) => {
        if (frame < step.at && i > 0) return null;
        const opacity = i === 0 ? 1 : interpolate(frame, [step.at, step.at + fade], [0, 1], {
          extrapolateLeft: 'clamp',
          extrapolateRight: 'clamp',
        });
        return (
          <div key={step.src} style={{position: 'absolute', inset: 0, opacity}}>
            <Img src={staticFile(step.src)} style={{width: SCREEN.width, height: SCREEN.height}} />
            {step.overlay}
          </div>
        );
      })}
    </>
  );
};
