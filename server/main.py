"""
Radio28 backend — FastAPI + SQLite + LiveKit token issuer + own WebSocket hub.

Runs on the same VPS as LiveKit (or anywhere reachable).
Env vars (see docker-compose):
  LK_API_KEY / LK_API_SECRET   — LiveKit credentials
  LK_URL                       — e.g. ws://livekit:7880  (internal, for SDK calls)
  LK_PUBLIC_URL                — e.g. wss://radio.example.com  (handed to clients)
  DB_PATH                      — default /data/radio28.db
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import os
import secrets
import sqlite3
import time
import uuid
from contextlib import contextmanager
from typing import Any, Optional

from fastapi import Depends, FastAPI, Header, HTTPException, WebSocket, WebSocketDisconnect, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# ---------------- config ----------------

DB_PATH = os.environ.get("DB_PATH", "/data/radio28.db")
LK_API_KEY = os.environ.get("LK_API_KEY", "devkey")
LK_API_SECRET = os.environ.get("LK_API_SECRET", "secretsecretsecretsecretsecretsecretsecretsecretsecretsecret")
LK_PUBLIC_URL = os.environ.get("LK_PUBLIC_URL", "ws://localhost:7880")

SESSION_TTL = 60 * 60 * 24 * 30  # 30 days
CHALLENGE_TTL = 300  # 5 minutes

# ---------------- db ----------------

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    callsign TEXT NOT NULL,
    route TEXT,
    public_key TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS channels (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL COLLATE NOCASE,
    is_private INTEGER NOT NULL DEFAULT 1,
    invite_code TEXT,
    creator_id TEXT NOT NULL,
    created_at REAL NOT NULL,
    UNIQUE(name, creator_id)
);
CREATE TABLE IF NOT EXISTS members (
    channel_id INTEGER NOT NULL,
    user_id TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'member',  -- creator | admin | member
    muted INTEGER NOT NULL DEFAULT 0,
    joined_at REAL NOT NULL,
    PRIMARY KEY (channel_id, user_id)
);
CREATE TABLE IF NOT EXISTS join_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id INTEGER NOT NULL,
    user_id TEXT NOT NULL,
    callsign TEXT NOT NULL,
    route TEXT,
    status TEXT NOT NULL DEFAULT 'pending',  -- pending | approved | rejected
    reason TEXT,
    created_at REAL NOT NULL,
    resolved_at REAL
);
CREATE TABLE IF NOT EXISTS bans (
    channel_id INTEGER NOT NULL,
    user_id TEXT NOT NULL,
    created_at REAL NOT NULL,
    PRIMARY KEY (channel_id, user_id)
);
CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS challenges (
    nonce TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_id INTEGER NOT NULL,
    user_id TEXT NOT NULL,
    callsign TEXT NOT NULL,
    started_at REAL NOT NULL,
    duration_sec REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_history_channel ON history(channel_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_req_channel ON join_requests(channel_id, status);
CREATE INDEX IF NOT EXISTS idx_members_channel ON members(channel_id);
"""


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


@contextmanager
def get_db():
    conn = db()
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with get_db() as conn:
        conn.executescript(SCHEMA)


# ---------------- auth helpers ----------------

def _b64_to_bytes(s: str) -> bytes:
    return base64.b64decode(s.encode())


def _bytes_to_int(b: bytes) -> int:
    return int.from_bytes(b, "big")


def parse_public_key(pem: str) -> tuple[int, int]:
    lines = [l for l in pem.split("\n") if l and not l.startswith("-----")]
    if len(lines) < 2:
        raise ValueError("bad public key")
    return _bytes_to_int(_b64_to_bytes(lines[0])), _bytes_to_int(_b64_to_bytes(lines[1]))


