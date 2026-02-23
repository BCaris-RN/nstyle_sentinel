export class HttpError extends Error {
  constructor(statusCode, message, code = 'http_error', details) {
    super(message);
    this.name = 'HttpError';
    this.statusCode = statusCode;
    this.code = code;
    this.details = details;
  }
}

export function isHttpError(error) {
  return error instanceof HttpError;
}
