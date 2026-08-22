/**
 * Tag normalisation and validation. Tags are compared case-insensitively and
 * without a leading @, so one person can't be impersonated by a different
 * spelling of their name.
 */
const USERNAME_PATTERN = /^[a-zA-Z0-9_]{3,20}$/;

export function normalizeUsername(raw: string): string {
  return raw.trim().replace(/^@/, "").toLowerCase();
}

export function isValidUsername(normalized: string): boolean {
  return USERNAME_PATTERN.test(normalized);
}
