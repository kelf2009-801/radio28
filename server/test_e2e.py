"""
End-to-end smoke test of radio28 backend (runs against a live server).

Usage:
  python test_e2e.py [base_url]    # default http://127.0.0.1:8000

Flow:
  1. register two users (Андрей=creator, Серёга=driver) with real RSA keys
  2. login both via challenge-response (real RSA signing)
  3. Андрей creates channel "Сызрань-28"
  4. Серёга finds it via search, joins -> pending
  5. Андрей sees the request, approves
  6. Серёга becomes member, gets a LiveKit voice token
  7. Андрей mutes Серёга -> voice token has canPublish=false
  8. Андрей kicks Серёга
  9. Серёга tries to rejoin via wrong invite code -> rejected; via right code -> member
  10. history write + read
"""
import base64
import hashlib
import json
import os
import secrets
import sys
import urllib.request
import uuid

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000"

# --- tiny RSA (no external deps) ---

def _i2b(i: int) -> bytes:
    return i.to_bytes((i.bit_length() + 7) // 8 or 1, "big")

def _b2i(b: bytes) -> int:
    return int.from_bytes(b, "big")

def gen_rsa(bits=2048):
    """Generate an RSA keypair. Uses Python's built-in pow for speed."""
    # Use openssl via subprocess — way faster than pure-python primegen
    import subprocess, tempfile, re
    tmpdir = tempfile.mkdtemp(prefix="radio28-test-")
    priv_pem = os.path.join(tmpdir, "k.pem")
    pub_pem = os.path.join(tmpdir, "k.pub")
    subprocess.run(
        ["openssl", "genrsa", "-out", priv_pem, str(bits)],
        check=True, capture_output=True,
    )
    subprocess.run(
        ["openssl", "rsa", "-in", priv_pem, "-pubout", "-out", pub_pem],
        check=True, capture_output=True,
    )
    # Extract n, e, d, p, q with openssl text dump
    txt = subprocess.run(
        ["openssl", "rsa", "-in", priv_pem, "-text", "-noout"],
        check=True, capture_output=True, text=True,
    ).stdout

    def grab(name):
        m = re.search(name + r":\s*\n((?:\s+[0-9a-f:]+\n?)+)", txt)
        if not m:
            m2 = re.search(name + r":\s*(\d+)", txt)
            return int(m2.group(1))
        hexstr = re.sub(r"[^0-9a-f]", "", m.group(1))
        return int(hexstr, 16)

    n = grab("modulus")
    e = grab("publicExponent")
    d = grab("privateExponent")
    p = grab("prime1")
    q = grab("prime2")
    return n, e, d, p, q

def pem_pub(n, e):
    return ("-----BEGIN RSA PUBLIC KEY-----\n"
            + base64.b64encode(_i2b(n)).decode() + "\n"
            + base64.b64encode(_i2b(e)).decode()
            + "\n-----END RSA PUBLIC KEY-----")

def sign(n, d, msg: bytes) -> str:
    """RSASSA-PKCS1-v1_5 with SHA-256."""
    digest = hashlib.sha256(msg).digest()
    prefix = bytes.fromhex("3031300d060960864801650304020105000420")
    t = prefix + digest
    k = (n.bit_length() + 7) // 8
    ps = b"\xff" * (k - len(t) - 3)
    em = b"\x00\x01" + ps + b"\x00" + t
    sig = pow(_b2i(em), d, n)
    return base64.b64encode(_i2b(sig)).decode()

# --- http ---

def req(method, path, body=None, token=None):
    url = BASE + path
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=15) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

def register_and_login(name, route=None):
    n, e, d, p, q = gen_rsa()
    pub = pem_pub(n, e)
    uid = 'user_' + hashlib.sha256(pub.encode()).hexdigest()[:16]
    s, j = req("POST", "/auth/register", {
        "user_id": uid, "callsign": name, "route": route, "public_key": pub,
    })
    assert s == 200, (s, j)
    # If server says existing user — use their ID
    if j.get("existing") and j.get("user_id"):
        uid = j["user_id"]
    s, ch = req("GET", f"/auth/challenge?user_id={uid}")
    assert s == 200, (s, ch)
    sig = sign(n, d, ch["nonce"].encode())
    s, j = req("POST", "/auth/login", {
        "user_id": uid, "nonce": ch["nonce"], "signature": sig,
    })
    assert s == 200, (s, j)
    return {"user_id": uid, "callsign": name, "token": j["session"]}
