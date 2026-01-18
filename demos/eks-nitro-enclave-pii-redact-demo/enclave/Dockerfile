# Nitro Enclave Image - Confidential PII Detection with Presidio
# This image will be converted to an EIF (Enclave Image File)
#
# The enclave runs completely isolated:
# - No network access (all communication via vsock)
# - No persistent storage
# - Memory encrypted by Nitro Hypervisor
# - Attestation proves exact code running
#
# BUILD INSTRUCTIONS:
# 1. Run: make build-kmstool
# 2. Run: make build

################################################################################
# Reference the pre-built kmstool image
################################################################################
ARG KMSTOOL_IMAGE=kmstool-enclave-cli
FROM ${KMSTOOL_IMAGE} AS kmstool

################################################################################
# Final enclave image with Python app
################################################################################
FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy kmstool binaries from the pre-built image
COPY --from=kmstool /kmstool_enclave_cli /usr/local/bin/
COPY --from=kmstool /usr/lib64/libnsm.so /usr/lib/

# Set library path for libnsm.so
ENV LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/lib"

# Install Python dependencies
RUN pip install --no-cache-dir \
    presidio-analyzer \
    presidio-anonymizer \
    spacy

# Download spaCy English model (required by Presidio)
RUN python -m spacy download en_core_web_lg

# Copy enclave application
COPY server.py /app/server.py
COPY config.py /app/config.py

WORKDIR /app

# Ensure python3 symlink exists for enclave init
RUN ln -sf /usr/local/bin/python /usr/bin/python3

# The enclave runs this command (use absolute path)
CMD ["/usr/local/bin/python", "/app/server.py"]
