import React from 'react';
import {Composition} from 'remotion';
import {STORY} from './theme';
import {Tagging, TAGGING_FRAMES} from './stories/Tagging';
import {EventItems, EVENT_ITEMS_FRAMES} from './stories/EventItems';

// One <Composition> per story; its id is the file name in
// shavtzak/web/stories/ (tagging -> stories/tagging.mp4).
// A video story: at most 30 s (STORY.fps * 30 frames). An image story: a
// <Still> with the same width and height, rendered as PNG (render.mjs).
export const Root: React.FC = () => (
  <>
    <Composition
      id="tagging"
      component={Tagging}
      durationInFrames={TAGGING_FRAMES}
      fps={STORY.fps}
      width={STORY.width}
      height={STORY.height}
    />
    <Composition
      id="event-items"
      component={EventItems}
      durationInFrames={EVENT_ITEMS_FRAMES}
      fps={STORY.fps}
      width={STORY.width}
      height={STORY.height}
    />
  </>
);
