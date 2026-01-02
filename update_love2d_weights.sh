#!/bin/bash
# Exports the latest training checkpoint to Love2D game weights
# Usage: ./update_love2d_weights.sh

set -e

cd "$(dirname "$0")"

echo "🎯 Finding latest checkpoint..."
LATEST=$(ls -1 five_hundred/static/model_checkpoint_*.pth 2>/dev/null | sort -t_ -k3 -n | tail -1)

if [ -z "$LATEST" ]; then
    echo "❌ No checkpoints found in five_hundred/static/"
    exit 1
fi

echo "📦 Latest checkpoint: $LATEST"
echo "🔄 Exporting weights to Love2D..."

python export_weights.py

echo "✅ Done! Love2D game updated with latest model."
echo "   Run: love five_hundred_love"
