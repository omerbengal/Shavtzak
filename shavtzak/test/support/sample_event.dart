import 'task_fixtures.dart';

/// The mockups' event: Tuesday 20 – Wednesday 21 October 2026, seen on
/// Tuesday at 14:40. Shared by the tests of the redesigned tasks screens so
/// they all describe the same day.
///
/// Screen order of [sampleStages]: rooms, setup, lunch, ws, dinner, out, bf.
final sampleNow = DateTime(2026, 10, 20, 14, 40);
final sampleTue = DateTime(2026, 10, 20);
final sampleWed = DateTime(2026, 10, 21);

final sampleEvent = buildEvent(
  id: 'e1',
  name: 'דו יומי הנהלה',
  startDate: sampleTue,
  endDate: sampleWed,
  location: 'מלון רויאל',
);

final stSetup = buildStage(
  id: 'setup',
  title: 'הקמה',
  date: sampleTue,
  startTime: '08:00',
  endTime: '09:00',
);
final stLunch = buildStage(
  id: 'lunch',
  title: 'ארוחת צהריים',
  date: sampleTue,
  startTime: '13:00',
  endTime: '14:00',
);
final stWorkshops = buildStage(
  id: 'ws',
  title: 'סדנאות',
  date: sampleTue,
  startTime: '14:30',
  endTime: '17:00',
  hotelLocation: 'חדרי הסדנה',
);
// A start time only.
final stDinner = buildStage(
  id: 'dinner',
  title: 'ארוחת ערב חגיגית',
  date: sampleTue,
  startTime: '19:30',
  hotelLocation: 'אולם האירועים',
);
// No time at all.
final stRooms = buildStage(id: 'rooms', title: 'חלוקת חדרים', date: sampleTue);
final stBreakfast = buildStage(
  id: 'bf',
  title: 'ארוחת בוקר',
  date: sampleWed,
  startTime: '07:30',
  endTime: '08:30',
);
// No time at all.
final stCheckout = buildStage(id: 'out', title: "צ'ק אאוט", date: sampleWed);

final sampleStages = [
  stSetup,
  stLunch,
  stWorkshops,
  stDinner,
  stRooms,
  stBreakfast,
  stCheckout,
];
