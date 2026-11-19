"""Read-only check of Ahead Plus in App Store Connect: changes nothing.

Prints the in-app purchase's state and which parts App Review needs are missing
(localization, price, availability, review screenshot), and the app versions it could go with.
The Paid Apps Agreement isn't visible through the API: check it in App Store Connect › Business.
"""
import os
import sys
import time

import jwt
import requests

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.ralphgeb.calendarwidgetapp"
PRODUCT_ID = "com.ralphgeb.calendarwidgetapp.unlock"


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"].strip(), "iat": now, "exp": now + 900,
                       "aud": "appstoreconnect-v1"},
                      os.environ["ASC_PRIVATE_KEY"].strip(), algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"})


def get(path):
    r = requests.get(path if path.startswith("http") else API + path,
                     headers={"Authorization": f"Bearer {token()}"}, timeout=60)
    if r.status_code != 200:
        errs = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in r.json().get("errors", [])) if r.text else ""
        return None, f"{r.status_code} {errs}"
    return r.json(), None


def main():
    apps, err = get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if err or not apps["data"]:
        print(f"::error::App {BUNDLE_ID} not found ({err})")
        return 1
    app = apps["data"][0]
    print(f"App: {app['attributes']['name']} ({app['id']})")

    iaps, err = get(f"/v1/apps/{app['id']}/inAppPurchasesV2?limit=50")
    if err:
        print(f"::error::Couldn't list in-app purchases: {err}")
        return 1
    print(f"In-app purchases: {len(iaps['data'])}")
    found = None
    for i in iaps["data"]:
        a = i["attributes"]
        print(f"  - {a.get('productId')} | {a.get('name')} | type {a.get('inAppPurchaseType')} | state {a.get('state')}")
        if a.get("productId") == PRODUCT_ID:
            found = i
    if not found:
        print(f"::error::No in-app purchase with product ID {PRODUCT_ID}. It has to be created in App Store Connect.")
        return 0

    iid = found["id"]
    state = found["attributes"].get("state")
    print(f"\n{PRODUCT_ID}: state {state}")
    if state in ("MISSING_METADATA", "DEVELOPER_ACTION_NEEDED", "REJECTED"):
        print(f"::warning::Ahead Plus is {state}: it can't be bought in the sandbox until it's complete.")

    locs, err = get(f"/v2/inAppPurchases/{iid}/inAppPurchaseLocalizations")
    if locs:
        for l in locs["data"]:
            a = l["attributes"]
            print(f"  localization {a.get('locale')}: name '{a.get('name')}', description '{a.get('description')}', state {a.get('state')}")
        if not locs["data"]:
            print("::warning::No localization (display name and description) yet.")
    else:
        print(f"  localizations: {err}")

    price, err = get(f"/v2/inAppPurchases/{iid}/iapPriceSchedule?include=manualPrices,baseTerritory")
    if price:
        base = price["data"].get("relationships", {}).get("baseTerritory", {}).get("data")
        print(f"  price schedule: base territory {base['id'] if base else 'none'}, {len(price.get('included', []))} price entries")
        if not base:
            print("::warning::No price set.")
    else:
        print(f"  price schedule: {err}")
        print("::warning::No price set (or couldn't read it).")

    avail, err = get(f"/v2/inAppPurchases/{iid}/inAppPurchaseAvailability?include=availableTerritories")
    if avail:
        n = len(avail["data"].get("relationships", {}).get("availableTerritories", {}).get("data", []) or [])
        print(f"  availability: {n} territories listed, new territories {avail['data']['attributes'].get('availableInNewTerritories')}")
    else:
        print(f"  availability: {err}")
        print("::warning::No availability set (or couldn't read it).")

    shot, err = get(f"/v2/inAppPurchases/{iid}/appStoreReviewScreenshot")
    if shot and shot.get("data"):
        a = shot["data"]["attributes"]
        print(f"  review screenshot: {a.get('fileName')} ({(a.get('assetDeliveryState') or {}).get('state')})")
    else:
        print("::warning::No App Review screenshot for Ahead Plus.")

    vers, err = get(f"/v1/apps/{app['id']}/appStoreVersions?limit=5")
    if vers:
        for v in vers["data"]:
            a = v["attributes"]
            print(f"  app version {a.get('versionString')}: {a.get('appStoreState') or a.get('appVersionState')}")
    print("\nThe Paid Apps Agreement can't be read through the API: check App Store Connect › Business.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
