"""Host-only, idempotent provisioning. Invoked by systemd at deployment/boot.

No credentials in argv or logs; provider response bodies are deliberately omitted
from errors. This program is never run by a Nix build or generate-secrets.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


class ProvisionError(Exception):
    pass


class API:
    def __init__(self, base, authorization, cloudflare=False):
        self.base, self.authorization, self.cloudflare = base, authorization, cloudflare

    def __call__(self, method, path, body=None):
        request = urllib.request.Request(
            self.base + path,
            method=method,
            data=None if body is None else json.dumps(body).encode(),
            headers={
                "Authorization": self.authorization,
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                result = json.load(response)
        except urllib.error.HTTPError as exc:
            raise ProvisionError(
                f"Provider API {method} failed: HTTP {exc.code}"
            ) from None
        except (OSError, ValueError):
            raise ProvisionError(
                "Provider API unavailable or returned invalid JSON"
            ) from None
        if self.cloudflare:
            if not result.get("success"):
                raise ProvisionError("Cloudflare rejected provisioning request")
            return result["result"]
        return result


def atomic(path, value):
    path = Path(path)
    tmp = path.with_suffix(".new")
    tmp.write_text(value)
    tmp.chmod(0o600)
    tmp.replace(path)


def unique(items, name):
    matches = [item for item in items if item["name"] == name]
    if len(matches) > 1:
        raise ProvisionError(f"Duplicate managed resource: {name}")
    return matches[0] if matches else None


def cloudflare(cfg, api, ownership_path=None):
    base = f"/accounts/{cfg['cloudflare_account_id']}/cfd_tunnel"
    name = "homelab-hermes"
    existing = api(
        "GET",
        base + "?" + urllib.parse.urlencode({"name": name, "is_deleted": "false"}),
    )
    tunnel = unique(existing, name)
    owned_id = None
    if ownership_path and Path(ownership_path).exists():
        owned_id = json.loads(Path(ownership_path).read_text())["tunnel_id"]
    created = tunnel is None
    if tunnel is None:
        tunnel = api("POST", base, {"name": name, "config_src": "cloudflare"})
        if ownership_path:
            atomic(ownership_path, json.dumps({"tunnel_id": tunnel["id"]}))
    if tunnel.get("config_src") != "cloudflare":
        raise ProvisionError(
            "homelab-hermes must be a remotely managed Cloudflare tunnel"
        )
    tunnel_id = tunnel["id"]
    hostname = cfg["hostname"]
    ingress = [
        {
            "hostname": hostname,
            "path": "^/telegram$",
            "service": "http://127.0.0.1:8443",
        },
        {
            "hostname": hostname,
            "path": "^/webhooks/[^/]+$",
            "service": "http://127.0.0.1:8644",
        },
        {"service": "http_status:404"},
    ]
    if not created and owned_id != tunnel_id:
        previous = (
            api("GET", base + f"/{tunnel_id}/configurations")
            .get("config", {})
            .get("ingress", [])
        )
        relevant = [
            {k: v for k, v in rule.items() if k in {"hostname", "path", "service"}}
            for rule in previous
        ]
        if relevant != ingress:
            raise ProvisionError(
                "Existing homelab-hermes tunnel is not owned by this configuration"
            )
        if ownership_path:
            atomic(ownership_path, json.dumps({"tunnel_id": tunnel_id}))
    dns_base = f"/zones/{cfg['cloudflare_zone_id']}/dns_records"
    records = api("GET", dns_base + "?" + urllib.parse.urlencode({"name": hostname}))
    desired = {
        "type": "CNAME",
        "name": hostname,
        "content": f"{tunnel_id}.cfargotunnel.com",
        "proxied": True,
        "ttl": 1,
    }
    if records and (
        len(records) != 1
        or any(records[0].get(k) != desired[k] for k in ("type", "content"))
    ):
        raise ProvisionError(
            "Hermes hostname already has an unrelated DNS record; choose an unused hostname"
        )
    api("PUT", base + f"/{tunnel_id}/configurations", {"config": {"ingress": ingress}})
    if records:
        if not records[0].get("proxied"):
            api("PATCH", dns_base + "/" + records[0]["id"], desired)
    else:
        api("POST", dns_base, desired)
    token = api("GET", base + f"/{tunnel_id}/token")
    if not isinstance(token, str) or not token:
        raise ProvisionError("Cloudflare did not return a tunnel run token")
    return token


def main():
    os.umask(0o077)
    cfg = json.loads(
        (Path(os.environ["CREDENTIALS_DIRECTORY"]) / "provision.json").read_text()
    )
    cf = API(
        "https://api.cloudflare.com/client/v4",
        "Bearer " + cfg["cloudflare_api_token"],
        True,
    )
    token = cloudflare(cfg, cf, Path(os.environ["STATE_DIRECTORY"]) / "ownership.json")
    runtime = Path(os.environ["RUNTIME_DIRECTORY"])
    atomic(runtime / "cloudflared-token", token + "\n")
    print("Hermes tunnel and DNS are ready")


if __name__ == "__main__":
    try:
        main()
    except (ProvisionError, KeyError, ValueError) as exc:
        # Never print arbitrary provider response payloads or secret-bearing JSON.
        sys.exit(
            str(exc)
            if isinstance(exc, ProvisionError)
            else "Invalid Hermes provisioning configuration"
        )
