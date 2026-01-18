"""
Configuration for the Enclave Server.

All settings are centralized here. Note that the enclave has limited
environment variable access, so most values are compile-time constants.
"""

import os
from dataclasses import dataclass


# vsock constant - bind to any CID (required for enclave)
VSOCK_CID_ANY = 0xFFFFFFFF


@dataclass(frozen=True)
class VsockConfig:
    """vsock server configuration."""
    # CID to bind to (VSOCK_CID_ANY for enclave)
    bind_cid: int = VSOCK_CID_ANY
    # Port to listen on for incoming requests from parent
    listen_port: int = 5000


@dataclass(frozen=True)
class KMSProxyConfig:
    """KMS proxy connection configuration."""
    # Parent's CID (always 3 for parent from enclave's perspective)
    parent_cid: int = 3
    # Port where parent runs the KMS vsock-proxy
    proxy_port: int = 8000
    # Connection timeout in seconds
    timeout_seconds: int = 30


@dataclass(frozen=True)
class PIIConfig:
    """PII detection configuration."""
    # Language for Presidio analysis
    language: str = 'en'
    # Entity types to detect
    entities: tuple = (
        "PERSON",
        "EMAIL_ADDRESS",
        "PHONE_NUMBER",
        "US_SSN",
        "CREDIT_CARD",
        "US_BANK_NUMBER",
        "IP_ADDRESS",
        "DATE_TIME",
        "LOCATION",
        "US_DRIVER_LICENSE",
        "US_PASSPORT",
        "IBAN_CODE",
        "NRP",
        "MEDICAL_LICENSE",
        "URL",
    )


@dataclass(frozen=True)
class Config:
    """Main enclave configuration."""
    vsock: VsockConfig
    kms_proxy: KMSProxyConfig
    pii: PIIConfig

    @classmethod
    def load(cls) -> 'Config':
        """
        Load configuration.

        Environment variables can override defaults, but inside the enclave
        most settings are fixed at build time.
        """
        return cls(
            vsock=VsockConfig(
                bind_cid=VSOCK_CID_ANY,
                listen_port=int(os.environ.get('VSOCK_PORT', '5000')),
            ),
            kms_proxy=KMSProxyConfig(
                parent_cid=int(os.environ.get('KMS_PROXY_CID', '3')),
                proxy_port=int(os.environ.get('KMS_PROXY_PORT', '8000')),
                timeout_seconds=int(os.environ.get('KMS_TIMEOUT', '30')),
            ),
            pii=PIIConfig(),
        )


# Global config instance
config = Config.load()
