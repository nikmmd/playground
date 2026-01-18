// Confidential PII Detection - Parent Application (REST API)
//
// This application runs on the HOST (outside the enclave) and:
// 1. Exposes REST API endpoints for PII detection
// 2. Runs a vsock proxy for KMS calls (with attestation)
// 3. Proxies requests to the Nitro Enclave via vsock
// 4. Manages enclave lifecycle
//
// The parent app CANNOT decrypt the data - only the enclave can.
package main

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/kms"
	_ "github.com/lib/pq"
	"github.com/mdlayher/vsock"

	"github.com/example/pii-detection-parent/config"
	"github.com/example/pii-detection-parent/seed"
)

var (
	cfg       *config.Config
	enclaveID string
	kmsClient *kms.Client
	awsCfg    aws.Config
)

// API Response types
type HealthResponse struct {
	Status         string `json:"status"`
	EnclaveRunning bool   `json:"enclave_running"`
	EnclaveID      string `json:"enclave_id,omitempty"`
}

type AttestationResponse struct {
	Status              string `json:"status"`
	AttestationDocument string `json:"attestation_document,omitempty"`
	Error               string `json:"error,omitempty"`
}

type RedactRequest struct {
	Text string `json:"text"`
}

type DetectResponse struct {
	Status       string                   `json:"status"`
	RedactedText string                   `json:"redacted_text,omitempty"`
	Entities     []map[string]interface{} `json:"entities,omitempty"`
	EntityCount  int                      `json:"entity_count,omitempty"`
	Error        string                   `json:"error,omitempty"`
}

type SeedRequest struct {
	Count int `json:"count"`
}

type SeedResponse struct {
	Status         string `json:"status"`
	RecordsCreated int    `json:"records_created"`
	Message        string `json:"message,omitempty"`
}

type Document struct {
	ID        int       `json:"id"`
	Content   string    `json:"content,omitempty"`
	Preview   string    `json:"preview,omitempty"`
	CreatedAt time.Time `json:"created_at,omitempty"`
}

type DocumentListResponse struct {
	Documents []Document `json:"documents"`
	Total     int        `json:"total"`
	Limit     int        `json:"limit"`
	Offset    int        `json:"offset"`
}

func main() {
	cfg = config.Load()

	log.Println("============================================================")
	log.Println("Confidential PII Detection - Parent Application (Go)")
	log.Println("============================================================")

	// Initialize AWS config and KMS client
	var err error
	awsCfg, err = awsconfig.LoadDefaultConfig(context.Background(),
		awsconfig.WithRegion(cfg.KMS.Region),
	)
	if err != nil {
		log.Printf("Warning: Failed to load AWS config: %v", err)
	} else {
		kmsClient = kms.NewFromConfig(awsCfg)
	}

	// Start KMS proxy
	go startKMSProxy()

	// Start enclave (required - exit if it fails)
	if err := startEnclave(); err != nil {
		log.Fatalf("Failed to start enclave: %v", err)
	}

	// Wait for enclave to initialize
	time.Sleep(5 * time.Second)

	// Verify enclave is responding
	resp, err := sendToEnclave(map[string]interface{}{"operation": "ping"})
	if err != nil {
		log.Fatalf("Enclave failed to respond to ping: %v", err)
	}
	if resp["status"] != "ok" {
		log.Fatalf("Enclave ping returned non-ok status: %v", resp)
	}
	log.Println("Enclave is ready and responding")

	// Setup router using Go 1.22+ enhanced ServeMux
	mux := http.NewServeMux()

	// Routes with method patterns
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("GET /attestation", handleAttestation)
	mux.HandleFunc("POST /redact", handleRedact)
	mux.HandleFunc("GET /kms-key", handleKMSKey)
	mux.HandleFunc("POST /seed", handleSeed)
	mux.HandleFunc("GET /documents", handleListDocuments)
	mux.HandleFunc("GET /documents/{id}", handleGetDocument)
	mux.HandleFunc("POST /documents/{id}/redact", handleRedactDocument)

	// Wrap with logging middleware
	handler := loggingMiddleware(mux)

	// Graceful shutdown
	srv := &http.Server{
		Addr:         fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.Port),
		Handler:      handler,
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 60 * time.Second,
	}

	go func() {
		log.Printf("Starting server on %s:%d", cfg.Server.Host, cfg.Server.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Wait for interrupt
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down...")
	stopEnclave()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}

// Middleware
func loggingMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}

