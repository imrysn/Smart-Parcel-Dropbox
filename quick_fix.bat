@echo off
REM Quick Fix Script for Smart Parcel Drop Box (Windows)
REM This script fixes common errors and rebuilds the project

echo 🔧 Starting Quick Fix Process...
echo.

REM Step 1: Clean the project
echo 1️⃣ Cleaning project...
call flutter clean
echo ✅ Clean complete
echo.

REM Step 2: Remove generated files
echo 2️⃣ Removing old generated files...
if exist .dart_tool rmdir /s /q .dart_tool
if exist build rmdir /s /q build
echo ✅ Generated files removed
echo.

REM Step 3: Get dependencies
echo 3️⃣ Getting dependencies...
call flutter pub get
echo ✅ Dependencies installed
echo.

REM Step 4: Run build_runner if needed  
echo 4️⃣ Running code generation...
call flutter pub run build_runner build --delete-conflicting-outputs
echo ✅ Code generation complete
echo.

REM Step 5: Analyze for errors
echo 5️⃣ Analyzing code...
call flutter analyze
echo.

REM Step 6: Run tests
echo 6️⃣ Running tests...
call flutter test
echo.

echo ✅ Quick Fix Complete!
echo.
echo Next steps:
echo - If you see errors, read ERROR_FIXES.md
echo - Run 'flutter run' to start the app
echo - Check Firebase Console for Crashlytics data
echo.
pause
