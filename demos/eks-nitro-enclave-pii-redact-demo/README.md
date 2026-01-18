# Confidential PII Redaction with AWS Nitro Enclaves

Process sensitive documents containing PII without exposing the data to the service operator. Uses AWS Nitro Enclaves for hardware-isolated execution and KMS attestation for cryptographic verification.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLIENT                                         │
│  POST /redact with plaintext → Receive redacted text with PII removed       │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │ HTTPS
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         PARENT APP (K8s Pod)                                │
│  • Go REST API                                                              │
│  • Encrypts data with KMS before sending to enclave                         │
│  • Passes AWS credentials to enclave via vsock                              │
│  • CANNOT decrypt data (no KMS Decrypt permission)                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │ vsock
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         NITRO ENCLAVE                                       │
│  • Receives encrypted data + credentials via vsock                          │
│  • Decrypts using kmstool_enclave_cli (with attestation)                    │
│  • Processes PII detection with Presidio                                    │
│  • Returns redacted text                                                    │
└─────────────────────────────────────────────────────────────────────────────┘
          │                                       │
          │ vsock-proxy                           │
          ▼                                       │
┌─────────────────────────┐                       │
│       AWS KMS           │                       │
│  Decrypt only if:       │                       │
│  PCR0 = <enclave-hash>  │                       │
└─────────────────────────┘                       │
                                                  ▼
                                    ┌─────────────────────────┐
                                    │      PostgreSQL         │
                                    │   (sample documents)    │
                                    └─────────────────────────┘
```

**Key Security Properties:**

- Parent app encrypts data but cannot decrypt (no KMS permission)
- Enclave decrypts via `kmstool_enclave_cli` which includes attestation document
- KMS only allows decrypt when `kms:RecipientAttestation:PCR0` matches enclave image hash
- Enclave has no network, no disk, memory encrypted by Nitro Hypervisor

**Network Architecture:**

- EKS cluster runs in VPC1 with private subnets and VPC endpoints
- PostgreSQL runs in VPC2 (isolated)
- VPCs connected via VPC peering for database access

## Quick Start

```bash
# 1. Deploy infrastructure (EKS, VPC, KMS, PostgreSQL)
make infra

# 2. Generate environment and configure kubectl
make env
make kubeconfig

# 3. Build kmstool (one-time, required for enclave)
make build-kmstool

# 4. Build enclave EIF and parent binary
make build

# 5. Upload artifacts to S3 (includes PCR0 metadata)
make deploy-s3

# 6. Update KMS policy with PCR0 (auto-read from S3)
make infra

# 7. Deploy to Kubernetes
make deploy-k8s

# 8. Test
make port-forward
# In another terminal:
curl http://localhost:8080/health
curl -X POST http://localhost:8080/redact \
  -H "Content-Type: application/json" \
  -d '{"text": "My name is John Smith and my SSN is 123-45-6789"}'
```

## Make Targets

| Target               | Description                                    |
| -------------------- | ---------------------------------------------- |
| `make infra`         | Deploy/update infrastructure with tofu         |
| `make env`           | Generate k8s/.env from terraform outputs       |
| `make kubeconfig`    | Update kubeconfig for EKS cluster              |
| `make build-kmstool` | Build kmstool-enclave-cli Docker image         |
| `make build`         | Build EIF and Go binary (uses Docker)          |
| `make deploy-s3`     | Upload EIF and binary to S3 with PCR0 metadata |
| `make deploy-k8s`    | Deploy to Kubernetes                           |
| `make status`        | Check pod status                               |
| `make logs`          | Tail pod logs                                  |
| `make port-forward`  | Port forward to localhost:8080                 |
| `make destroy`       | Destroy all infrastructure                     |

## API Endpoints

| Endpoint                 | Method | Description                         |
| ------------------------ | ------ | ----------------------------------- |
| `/health`                | GET    | Health check + enclave status       |
| `/attestation`           | GET    | Get enclave attestation document    |
| `/redact`                | POST   | Redact PII from plaintext           |
| `/seed`                  | POST   | Seed database with sample documents |
| `/documents`             | GET    | List documents                      |
| `/documents/{id}/redact` | POST   | Redact PII in stored document       |

## Project Structure

```
├── terraform/           # Infrastructure (EKS, VPC, KMS, PostgreSQL)
├── enclave/             # Nitro Enclave (Dockerfile, Python server)
├── parent-app/          # Go REST API (runs outside enclave)
├── k8s/                 # Kubernetes manifests
├── scripts/             # Build and setup scripts
└── Makefile             # Build and deploy commands
```

## How It Works

1. **Parent app** receives plaintext, encrypts with KMS, passes to enclave via vsock
2. **Enclave** receives encrypted data + AWS credentials
3. **kmstool_enclave_cli** decrypts data by calling KMS through vsock-proxy
   - Includes attestation document with PCR0 (image hash)
   - KMS verifies PCR0 matches policy before allowing decrypt
4. **Presidio** detects and redacts PII entities
5. **Redacted text** returned to client

## Examples

**Redact PII from plaintext:**

```bash
curl -X POST http://localhost:8080/redact \
  -H "Content-Type: application/json" \
  -d '{"text": "My name is John Smith and my email is john@example.com"}' | jq
```

```json
{
  "status": "ok",
  "redacted_text": "My name is <PERSON> and my email is <EMAIL_ADDRESS>",
  "entities": [
    { "type": "PERSON", "start": 11, "end": 21, "score": 0.85 },
    { "type": "EMAIL_ADDRESS", "start": 38, "end": 54, "score": 1 }
  ],
  "entity_count": 3
}
```

**Redact PII from stored document:**

```bash
curl -X POST http://localhost:8080/documents/1/redact | jq
```

```json
{
  "status": "ok",
  "redacted_text": "Customer Complaint:\n\nI am <PERSON> (<EMAIL_ADDRESS>) and I'm having issues.\nPhone: <PHONE_NUMBER>\nDOB: <DATE_TIME>\nAccount ending in 4567 shows unauthorized transactions.\nPlease contact me ASAP.\n\nIP Address for reference: <IP_ADDRESS>",
  "entities": [
    { "type": "PERSON", "start": 26, "end": 39, "score": 0.85 },
    { "type": "EMAIL_ADDRESS", "start": 41, "end": 58, "score": 1 },
    { "type": "PHONE_NUMBER", "start": 90, "end": 102, "score": 0.75 },
    { "type": "DATE_TIME", "start": 108, "end": 118, "score": 0.6 },
    { "type": "IP_ADDRESS", "start": 226, "end": 239, "score": 0.95 }
  ],
  "entity_count": 7
}
```

## Cleanup

```bash
make destroy
```
