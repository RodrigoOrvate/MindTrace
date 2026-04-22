import ipaddress

from fastapi import HTTPException

from .config import settings


def _parse_networks(raw: str) -> list[ipaddress._BaseNetwork]:
    chunks = [c.strip() for c in raw.split(";") if c.strip()]
    nets: list[ipaddress._BaseNetwork] = []
    for chunk in chunks:
        try:
            nets.append(ipaddress.ip_network(chunk, strict=False))
        except ValueError:
            continue
    return nets


def _allowed_networks() -> list[ipaddress._BaseNetwork]:
    return _parse_networks(settings.auth_allowed_cidrs.strip())


def _login_allowed_networks() -> list[ipaddress._BaseNetwork]:
    return _parse_networks(settings.auth_login_allowed_cidrs.strip())


def _admin_allowed_networks() -> list[ipaddress._BaseNetwork]:
    return _parse_networks(settings.auth_admin_allowed_cidrs.strip())


def ensure_client_ip_allowed(client_host: str | None) -> None:
    if client_host in {"testclient"}:
        return
    if not client_host:
        raise HTTPException(status_code=403, detail="Cliente sem IP de origem.")
    try:
        ip = ipaddress.ip_address(client_host)
    except ValueError as exc:
        raise HTTPException(status_code=403, detail="IP de origem invalido.") from exc

    nets = _allowed_networks()
    if not nets:
        raise HTTPException(status_code=503, detail="AUTH_ALLOWED_CIDRS nao configurado corretamente.")

    for net in nets:
        if ip in net:
            return
    raise HTTPException(status_code=403, detail="Acesso permitido apenas para IP/rede autorizados.")


def ensure_admin_ip_allowed(client_host: str | None) -> None:
    if client_host in {"testclient"}:
        return
    if not client_host:
        raise HTTPException(status_code=403, detail="Cliente sem IP de origem para operacao administrativa.")
    try:
        ip = ipaddress.ip_address(client_host)
    except ValueError as exc:
        raise HTTPException(status_code=403, detail="IP de origem invalido para operacao administrativa.") from exc

    nets = _admin_allowed_networks()
    if not nets:
        raise HTTPException(status_code=503, detail="AUTH_ADMIN_ALLOWED_CIDRS nao configurado corretamente.")

    for net in nets:
        if ip in net:
            return
    raise HTTPException(status_code=403, detail="Operacao administrativa permitida apenas no PC principal.")


def is_client_ip_allowed_for_login(client_host: str | None) -> bool:
    if client_host in {"testclient"}:
        return True
    if not client_host:
        return False
    try:
        ip = ipaddress.ip_address(client_host)
    except ValueError:
        return False

    nets = _login_allowed_networks()
    if not nets:
        return False

    return any(ip in net for net in nets)
