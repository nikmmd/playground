// Package config provides centralized configuration for the parent application.
package config

import (
	"os"
	"strconv"
)

// Config holds all application configuration.
type Config struct {
	Server   ServerConfig
	Enclave  EnclaveConfig
	KMS      KMSConfig
	Postgres PostgresConfig
}

// ServerConfig holds HTTP server settings.
type ServerConfig struct {
	Host string
	Port int
}

// EnclaveConfig holds Nitro Enclave settings.
type EnclaveConfig struct {
	CID      uint32
	Port     uint32
	EIFPath  string
	CPUs     int
	MemoryMB int
}

// KMSConfig holds AWS KMS settings.
type KMSConfig struct {
	KeyARN    string
	ProxyPort int
	Region    string
}

// PostgresConfig holds database connection settings.
type PostgresConfig struct {
	Host     string
	Port     int
	Database string
	User     string
	Password string
}

// IsConfigured returns true if PostgreSQL is fully configured.
func (p PostgresConfig) IsConfigured() bool {
	return p.Host != "" && p.User != "" && p.Password != ""
}

// Load reads configuration from environment variables.
func Load() *Config {
	return &Config{
		Server: ServerConfig{
			Host: getEnv("HOST", "0.0.0.0"),
			Port: getEnvInt("PORT", 8080),
		},
		Enclave: EnclaveConfig{
			CID:      uint32(getEnvInt("ENCLAVE_CID", 16)),
			Port:     uint32(getEnvInt("VSOCK_PORT", 5000)),
			EIFPath:  getEnv("EIF_PATH", "/enclave/server.eif"),
			CPUs:     getEnvInt("ENCLAVE_CPUS", 2),
			MemoryMB: getEnvInt("ENCLAVE_MEMORY_MB", 2048),
		},
		KMS: KMSConfig{
			KeyARN:    getEnv("KMS_KEY_ARN", ""),
			ProxyPort: getEnvInt("KMS_PROXY_PORT", 8000),
			Region:    getEnv("AWS_REGION", "us-east-1"),
		},
		Postgres: PostgresConfig{
			Host:     getEnv("POSTGRES_HOST", ""),
			Port:     getEnvInt("POSTGRES_PORT", 5432),
			Database: getEnv("POSTGRES_DATABASE", "eventsdb"),
			User:     getEnv("POSTGRES_USER", ""),
			Password: getEnv("POSTGRES_PASSWORD", ""),
		},
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}
