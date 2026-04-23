import ipaddress
import logging

from fastapi import HTTPException

from .config import settings

logger = logging.getLogger("animal_lifecycle.security")

_LOOPBACK_IPS = {"127.0.0.1", "::1", "localhost"}


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


def _normalize_mac(mac: str) -> str:
    """Normaliza MAC para formato XX:XX:XX:XX:XX:XX em maiúsculas."""
    return mac.strip().upper().replace("-", ":").replace(".", ":")


def _parse_allowed_macs(raw: str) -> set[str]:
    macs: set[str] = set()
    for chunk in raw.split(";"):
        chunk = chunk.strip()
        if chunk:
            macs.add(_normalize_mac(chunk))
    return macs


def _lookup_client_mac(client_ip: str) -> str | None:
    """Resolve MAC via ARP para o IP informado. Retorna None se não identificado."""
    try:
        import getmac  # type: ignore[import]

        mac = getmac.get_mac_address(ip=client_ip)
        if mac:
            return _normalize_mac(mac)
        return None
    except Exception:
        return None


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


def ensure_admin_mac_allowed(client_host: str | None) -> None:
    """Verifica se o endereço MAC físico do cliente está autorizado para operações admin.

    Quando AUTH_ADMIN_ALLOWED_MACS não está configurado, a verificação é ignorada
    (modo compatibilidade). Quando configurado, o MAC é resolvido via ARP e comparado
    à lista autorizada — bloqueando Wi-Fi e dispositivos não reconhecidos.
    """
    allowed_macs_raw = settings.auth_admin_allowed_macs.strip()
    if not allowed_macs_raw:
        return  # verificação desativada — apenas IP protege

    if client_host in {"testclient"}:
        return  # bypass para testes automatizados

    if not client_host:
        raise HTTPException(status_code=403, detail="Cliente sem IP para validacao de hardware.")

    # Loopback não tem MAC físico — aceitar se já passou pela verificação de IP
    if client_host in _LOOPBACK_IPS:
        return

    allowed = _parse_allowed_macs(allowed_macs_raw)
    if not allowed:
        return

    mac = _lookup_client_mac(client_host)
    if mac is None:
        logger.warning(
            "Tentativa de admin de %s — MAC nao resolvido via ARP (bloqueado).",
            client_host,
        )
        raise HTTPException(
            status_code=403,
            detail="Validacao de hardware falhou — MAC nao identificado. Use a conexao Ethernet.",
        )

    if mac not in allowed:
        logger.warning(
            "Tentativa de admin de %s com MAC %s — hardware nao autorizado.",
            client_host,
            mac,
        )
        raise HTTPException(
            status_code=403,
            detail="Acesso administrativo bloqueado: hardware nao autorizado (somente Ethernet do PC principal).",
        )


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


def is_admin_ip_allowed_for_login(client_host: str | None) -> bool:
    """Verifica se o IP está autorizado para emitir token de administrador."""
    if client_host in {"testclient"}:
        return True
    if not client_host:
        return False
    try:
        ip = ipaddress.ip_address(client_host)
    except ValueError:
        return False

    nets = _admin_allowed_networks()
    if not nets:
        return False

    return any(ip in net for net in nets)
