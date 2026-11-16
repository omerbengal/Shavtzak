import {TaskError} from './tasks';

/// A member's own order of the cards on the admin home (`homeCardOrder` on
/// their teamMembers document), written by `teamMember.setHomeCardOrder`.
/// The ids are the app's; the app ignores ones it does not know and adds
/// cards missing from the list, so the backend only checks the shape.
export const MAX_HOME_CARDS = 30;
const MAX_ID_LENGTH = 40;

export function parseHomeCardOrder(value: unknown): string[] {
  if (!Array.isArray(value)) {
    throw new TaskError(400, 'order must be a list of card ids');
  }
  if (value.length > MAX_HOME_CARDS) {
    throw new TaskError(400, `order has more than ${MAX_HOME_CARDS} cards`);
  }
  const order: string[] = [];
  for (const id of value) {
    if (typeof id !== 'string' || id.length === 0 || id.length > MAX_ID_LENGTH) {
      throw new TaskError(400, 'each card id must be a short non-empty string');
    }
    if (!order.includes(id)) order.push(id);
  }
  return order;
}
