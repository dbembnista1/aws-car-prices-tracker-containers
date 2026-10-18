import json
import os
import random
import re
import time
from datetime import datetime, timezone

import boto3
import requests
from botocore.exceptions import ClientError
from bs4 import BeautifulSoup

TABLE_NAME = os.environ["TABLE_NAME"]
TARGETS_BUCKET = os.environ["TARGETS_BUCKET"]
TARGETS_KEY = os.environ["TARGETS_KEY"]

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)

PETROLONLY_SUFFIX = "-petrolonly"
PRICE_MIN = 1000
PRICE_MAX = 10_000_000
NEXT_DATA_RE = re.compile(
    r'<script[^>]*id=["\']__NEXT_DATA__["\'][^>]*>(.*?)</script>',
    re.IGNORECASE | re.DOTALL,
)
H3_PRICE_RE = re.compile(r"^\s*(\d[\d\s]{2,})\s*(?:PLN)?\s*$", re.IGNORECASE)


def _as_listing_price(value):
    try:
        price = int(value)
    except (TypeError, ValueError):
        return None
    if PRICE_MIN <= price <= PRICE_MAX:
        return price
    return None


def _price_from_amount(amount):
    if not isinstance(amount, dict):
        return None
    currency = str(amount.get("currencyCode") or "PLN").upper()
    if currency not in ("PLN", ""):
        return None
    if amount.get("units") is not None:
        return _as_listing_price(amount["units"])
    raw = str(amount.get("value") or "").replace(" ", "").replace("\xa0", "")
    return _as_listing_price(raw)


def _prices_from_advert_search(payload):
    if not isinstance(payload, dict):
        return []
    search = payload.get("advertSearch")
    if not isinstance(search, dict):
        return []
    prices = []
    for edge in search.get("edges") or []:
        node = (edge or {}).get("node") or {}
        amount = ((node.get("price") or {}).get("amount") or {})
        price = _price_from_amount(amount)
        if price is not None:
            prices.append(price)
    return prices


def _walk_objects(root):
    stack = [root]
    seen = 0
    while stack and seen < 100000:
        current = stack.pop()
        seen += 1
        if isinstance(current, dict):
            yield current
            stack.extend(current.values())
        elif isinstance(current, list):
            stack.extend(current)


def _maybe_json(value):
    if isinstance(value, dict):
        return value
    if not isinstance(value, str) or not value.startswith("{"):
        return None
    try:
        parsed = json.loads(value)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def prices_from_next_data(html):
    match = NEXT_DATA_RE.search(html)
    if not match:
        return []
    try:
        data = json.loads(match.group(1))
    except json.JSONDecodeError:
        return []

    roots = [data]
    for obj in _walk_objects(data):
        nested = _maybe_json(obj.get("data"))
        if nested:
            roots.append(nested)

    for root in roots:
        for obj in _walk_objects(root):
            prices = _prices_from_advert_search(obj)
            if prices:
                return prices
    return []


def prices_from_h3_text(html):
    soup = BeautifulSoup(html, "html.parser")
    prices = []
    for heading in soup.find_all("h3"):
        text = heading.get_text(strip=True).replace("\xa0", " ")
        match = H3_PRICE_RE.match(text)
        if not match:
            continue
        price = _as_listing_price(match.group(1).replace(" ", ""))
        if price is not None:
            prices.append(price)
    return prices


def extract_listing_prices(html):
    prices = prices_from_next_data(html)
    if prices:
        return prices, "next-data"
    prices = prices_from_h3_text(html)
    if prices:
        return prices, "h3-text"
    return [], "none"


def fetch_car_prices_with_retry(url, max_retries=5, backoff_factor=2):
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/131.0.0.0 Safari/537.36"
        ),
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7",
        "Accept-Encoding": "gzip, deflate, br",
        "Connection": "keep-alive",
    }

    for attempt in range(max_retries):
        try:
            response = requests.get(url, headers=headers, timeout=30)
            status = response.status_code
            if status == 429 or status >= 500:
                print(f"HTTP {status}, retrying ({attempt + 1}/{max_retries})")
            elif status != 200:
                print(f"HTTP {status} ({len(response.content)} bytes)")
                return []
            else:
                prices, source = extract_listing_prices(response.text)
                if prices:
                    print(f"Parsed {len(prices)} listing prices from {source}")
                    return prices
                print(
                    f"No listing prices in HTML (status {status}, "
                    f"{len(response.content)} bytes)"
                )
                return []
        except requests.RequestException as exc:
            print(f"Request failed: {exc}")

        sleep_time = backoff_factor ** attempt + random.uniform(0, 1)
        time.sleep(sleep_time)

    return []


def median_int(prices):
    ordered = sorted(prices)
    n = len(ordered)
    mid = n // 2
    if n % 2 == 1:
        return ordered[mid]
    return int((ordered[mid - 1] + ordered[mid]) / 2)


def aggregate_prices(series, prices):
    if series.endswith(PETROLONLY_SUFFIX):
        return int(sum(prices) / len(prices)), "mean"
    return median_int(prices), "median"


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
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    summary = {}
    last_index = len(targets) - 1
    for index, target in enumerate(targets):
        series = target["series"]
        print(f"Fetching prices for: {series}")
        car_prices = fetch_car_prices_with_retry(target["url"])
        if car_prices:
            value, method = aggregate_prices(series, car_prices)
            print(f"{method} for {series}: {value} PLN ({len(car_prices)} listings)")
            summary[series] = value
            item = {"date": timestamp}
            item.update(summary)
            table.put_item(Item=item)
            print(f"Saved {len(summary)} series for {timestamp}.")
        else:
            print(f"No prices found for {series}.")
        if index < last_index:
            time.sleep(random.uniform(1, 3))
    return summary


def lambda_handler(event, context):
    targets = load_targets()
    summary = fetch_prices_from_targets(targets)
    if not summary:
        raise RuntimeError("No series produced a price; refusing to write an empty item")
    return summary