def verify_rsa_signature(public_pem: str, message: bytes, signature_b64: str) -> bool:
    """Verify RSASSA-PKCS1-v1_5 with SHA-256 — pure Python."""
    try:
        n, e = parse_public_key(public_pem)
        sig = _bytes_to_int(base64.b64decode(signature_b64))
        # RSA verify: m = sig^e mod n
        m = pow(sig, e, n)
        em_len = (n.bit_length() + 7) // 8
        em = m.to_bytes(em_len, "big")
        # Build expected EMSA-PKCS1-v1_5 encoding for SHA-256
        digest = hashlib.sha256(message).digest()
        digest_info_prefix = bytes.fromhex("3031300d060960864801650304020105000420")
        t = digest_info_prefix + digest
        if em_len < len(t) + 11:
            return False
        ps = b"\xff" * (em_len - len(t) - 3)
        expected = b"\x00\x01" + ps + b"\x00" + t
        return secrets.compare_digest(em, expected)
    except Exception:
        return False


def new_session(user_id: str) -> str:
    token = secrets.token_urlsafe(32)
    with get_db() as conn:
        conn.execute(
            "INSERT INTO sessions (token, user_id, created_at) VALUES (?,?,?)",
            (token, user_id, time.time()),
        )
    return token


def user_by_session(token: Optional[str]) -> Optional[sqlite3.Row]:
    if not token:
        return None
    with get_db() as conn:
        row = conn.execute(
            "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id "
            "WHERE s.token = ? AND s.created_at > ?",
            (token, time.time() - SESSION_TTL),
        ).fetchone()
        return row


async def current_user(authorization: Optional[str] = Header(None)) -> sqlite3.Row:
    token = None
    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:]
    u = user_by_session(token)
    if u is None:
        raise HTTPException(401, "unauthorized")
    return u


# ---------------- app ----------------

app = FastAPI(title="radio28")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def _startup():
    init_db()



@app.get("/health")
def health():
    return {"status": "ok", "ts": time.time()}


# ---------------- pydantic ----------------

class RegisterBody(BaseModel):
    user_id: str
    callsign: str
    route: Optional[str] = None
    public_key: str


class LoginBody(BaseModel):
    user_id: str
    nonce: str
    signature: str


class ChannelBody(BaseModel):
    name: str
    invite_code: Optional[str] = None
    is_private: bool = True


class JoinBody(BaseModel):
    invite_code: Optional[str] = None


class RejectBody(BaseModel):
    reason: Optional[str] = None


class MuteBody(BaseModel):
    muted: bool


# ---------------- auth endpoints ----------------

@app.post("/auth/register")
def register(body: RegisterBody):
    with get_db() as conn:
        is_first_user = conn.execute("SELECT 1 FROM users LIMIT 1").fetchone() is None
        existing = conn.execute("SELECT id FROM users WHERE id = ?", (body.user_id,)).fetchone()
        if existing:
            # idempotent re-register (reinstall keeps uuid) — update callsign
            conn.execute(
                "UPDATE users SET callsign = ?, route = ?, public_key = ? WHERE id = ?",
                (body.callsign, body.route, body.public_key, body.user_id),
            )
        else:
            conn.execute(
                "INSERT INTO users (id, callsign, route, public_key, created_at) VALUES (?,?,?,?,?)",
                (body.user_id, body.callsign, body.route, body.public_key, time.time()),
            )
        # The very first account on a fresh server owns the default private channel.
        if is_first_user:
            seed_name = os.environ.get("SEED_CHANNEL_NAME", "Сызрань-28")
            ch = conn.execute("SELECT id FROM channels WHERE name = ?", (seed_name,)).fetchone()
            if not ch:
                cur = conn.execute(
                    "INSERT INTO channels (name, is_private, invite_code, creator_id, created_at) "
                    "VALUES (?,?,?,?,?)",
                    (seed_name, 1, None, body.user_id, time.time()),
                )
                conn.execute(
                    "INSERT INTO members (channel_id, user_id, role, joined_at) VALUES (?,?,?,?)",
                    (cur.lastrowid, body.user_id, "creator", time.time()),
                )
    return {"ok": True, "first_user": is_first_user}


