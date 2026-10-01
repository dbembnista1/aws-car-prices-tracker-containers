import json
import os
import random
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


def fetch_car_prices_with_retry(url, max_retries=5, backoff_factor=2):
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
        "Accept-Encoding": "gzip, deflate, br",
        "Connection": "keep-alive",
    }

    for attempt in range(max_retries):
        try:
            response = requests.get(url, headers=headers, timeout=30)
            soup = BeautifulSoup(response.content, "html.parser")
            prices = []
            for item in soup.select("h3.eg88ra81.ooa-3ewd90"):
                price = item.get_text(strip=True).replace(" ", "").replace("PLN", "")
                try:
                    prices.append(int(price))
                except ValueError:
                    continue

            if prices:
                return prices
            print(
                f"No listing prices in HTML (status {response.status_code}, "
                f"{len(response.content)} bytes)"
            )

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
