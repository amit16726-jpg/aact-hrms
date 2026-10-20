/** Server errors arrive as "CODE: human message". */
export class ApiError extends Error {
  code: string;
  detail: string;
  constructor(code: string, detail: string) {
    super(detail || code);
    this.code = code;
    this.detail = detail;
  }
}

const KNOWN = /^([A-Z][A-Z_]{2,40}):\s*([\s\S]*)$/;

export function parseError(err: unknown): ApiError {
  if (err instanceof ApiError) return err;
  const raw =
    typeof err === 'string'
      ? err
      : err && typeof err === 'object' && 'message' in err
        ? String((err as { message: unknown }).message ?? '')
        : '';
  const m = KNOWN.exec(raw.trim());
  if (m) return new ApiError(m[1], m[2].trim());
  if (/Failed to fetch|NetworkError|network/i.test(raw)) return new ApiError('NETWORK', raw);
  if (/JWT|not signed in|invalid claim/i.test(raw)) return new ApiError('NOT_SIGNED_IN', raw);
  if (/permission denied/i.test(raw)) return new ApiError('NOT_ALLOWED', raw);
  return new ApiError('UNKNOWN', raw || 'Something went wrong.');
}
