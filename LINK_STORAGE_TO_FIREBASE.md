# Link Custom Storage Bucket to Firebase

## The Problem
Firebase doesn't recognize custom-named buckets automatically. We need to link them.

## Solution 1: Initialize Firebase Storage via Console (Recommended)

1. Go to [Firebase Console Storage](https://console.firebase.google.com/project/cgameapp-11628/storage)

2. When you see "Get Started", click it

3. **IMPORTANT**: When it shows the error about domain verification:
   - Look for a **"Import existing bucket"** option
   - Or a **"Use existing Google Cloud Storage bucket"** link
   - Select your bucket: `cgameapp-11628-clips`

4. If no import option appears:
   - Click browser back button
   - Storage might now show as initialized
   - Check if Rules tab is available

## Solution 2: Use gcloud CLI to Set Default Bucket

```bash
# Set your custom bucket as the default for the Firebase project
gcloud config set project cgameapp-11628

# Link the bucket to Firebase
gsutil defacl ch -u firebase-storage@system.gserviceaccount.com:O gs://cgameapp-11628-clips

# Grant Firebase service account access
gsutil iam ch serviceAccount:firebase-storage@system.gserviceaccount.com:roles/storage.admin gs://cgameapp-11628-clips
```

## Solution 3: Manual Rules Upload (Skip Firebase Deploy)

Since you already created the bucket, you can set rules directly in Google Cloud Console:

1. Go to [Google Cloud Storage](https://console.cloud.google.com/storage/browser/cgameapp-11628-clips;tab=permissions?project=cgameapp-11628)

2. Click **PERMISSIONS** tab

3. Click **ADD** and add:
   - **New principals**: `allAuthenticatedUsers`
   - **Role**: `Storage Object Viewer`

4. For user-specific access, you'll need to handle this in your app code using Firebase Auth tokens

## Solution 4: Use the App WITHOUT Firebase Deploy

The bucket exists and works! Just:

1. **Skip the firebase deploy step** - Rules aren't critical for testing

2. **Update your app** (`StorageService.swift`):
```swift
private let STORAGE_ENABLED = true
private let CUSTOM_BUCKET_URL: String? = "gs://cgameapp-11628-clips"
```

3. **Test the app** - It should work with the bucket even without deployed rules

## Solution 5: Initialize Default Bucket (Last Resort)

If you must use Firebase deploy:

1. Try creating the default bucket after all:
```bash
# This might work now that APIs are enabled
gsutil mb -p cgameapp-11628 gs://cgameapp-11628.appspot.com
```

2. If domain verification required, create with alternative:
```bash
gsutil mb -p cgameapp-11628 gs://cgameapp-11628-default
```

3. Update `firebase.json`:
```json
{
  "storage": {
    "rules": "storage.rules",
    "bucket": "cgameapp-11628-clips"
  }
}
```

Then try: `firebase deploy --only storage`

## Immediate Workaround: Direct Storage Usage

Your bucket EXISTS and WORKS! The app can use it directly:

### In `StorageService.swift`, ensure:
```swift
private let STORAGE_ENABLED = true
private let CUSTOM_BUCKET_URL: String? = "gs://cgameapp-11628-clips"
```

### The app will work because:
- ✅ Bucket exists in Google Cloud
- ✅ Firebase SDK can access any GCS bucket
- ✅ Authentication still works via Firebase Auth
- ⚠️ Rules aren't enforced (but Auth still protects access)

## Test Without Rules

1. Build and run the app
2. Sign in (Google/Apple/etc)
3. Record a clip
4. Check if upload works to your bucket

The Firebase SDK will use your custom bucket directly, even if Firebase Console doesn't recognize it!

## Success Indicators

Your storage is working if:
- Files appear in [Google Cloud Console](https://console.cloud.google.com/storage/browser/cgameapp-11628-clips)
- No errors in Xcode console
- Clips upload after recording

## Remember

**The app works perfectly with local storage** if you can't resolve this. Just keep:
```swift
private let STORAGE_ENABLED = false
```

All core features work without cloud storage!