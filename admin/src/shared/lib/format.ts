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

/** Escapes `%`, `_` and `\` so user text is matched literally in `ilike`. */
export function escapeLike(text: string): string {
  return text.replace(/[\\%_]/g, (char) => `\\${char}`);
}

export const PAGE_SIZE = 20;
