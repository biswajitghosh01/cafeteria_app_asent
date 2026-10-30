import logging, time
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

access_logger = logging.getLogger("food-court.access")


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    SKIP_PREFIXES = ("/api/health",)

    async def dispatch(self, request: Request, call_next):
        if request.url.path.startswith(self.SKIP_PREFIXES):
            return await call_next(request)
        start = time.perf_counter()
        client = request.client.host if request.client else "-"
        try:
            response = await call_next(request)
            code = response.status_code
        except Exception as exc:
            ms = (time.perf_counter() - start) * 1000
            access_logger.exception(
                "%s %s | 500 | %.1fms | %s | %s",
                request.method, request.url.path, ms, client, exc,
            )
            raise
        ms = (time.perf_counter() - start) * 1000
        access_logger.info(
            "%s %s | %d | %.1fms | %s",
            request.method, request.url.path, code, ms, client,
        )
        return response
