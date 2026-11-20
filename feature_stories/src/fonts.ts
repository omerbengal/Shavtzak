import {continueRender, delayRender, staticFile} from 'remotion';

// Rubik, the app's font (shavtzak/assets/fonts), for anything drawn here.
const faces = [
  {weight: '400', file: 'fonts/Rubik-Regular.ttf'},
  {weight: '700', file: 'fonts/Rubik-Bold.ttf'},
];

let loaded = false;
export const loadRubik = () => {
  if (loaded) return;
  loaded = true;
  const handle = delayRender('Rubik');
  Promise.all(
    faces.map((f) => {
      const face = new FontFace('Rubik', `url(${staticFile(f.file)})`, {weight: f.weight});
      return face.load().then((ready) => document.fonts.add(ready));
    }),
  )
    .then(() => continueRender(handle))
    .catch((err) => {
      console.error(err);
      continueRender(handle);
    });
};
