// The app's colours (shavtzak/lib/core/theme/app_theme.dart and the team
// tasks' style files). Use these, never new ones: a story must look like the app.
export const theme = {
  primary: '#2196F3',
  primaryDark: '#1976D2',
  primaryLight: '#BBDEFB',
  accent: '#FF9800',
  success: '#4CAF50',
  background: '#FAFAFA',
  textPrimary: '#212121',
  // Tags (team_task_mentions.dart: mentionColor / mentionLight).
  mention: '#8E24AA',
  mentionLight: '#F3E5F5',
};

// Every story: portrait, phone-shaped, 30 fps.
export const STORY = {width: 1080, height: 1920, fps: 30};

// The phone the screens were captured on (tool/story_capture): 390 x 844 points.
export const SCREEN = {width: 390, height: 844};
