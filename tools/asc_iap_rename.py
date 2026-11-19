"""Names the in-app purchase "Ahead Plus" in App Store Connect (UK and US English), and prints
what it costs in the UK and the US. Safe to run again.
"""
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.ralphgeb.calendarwidgetapp"
PRODUCT_ID = "com.ralphgeb.calendarwidgetapp.unlock"
NAME = "Ahead Plus"
DESCRIPTIONS = {
    "en-GB": "Every widget, theme and colour, for good.",
    "en-US": "Every widget, theme and color, for good.",
}


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 900,
                       "aud": "appstoreconnect-v1"},
                      os.environ["ASC_PRIVATE_KEY"].strip(), algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"})


def call(method, path, body=None):
    r = requests.request(method, path if path.startswith("http") else API + path, json=body,
                         headers={"Authorization": f"Bearer {token()}"}, timeout=60)
    if r.status_code not in (200, 201, 204):
        errs = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in r.json().get("errors", [])) if r.text else ""
        raise RuntimeError(f"{method} {path} -> {r.status_code} {errs}")
    return r.json() if r.text else {}


def main():
    app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]["id"]
    iap = next(i for i in call("GET", f"/v1/apps/{app}/inAppPurchasesV2?limit=50")["data"]
               if i["attributes"]["productId"] == PRODUCT_ID)
    iid = iap["id"]

    # the reference name (only seen in App Store Connect)
    if iap["attributes"].get("name") != NAME:
        call("PATCH", f"/v2/inAppPurchases/{iid}",
             {"data": {"type": "inAppPurchases", "id": iid, "attributes": {"name": NAME}}})
        print(f"Reference name -> {NAME}")

    # the name and description customers see
    locs = {l["attributes"]["locale"]: l for l in call("GET", f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations")["data"]}
    for locale, desc in DESCRIPTIONS.items():
      try:
        if locale in locs:
            call("PATCH", f"/v1/inAppPurchaseLocalizations/{locs[locale]['id']}",
                 {"data": {"type": "inAppPurchaseLocalizations", "id": locs[locale]["id"],
                           "attributes": {"name": NAME, "description": desc}}})
            print(f"{locale}: updated to '{NAME}' / '{desc}'")
        else:
            call("POST", "/v1/inAppPurchaseLocalizations",
                 {"data": {"type": "inAppPurchaseLocalizations",
                           "attributes": {"locale": locale, "name": NAME, "description": desc},
                           "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iid}}}}})
            print(f"{locale}: added '{NAME}' / '{desc}'")
      except RuntimeError as e:
        print(f"::warning::{locale}: couldn't change it now ({e})")

    # what it costs
    for kind in ("manualPrices", "automaticPrices"):
        for terr in ("GBR", "USA"):
            r = requests.get(f"{API}/v1/inAppPurchasePriceSchedules/{iid}/{kind}",
                             params={"filter[territory]": terr, "include": "inAppPurchasePricePoint"},
                             headers={"Authorization": f"Bearer {token()}"}, timeout=60)
            if r.status_code != 200:
                continue
            for p in r.json().get("included", []):
                if p["type"] == "inAppPurchasePricePoints":
                    print(f"Price {terr} ({kind}): {p['attributes'].get('customerPrice')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
