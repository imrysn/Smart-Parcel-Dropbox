#!/bin/bash
# Performance Optimization Script
# Applies all recommended fixes to the Flutter app

echo "🚀 Starting Performance Optimization..."
echo ""

# Backup original files
echo "📦 Creating backups..."
cp lib/screens/home_screen.dart lib/screens/home_screen.dart.backup
echo "✅ Backed up home_screen.dart"

# Replace home screen with optimized version
echo ""
echo "🔧 Applying optimizations..."
if [ -f "lib/screens/home_screen_optimized.dart" ]; then
    cp lib/screens/home_screen_optimized.dart lib/screens/home_screen.dart
    echo "✅ Replaced home_screen.dart with optimized version"
else
    echo "⚠️  home_screen_optimized.dart not found, skipping..."
fi

# Run flutter clean and get dependencies
echo ""
echo "🧹 Cleaning build artifacts..."
flutter clean

echo ""
echo "📥 Getting dependencies..."
flutter pub get

# Check for performance issues
echo ""
echo "🔍 Checking for common performance issues..."
echo ""

# Check for missing const keywords
echo "Checking for missing 'const' keywords..."
grep -r "Icon(" lib/screens/*.dart | grep -v "const Icon" | wc -l | xargs -I {} echo "  Found {} Icons without const"
grep -r "Text(" lib/screens/*.dart | grep -v "const Text" | grep -v "Text(" | wc -l | xargs -I {} echo "  Found {} Text widgets without const"
grep -r "SizedBox(" lib/screens/*.dart | grep -v "const SizedBox" | wc -l | xargs -I {} echo "  Found {} SizedBox without const"

# Check for ListView without keys
echo ""
echo "Checking for ListView without keys..."
grep -r "ListView.builder" lib/screens/*.dart | grep -v "key:" | wc -l | xargs -I {} echo "  Found {} ListViews potentially missing keys"

# Check for FutureBuilder in build method
echo ""
echo "Checking for FutureBuilder issues..."
grep -r "FutureBuilder" lib/screens/*.dart | wc -l | xargs -I {} echo "  Found {} FutureBuilder usages (verify they cache futures)"

echo ""
echo "✨ Optimization complete!"
echo ""
echo "📋 Next steps:"
echo "  1. Review PERFORMANCE_OPTIMIZATION_APPLIED.md"
echo "  2. Test app: flutter run"
echo "  3. Profile with: flutter run --profile"
echo "  4. Use DevTools to verify improvements"
echo ""
echo "🔄 To restore backups:"
echo "  cp lib/screens/home_screen.dart.backup lib/screens/home_screen.dart"
