#!/usr/bin/env python3
"""
Confidential PII Detection Server - Nitro Enclave

This server runs INSIDE the Nitro Enclave and:
1. Receives encrypted data via vsock from the parent app
2. Uses KMS with attestation to decrypt the data (only this enclave can decrypt)
3. Runs PII detection on the plaintext
4. Returns redacted text and detected entities

The enclave has NO network access - all communication goes through vsock.
KMS calls are proxied through the parent's vsock-proxy.
"""

import json
import socket
import subprocess
import base64
import sys
from typing import Dict, List, Any, Tuple
from dataclasses import dataclass

from config import config


def log(msg: str):
    """Log to stderr (stdout may not be visible in enclave)."""
    print(f"[ENCLAVE] {msg}", file=sys.stderr, flush=True)


@dataclass
class PIIEntity:
    """Detected PII entity."""
    entity_type: str
    start: int
    end: int
    score: float = 1.0


class PIIDetector:
    """
    PII detection using Microsoft Presidio.
    Presidio uses NLP models for accurate PII detection.
    """

    def __init__(self):
        from presidio_analyzer import AnalyzerEngine
        from presidio_anonymizer import AnonymizerEngine

        # Initialize Presidio engines
        self.analyzer = AnalyzerEngine()
        self.anonymizer = AnonymizerEngine()

        # Supported entity types from config
        self.entities = list(config.pii.entities)
        self.language = config.pii.language

        log("Presidio analyzer initialized")

    def detect(self, text: str) -> Tuple[str, List[Dict[str, Any]]]:
        """
        Detect and redact PII from text using Presidio.

        Returns:
            Tuple of (redacted_text, list of detected entities)
        """
        # Analyze text for PII
        results = self.analyzer.analyze(
            text=text,
            entities=self.entities,
            language=self.language
        )

        # Convert to our format
        entities = []
        for result in results:
            entities.append({
                'type': result.entity_type,
                'start': result.start,
                'end': result.end,
                'score': round(result.score, 2)
            })

        # Anonymize (redact) PII
        anonymized = self.anonymizer.anonymize(
            text=text,
            analyzer_results=results
        )

        redacted_text = anonymized.text

        # Sort entities by position for output
        entities = sorted(entities, key=lambda x: x['start'])

        return redacted_text, entities


class KMSProxy:
    """
    Calls kmstool_enclave_cli for KMS operations with attestation.

    kmstool_enclave_cli handles:
    - TLS communication through vsock-proxy
    - AWS SigV4 request signing
    - Attestation document generation and attachment
    """

    def __init__(self):
        self.proxy_port = config.kms_proxy.proxy_port

    def decrypt(self, ciphertext_blob: bytes, key_id: str, credentials: dict) -> bytes:
        """
        Decrypt using kmstool_enclave_cli with attestation.

        The tool automatically attaches an attestation document to the KMS request.
        KMS validates the attestation before returning the plaintext.
        """
        ciphertext_b64 = base64.b64encode(ciphertext_blob).decode('utf-8')

        cmd = [
            "/usr/local/bin/kmstool_enclave_cli",
            "decrypt",
            "--region", credentials.get("region", "us-east-1"),
            "--proxy-port", str(self.proxy_port),
            "--aws-access-key-id", credentials["access_key_id"],
            "--aws-secret-access-key", credentials["secret_access_key"],
            "--ciphertext", ciphertext_b64,
        ]

        # Add session token if present (required for temporary credentials)
        if credentials.get("session_token"):
            cmd.extend(["--aws-session-token", credentials["session_token"]])

        log(f"Calling kmstool_enclave_cli decrypt on port {self.proxy_port}...")
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            log(f"kmstool stderr: {result.stderr}")
            raise Exception(f"kmstool_enclave_cli failed: {result.stderr}")

        # Parse output format: "PLAINTEXT: <base64-encoded-plaintext>"
        for line in result.stdout.splitlines():
            if line.startswith("PLAINTEXT:"):
                plaintext_b64 = line.split(":", 1)[1].strip()
                return base64.b64decode(plaintext_b64)

        log(f"kmstool stdout: {result.stdout}")
        raise Exception(f"No PLAINTEXT in kmstool output")


def get_attestation_document() -> bytes:
    """
    Get attestation document from Nitro Secure Module (NSM).

    The attestation document contains:
    - PCR values (hashes of enclave image, kernel, app)
    - Public key for secure channel
    - Timestamp
    - Signature by AWS Nitro
    """
    try:
        # Try to use NSM library (only available inside enclave)
        import aws_nsm_interface
        fd = aws_nsm_interface.open_nsm_device()
        attestation = aws_nsm_interface.get_attestation_document(fd)
        aws_nsm_interface.close_nsm_device(fd)
        return attestation
    except ImportError:
        # Running outside enclave for testing
        log("WARNING: NSM not available, returning mock attestation")
        return json.dumps({
            'mock': True,
            'message': 'Running outside Nitro Enclave',
            'pcrs': {
                'PCR0': '0' * 96,
                'PCR1': '0' * 96,
                'PCR2': '0' * 96
            }
        }).encode('utf-8')


