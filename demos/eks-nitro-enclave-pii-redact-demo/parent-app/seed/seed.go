// Package seed provides database seeding functionality with sample PII documents.
package seed

import (
	"database/sql"
	"fmt"
	"math/rand"
)

// SampleDocuments contains sample documents with various PII types for testing.
var SampleDocuments = []string{
	`Dear Support Team,

My name is John Smith and I need help with my account.
You can reach me at john.smith@example.com or call (555) 123-4567.
My SSN is 123-45-6789 for verification purposes.
My credit card 4532-1234-5678-9012 was charged incorrectly.

Thanks,
John Smith`,

	`Customer Complaint:

I am Sarah Johnson (sarah.j@email.com) and I'm having issues.
Phone: 555-987-6543
DOB: 03/15/1985
Account ending in 4567 shows unauthorized transactions.
Please contact me ASAP.

IP Address for reference: 192.168.1.100`,

	`Medical Record Request:

Patient: Michael Brown
Email: m.brown@hospital.org
Phone: (555) 456-7890
SSN: 987-65-4321
DOB: 12/25/1970

Please send records to:
123 Main Street, Springfield, IL 62701`,

	`Employment Application:

Applicant: Emily Davis
Contact: emily.davis@gmail.com | 555-321-0987
SSN: 456-78-9012
Driver's License: D1234567
Current Address: 456 Oak Ave, Chicago, IL 60601

References available upon request.`,

	`Insurance Claim #12345:

Policyholder: Robert Wilson
Email: r.wilson@insurance.net
Phone: (555) 789-0123
Policy Number: POL-9876543
SSN: 234-56-7890
Bank Account: 1234567890 (for reimbursement)

Incident occurred on 01/15/2024.`,
}

// CreateTable creates the documents table if it doesn't exist.
func CreateTable(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS documents (
			id SERIAL PRIMARY KEY,
			content TEXT NOT NULL,
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
		)
	`)
	return err
}

// InsertDocuments inserts random sample documents into the database.
// Returns the number of successfully inserted records.
func InsertDocuments(db *sql.DB, count int) (int, error) {
	if err := CreateTable(db); err != nil {
		return 0, fmt.Errorf("failed to create table: %w", err)
	}

	inserted := 0
	for range count {
		doc := SampleDocuments[rand.Intn(len(SampleDocuments))]
		_, err := db.Exec("INSERT INTO documents (content) VALUES ($1)", doc)
		if err != nil {
			continue
		}
		inserted++
	}

	return inserted, nil
}
