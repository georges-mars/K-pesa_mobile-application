#!/bin/bash
# Reset database completely

echo "⚠️  This will DELETE ALL DATA from the database!"
read -p "Are you sure? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo "Clearing database..."
psql -U kpesa_user -d kpesa -f clear-database.sql

echo "Regenerating encryption keys..."
node key-setup.js

echo "✅ Database reset complete!"
