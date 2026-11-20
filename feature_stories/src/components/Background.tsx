import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';
import {theme} from '../theme';

// A calm backdrop in the app's blues, two soft circles drifting slowly.
export const Background: React.FC = () => {
  const frame = useCurrentFrame();
  const drift = (speed: number, range: number) => Math.sin(frame / speed) * range;
  return (
    <AbsoluteFill style={{background: `linear-gradient(180deg, #E3F2FD 0%, #FFFFFF 70%)`}}>
      <div
        style={{
          position: 'absolute',
          width: 900,
          height: 900,
          borderRadius: 450,
          left: -300 + drift(60, 40),
          top: -250 + drift(80, 30),
          background: theme.primaryLight,
          opacity: interpolate(frame, [0, 20], [0, 0.45], {extrapolateRight: 'clamp'}),
          filter: 'blur(60px)',
        }}
      />
      <div
        style={{
          position: 'absolute',
          width: 700,
          height: 700,
          borderRadius: 350,
          right: -260 + drift(70, 30),
          bottom: -200 + drift(50, 40),
          background: theme.mentionLight,
          opacity: interpolate(frame, [0, 20], [0, 0.7], {extrapolateRight: 'clamp'}),
          filter: 'blur(60px)',
        }}
      />
    </AbsoluteFill>
  );
};