// Enclave communication
func connectToEnclave() (*vsock.Conn, error) {
	var conn *vsock.Conn
	var err error

	for attempt := 0; attempt < 5; attempt++ {
		conn, err = vsock.Dial(cfg.Enclave.CID, cfg.Enclave.Port, nil)
		if err == nil {
			return conn, nil
		}
		log.Printf("Connection attempt %d failed: %v", attempt+1, err)
		time.Sleep(time.Second)
	}
	return nil, fmt.Errorf("failed to connect to enclave: %w", err)
}

func sendToEnclave(request map[string]interface{}) (map[string]interface{}, error) {
	conn, err := connectToEnclave()
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	conn.SetDeadline(time.Now().Add(30 * time.Second))

	// Send request
	data, err := json.Marshal(request)
	if err != nil {
		return nil, err
	}

	// Send length prefix (4 bytes, big endian)
	lengthBuf := make([]byte, 4)
	binary.BigEndian.PutUint32(lengthBuf, uint32(len(data)))
	if _, err := conn.Write(lengthBuf); err != nil {
		return nil, err
	}
	if _, err := conn.Write(data); err != nil {
		return nil, err
	}

	// Receive response
	if _, err := conn.Read(lengthBuf); err != nil {
		return nil, err
	}
	responseLen := binary.BigEndian.Uint32(lengthBuf)

	responseData := make([]byte, responseLen)
	totalRead := 0
	for totalRead < int(responseLen) {
		n, err := conn.Read(responseData[totalRead:])
		if err != nil {
			return nil, err
		}
		totalRead += n
	}

	var response map[string]interface{}
	if err := json.Unmarshal(responseData, &response); err != nil {
		return nil, err
	}

	return response, nil
}

// Enclave lifecycle
func startEnclave() error {
	log.Printf("Starting enclave from %s", cfg.Enclave.EIFPath)
	log.Printf("CPUs: %d, Memory: %dMB", cfg.Enclave.CPUs, cfg.Enclave.MemoryMB)

	args := []string{
		"run-enclave",
		"--eif-path", cfg.Enclave.EIFPath,
		"--cpu-count", strconv.Itoa(cfg.Enclave.CPUs),
		"--memory", strconv.Itoa(cfg.Enclave.MemoryMB),
		"--enclave-cid", strconv.Itoa(int(cfg.Enclave.CID)),
	}

	// Add debug mode if DEBUG env var is set
	if os.Getenv("DEBUG") != "" {
		log.Println("DEBUG mode enabled - enclave console will be available")
		args = append(args, "--debug-mode")
	}

	cmd := exec.Command("nitro-cli", args...)

	// Use Output() instead of CombinedOutput() to get only stdout (JSON)
	// stderr may contain progress messages that break JSON parsing
	output, err := cmd.Output()
	if err != nil {
		// Get stderr for error reporting
		if exitErr, ok := err.(*exec.ExitError); ok {
			return fmt.Errorf("failed to start enclave: %w, stderr: %s", err, exitErr.Stderr)
		}
		return fmt.Errorf("failed to start enclave: %w", err)
	}

	var result map[string]interface{}
	if err := json.Unmarshal(output, &result); err != nil {
		return fmt.Errorf("failed to parse enclave output: %w, raw output: %s", err, output)
	}

	if id, ok := result["EnclaveID"].(string); ok {
		enclaveID = id
		log.Printf("Enclave started with ID: %s", enclaveID)
	}

	return nil
}

func stopEnclave() {
	if enclaveID != "" {
		log.Printf("Stopping enclave %s", enclaveID)
		exec.Command("nitro-cli", "terminate-enclave", "--enclave-id", enclaveID).Run()
		enclaveID = ""
	}
}

func isEnclaveRunning() bool {
	cmd := exec.Command("nitro-cli", "describe-enclaves")
	output, err := cmd.Output()
	if err != nil {
		return false
	}

	var enclaves []interface{}
	if err := json.Unmarshal(output, &enclaves); err != nil {
		return false
	}

	return len(enclaves) > 0
}

