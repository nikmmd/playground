.PHONY: help build build-kmstool deploy destroy env kubeconfig clean clean-all

# Terraform or OpenTofu
TF ?= tofu

# Default environment file
ENV_FILE ?= k8s/.env

help:
	@echo "PII Redaction with Nitro Enclaves"
	@echo ""
	@echo "Setup:"
	@echo "  make infra         Deploy infrastructure (tofu/terraform)"
	@echo "  make env           Generate k8s/.env from tofu outputs"
	@echo "  make kubeconfig    Update kubeconfig for EKS cluster"
	@echo ""
	@echo "Build:"
	@echo "  make build-kmstool Build kmstool-enclave-cli from AWS SDK"
	@echo "  make build         Build EIF and Go binary (uses Docker)"
	@echo "  make deploy-s3     Upload artifacts to S3"
	@echo ""
	@echo "Deploy:"
	@echo "  make deploy        Deploy to Kubernetes"
	@echo "  make status        Check deployment status"
	@echo "  make logs          Tail pod logs"
	@echo "  make port-forward  Port forward to localhost:8080"
	@echo ""
	@echo "Cleanup:"
	@echo "  make destroy       Destroy all infrastructure"
	@echo ""
	@echo "Options:"
	@echo "  ENV_FILE=path      Use custom env file (default: k8s/.env)"
	@echo "  TF=terraform       Use terraform instead of tofu (default: tofu)"

# Infrastructure
infra:
	cd terraform && $(TF) init && $(TF) apply

env:
	TF=$(TF) ./scripts/setup-env.sh

kubeconfig:
	@cd terraform && eval $$($(TF) output -raw eks_update_kubeconfig_command)

# Build
KMSTOOL_REPO = https://github.com/aws/aws-nitro-enclaves-sdk-c.git
KMSTOOL_DIR = build/aws-nitro-enclaves-sdk-c
# Pin to working version (latest has Rust 2024 edition issues with wit-bindgen)
KMSTOOL_TAG ?= v0.4.3

build-kmstool:
	@mkdir -p build
	@if [ ! -d "$(KMSTOOL_DIR)" ]; then \
		echo "Cloning aws-nitro-enclaves-sdk-c..."; \
		git clone $(KMSTOOL_REPO) $(KMSTOOL_DIR); \
	fi
	@echo "Checking out tag $(KMSTOOL_TAG)..."
	@cd $(KMSTOOL_DIR) && \
		git fetch --tags && \
		git checkout $(KMSTOOL_TAG)
	@echo "Patching Dockerfile to use Rust 1.88..."
	@sed -i 's/--default-toolchain 1.71/--default-toolchain 1.88/g' $(KMSTOOL_DIR)/containers/Dockerfile.al2
	@echo "Building kmstool-enclave-cli Docker image..."
	cd $(KMSTOOL_DIR) && docker build -f containers/Dockerfile.al2 --target kmstool-enclave-cli -t kmstool-enclave-cli .
	@echo ""
	@echo "Done! kmstool-enclave-cli image is ready."
	@echo "Now run 'make build' to build the enclave."

build:
	./scripts/build-enclave.sh --docker

deploy-s3: build
	@if [ ! -f $(ENV_FILE) ]; then echo "Run 'make env' first"; exit 1; fi
	@if [ ! -f build/pcr0.txt ]; then echo "PCR0 not found. Run 'make build' first"; exit 1; fi
	@source $(ENV_FILE) && \
		PCR0=$$(cat build/pcr0.txt) && \
		echo "Uploading EIF with PCR0: $$PCR0" && \
		aws s3 cp build/pii-detection.eif s3://$$EIF_BUCKET/pii-detection.eif \
			--metadata pcr0=$$PCR0 && \
		aws s3 cp build/pii-detection-parent s3://$$EIF_BUCKET/pii-detection-parent
	@echo ""
	@echo "Uploaded to S3 with PCR0 metadata."
	@echo "Run 'make infra' to update KMS key policy (PCR0 is read automatically from S3)."

# Deploy
deploy-k8s:
	@if [ ! -f $(ENV_FILE) ]; then echo "Run 'make env' first"; exit 1; fi
	@set -a && source $(ENV_FILE) && set +a && \
		kustomize build k8s | envsubst | kubectl apply -f -
	@echo ""
	@echo "Creating postgres-credentials secret..."
	@set -a && source $(ENV_FILE) && set +a && \
		kubectl create secret generic postgres-credentials \
			--namespace enclave-demo \
			--from-literal=host="$$POSTGRES_HOST" \
			--from-literal=port="$$POSTGRES_PORT" \
			--from-literal=database="$$POSTGRES_DATABASE" \
			--from-literal=username="$$POSTGRES_USER" \
			--from-literal=password="$$POSTGRES_PASSWORD" \
			--dry-run=client -o yaml | kubectl apply -f -

status:
	kubectl get pods -n enclave-demo
	@echo ""
	kubectl get nodes -l node.kubernetes.io/nitro-enclave=true

logs:
	kubectl logs -f -n enclave-demo -l app=pii-detection

port-forward:
	@echo "Forwarding to http://localhost:8080"
	kubectl port-forward svc/pii-detection 8080:80 -n enclave-demo

# Cleanup
destroy:
	kubectl delete -k k8s/ --ignore-not-found
	cd terraform && $(TF) destroy

clean:
	rm -rf build/pii-detection.eif build/pii-detection-parent build/pcr0.txt
	rm -f k8s/.env

clean-all: clean
	rm -rf build/aws-nitro-enclaves-sdk-c