def main():
    print(f"== radio28 backend e2e against {BASE} ==")

    s, j = req("GET", "/health")
    assert j.get("status") == "ok", j
    print("[ok] health")

    andrey = register_and_login("Андрей", "№28")
    sergey = register_and_login("Серёга", "№28")
    print(f"[ok] registered: andrey={andrey['user_id'][:8]} sergey={sergey['user_id'][:8]}")

    # 3) andrey creates channel manually (no auto-seed)
    s, j = req("POST", "/channels", {"name": "Сызрань-28"}, token=andrey["token"])
    assert s == 200, (s, j)
    cid = j["channel"]["id"]
    assert j["channel"]["role"] == "creator", j
    assert j["channel"]["is_private"] is True, j
    print(f"[ok] andrey created channel #{cid} (creator, private)")

    # 4) sergey search + join -> pending
    from urllib.parse import quote
    s, j = req("GET", f"/channels/search?q={quote('Сызрань')}", token=sergey["token"])
    assert any(c["id"] == cid for c in j["channels"]), j
    s, j = req("POST", f"/channels/{cid}/join", {}, token=sergey["token"])
    assert s == 200 and j["status"] == "pending", (s, j)
    print("[ok] sergey join -> pending")

    # 5) andrey lists requests, approves
    s, j = req("GET", f"/channels/{cid}/requests", token=andrey["token"])
    assert s == 200 and len(j["requests"]) == 1, (s, j)
    rid = j["requests"][0]["id"]
    s, j = req("POST", f"/channels/{cid}/requests/{rid}/approve", token=andrey["token"])
    assert s == 200, (s, j)
    print("[ok] approve")

    # 6) sergey is a member + gets voice token with canPublish
    s, j = req("GET", f"/channels/{cid}/join_status", token=sergey["token"])
    assert j["status"] == "member", j
    s, j = req("POST", f"/channels/{cid}/voice_token", token=sergey["token"])
    assert s == 200 and "token" in j and "url" in j, (s, j)
    # decode payload
    payload = j["token"].split(".")[1]
    payload += "=" * (-len(payload) % 4)
    claims = json.loads(base64.urlsafe_b64decode(payload))
    assert claims["video"]["canPublish"] is True, claims
    print(f"[ok] voice token iss={claims['iss']} room={claims['video']['room']}")

    # 7) mute -> canPublish=false
    s, j = req("POST", f"/channels/{cid}/members/{sergey['user_id']}/mute",
               {"muted": True}, token=andrey["token"])
    assert s == 200, (s, j)
    s, j = req("POST", f"/channels/{cid}/voice_token", token=sergey["token"])
    payload = j["token"].split(".")[1]
    payload += "=" * (-len(payload) % 4)
    claims = json.loads(base64.urlsafe_b64decode(payload))
    assert claims["video"]["canPublish"] is False, claims
    print("[ok] mute -> canPublish=false")

    # unmute back
    s, j = req("POST", f"/channels/{cid}/members/{sergey['user_id']}/mute",
               {"muted": False}, token=andrey["token"])
    assert s == 200

    # 8) kick
    s, j = req("POST", f"/channels/{cid}/members/{sergey['user_id']}/kick",
               token=andrey["token"])
    assert s == 200, (s, j)
    s, j = req("GET", f"/channels/{cid}/join_status", token=sergey["token"])
    assert j["status"] == "none", j
    print("[ok] kick")

    # 9) wrong invite code -> 403; regenerate -> right code works
    s, j = req("POST", f"/channels/{cid}/invite_code/regenerate", token=andrey["token"])
    code = j["invite_code"]
    s, j = req("POST", f"/channels/{cid}/join", {"invite_code": "000000"}, token=sergey["token"])
    assert s == 403, (s, j)
    s, j = req("POST", f"/channels/{cid}/join", {"invite_code": code}, token=sergey["token"])
    assert s == 200 and j["status"] == "member", (s, j)
    print(f"[ok] invite code flow (code {code})")

    # 10) history
    s, j = req("POST", f"/channels/{cid}/history", {"duration_sec": 7.5}, token=andrey["token"])
    assert s == 200
    s, j = req("GET", f"/channels/{cid}/history", token=andrey["token"])
    assert s == 200 and len(j["history"]) >= 1, (s, j)
    print(f"[ok] history ({len(j['history'])} entries)")

    # members list
    s, j = req("GET", f"/channels/{cid}/members", token=andrey["token"])
    names = [m["callsign"] for m in j["members"]]
    assert "Андрей" in names and "Серёга" in names, j
    print(f"[ok] members: {names}")

    print("\nALL E2E CHECKS PASSED ✅")

if __name__ == "__main__":
    main()
