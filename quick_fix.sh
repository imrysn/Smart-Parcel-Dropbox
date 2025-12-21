#!/bin/bash

# Quick Fix Script for Smart Parcel Drop Box
# This script fixes common errors and rebuilds the project

echo "🔧 Starting Quick Fix Process..."
echo ""

# Step 1: Clean the project
echo "1️⃣ Cleaning project..."
flutter clean
echo "✅ Clean complete"
echo ""

# Step 2: Remove generated files
echo "2️⃣ Removing old generated files..."
rm -rf .dart_tool
rm -rf build
echo "✅ Generated files removed"
echo ""

# Step 3: Get dependencies
echo "3️⃣ Getting dependencies..."
flutter pub get
echo "✅ Dependencies installed"
echo ""

# Step 4: Run build_runner if needed
echo "4️⃣ Running code generation..."
flutter pub run build_runner build --delete-conflicting-outputs
echo "✅ Code generation complete"
echo ""

# Step 5: Analyze for errors
echo "5️⃣ Analyzing code..."
flutter analyze
echo ""

# Step 6: Run tests
echo "6️⃣ Running tests..."
flutter test
echo ""

echo "✅ Quick Fix Complete!"
echo ""
echo "Next steps:"
echo "- If you see errors, read ERROR_FIXES.md"
echo "- Run 'flutter run' to start the app"
echo "- Check Firebase Console for Crashlytics data"
