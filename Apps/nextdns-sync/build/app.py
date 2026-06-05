from datetime import datetime

import requests
import argparse
import yaml
import time
import os
import logging
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
import threading

# ----------------------------
# Logging
# ----------------------------

LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
VERSION = os.getenv("APP_VERSION", "dev")

logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[logging.StreamHandler(sys.stdout)]
)

log = logging.getLogger("nextdns-sync")
log.info(f"Starting nextdns-sync application v{VERSION}")

# ----------------------------
# Healthcheck server
# ----------------------------

class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, format, *args):
        # Only log healthcheck requests when DEBUG is enabled
        if log.isEnabledFor(logging.DEBUG):
            log.debug("Healthcheck request: %s" % (format % args))
        return

def start_health_server():
    server = HTTPServer(("0.0.0.0", 8080), HealthHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

start_health_server()

# ----------------------------
# Config
# ----------------------------

ADGUARD_FILE = "/app/AdGuardHome.yaml"

NEXTDNS_CONFIG_ID = os.getenv("NEXTDNS_CONFIG_ID")
NEXTDNS_API_KEY = os.getenv("NEXTDNS_API_KEY")
INTERVAL = int(os.getenv("SYNC_INTERVAL_SECONDS", "3600"))

# Validation
if not NEXTDNS_CONFIG_ID:
    log.error("NEXTDNS_CONFIG_ID is required")
    raise RuntimeError("NEXTDNS_CONFIG_ID is required")

if not NEXTDNS_API_KEY:
    log.error("NEXTDNS_API_KEY is required")
    raise RuntimeError("NEXTDNS_API_KEY is required")

BASE_URL = f"https://api.nextdns.io/profiles/{NEXTDNS_CONFIG_ID}/rewrites"

HEADERS = {
    "X-Api-Key": NEXTDNS_API_KEY,
    "Content-Type": "application/json",
    "User-Agent": "nextdns-sync/1.0"
}

REQUEST_TIMEOUT = 10

# ----------------------------
# AdGuard
# ----------------------------

def load_adguard_rewrites():
    log.debug(f"Loading AdGuard rewrites from {ADGUARD_FILE}")
    with open(ADGUARD_FILE, "r") as f:
        data = yaml.safe_load(f)

    rewrites = data.get("filtering", {}).get("rewrites", [])
    log.debug(f"Loaded {len(rewrites)} AdGuard rewrites")

    result = {}
    for r in rewrites:
        domain = r["domain"].rstrip(".").lower()
        answer = r["answer"].rstrip(".").lower()
        result[domain] = answer

    log.debug(f"Normalized AdGuard rewrites: {len(result)} entries")
    return result

# ----------------------------
# NextDNS
# ----------------------------

def get_nextdns_rewrites():
    log.debug(f"Fetching NextDNS rewrites from {BASE_URL}")
    r = requests.get(BASE_URL, headers=HEADERS, timeout=REQUEST_TIMEOUT)
    r.raise_for_status()

    data = r.json()
    rewrites = data.get("data", [])

    log.debug(f"Loaded {len(rewrites)} NextDNS rewrites")

    result = {}
    for r in rewrites:
        domain = r["name"].rstrip(".").lower()
        result[domain] = {
            "id": r["id"],
            "content": r["content"].rstrip(".").lower()
        }

    log.debug(f"Normalized NextDNS rewrites: {len(result)} entries")
    return result

# ----------------------------
# Sync logic
# ----------------------------

def sync_rewrites(adguard, nextdns, dry_run=False):
    log.info("Calculating differences between AdGuard and NextDNS…")

    log.debug(f"AdGuard entries: {len(adguard)}")
    log.debug(f"NextDNS entries: {len(nextdns)}")

    to_add = {}
    to_update = {}
    to_delete = []

    for domain, value in adguard.items():
        if domain not in nextdns:
            log.debug(f"Marking for ADD: {domain} -> {value}")
            to_add[domain] = value
        elif nextdns[domain]["content"] != value:
            log.debug(
                f"Marking for UPDATE: {domain} "
                f"(AdGuard={value}, NextDNS={nextdns[domain]['content']})"
            )
            to_update[domain] = value

    for domain in nextdns:
        if domain not in adguard:
            log.debug(f"Marking for DELETE: {domain}")
            to_delete.append(domain)

    log.info(f"PLAN — ADD={len(to_add)}, UPDATE={len(to_update)}, DELETE={len(to_delete)}")

    if dry_run:
        log.info("DRY RUN (no changes will be applied)")

    # ADD
    for domain, value in to_add.items():
        log.info(f"ADD {domain} -> {value}")
        log.debug(f"POST payload: {{'name': '{domain}', 'content': '{value}'}}")
        if not dry_run:
            requests.post(
                BASE_URL,
                headers=HEADERS,
                json={"name": domain, "content": value},
                timeout=REQUEST_TIMEOUT
            ).raise_for_status()

    # UPDATE
    for domain, value in to_update.items():
        rewrite_id = nextdns[domain]["id"]
        log.info(f"UPDATE {domain} -> {value}")
        log.debug(f"PUT target ID: {rewrite_id}")
        if not dry_run:
            requests.put(
                f"{BASE_URL}/{rewrite_id}",
                headers=HEADERS,
                json={"id": rewrite_id, "name": domain, "content": value},
                timeout=REQUEST_TIMEOUT
            ).raise_for_status()

    # DELETE
    for domain in to_delete:
        rewrite_id = nextdns[domain]["id"]
        log.info(f"DELETE {domain}")
        log.debug(f"DELETE target ID: {rewrite_id}")
        if not dry_run:
            requests.delete(
                f"{BASE_URL}/{rewrite_id}",
                headers=HEADERS,
                timeout=REQUEST_TIMEOUT
            ).raise_for_status()

    log.info("Synchronization completed successfully")

# ----------------------------
# Main
# ----------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Simulate changes")
    args = parser.parse_args()

    start_time = time.time()

    adguard_rewrites = load_adguard_rewrites()
    nextdns_rewrites = get_nextdns_rewrites()

    sync_rewrites(adguard_rewrites, nextdns_rewrites, args.dry_run)

    elapsed = time.time() - start_time
    log.debug(f"Sync duration: {elapsed:.3f} seconds")

    log.info("Sync finished")

def main_loop():
    log.info(f"Synchronization interval set to {INTERVAL} seconds")
    while True:
        try:
            main()
        except Exception as exception:
            log.error(f"Sync failed: {exception}")
        time.sleep(INTERVAL)

if __name__ == "__main__":
    main_loop()