// KMS Proxy
func startKMSProxy() {
	log.Printf("Starting KMS vsock proxy on port %d", cfg.KMS.ProxyPort)

	cmd := exec.Command("vsock-proxy",
		strconv.Itoa(cfg.KMS.ProxyPort),
		fmt.Sprintf("kms.%s.amazonaws.com", cfg.KMS.Region),
		"443",
	)

	if err := cmd.Run(); err != nil {
		log.Printf("KMS proxy error: %v", err)
	}
}

// Database
func getDB() (*sql.DB, error) {
	if !cfg.Postgres.IsConfigured() {
		return nil, fmt.Errorf("PostgreSQL not configured")
	}

	connStr := fmt.Sprintf("host=%s port=%d user=%s password=%s dbname=%s sslmode=disable",
		cfg.Postgres.Host, cfg.Postgres.Port, cfg.Postgres.User, cfg.Postgres.Password, cfg.Postgres.Database)

	return sql.Open("postgres", connStr)
}

// AWS Credentials for enclave
func getCredentials(ctx context.Context) (map[string]string, error) {
	creds, err := awsCfg.Credentials.Retrieve(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve AWS credentials: %w", err)
	}

	return map[string]string{
		"access_key_id":     creds.AccessKeyID,
		"secret_access_key": creds.SecretAccessKey,
		"session_token":     creds.SessionToken,
		"region":            cfg.KMS.Region,
	}, nil
}

// JSON response helper
func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// HTTP Handlers
func handleHealth(w http.ResponseWriter, r *http.Request) {
	running := isEnclaveRunning()

	httpStatus := http.StatusOK
	status := "ok"
	if !running {
		httpStatus = http.StatusServiceUnavailable
		status = "unhealthy"
	}

	writeJSON(w, httpStatus, HealthResponse{
		Status:         status,
		EnclaveRunning: running,
		EnclaveID:      enclaveID,
	})
}

func handleAttestation(w http.ResponseWriter, r *http.Request) {
	resp, err := sendToEnclave(map[string]interface{}{"operation": "attestation"})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	if resp["status"] == "ok" {
		writeJSON(w, http.StatusOK, AttestationResponse{
			Status:              "ok",
			AttestationDocument: resp["attestation_document"].(string),
		})
	} else {
		msg := "Unknown error"
		if m, ok := resp["message"].(string); ok {
			msg = m
		}
		writeJSON(w, http.StatusOK, AttestationResponse{
			Status: "error",
			Error:  msg,
		})
	}
}

func handleRedact(w http.ResponseWriter, r *http.Request) {
	if cfg.KMS.KeyARN == "" {
		writeError(w, http.StatusInternalServerError, "KMS_KEY_ARN not configured")
		return
	}

	var req RedactRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	if req.Text == "" {
		writeError(w, http.StatusBadRequest, "text field is required")
		return
	}

	// Encrypt plaintext with KMS before sending to enclave
	if kmsClient == nil {
		writeError(w, http.StatusInternalServerError, "KMS client not initialized")
		return
	}

	encryptOutput, err := kmsClient.Encrypt(r.Context(), &kms.EncryptInput{
		KeyId:     aws.String(cfg.KMS.KeyARN),
		Plaintext: []byte(req.Text),
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("KMS encryption failed: %v", err))
		return
	}

	encryptedB64 := base64.StdEncoding.EncodeToString(encryptOutput.CiphertextBlob)

	// Get credentials to pass to enclave
	creds, err := getCredentials(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get credentials: %v", err))
		return
	}

	resp, err := sendToEnclave(map[string]interface{}{
		"operation":      "detect",
		"encrypted_data": encryptedB64,
		"key_id":         cfg.KMS.KeyARN,
		"credentials":    creds,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, buildDetectResponse(resp))
}

func handleKMSKey(w http.ResponseWriter, r *http.Request) {
	if cfg.KMS.KeyARN == "" {
		writeError(w, http.StatusNotFound, "KMS_KEY_ARN not configured")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"key_arn": cfg.KMS.KeyARN})
}

