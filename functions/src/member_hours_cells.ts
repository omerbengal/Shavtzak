// The Drive assignments export's cells for a member with hours of their own.
//
// Mirrors the member's card in /user/assignments (memberCardTimeRows in
// user_assignments_screen.dart): the member's own days, their arrival, and
// their departure, each with what the event itself does in brackets. Keep the
// wording of the two in step.

import {customHoursInterval, eventStretch, formatWallMinutes, wallDayKeysTouched, wallTimeMinutes} from './event_stretch';

export interface MemberHoursEventInput {
  /** 'yyyy-MM-dd' of the event's first and last Israel calendar day. */
  firstDayKey: string;
  lastDayKey: string;
  assemblyTime: string;
  startTime: string;
  endTime: string;
  teamEndTime: string;
}

export interface MemberHoursCells {
  /** 'dd/MM/yyyy', followed by the event notes that apply. */
  startDate: string;
  /** '' when the member is there one day (as the export does for one-day events). */
  endDate: string;
  assembly: string;
  /** 'יציאה d.M HH:mm', with the event's end in brackets when it has one. */
  departureNote: string;
}

function dayMonth(dayKey: string): string {
  const [, month, day] = dayKey.split('-');
  return `${Number(day)}.${Number(month)}`;
}

function sheetDate(dayKey: string): string {
  const [year, month, day] = dayKey.split('-');
  return `${day}/${month}/${year}`;
}

/** 'd.M HH:mm' of a wall-clock moment; a moment at 00:00 names its own day. */
function dayAndTime(minutes: number): string {
  const moment = formatWallMinutes(minutes);
  return `${dayMonth(moment.slice(0, 10))} ${moment.slice(11, 16)}`;
}

/**
 * The cells for an assignment's own hours, or null when it has none that can
 * be read (customHoursInterval), in which case the row keeps the event's.
 */
export function memberHoursCells(
  event: MemberHoursEventInput,
  customStartAt: unknown,
  customEndAt: unknown,
): MemberHoursCells | null {
  const window = customHoursInterval(customStartAt, customEndAt);
  // An event whose days cannot be read (bad data) keeps the row as it was.
  if (window == null || event.firstDayKey.length === 0 || event.lastDayKey.length === 0) return null;

  const [ownFirst, ownLast] = wallDayKeysTouched(window);
  const firstNote = ownFirst === event.firstDayKey ? '' : ` (האירוע מ-${dayMonth(event.firstDayKey)})`;
  const lastNote = ownLast === event.lastDayKey ? '' : ` (האירוע עד ${dayMonth(event.lastDayKey)})`;
  const oneDay = ownFirst === ownLast;

  const arrival = ownFirst === event.firstDayKey
    ? formatWallMinutes(window.start).slice(11, 16)
    : dayAndTime(window.start);
  const assembly = event.assemblyTime.trim();

  const stretchEnd = eventStretch({
    firstDay: new Date(`${event.firstDayKey}T00:00:00.000Z`),
    lastDay: new Date(`${event.lastDayKey}T00:00:00.000Z`),
    assemblyTime: event.assemblyTime,
    startTime: event.startTime,
    endTime: event.endTime,
    teamEndTime: event.teamEndTime,
  }).end;
  const stretchEndLabel = wallTimeMinutes(event.teamEndTime) != null
    ? 'סיום צוות משוער'
    : wallTimeMinutes(event.endTime) != null
      ? 'סיום מופע משוער'
      : null;

  return {
    startDate: `${sheetDate(ownFirst)}${firstNote}${oneDay ? lastNote : ''}`,
    endDate: oneDay ? '' : `${sheetDate(ownLast)}${lastNote}`,
    assembly: assembly.length === 0 ? arrival : `${arrival} (התייצבות צוות ${assembly})`,
    departureNote: `יציאה ${dayAndTime(window.end)}` +
      (stretchEndLabel == null ? '' : ` (${stretchEndLabel} ${dayAndTime(stretchEnd)})`),
  };
}
