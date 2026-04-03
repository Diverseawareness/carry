# Supabase Storage Setup for Carry

Storage buckets cannot be created via SQL migrations. Set these up
manually in the Supabase Dashboard or via the Management API.

## Avatars Bucket

Used by `AuthService.uploadAvatar()` to store player profile photos.

### Create the bucket

1. Go to **Storage** in the Supabase Dashboard
2. Click **New bucket**
3. Settings:
   - **Name**: `avatars`
   - **Public**: Yes (images are served via public URLs)
   - **File size limit**: 5 MB
   - **Allowed MIME types**: `image/jpeg`, `image/png`, `image/webp`

### Storage policies

Add these policies under **Storage > Policies > avatars**:

**SELECT (public read)** -- anyone can view avatar images:
```sql
CREATE POLICY "Avatar images are publicly accessible"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');
```

**INSERT (authenticated upload)** -- users can upload their own avatar:
```sql
CREATE POLICY "Users can upload their own avatar"
ON storage.objects FOR INSERT
WITH CHECK (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
);
```

**UPDATE (authenticated overwrite)** -- users can replace their avatar:
```sql
CREATE POLICY "Users can update their own avatar"
ON storage.objects FOR UPDATE
USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
);
```

**DELETE (authenticated delete)** -- users can remove their avatar:
```sql
CREATE POLICY "Users can delete their own avatar"
ON storage.objects FOR DELETE
USING (
    bucket_id = 'avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
);
```

### File path convention

The app uploads avatars to: `{userId}/avatar.jpg`

Example: `d4a01700-1234-5678-9abc-def012345678/avatar.jpg`

This matches the policy above which checks that the first folder
in the path equals the authenticated user's ID.

### Public URL format

```
https://<project-ref>.supabase.co/storage/v1/object/public/avatars/{userId}/avatar.jpg
```

## Management API alternative

If you prefer to script bucket creation:

```bash
curl -X POST 'https://seeitehizboxjbnccnyd.supabase.co/storage/v1/bucket' \
  -H 'Authorization: Bearer <service_role_key>' \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "avatars",
    "name": "avatars",
    "public": true,
    "file_size_limit": 5242880,
    "allowed_mime_types": ["image/jpeg", "image/png", "image/webp"]
  }'
```
