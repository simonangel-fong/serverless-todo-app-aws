"""Structured JSON logging for CloudWatch.

Configured once at module load (outside the handler) so it's reused across warm
invocations. Emits one JSON object per log record; structured fields are passed
through `extra=`. Never log tokens, raw claims, or full request bodies — only a
user id (sub) for correlation.
"""

import json
import logging
import os

_STRUCTURED_FIELDS = ("request_id", "method", "route", "item_id", "status", "owner_id")


class JsonFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "level": record.levelname,
            "message": record.getMessage(),
        }
        for key in _STRUCTURED_FIELDS:
            if key in record.__dict__:
                payload[key] = record.__dict__[key]
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
