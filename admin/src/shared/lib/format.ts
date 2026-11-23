const dateTime = new Intl.DateTimeFormat('en-MY', {
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
});

export function formatDateTime(iso: string): string {
  return dateTime.format(new Date(iso));
}

/** `RM 25`, `RM 1,250.50`: sen as shown to people. Integer arithmetic only. */
export function formatRm(sen: number): string {
  const ringgit = Math.trunc(sen / 100).toLocaleString('en-MY');
  const cents = sen % 100;
  return cents === 0 ? `RM ${ringgit}` : `RM ${ringgit}.${String(cents).padStart(2, '0')}`;
}

/** Escapes `%`, `_` and `\` so user text is matched literally in `ilike`. */
export function escapeLike(text: string): string {
  return text.replace(/[\\%_]/g, (char) => `\\${char}`);
}

export const PAGE_SIZE = 20;