@app.get("/auth/challenge")
def challenge(user_id: str = Query(...)):
    with get_db() as conn:
        u = conn.execute("SELECT id FROM users WHERE id = ?", (user_id,)).fetchone()
        if not u:
            raise HTTPException(404, "user_not_found")
        nonce = secrets.token_urlsafe(24)
        conn.execute("DELETE FROM challenges WHERE created_at < ?", (time.time() - CHALLENGE_TTL,))
        conn.execute(
            "INSERT INTO challenges (nonce, user_id, created_at) VALUES (?,?,?)",
            (nonce, user_id, time.time()),
        )
    return {"nonce": nonce}


@app.post("/auth/login")
def login(body: LoginBody):
    with get_db() as conn:
        ch = conn.execute(
            "SELECT * FROM challenges WHERE nonce = ? AND user_id = ? AND created_at > ?",
            (body.nonce, body.user_id, time.time() - CHALLENGE_TTL),
        ).fetchone()
        if not ch:
            raise HTTPException(401, "challenge_expired")
        u = conn.execute("SELECT * FROM users WHERE id = ?", (body.user_id,)).fetchone()
        if not u:
            raise HTTPException(404, "user_not_found")
        ok = verify_rsa_signature(u["public_key"], body.nonce.encode(), body.signature)
        conn.execute("DELETE FROM challenges WHERE nonce = ?", (body.nonce,))
        if not ok:
            raise HTTPException(401, "bad_signature")
    return {"session": new_session(body.user_id), "callsign": u["callsign"], "route": u["route"]}


# ---------------- channels ----------------

def _channel_json(conn: sqlite3.Connection, row: sqlite3.Row, user_id: Optional[str] = None) -> dict:
    member_count = conn.execute(
        "SELECT COUNT(*) AS c FROM members WHERE channel_id = ?", (row["id"],)
    ).fetchone()["c"]
    role = None
    if user_id:
        m = conn.execute(
            "SELECT role FROM members WHERE channel_id = ? AND user_id = ?",
            (row["id"], user_id),
        ).fetchone()
        role = m["role"] if m else None
    return {
        "id": row["id"],
        "name": row["name"],
        "is_private": bool(row["is_private"]),
        "has_invite_code": bool(row["invite_code"]),
        "member_count": member_count,
        "role": role,
    }


@app.get("/channels/search")
def search_channels(q: str = Query(..., min_length=2), user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM channels WHERE name LIKE ? ORDER BY created_at DESC LIMIT 30",
            (f"%{q}%",),
        ).fetchall()
        return {"channels": [_channel_json(conn, r, user["id"]) for r in rows]}


