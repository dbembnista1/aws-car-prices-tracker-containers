import json
import os
import random
import re
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

TABLE_NAME = os.environ["TABLE_NAME"]
TARGETS_BUCKET = os.environ["TARGETS_BUCKET"]
TARGETS_KEY = os.environ["TARGETS_KEY"]

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

# Same listing price node as data_collector.py (C4 will replace aggregation and query).
PRICE_CLASS_RE = re.compile(
    r'class="[^"]*(?:eg88ra81[^"]*ooa-3ewd90|ooa-3ewd90[^"]*eg88ra81)[^"]*"[^>]*>([^<]+)',
    re.IGNORECASE,
)


def fetch_car_prices_with_retry(url, max_retries=5, backoff_factor=2):
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
        "Connection": "keep-alive",
    }
    request = urllib.request.Request(url, headers=headers)

    for attempt in range(max_retries):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                html = response.read().decode("utf-8", errors="replace")
            prices = parse_prices(html)
            if prices:
                return prices
        except urllib.error.URLError as exc:
            print(f"Request failed: {exc}")

        sleep_time = backoff_factor ** attempt + random.uniform(0, 1)
        time.sleep(sleep_time)

    return []


def parse_prices(html):
    prices = []
    for match in PRICE_CLASS_RE.finditer(html):
        raw = match.group(1).replace(" ", "").replace("PLN", "")
        try:
            prices.append(int(raw))
        except ValueError:
            continue
    return prices


def load_targets():
    try:
        obj = s3.get_object(Bucket=TARGETS_BUCKET, Key=TARGETS_KEY)
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code in ("NoSuchKey", "404"):
            raise ValueError(
                f"Targets catalog s3://{TARGETS_BUCKET}/{TARGETS_KEY} is missing. "
                "Upload collector_targets.json (C3), then retry."
            ) from exc
        raise

    payload = json.loads(obj["Body"].read().decode("utf-8"))
    targets = payload.get("targets")
    if not isinstance(targets, list) or not targets:
        raise ValueError("collector_targets.json: 'targets' must be a non-empty list")

    cleaned = []
    for index, item in enumerate(targets):
        if not isinstance(item, dict):
            raise ValueError(f"targets[{index}] must be an object with 'series' and 'url'")
        series = str(item.get("series") or "").strip()
        url = str(item.get("url") or "").strip()
        if not series or not url:
            raise ValueError(f"targets[{index}] needs non-empty 'series' and 'url'")
        cleaned.append({"series": series, "url": url})
    return cleaned


def fetch_prices_from_targets(targets):
    summary = {}
    for target in targets:
        series = target["series"]
        print(f"Fetching prices for: {series}")
        car_prices = fetch_car_prices_with_retry(target["url"])
        if car_prices:
            average_price = int(sum(car_prices) / len(car_prices))
            print(f"Average price for {series}: {average_price} PLN")
            summary[series] = average_price
        else:
            print(f"No prices found for {series}.")
        time.sleep(random.uniform(2, 6))
    return summary


def add_car_prices(prices_average):
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    item = {"date": timestamp}
    item.update(prices_average)
    table.put_item(Item=item)
    print("Car prices added to the DB table.")


def lambda_handler(event, context):
    targets = load_targets()
    summary = fetch_prices_from_targets(targets)
    if not summary:
        raise RuntimeError("No series produced a price; refusing to write an empty item")
    add_car_prices(summary)
    return summary