func handleSeed(w http.ResponseWriter, r *http.Request) {
	var req SeedRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		req.Count = 100
	}
	if req.Count <= 0 {
		req.Count = 100
	}

	db, err := getDB()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer db.Close()

	recordsCreated, err := seed.InsertDocuments(db, req.Count)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	log.Printf("Seeded %d documents to PostgreSQL", recordsCreated)

	writeJSON(w, http.StatusOK, SeedResponse{
		Status:         "ok",
		RecordsCreated: recordsCreated,
		Message:        fmt.Sprintf("Created %d sample documents with PII", recordsCreated),
	})
}

func handleListDocuments(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 10
	}
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))

	db, err := getDB()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer db.Close()

	rows, err := db.Query(`
		SELECT id, LEFT(content, 100) as preview, created_at
		FROM documents
		ORDER BY id
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	var documents []Document
	for rows.Next() {
		var doc Document
		var createdAt sql.NullTime
		if err := rows.Scan(&doc.ID, &doc.Preview, &createdAt); err != nil {
			continue
		}
		if len(doc.Preview) == 100 {
			doc.Preview += "..."
		}
		if createdAt.Valid {
			doc.CreatedAt = createdAt.Time
		}
		documents = append(documents, doc)
	}

	var total int
	db.QueryRow("SELECT COUNT(*) FROM documents").Scan(&total)

	writeJSON(w, http.StatusOK, DocumentListResponse{
		Documents: documents,
		Total:     total,
		Limit:     limit,
		Offset:    offset,
	})
}

func handleGetDocument(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "Invalid document ID")
		return
	}

	db, err := getDB()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer db.Close()

	var doc Document
	var createdAt sql.NullTime
	err = db.QueryRow("SELECT id, content, created_at FROM documents WHERE id = $1", id).
		Scan(&doc.ID, &doc.Content, &createdAt)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Document not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if createdAt.Valid {
		doc.CreatedAt = createdAt.Time
	}

	writeJSON(w, http.StatusOK, doc)
}

func handleRedactDocument(w http.ResponseWriter, r *http.Request) {
	if cfg.KMS.KeyARN == "" {
		writeError(w, http.StatusInternalServerError, "KMS_KEY_ARN not configured")
		return
	}

	idStr := r.PathValue("id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		writeError(w, http.StatusBadRequest, "Invalid document ID")
		return
	}

	db, err := getDB()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer db.Close()

	var content string
	err = db.QueryRow("SELECT content FROM documents WHERE id = $1", id).Scan(&content)
	if err == sql.ErrNoRows {
		writeError(w, http.StatusNotFound, "Document not found")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	// Encrypt with KMS
	if kmsClient == nil {
		writeError(w, http.StatusInternalServerError, "KMS client not initialized")
		return
	}

	encryptOutput, err := kmsClient.Encrypt(r.Context(), &kms.EncryptInput{
		KeyId:     aws.String(cfg.KMS.KeyARN),
		Plaintext: []byte(content),
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("KMS encryption failed: %v", err))
		return
	}

	encryptedB64 := base64.StdEncoding.EncodeToString(encryptOutput.CiphertextBlob)

	// Get credentials to pass to enclave
	creds, err := getCredentials(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, fmt.Sprintf("Failed to get credentials: %v", err))
		return
	}

	log.Printf("Document %d encrypted, sending to enclave", id)

	resp, err := sendToEnclave(map[string]interface{}{
		"operation":      "detect",
		"encrypted_data": encryptedB64,
		"key_id":         cfg.KMS.KeyARN,
		"credentials":    creds,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, buildDetectResponse(resp))
}

func buildDetectResponse(resp map[string]interface{}) DetectResponse {
	response := DetectResponse{
		Status: resp["status"].(string),
	}
	if text, ok := resp["redacted_text"].(string); ok {
		response.RedactedText = text
	}
	if entities, ok := resp["entities"].([]interface{}); ok {
		response.Entities = make([]map[string]interface{}, len(entities))
		for i, e := range entities {
			response.Entities[i] = e.(map[string]interface{})
		}
	}
	if count, ok := resp["entity_count"].(float64); ok {
		response.EntityCount = int(count)
	}
	if msg, ok := resp["message"].(string); ok {
		response.Error = msg
	}
	return response
}