def receive_request(conn: socket.socket) -> dict:
    """Receive JSON request from vsock connection."""
    # First receive the length (4 bytes, big endian)
    length_bytes = conn.recv(4)
    if len(length_bytes) < 4:
        raise ValueError("Failed to receive data length")

    data_length = int.from_bytes(length_bytes, byteorder='big')
    log(f"Expecting {data_length} bytes")

    # Receive the actual data
    chunks = []
    received = 0
    while received < data_length:
        chunk = conn.recv(min(65536, data_length - received))
        if not chunk:
            raise ValueError("Connection closed while receiving data")
        chunks.append(chunk)
        received += len(chunk)

    data = b''.join(chunks)
    return json.loads(data.decode('utf-8'))


def send_response(conn: socket.socket, response: dict):
    """Send JSON response via vsock connection."""
    data = json.dumps(response).encode('utf-8')
    conn.sendall(len(data).to_bytes(4, byteorder='big'))
    conn.sendall(data)


class EnclaveServer:
    """Main PII detection server running inside the enclave."""

    def __init__(self):
        self.pii_detector = PIIDetector()
        self.kms_proxy = KMSProxy()

    def handle_request(self, request: dict) -> dict:
        """
        Handle incoming request.

        Operations:
        - 'ping': Health check
        - 'attestation': Return attestation document
        - 'detect': Decrypt, detect PII, return redacted text
        """
        operation = request.get('operation', request.get('action'))
        log(f"Handling operation: {operation}")

        try:
            if operation == 'ping':
                return {'status': 'ok', 'message': 'Enclave PII detector is running'}

            elif operation == 'attestation':
                attestation_doc = get_attestation_document()
                return {
                    'status': 'ok',
                    'attestation_document': base64.b64encode(attestation_doc).decode('utf-8')
                }

            elif operation == 'detect':
                return self._handle_detect_encrypted(request)

            else:
                return {'status': 'error', 'message': f'Unknown operation: {operation}'}

        except Exception as e:
            log(f"Error handling request: {e}")
            return {'status': 'error', 'message': str(e)}

    def _handle_detect_encrypted(self, request: dict) -> dict:
        """
        Process encrypted PII detection request.

        Expected request:
        {
            'operation': 'detect',
            'encrypted_data': '<base64 KMS ciphertext>',
            'key_id': 'arn:aws:kms:...',
            'credentials': {
                'access_key_id': '...',
                'secret_access_key': '...',
                'session_token': '...',  # optional
                'region': 'us-east-1'
            }
        }
        """
        encrypted_data = request.get('encrypted_data')
        key_id = request.get('key_id')
        credentials = request.get('credentials')

        if not encrypted_data or not key_id:
            return {'status': 'error', 'message': 'Missing encrypted_data or key_id'}

        if not credentials:
            return {'status': 'error', 'message': 'Missing credentials'}

        if not credentials.get('access_key_id') or not credentials.get('secret_access_key'):
            return {'status': 'error', 'message': 'Missing access_key_id or secret_access_key in credentials'}

        # Decrypt using KMS (via kmstool with attestation)
        log("Decrypting data via KMS with attestation...")
        ciphertext = base64.b64decode(encrypted_data)
        plaintext_bytes = self.kms_proxy.decrypt(ciphertext, key_id, credentials)
        text = plaintext_bytes.decode('utf-8')

        # Detect and redact PII
        log("Running PII detection...")
        redacted_text, entities = self.pii_detector.detect(text)

        log(f"Detected {len(entities)} PII entities")

        return {
            'status': 'ok',
            'redacted_text': redacted_text,
            'entities': entities,
            'entity_count': len(entities)
        }

    def run(self):
        """Start the vsock server."""
        sock = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((config.vsock.bind_cid, config.vsock.listen_port))
        sock.listen(5)

        log("=" * 60)
        log("Confidential PII Detection - Nitro Enclave Server")
        log("=" * 60)
        log(f"Listening on vsock port {config.vsock.listen_port}")

        while True:
            try:
                log("Waiting for connection...")
                conn, addr = sock.accept()
                log(f"Connection from CID {addr[0]}")

                try:
                    request = receive_request(conn)
                    response = self.handle_request(request)
                    send_response(conn, response)
                    log(f"Response sent: status={response.get('status')}")
                except Exception as e:
                    log(f"Error processing request: {e}")
                    try:
                        send_response(conn, {'status': 'error', 'message': str(e)})
                    except:
                        pass
                finally:
                    conn.close()

            except Exception as e:
                log(f"Server error: {e}")


def main():
    server = EnclaveServer()
    server.run()


if __name__ == "__main__":
    main()
