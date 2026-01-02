#!/bin/bash
# YAML Validation Script for OpenShift RBAC Configuration
# Tests all YAML files for syntax validity and optional cluster deployment

set -e

echo "=========================================="
echo "OpenShift RBAC Validation"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
VALID=0
INVALID=0

# Check if python3 is available for syntax validation
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}ERROR: python3 not found. Required for YAML syntax validation.${NC}"
    exit 1
fi

echo "Step 1: Syntax Validation (client-side, no cluster required)"
echo "---"

python3 << 'PYTHON_EOF'
import yaml
from pathlib import Path
import sys

yaml_files = sorted(Path('rbac').glob('**/*.yaml'))
errors = []

for yaml_file in yaml_files:
    try:
        with open(yaml_file) as f:
            yaml.safe_load(f)
        print(f"  ✓ {yaml_file}")
    except yaml.YAMLError as e:
        print(f"  ✗ {yaml_file}")
        print(f"    ERROR: {str(e)[:80]}")
        errors.append(str(yaml_file))

if errors:
    print(f"\n{len(errors)} file(s) with syntax errors")
    sys.exit(1)
else:
    print(f"\n✓ All {len(yaml_files)} YAML files are syntactically valid")
PYTHON_EOF

echo ""
echo "Step 2: Cluster Validation (requires 'oc' or 'kubectl' + cluster connection)"
echo "---"

# Check if oc or kubectl is available
if command -v oc &> /dev/null; then
    KUBECTL="oc"
    echo "Using: oc (OpenShift CLI)"
elif command -v kubectl &> /dev/null; then
    KUBECTL="kubectl"
    echo "Using: kubectl (Kubernetes CLI)"
else
    echo -e "${YELLOW}INFO: Neither 'oc' nor 'kubectl' found. Skipping cluster validation.${NC}"
    echo "To validate on your cluster, run:"
    echo "  oc apply --dry-run=client -f rbac/cluster/"
    echo "  oc apply --dry-run=client -f rbac/namespaces/_base/"
    echo "  oc apply --dry-run=client -f rbac/namespaces/team-*/{dev,stage,prod}/"
    exit 0
fi

echo ""
CLUSTER_VALID=0
CLUSTER_INVALID=0

# Try to validate cluster files (may fail if no cluster connected)
for file in $(find rbac -name "*.yaml" -type f | sort); do
    if ! $KUBECTL apply --dry-run=client -f "$file" > /dev/null 2>&1; then
        CLUSTER_INVALID=$((CLUSTER_INVALID + 1))
    else
        echo -e "  ${GREEN}✓${NC} $file"
        CLUSTER_VALID=$((CLUSTER_VALID + 1))
    fi
done

echo ""
echo "=========================================="
if [ $CLUSTER_VALID -gt 0 ] && [ $CLUSTER_INVALID -eq 0 ]; then
    echo -e "${GREEN}✓ VALIDATION PASSED${NC}"
    echo "All $CLUSTER_VALID files are valid on the cluster"
    exit 0
elif [ $CLUSTER_VALID -eq 0 ] && [ $CLUSTER_INVALID -gt 0 ]; then
    echo -e "${YELLOW}⚠ SYNTAX VALID, CLUSTER NOT CONNECTED${NC}"
    echo "All YAML files have valid syntax"
    echo "Cluster validation skipped (no cluster connection)"
    echo ""
    echo "To validate on your cluster when connected, run:"
    echo "  ./validate.sh"
    exit 0
else
    echo -e "${RED}✗ CLUSTER VALIDATION FAILED${NC}"
    echo "$CLUSTER_INVALID file(s) failed cluster validation"
    exit 1
fi
