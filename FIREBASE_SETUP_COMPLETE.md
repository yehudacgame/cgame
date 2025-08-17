# 🔥 CGame Firebase Setup Guide - Gaming Edition

## Overview

This guide will help you set up Firebase for CGame with gaming-focused authentication and cloud sync features.

## 🎮 Gaming Authentication Methods Supported

- **Quick Start**: Anonymous authentication for instant gaming
- **Google**: Universal sign-in 
- **Apple**: Premium iOS experience with Sign in with Apple
- **Twitter/X**: Social gaming integration
- **Email/Password**: Classic authentication
- **Gaming Profiles**: Link Steam, Epic, Xbox, PlayStation, Discord and more

## Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Create a project"**
3. Project name: `CGame` (or your preferred name)
4. **Enable Google Analytics** (recommended for user insights)
5. Choose Analytics location and accept terms

## Step 2: Add iOS App to Firebase

1. In Firebase project, click **"Add app"** → **iOS**
2. **Bundle ID**: `com.cgameapp.app` (must match your Xcode project)
3. **App nickname**: `CGame iOS`
4. **App Store ID**: (leave empty for now)
5. **Download `GoogleService-Info.plist`**

### 📁 Important: Add GoogleService-Info.plist to Xcode

1. Drag `GoogleService-Info.plist` into Xcode project
2. **Target**: Add to `CGame` app target ONLY (not extension)
3. **Add to target**: ✅ CGame, ❌ CGameExtension
4. **Copy items**: ✅ Yes

## Step 3: Enable Firebase Services

### Authentication Setup

1. Firebase Console → **Authentication** → **Get started**
2. **Sign-in method** → Enable these methods:

#### Email/Password
- Click **Email/Password** → **Enable** → **Save**

#### Google Sign-In  
- Click **Google** → **Enable**
- **Web SDK configuration**: Copy the **Web client ID** for later
- **Save**

#### Apple Sign-In
- Click **Apple** → **Enable**  
- **Bundle ID**: `com.cgameapp.app`
- Leave other fields empty for now → **Save**

#### Anonymous Authentication
- Click **Anonymous** → **Enable** → **Save**

### Firestore Database Setup

1. Firebase Console → **Firestore Database** → **Create database**
2. **Start in production mode** (we'll update rules)
3. **Location**: Choose `us-central1` or closest to your users
4. **Done**

### Storage Setup  

1. Firebase Console → **Storage** → **Get started**
2. **Start in production mode** 
3. **Location**: Same as Firestore → **Done**

## Step 4: Configure Security Rules

### Firestore Security Rules

Replace default rules with these gamer-friendly rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      
      // User subcollections (settings, clips, gaming profiles, stats)
      match /{document=**} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
    
    // Allow authenticated users to read gaming platform info (if needed)
    match /platforms/{document} {
      allow read: if request.auth != null;
    }
  }
}
```

### Storage Security Rules

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Users can only access their own gaming clips
    match /clips/{userId}/{clipId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Users can only access their own thumbnails
    match /thumbnails/{userId}/{clipId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## Step 5: Add Firebase Dependencies to Xcode

1. Open `CGame.xcodeproj` in Xcode
2. Select project in navigator → **Package Dependencies** tab
3. Click **+** → **Add Package Dependency**
4. URL: `https://github.com/firebase/firebase-ios-sdk`
5. **Dependency Rule**: Up to Next Major Version
6. **Add Package**

### Select Products (IMPORTANT - Main App Only):
Add these to **CGame target ONLY** (not extension):
- ✅ **FirebaseAuth**
- ✅ **FirebaseFirestore** 
- ✅ **FirebaseStorage**
- ✅ **GoogleSignIn** (for Google Sign-In)

**⚠️ DO NOT add Firebase to CGameExtension target - it will cause build issues.**

## Step 6: Apple Sign In Configuration (iOS Developer Account Required)