@app.get("/channels/mine")
def my_channels(user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        rows = conn.execute(
            "SELECT c.* FROM channels c JOIN members m ON m.channel_id = c.id WHERE m.user_id = ?",
            (user["id"],),
        ).fetchall()
        return {"channels": [_channel_json(conn, r, user["id"]) for r in rows]}


@app.post("/channels")
def create_channel(body: ChannelBody, user: sqlite3.Row = Depends(current_user)):
    name = body.name.strip()
    if len(name) < 2:
        raise HTTPException(400, "name_too_short")
    with get_db() as conn:
        try:
            cur = conn.execute(
                "INSERT INTO channels (name, is_private, invite_code, creator_id, created_at) "
                "VALUES (?,?,?,?,?)",
                (name, 1 if body.is_private else 0, body.invite_code or None, user["id"], time.time()),
            )
        except sqlite3.IntegrityError:
            raise HTTPException(409, "channel_exists")
        cid = cur.lastrowid
        conn.execute(
            "INSERT INTO members (channel_id, user_id, role, joined_at) VALUES (?,?,?,?)",
            (cid, user["id"], "creator", time.time()),
        )
        row = conn.execute("SELECT * FROM channels WHERE id = ?", (cid,)).fetchone()
        return {"channel": _channel_json(conn, row, user["id"])}


def _is_admin(conn, channel_id: int, user_id: str) -> bool:
    r = conn.execute(
        "SELECT role FROM members WHERE channel_id = ? AND user_id = ?",
        (channel_id, user_id),
    ).fetchone()
    return bool(r and r["role"] in ("creator", "admin"))


def _is_banned(conn, channel_id: int, user_id: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM bans WHERE channel_id = ? AND user_id = ?", (channel_id, user_id)
    ).fetchone() is not None


@app.post("/channels/{cid}/join")
def join_channel(cid: int, body: JoinBody, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        ch = conn.execute("SELECT * FROM channels WHERE id = ?", (cid,)).fetchone()
        if not ch:
            raise HTTPException(404, "channel_not_found")
        if _is_banned(conn, cid, user["id"]):
            raise HTTPException(403, "banned")
        existing = conn.execute(
            "SELECT role FROM members WHERE channel_id = ? AND user_id = ?", (cid, user["id"])
        ).fetchone()
        if existing:
            return {"status": "member"}
        # open channel — instant member
        if not ch["is_private"]:
            conn.execute(
                "INSERT INTO members (channel_id, user_id, role, joined_at) VALUES (?,?,?,?)",
                (cid, user["id"], "member", time.time()),
            )
            return {"status": "member"}
        # invite code = instant accept
        if ch["invite_code"] and body.invite_code and secrets.compare_digest(
            ch["invite_code"], body.invite_code
        ):
            conn.execute(
                "INSERT INTO members (channel_id, user_id, role, joined_at) VALUES (?,?,?,?)",
                (cid, user["id"], "member", time.time()),
            )
            return {"status": "member"}
        if ch["invite_code"] and body.invite_code and not secrets.compare_digest(
            ch["invite_code"], body.invite_code
        ):
            raise HTTPException(403, "wrong_invite_code")

        # rate limit: 1 pending request / minute / device
        last = conn.execute(
            "SELECT created_at FROM join_requests WHERE channel_id = ? AND user_id = ? "
            "ORDER BY created_at DESC LIMIT 1",
            (cid, user["id"]),
        ).fetchone()
        if last and time.time() - last["created_at"] < 60:
            raise HTTPException(429, "slow_down")
        # auto-ban after 5 consecutive rejections
        rejected = conn.execute(
            "SELECT COUNT(*) AS c FROM join_requests WHERE channel_id = ? AND user_id = ? AND status = 'rejected'",
            (cid, user["id"]),
        ).fetchone()["c"]
        if rejected >= 5:
            conn.execute(
                "INSERT OR IGNORE INTO bans (channel_id, user_id, created_at) VALUES (?,?,?)",
                (cid, user["id"], time.time()),
            )
            raise HTTPException(403, "banned")

        # existing pending?
        pend = conn.execute(
            "SELECT id FROM join_requests WHERE channel_id = ? AND user_id = ? AND status = 'pending'",
            (cid, user["id"]),
        ).fetchone()
        if not pend:
            conn.execute(
                "INSERT INTO join_requests (channel_id, user_id, callsign, route, created_at) "
                "VALUES (?,?,?,?,?)",
                (cid, user["id"], user["callsign"], user["route"], time.time()),
            )
        _notify_channel_admins_sync(conn, cid, {
            "type": "join_request",
            "channel_id": cid,
            "callsign": user["callsign"],
        })
        return {"status": "pending"}


@app.get("/channels/{cid}/join_status")
def join_status(cid: int, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        m = conn.execute(
            "SELECT role FROM members WHERE channel_id = ? AND user_id = ?", (cid, user["id"])
        ).fetchone()
        if m:
            return {"status": "member"}
        r = conn.execute(
            "SELECT status, reason FROM join_requests WHERE channel_id = ? AND user_id = ? "
            "ORDER BY created_at DESC LIMIT 1",
            (cid, user["id"]),
        ).fetchone()
        if not r:
            return {"status": "none"}
        # If the latest request was approved but the member row is gone (kicked),
        # the user is out — treat as "none" so the app drops the channel.
        if r["status"] == "approved":
            return {"status": "none"}
        return {"status": r["status"], "reason": r["reason"]}


# ---------------- members / admin ----------------

@app.get("/channels/{cid}/members")
def members(cid: int, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        if not _is_admin(conn, cid, user["id"]):
            # members can see the roster too — plan says "водитель видит кто онлайн"
            m = conn.execute(
                "SELECT 1 FROM members WHERE channel_id = ? AND user_id = ?", (cid, user["id"])
            ).fetchone()
            if not m:
                raise HTTPException(403, "not_a_member")
        rows = conn.execute(
            "SELECT m.user_id, m.role, m.muted, u.callsign, u.route "
            "FROM members m JOIN users u ON u.id = m.user_id WHERE m.channel_id = ?",
            (cid,),
        ).fetchall()
        online = _online_user_ids(cid)
        return {
            "members": [
                {
                    "user_id": r["user_id"],
                    "callsign": r["callsign"],
                    "route": r["route"],
                    "role": r["role"],
                    "online": r["user_id"] in online,
                    "muted": bool(r["muted"]),
                }
                for r in rows
            ]
        }


@app.get("/channels/{cid}/requests")
def requests_list(cid: int, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        if not _is_admin(conn, cid, user["id"]):
            raise HTTPException(403, "not_admin")
        rows = conn.execute(
            "SELECT id, user_id, callsign, route, created_at FROM join_requests "
            "WHERE channel_id = ? AND status = 'pending' ORDER BY created_at ASC",
            (cid,),
        ).fetchall()
        return {
            "requests": [
                {
                    "id": r["id"],
                    "user_id": r["user_id"],
                    "callsign": r["callsign"],
                    "route": r["route"],
                    "created_at": time.strftime("%H:%M", time.localtime(r["created_at"])),
                }
                for r in rows
            ]
        }


def _resolve_request(conn, cid: int, rid: int, status: str, reason: Optional[str] = None):
    r = conn.execute(
        "SELECT * FROM join_requests WHERE id = ? AND channel_id = ? AND status = 'pending'",
        (rid, cid),
    ).fetchone()
    if not r:
        raise HTTPException(404, "request_not_found")
    conn.execute(
        "UPDATE join_requests SET status = ?, reason = ?, resolved_at = ? WHERE id = ?",
        (status, reason, time.time(), rid),
    )
    return r


@app.post("/channels/{cid}/requests/{rid}/approve")
def approve(cid: int, rid: int, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        if not _is_admin(conn, cid, user["id"]):
            raise HTTPException(403, "not_admin")
        r = _resolve_request(conn, cid, rid, "approved")
        conn.execute(
            "INSERT OR IGNORE INTO members (channel_id, user_id, role, joined_at) VALUES (?,?,?,?)",
            (cid, r["user_id"], "member", time.time()),
        )
    _notify_user_sync(r["user_id"], {"type": "approved", "channel_id": cid})
    return {"ok": True}


@app.post("/channels/{cid}/requests/{rid}/reject")
def reject(cid: int, rid: int, body: RejectBody, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        if not _is_admin(conn, cid, user["id"]):
            raise HTTPException(403, "not_admin")
        r = _resolve_request(conn, cid, rid, "rejected", body.reason)
    _notify_user_sync(r["user_id"], {
        "type": "rejected", "channel_id": cid, "reason": body.reason,
    })
    return {"ok": True}


def _guard_target(conn, cid: int, target_id: str, actor_id: str):
    """Creator can't be kicked/banned/muted; admins can't touch creator."""
    target = conn.execute(
        "SELECT role FROM members WHERE channel_id = ? AND user_id = ?", (cid, target_id)
    ).fetchone()
    if not target:
        raise HTTPException(404, "not_a_member")
    actor = conn.execute(
        "SELECT role FROM members WHERE channel_id = ? AND user_id = ?", (cid, actor_id)
    ).fetchone()
    if target["role"] == "creator":
        raise HTTPException(403, "cant_touch_creator")
    if actor["role"] != "creator" and target["role"] == "admin":
        raise HTTPException(403, "admin_cant_touch_admin")


@app.post("/channels/{cid}/members/{uid}/kick")
def kick(cid: int, uid: str, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        if not _is_admin(conn, cid, user["id"]):
            raise HTTPException(403, "not_admin")
        _guard_target(conn, cid, uid, user["id"])
        conn.execute("DELETE FROM members WHERE channel_id = ? AND user_id = ?", (cid, uid))
    _notify_user_sync(uid, {"type": "kicked", "channel_id": cid})
    return {"ok": True}


@app.post("/channels/{cid}/members/{uid}/ban")
def ban(cid: int, uid: str, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        if not _is_admin(conn, cid, user["id"]):
            raise HTTPException(403, "not_admin")
        _guard_target(conn, cid, uid, user["id"])
        conn.execute("DELETE FROM members WHERE channel_id = ? AND user_id = ?", (cid, uid))
        conn.execute(
            "INSERT OR REPLACE INTO bans (channel_id, user_id, created_at) VALUES (?,?,?)",
            (cid, uid, time.time()),
        )
    _notify_user_sync(uid, {"type": "banned", "channel_id": cid})
    return {"ok": True}


@app.post("/channels/{cid}/members/{uid}/mute")
def mute(cid: int, uid: str, body: MuteBody, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        if not _is_admin(conn, cid, user["id"]):
            raise HTTPException(403, "not_admin")
        _guard_target(conn, cid, uid, user["id"])
        conn.execute(
            "UPDATE members SET muted = ? WHERE channel_id = ? AND user_id = ?",
            (1 if body.muted else 0, cid, uid),
        )
    _notify_user_sync(uid, {
        "type": "muted" if body.muted else "unmuted", "channel_id": cid,
    })
    return {"ok": True}


@app.post("/channels/{cid}/invite_code/regenerate")
def regen_code(cid: int, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        if not _is_admin(conn, cid, user["id"]):
            raise HTTPException(403, "not_admin")
        code = f"{secrets.randbelow(1000000):06d}"
        conn.execute("UPDATE channels SET invite_code = ? WHERE id = ?", (code, cid))
    return {"invite_code": code}


# ---------------- voice token (LiveKit) ----------------

@app.post("/channels/{cid}/voice_token")
def voice_token(cid: int, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        m = conn.execute(
            "SELECT role, muted FROM members WHERE channel_id = ? AND user_id = ?",
            (cid, user["id"]),
        ).fetchone()
        if not m:
            raise HTTPException(403, "not_a_member")
        ch = conn.execute("SELECT name FROM channels WHERE id = ?", (cid,)).fetchone()
        if not ch:
            raise HTTPException(404, "channel_not_found")
        muted = bool(m["muted"])
    token = _livekit_jwt(
        api_key=LK_API_KEY,
        api_secret=LK_API_SECRET,
        identity=user["id"],
        name=user["callsign"],
        room=f"channel-{cid}",
        can_publish=not muted,
    )
    return {"url": LK_PUBLIC_URL, "token": token, "muted": muted}


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def _livekit_jwt(api_key: str, api_secret: str, identity: str, name: str,
                 room: str, can_publish: bool) -> str:
    """Minimal JWT for LiveKit access token (HS256)."""
    import hmac as _hmac

    header = {"alg": "HS256", "typ": "JWT"}
    now = int(time.time())
    payload = {
        "iss": api_key,
        "sub": identity,
        "name": name,
        "iat": now,
        "nbf": now - 60,
        "exp": now + 60 * 60 * 6,  # 6 h
        "video": {
            "roomJoin": True,
            "room": room,
            "canPublish": can_publish,
            "canSubscribe": True,
            "canPublishData": True,
        },
    }
    seg = f"{_b64url(json.dumps(header, separators=(',', ':')).encode())}." \
          f"{_b64url(json.dumps(payload, separators=(',', ':')).encode())}"
    sig = _hmac.new(api_secret.encode(), seg.encode(), hashlib.sha256).digest()
    return f"{seg}.{_b64url(sig)}"


# ---------------- history ----------------

class HistoryBody(BaseModel):
    duration_sec: float


@app.post("/channels/{cid}/history")
def add_history(cid: int, body: HistoryBody, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        m = conn.execute(
            "SELECT 1 FROM members WHERE channel_id = ? AND user_id = ?", (cid, user["id"])
        ).fetchone()
        if not m:
            raise HTTPException(403, "not_a_member")
        conn.execute(
            "INSERT INTO history (channel_id, user_id, callsign, started_at, duration_sec) "
            "VALUES (?,?,?,?,?)",
            (cid, user["id"], user["callsign"], time.time() - body.duration_sec, body.duration_sec),
        )
    return {"ok": True}


@app.get("/channels/{cid}/history")
def get_history(cid: int, user: sqlite3.Row = Depends(current_user)):
    with get_db() as conn:
        m = conn.execute(
            "SELECT 1 FROM members WHERE channel_id = ? AND user_id = ?", (cid, user["id"])
        ).fetchone()
        if not m:
            raise HTTPException(403, "not_a_member")
        rows = conn.execute(
            "SELECT callsign, started_at, duration_sec FROM history WHERE channel_id = ? "
            "ORDER BY started_at DESC LIMIT 200",
            (cid,),
        ).fetchall()
        return {
            "history": [
                {
                    "callsign": r["callsign"],
                    "started_at": time.strftime("%d.%m %H:%M", time.localtime(r["started_at"])),
                    "duration_sec": r["duration_sec"],
                }
                for r in rows
            ]
        }


# ---------------- WebSocket hub ----------------

class Hub:
    """channel_id -> set of (user_id, websocket); plus user_id -> set of websockets."""

    def __init__(self):
        self.by_user: dict[str, set[WebSocket]] = {}
        self.lock = asyncio.Lock()

    async def add(self, user_id: str, ws: WebSocket):
        async with self.lock:
            self.by_user.setdefault(user_id, set()).add(ws)

    async def remove(self, user_id: str, ws: WebSocket):
        async with self.lock:
            if user_id in self.by_user:
                self.by_user[user_id].discard(ws)
                if not self.by_user[user_id]:
                    del self.by_user[user_id]

    async def send_user(self, user_id: str, msg: dict):
        async with self.lock:
            targets = list(self.by_user.get(user_id, ()))
        for w in targets:
            try:
                await w.send_text(json.dumps(msg))
            except Exception:
                pass

    def online_users(self) -> set[str]:
        return set(self.by_user.keys())


HUB = Hub()


def _online_user_ids(_channel_id: int) -> set[str]:
    # presence is global (app is connected or not) — per-channel presence
    # happens via LiveKit in the radio screen
    return HUB.online_users()


async def _notify_user(user_id: str, msg: dict):
    await HUB.send_user(user_id, msg)


def _notify_user_sync(user_id: str, msg: dict):
    """Fire-and-forget from sync endpoint handlers."""
    try:
        loop = asyncio.get_event_loop()
        loop.create_task(_notify_user(user_id, msg))
    except RuntimeError:
        pass


def _notify_channel_admins_sync(conn: sqlite3.Connection, channel_id: int, msg: dict):
    rows = conn.execute(
        "SELECT user_id FROM members WHERE channel_id = ? AND role IN ('creator','admin')",
        (channel_id,),
    ).fetchall()
    for r in rows:
        _notify_user_sync(r["user_id"], msg)


async def _notify_channel_admins(conn: sqlite3.Connection, channel_id: int, msg: dict):
    rows = conn.execute(
        "SELECT user_id FROM members WHERE channel_id = ? AND role IN ('creator','admin')",
        (channel_id,),
    ).fetchall()
    for r in rows:
        await _notify_user(r["user_id"], msg)


@app.websocket("/ws")
async def ws_endpoint(websocket: WebSocket, token: str = Query(...)):
    u = user_by_session(token)
    if u is None:
        await websocket.close(code=4401)
        return
    await websocket.accept()
    user_id = u["id"]
    await HUB.add(user_id, websocket)
    try:
        await websocket.send_text(json.dumps({"type": "hello", "user_id": user_id}))
        while True:
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
            except Exception:
                continue
            if msg.get("type") == "ping":
                await websocket.send_text(json.dumps({"type": "pong"}))
    except WebSocketDisconnect:
        pass
    finally:
        await HUB.remove(user_id, websocket)
