"""Jen čtení: zeptá se televize Samsung v domácí síti, kdo je (GET http://IP:8001/api/v2/).

Použití:  python tv_info.py 192.168.1.20 [další IP ...]

Vypíše název, model, MAC a stav režimu vývojáře. Slouží k ověření, že instalujete
do SVÉ televize (a ne do sousedovy na stejné síti).
Pozor: pole developerMode u některých modelů hlásí "0" i když je režim zapnutý –
skutečný test je až `sdb connect`.
"""
import json
import sys
import urllib.request

KEYS = ["name", "modelName", "model", "OS", "resolution", "networkType", "wifiMac", "developerMode", "developerIP"]

for ip in sys.argv[1:]:
    try:
        with urllib.request.urlopen(f"http://{ip}:8001/api/v2/", timeout=3) as r:
            device = json.loads(r.read()).get("device", {})
        print(ip, json.dumps({k: device.get(k) for k in KEYS}, ensure_ascii=False))
    except Exception as e:  # TV vypnutá, jiná značka, jiná IP...
        print(ip, "-", type(e).__name__, str(e)[:80])
