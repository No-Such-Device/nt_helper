#!/bin/bash

# Release notes generation script for GitHub Actions workflow
# This script generates categorized release notes from git commits and PRs
# Usage: ./scripts/release-notes-for-workflow.sh [current-tag] [previous-tag]

set -e

CURRENT_TAG=${1:-$GITHUB_REF_NAME}
PREVIOUS_TAG=${2:-$(git tag --sort=-version:refname | grep -v "$CURRENT_TAG" | head -1)}

if [ -z "$CURRENT_TAG" ]; then
    echo "Error: No tag specified"
    exit 1
fi

if [ -z "$PREVIOUS_TAG" ]; then
    echo "Warning: No previous tag found, using initial commit"
    PREVIOUS_TAG=$(git rev-list --max-parents=0 HEAD)
fi

echo "Generating release notes for $CURRENT_TAG (comparing with $PREVIOUS_TAG)"

# A reviewed version-specific summary avoids publishing superseded intermediate
# implementation descriptions from a multi-commit fix series. Other versions
# retain the established categorized-commit fallback below.
VERSION_NOTES="docs/releases/${CURRENT_TAG#v}.md"
if [ -f "$VERSION_NOTES" ]; then
    {
        cat "$VERSION_NOTES"
        echo ""
        echo "---"
        echo "**Full Changelog**: https://github.com/No-Such-Device/nt_helper/compare/${PREVIOUS_TAG}...${CURRENT_TAG}"
    } > release_notes.md
    cat release_notes.md
    exit 0
fi

# Generate release notes with categorization
{
    echo "## 🚀 What's New in $CURRENT_TAG"
    echo ""
    
    # Features (feat:, add:, new:)
    FEATURES=$(git log --pretty=format:"- %s" ${PREVIOUS_TAG}..${CURRENT_TAG} --grep="feat:" --grep="add:" --grep="new:" --grep="feature:" -i)
    if [ ! -z "$FEATURES" ]; then
        echo "### ✨ Features"
        echo "$FEATURES"
        echo ""
    fi
    
    # Improvements (improve:, enhance:, update:)  
    IMPROVEMENTS=$(git log --pretty=format:"- %s" ${PREVIOUS_TAG}..${CURRENT_TAG} --grep="improve:" --grep="enhance:" --grep="update:" --grep="refactor:" -i)
    if [ ! -z "$IMPROVEMENTS" ]; then
        echo "### 🔧 Improvements"
        echo "$IMPROVEMENTS"
        echo ""
    fi
    
    # Bug fixes (fix:, bug:)
    FIXES=$(git log --pretty=format:"- %s" ${PREVIOUS_TAG}..${CURRENT_TAG} --grep="fix:" --grep="bug:" -i)
    if [ ! -z "$FIXES" ]; then
        echo "### 🐛 Bug Fixes"
        echo "$FIXES"
        echo ""
    fi
    
    # Documentation (docs:, doc:)
    DOCS=$(git log --pretty=format:"- %s" ${PREVIOUS_TAG}..${CURRENT_TAG} --grep="docs:" --grep="doc:" -i)
    if [ ! -z "$DOCS" ]; then
        echo "### 📚 Documentation"
        echo "$DOCS"
        echo ""
    fi
    
    # Pull requests merged
    PRS=$(git log --pretty=format:"- %s" ${PREVIOUS_TAG}..${CURRENT_TAG} --grep="#[0-9]" | head -10)
    if [ ! -z "$PRS" ]; then
        echo "### 📋 Pull Requests"
        echo "$PRS"
        echo ""
    fi
    
    # Other changes (excluding the categorized ones and version bumps)
    OTHER=$(git log --pretty=format:"- %s" ${PREVIOUS_TAG}..${CURRENT_TAG} --invert-grep --grep="feat:" --grep="add:" --grep="new:" --grep="feature:" --grep="improve:" --grep="enhance:" --grep="update:" --grep="refactor:" --grep="fix:" --grep="bug:" --grep="docs:" --grep="doc:" --grep="Bump version" --grep="bump version" -i)
    if [ ! -z "$OTHER" ]; then
        echo "### 🔄 Other Changes"
        echo "$OTHER"
        echo ""
    fi
    
    echo "---"
    echo "**Full Changelog**: https://github.com/thorinside/nt_helper/compare/${PREVIOUS_TAG}...${CURRENT_TAG}"
    
} > release_notes.md

# Output the content for workflow use
cat release_notes.md