import { describe, expect, it } from 'vitest';

import { parseReportedChat } from './moderationService';

const valid = {
  conversation_id: 'c1',
  listing_title: 'Casio calculator',
  buyer: { id: 'u1', name: 'Siti', email: 'siti@student.usm.my' },
  seller: { id: 'u2', name: 'Ali', email: 'ali@student.usm.my' },
  closed_at: null,
  messages: [{ id: 1, from: 'buyer', body: 'Hi', created_at: '2026-11-16T09:00:00Z' }],
};

describe('parseReportedChat', () => {
  it('reads the chat, its people and messages', () => {
    const chat = parseReportedChat(valid);
    expect(chat.listingTitle).toBe('Casio calculator');
    expect(chat.buyer).toEqual({ name: 'Siti', email: 'siti@student.usm.my' });
    expect(chat.closedAt).toBeNull();
    expect(chat.messages).toEqual([{ id: 1, from: 'buyer', body: 'Hi', createdAt: '2026-11-16T09:00:00Z' }]);
  });

  it('rejects anything else instead of guessing', () => {
    expect(() => parseReportedChat(null)).toThrow();
    expect(() =>
      parseReportedChat({ ...valid, messages: [{ id: 1, from: 'admin', body: 'x', created_at: 'y' }] }),
    ).toThrow();
    expect(() => parseReportedChat({ ...valid, buyer: null })).toThrow();
  });
});
