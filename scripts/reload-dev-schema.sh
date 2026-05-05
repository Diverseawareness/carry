#!/bin/bash
# Reloads the PostgREST schema cache on the Supabase dev branch.
# Run this when the app shows PGRST205 "Could not find table in schema cache".

SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdiaGxqd3Rib2JieGVydmVreGtnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3ODAwNzgyMiwiZXhwIjoyMDkzNTgzODIyfQ.SjsOl-OeCldiYdDKTIBvc_O_oc2yjbsPRiuSnxf_Xk0"
DEV_URL="https://gbhljwtbobbxervekxkg.supabase.co"

curl -s -X POST "$DEV_URL/rest/v1/rpc/reload_pgrst_schema" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  && echo "✓ Dev schema cache reloaded"
