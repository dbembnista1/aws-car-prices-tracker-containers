import json
import os
import random
import re
import time
from datetime import datetime

import boto3
import requests
from bs4 import BeautifulSoup

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
        except requests.RequestException as e:
            print(f"Request failed: {e}")

        sleep_time = backoff_factor ** attempt + random.uniform(0, 1)
        time.sleep(sleep_time)

    return []

def extract_car_company_and_model_from_url(url):
    match = re.search(r'/osobowe/([^/]+)/([^/]+)/', url)
    if match:
        company = match.group(1).capitalize()
        model = match.group(2).upper()
        return company, model
    return "Unknown", "Unknown"

def fetch_prices_from_multiple_urls(urls):
    all_prices = {}
    for url in urls:
        car_company, car_model = extract_car_company_and_model_from_url(url)
        print(f"Fetching prices for: {car_company} {car_model}")
        car_prices = fetch_car_prices_with_retry(url)
        if car_prices:
            average_price = int(sum(car_prices) / len(car_prices))
            print(f"Average price for {car_company} {car_model}: {average_price} PLN")
            all_prices[f"{car_company} {car_model}"] = {
                "prices": car_prices,
                "average_price": average_price
            }
        else:
            print(f"No prices found for {car_company} {car_model}.")
        time.sleep(random.uniform(2, 6))  # To avoid making requests too quickly
    summary = {car: data['average_price'] for car, data in all_prices.items()}
    return summary

# Initialize the DynamoDB resource
dynamodb = boto3.resource('dynamodb', region_name='eu-central-1')
table_name = 'car_prices'
table = dynamodb.Table(table_name)

def add_car_prices(prices_average):
    now = datetime.now()
    # Changed date format to YYYY-MM-DD HH:MM:SS
    timestamp = now.strftime("%Y-%m-%d %H:%M:%S")
    item = {'date': timestamp}
    item.update(prices_average)
    table.put_item(Item=item)
    print("Car prices added to the DB table.")

def lambda_handler(event, context):
    # Retrieve URLs from environment variables
    urls = os.environ.get('URLS', '').split(',')

    if not urls or urls == ['']:
        raise ValueError("No URLs provided in environment variables")

    summary = fetch_prices_from_multiple_urls(urls)
    add_car_prices(summary)
    return summary