### Apple Developer Console Setup
1. [Apple Developer Console](https://developer.apple.com/) → **Certificates, Identifiers & Profiles**
2. **Identifiers** → Your App ID (`com.cgameapp.app`)
3. **Capabilities** → **Sign In with Apple** → ✅ **Enable** 
4. **Save**

### Update Firebase Apple Configuration
1. Firebase Console → **Authentication** → **Sign-in method** → **Apple**
2. **Services ID**: (optional - leave empty)
3. **Apple Team ID**: Find in Apple Developer account membership
4. **Key ID** & **Private Key**: (optional for basic setup)
5. **Save**

## Step 7: Google Sign-In Configuration

### Get Web Client ID
1. Firebase Console → **Project Settings** → **General**
2. **Your apps** → **Web app** → **SDK setup and configuration**
3. Copy the **Web client ID** (looks like: `123456789-abc123.googleusercontent.com`)

### Update Info.plist
1. Open `CGame/Info.plist` in Xcode
2. Add new entry:
   - **Key**: `REVERSED_CLIENT_ID`
   - **Type**: String  
   - **Value**: Reverse of Web Client ID (e.g., `com.googleusercontent.apps.123456789-abc123`)

## Step 8: Test Firebase Integration

### Build and Run
1. **Clean Build**: ⌘⇧K
2. **Build**: ⌘B  
3. **Run on Device**: ⌘R (Firebase requires physical device)

### Test Authentication Flow
1. Launch app → **Authentication screen should appear**
2. Try **Quick Start** → Should sign in anonymously
3. Try **Google Sign-In** → Should show Google auth flow
4. Try **Apple Sign-In** → Should show Apple auth flow

### Verify Cloud Sync
1. Sign in with full account (not anonymous)
2. Record gameplay and create clips  
3. Check **Firebase Console** → **Firestore** → Should see user data
4. Check **Storage** → Should see uploaded video files

## 🎯 Gaming Features Enabled

### User Experience
- **Quick Start**: Instant gaming without account creation
- **Multiple Sign-In Options**: Choose your preferred platform
- **Gaming Profile Linking**: Connect Steam, Epic, Xbox, PlayStation accounts
- **Automatic Cloud Sync**: Clips automatically upload for signed-in users
- **Cross-Device Access**: Access clips on any device
- **Smart Storage**: Local clips for anonymous users, cloud for authenticated

### Data Structure Created
```
Firestore:
/users/{userId}/
  ├── settings/userSettings (video quality, game profiles)
  ├── clips/{clipId} (metadata, events, timestamps)
  ├── gamingProfiles/{profileId} (Steam, Xbox, etc.)
  └── stats/overall (kills, playtime, achievements)

Storage:
/clips/{userId}/{clipId}.mp4 (actual video files)
/thumbnails/{userId}/{clipId}.jpg (video thumbnails)
```

## 🚀 Ready to Game!

Your Firebase setup is complete! The app now supports:

- **Anonymous gaming** for quick sessions
- **Full account creation** for cloud features  
- **Multi-platform sign-in** for gamers
- **Automatic cloud backup** of gaming highlights
- **Gaming profile integration** across platforms

## Troubleshooting

### Common Issues

**Build Errors**: Make sure Firebase is added to main app target only, not extension

**Sign-In Fails**: Check bundle IDs match between Xcode and Firebase Console

**Google Sign-In Issues**: Verify REVERSED_CLIENT_ID in Info.plist

**No Clips Syncing**: Check Firestore rules and user authentication status

### Debug Steps
1. Check **Xcode Console** for Firebase initialization logs
2. **Firebase Console** → **Authentication** → **Users** to see sign-ins
3. **Firestore** → **Data** to verify clip uploads  
4. **Storage** → **Files** to see video uploads

## Support

For technical issues:
- Check Firebase Console error logs
- Verify security rules and authentication
- Test with clean install on device
- Check Xcode build logs for specific errors

**Your gaming highlight app is now powered by Firebase! 🎮🔥**