import React from 'react';
import {SCREEN} from '../theme';

// A phone frame around a 390 x 844 point screen. [x], [y] = its centre on the
// canvas, [scale] = canvas pixels per point. Children are laid out in screen
// points (0..390, 0..844), so captured coordinates (points.json) fit as is.
export const BEZEL = 10;

export type PhonePose = {x: number; y: number; scale: number; opacity?: number; rotate?: number};

export const Phone: React.FC<{pose: PhonePose; children: React.ReactNode}> = ({pose, children}) => {
  const w = SCREEN.width + BEZEL * 2;
  const h = SCREEN.height + BEZEL * 2;
  return (
    <div
      style={{
        position: 'absolute',
        width: w,
        height: h,
        left: pose.x - w / 2,
        top: pose.y - h / 2,
        transform: `scale(${pose.scale}) rotate(${pose.rotate ?? 0}deg)`,
        transformOrigin: 'center center',
        opacity: pose.opacity ?? 1,
        borderRadius: 52,
        background: '#1B1F24',
        boxShadow: '0 30px 80px rgba(13, 71, 161, 0.28), 0 6px 18px rgba(0,0,0,0.18)',
      }}
    >
      <div
        style={{
          position: 'absolute',
          left: BEZEL,
          top: BEZEL,
          width: SCREEN.width,
          height: SCREEN.height,
          borderRadius: 42,
          overflow: 'hidden',
          background: '#FAFAFA',
        }}
      >
        {children}
      </div>
    </div>
  );
};

// A point on the phone's screen, in canvas pixels.
export const toCanvas = (pose: PhonePose, px: number, py: number) => ({
  x: pose.x + (px - SCREEN.width / 2) * pose.scale,
  y: pose.y + (py - SCREEN.height / 2) * pose.scale,
});
