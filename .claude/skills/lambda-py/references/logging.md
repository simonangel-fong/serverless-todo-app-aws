# Structured logging

Lambda logs go to CloudWatch. Plain `print` gives you unsearchable text; **JSON
logs** let you filter by request id, route, or status in CloudWatch Logs Insights.
The goal is: for any request, you can find its log line and see what happened,
without ever logging a secret.

## Setup

Use the stdlib `logging` module (not `print`) so levels work and Lambda's runtime
picks it up. Configure once at module load, outside the handler, so it's reused
across warm invocations.

```python
# logging_setup.py
import json, logging, os

class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "level": record.levelname,
            "message": record.getMessage(),
        }
        # Merge structured fields passed via extra=...
        for key, val in getattr(record, "__dict__", {}).items():
            if key in ("request_id", "method", "route", "item_id", "status"):
                payload[key] = val
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload)

def get_logger():
    logger = logging.getLogger("app")
    if not logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(JsonFormatter())
        logger.addHandler(handler)
        logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))
        logger.propagate = False
    return logger
```

## What to log

- **One line per request** at INFO: request id, method, route/item id. Enough to
  trace a request through CloudWatch.
- **Handled errors** at WARNING (validation, not-found) — expected, but useful to
  see rates.
- **Unhandled exceptions** at ERROR with the stack trace, via `log.exception(...)`
  in the last-resort handler. This is what you'll actually debug from.

Pass structured fields through `extra=`:

```python
log.info("request", extra={"request_id": rid, "method": method, "item_id": item_id})
```

## What to NEVER log

- **Tokens, `Authorization` headers, or raw claims.** Log the `sub` (a user id) if
  you need to correlate by user, never the token itself.
- **Full request bodies** if they can contain anything sensitive — log field names
  or a size, not values.
- **Secrets / connection strings / keys.**

A leaked token in CloudWatch is a real credential sitting in a log retained for
weeks. Treat logs as readable by more people than you'd like.

## Consider Powertools for larger projects

`aws-lambda-powertools` provides a batteries-included structured `Logger` (plus
tracing and metrics) and auto-injects Lambda context like the request id and cold-
start flag. For a small handler the ~30 lines above avoid a dependency; for
anything bigger, Powertools is worth it and is the AWS-blessed path. Match the
choice to the project's size and existing dependencies.
