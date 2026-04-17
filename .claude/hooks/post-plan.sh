#!/bin/bash

# Post-Plan Hook: 플랜 완료 후 문서 생성 가이드
# 이 훅은 플랜 작업이 완료된 후 사용자에게 다음 단계를 안내합니다.

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLAN_DIR="$PROJECT_ROOT/.claude/plans"
DOCS_DIR="$PROJECT_ROOT/docs"

# 가장 최근의 플랜 파일 찾기
LATEST_PLAN=$(ls -t "$PLAN_DIR"/*.md 2>/dev/null | head -1)

if [ -z "$LATEST_PLAN" ]; then
  echo "ℹ️  플랜 파일을 찾을 수 없습니다."
  exit 0
fi

PLAN_NAME=$(basename "$LATEST_PLAN" .md)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 플랜 작업 완료!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 다음 작업 가이드:"
echo ""
echo "1️⃣  구현 코드 작성 (위 플랜 참고)"
echo ""
echo "2️⃣  문서 작성:"
echo "   - docs/changelog-v*.md 파일 생성 (구현 내용 정리)"
echo "   - CLAUDE.md 버전 업데이트"
echo "   - docs/db-schema.md 스키마 변경사항 추가"
echo "   - docs/ui-architecture.md 위젯 변경사항 추가"
echo "   - docs/features.md 기능 체크리스트 업데이트"
echo ""
echo "3️⃣  빌드 검증:"
echo "   flutter analyze"
echo ""
echo "4️⃣  커밋 (선택):"
echo "   git add docs/"
echo "   git commit -m 'docs: update for v* changes'"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
