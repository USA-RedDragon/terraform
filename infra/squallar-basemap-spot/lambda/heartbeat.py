"""Weekly heartbeat and staleness alarm for the basemap archive.

Deliberately does NOT check "did the build report an error". Every failure mode
that matters -- spot reclaimed, box wedged, disk full, instance never launched
-- produces NOTHING, not an error. So the only check that covers them is
absence-of-artifact: is there a recent archive?

It reads the status object over plain public HTTPS, which is why this function
needs no R2 credentials at all.

It mails on BOTH outcomes on purpose. A checker that only speaks up on failure
is indistinguishable from a checker that has died, so silence would be
ambiguous. Mailing every run makes silence itself the alarm.
"""

import json
import os
import smtplib
import ssl
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage

STATUS_URL = os.environ["ARCHIVE_BASE_URL"].rstrip("/") + "/status/latest.json"
STALE_AFTER_DAYS = int(os.environ.get("STALE_AFTER_DAYS", "40"))


def _mail(subject: str, body: str) -> None:
    import boto3

    key = boto3.client("ssm").get_parameter(
        Name=os.environ["SMTP_PARAM"], WithDecryption=True
    )["Parameter"]["Value"]

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = os.environ["ALERT_FROM"]
    msg["To"] = os.environ["ALERT_EMAIL"]
    msg.set_content(body)

    # Explicit timeout: the Lambda's own 60s limit would otherwise be the only
    # bound, and that surfaces as an opaque function timeout rather than a
    # readable SMTP error. Same defect as the build script's, which hung a box
    # for hours on 2026-08-28.
    with smtplib.SMTP_SSL(
        os.environ["SMTP_HOST"],
        int(os.environ["SMTP_PORT"]),
        timeout=20,
        context=ssl.create_default_context(),
    ) as s:
        s.login("squallar", key)
        s.send_message(msg)


def handler(event, context):  # noqa: ARG001
    now = datetime.now(timezone.utc)
    try:
        # AN EXPLICIT USER-AGENT IS LOAD-BEARING, NOT POLITENESS.
        # Cloudflare 403s urllib's default `Python-urllib/3.13` before the
        # request ever reaches R2. Measured 2026-08-27 against the real host:
        # the same missing key returns 404 with curl's UA or with none, and 403
        # with urllib's. Without this the heartbeat can NEVER read the status
        # object, so it would report STALE forever -- and an alarm that always
        # fires is as useless as one that never does.
        req = urllib.request.Request(
            STATUS_URL,
            headers={"User-Agent": "squallar-basemap-heartbeat/1 (+https://squallar.app)"},
        )
        with urllib.request.urlopen(req, timeout=20) as r:
            status = json.loads(r.read())
        completed = datetime.fromisoformat(status["completed"].replace("Z", "+00:00"))
        age = now - completed
    except urllib.error.HTTPError as exc:
        # 404 and everything else are DIFFERENT FAILURES and must not be
        # reported as the same thing. A 404 means the build has not published;
        # anything else means we could not ask the question -- a WAF rule, a
        # broken custom-domain binding, a bucket policy change. Reporting the
        # second as "the build never ran" sends somebody to read a CloudWatch
        # log group that has nothing wrong in it.
        if exc.code == 404:
            _mail(
                "squallar basemap: NO ARCHIVE PUBLISHED",
                f"{STATUS_URL} returned 404.\n\n"
                "The status object is written LAST, after the archive verifies\n"
                "through the public path, so its absence means no build has\n"
                "completed. Check the EventBridge schedule and the CloudWatch\n"
                "log group.\n",
            )
            return {"ok": False, "reason": "not-published"}
        _mail(
            f"squallar basemap: STATUS UNREADABLE ({exc.code})",
            f"{STATUS_URL} returned HTTP {exc.code}, which is not 404.\n\n"
            "This is NOT 'the build did not run' -- it means the check could\n"
            "not be made. Look at the R2 custom domain, the bucket's public\n"
            "access, and any Cloudflare WAF or bot rule before looking at the\n"
            "build itself.\n",
        )
        return {"ok": False, "reason": f"http-{exc.code}"}
    except Exception as exc:  # noqa: BLE001
        _mail(
            "squallar basemap: STATUS CHECK FAILED",
            f"Could not reach {STATUS_URL}\n\n{type(exc).__name__}: {exc}\n",
        )
        return {"ok": False, "reason": "unreachable"}

    stale = age > timedelta(days=STALE_AFTER_DAYS)
    gb = status.get("bytes", 0) / 1e9
    detail = (
        f"generation {status.get('generation')}\n"
        f"key        {status.get('key')}\n"
        f"size       {gb:.2f} GB\n"
        f"completed  {status.get('completed')}\n"
        f"age        {age.days} days (stale after {STALE_AFTER_DAYS})\n"
        f"url        {STATUS_URL}\n"
    )

    if stale:
        _mail(
            f"squallar basemap: STALE, {age.days} days old",
            detail + "\nThe last scheduled build did not produce an archive.\n",
        )
    else:
        _mail(f"squallar basemap OK: {age.days} days old", detail)

    return {"ok": not stale, "age_days": age.days}
