# OpenShift RBAC: Namespace-Per-Team-Per-Environment Design

A **production-ready, fully documented RBAC design** for OpenShift that scales consistently across multiple teams and environments.

## Key Features

✓ **Namespace per team per environment** (`app-<team>-dev/stage/prod`)  
✓ **IdP-managed groups** (not individual users)  
✓ **Dev-first iteration** (humans deploy in dev, CI deploys stage/prod)  
✓ **Secrets locked down** (developers can read in dev only)  
✓ **Break-glass emergency access** in production  
✓ **23 pre-built YAML files** + complete documentation  
✓ **Scales to dozens of teams** without new patterns  

---

## Quick Navigation

| Purpose | Location |
|---------|----------|
| **Commands & troubleshooting** | [One-Liner Commands](#one-liner-commands) below |
| **Architecture & decisions** | [Architecture Summary](#architecture-summary) below |
| **Group setup checklist** | [Groups](#groups) below |
| **Role catalog** | [Role Catalog](#role-catalog) below |
| **Deployment steps** | [Deployment](#deployment) below |
| **Add new team** | [Adding a New Team](#adding-a-new-team) below |

---

## Architecture Summary

### Namespace Layout (per team `<team>`)

```
app-<team>-dev       ← developers can edit + read secrets
app-<team>-stage     ← developers can view only
app-<team>-prod      ← developers can view only + break-glass
```

**Shared namespaces:**
```
platform-tools
platform-observability (optional)
data-shared (or data-<domain>)
```

### Decision: Secrets Policy

**Developers CAN read Secrets in dev only** (fast iteration).  
Stage/prod developers cannot access secrets (policy security).

### Deployment Model

| Environment | Who Deploys | How |
|-------------|-------------|-----|
| **Dev** | Developers + CI | `oc apply` directly or via CI |
| **Stage** | CI/GitOps only | Pull-request-driven, automated |
| **Prod** | CI/GitOps only | Pull-request-driven, approval gates |

---

## Groups

### Cluster-Scoped (IdP Groups)

| Group | Role | Purpose |
|-------|------|---------|
| `ocp-platform-admin` | `cluster-admin` | Platform engineers, cluster admins |
| `ocp-sre-cluster-read` | `cluster-reader` | SRE on-call, read-only cluster visibility |
| `ocp-cyber-audit` | `security-audit` | Compliance & audit, no modifications |
| `ocp-breakglass` | `admin` (prod ns only) | Emergency access, time-bound membership |

### Team-Based Groups

For each application team `<team>`, create:
- `ocp-app-<team>-developers` — team developers
- `ocp-app-<team>-leads` (optional) — team leads, elevated in dev

### Cross-Team Groups (Shared)

| Group | Used In | Role | Purpose |
|-------|---------|------|---------|
| `ocp-devops` | All team namespaces | `admin` | DevOps/platform engineers manage all namespaces |
| `ocp-sre-support` | All team namespaces | `support` | SRE support: read logs, exec pods, no deploy |
| `ocp-cyber-audit` | All namespaces | `view` | Security/compliance: read-only access |

### ServiceAccounts (per namespace)

| Account | Role | Purpose |
|---------|------|---------|
| `ci-deployer` | `deployer` | CI/GitOps applies manifests in all environments |

### Complete Group Roster Example (Payments Team)

```
CLUSTER-LEVEL:
  ocp-platform-admin
  ocp-sre-cluster-read
  ocp-cyber-audit
  ocp-breakglass

TEAM-SPECIFIC:
  ocp-app-payments-developers
  ocp-app-payments-leads (optional)

SHARED/CROSS-TEAM:
  ocp-devops
  ocp-sre-support
```

---

## Role Catalog

### Cluster-Scoped (Built-in)

| Role | Used By | Scope |
|------|---------|-------|
| `cluster-admin` | `ocp-platform-admin` | Full cluster access |
| `cluster-reader` | `ocp-sre-cluster-read` | Read-only cluster visibility |
| `security-audit` | `ocp-cyber-audit` | Compliance auditing |

### Namespace-Scoped (Custom + Built-in)

| Role | Dev | Stage | Prod | Purpose |
|------|-----|-------|------|---------|
| `developer-dev` | ✓ | — | — | Edit + read secrets (fast iteration) |
| `developer-nonprod` | — | ✓ | ✓ | View only, no secrets (read-only) |
| `support` | ✓ | ✓ | ✓ | Troubleshoot: read pods/logs/events + exec |
| `deployer` | ✓ | ✓ | ✓ | CI/GitOps: apply manifests, read-only secrets |
| `admin` (built-in) | ✓ | ✓ | ✓ | DevOps: full namespace control |
| `view` (built-in) | ✓ | ✓ | ✓ | Cyber audit: read-only |

**Location:** [rbac/namespaces/_base/](rbac/namespaces/_base/)

### Role Definitions

#### `developer-dev` (DEV only)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer-dev
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["route.openshift.io"]
  resources: ["routes"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods", "pods/log", "events"]
  verbs: ["get", "list", "watch"]
```

#### `developer-nonprod` (STAGE/PROD, view-only)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer-nonprod
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["services", "configmaps", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["route.openshift.io"]
  resources: ["routes"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
```

#### `support` (SRE troubleshooting)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: support
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "services", "endpoints", "configmaps", "events"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["route.openshift.io"]
  resources: ["routes"]
  verbs: ["get", "list", "watch"]
```

#### `deployer` (CI/GitOps)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployer
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["services", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["route.openshift.io"]
  resources: ["routes"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods", "pods/log", "events"]
  verbs: ["get", "list", "watch"]
```

---

## Environment Policy

### DEV (`app-<team>-dev`)

| Group | Role | Rationale |
|-------|------|-----------|
| `ocp-app-<team>-developers` | `developer-dev` | Fast iteration, edit everything + read secrets |
| `ocp-devops` | `admin` | Full control, RBAC management |
| `ocp-sre-support` | `support` | Troubleshoot, exec pods |
| `ocp-cyber-audit` | `view` | Compliance access |
| `ci-deployer` (SA) | `deployer` | CI/GitOps deployments |

**Effect:** Humans can deploy here directly via `oc apply`.

### STAGE (`app-<team>-stage`)

| Group | Role | Rationale |
|-------|------|-----------|
| `ocp-app-<team>-developers` | `developer-nonprod` | View only, no secrets (read-only) |
| `ocp-devops` | `admin` | Full control |
| `ocp-sre-support` | `support` | Troubleshoot |
| `ocp-cyber-audit` | `view` | Compliance |
| `ci-deployer` (SA) | `deployer` | CI promotions |

**Effect:** Only CI/GitOps deploys; humans read-only.

### PROD (`app-<team>-prod`)

| Group | Role | Rationale |
|-------|------|-----------|
| `ocp-app-<team>-developers` | `developer-nonprod` | View only, no secrets |
| `ocp-devops` | `admin` | Full control (consider guardrails) |
| `ocp-sre-support` | `support` | Troubleshoot |
| `ocp-cyber-audit` | `view` | Compliance |
| `ci-deployer` (SA) | `deployer` | CI deployments |
| `ocp-breakglass` | `admin` | Emergency access only (time-bound) |

**Effect:** Only CI/GitOps deploys; break-glass for emergencies.

---

## Deployment

### Prerequisites

- OpenShift CLI (`oc`) installed and authenticated
- Cluster admin access for initial setup
- IdP groups synced to OpenShift (see [Groups](#groups) above)
- All 23 YAML files in `rbac/`

### Step 1: Create IdP Groups

In your identity provider (LDAP, Okta, Azure AD, etc.), create:

```
Cluster-level:
  ocp-platform-admin
  ocp-sre-cluster-read
  ocp-cyber-audit
  ocp-breakglass

Team-level (example: payments):
  ocp-app-payments-developers
  ocp-app-payments-leads (optional)

Shared/cross-team:
  ocp-devops
  ocp-sre-support
```

### Step 2: Create Namespaces

```bash
# Create team namespaces
oc new-project app-payments-dev
oc new-project app-payments-stage
oc new-project app-payments-prod

# Verify
oc get namespaces | grep payments
```

### Step 3: Apply Cluster-Level RBAC (one-time)

```bash
oc apply -f rbac/cluster/clusterrolebinding-platform-admin.yaml
oc apply -f rbac/cluster/clusterrolebinding-sre-cluster-read.yaml
oc apply -f rbac/cluster/clusterrolebinding-cyber-audit.yaml

# Verify
oc get clusterrolebindings | grep -E "platform-admin|sre-cluster-read|cyber-audit"
```

### Step 4: Apply Base Roles to All Three Namespaces

```bash
TEAM=payments
ENVS=(dev stage prod)

for ENV in "${ENVS[@]}"; do
  NS="app-${TEAM}-${ENV}"
  
  # Apply base roles
  oc apply -n "${NS}" -f rbac/namespaces/_base/role-support.yaml
  oc apply -n "${NS}" -f rbac/namespaces/_base/role-deployer.yaml
  oc apply -n "${NS}" -f rbac/namespaces/_base/role-developer-dev.yaml
  oc apply -n "${NS}" -f rbac/namespaces/_base/role-developer-nonprod.yaml
done

# Verify
oc get roles -n app-payments-dev
oc get roles -n app-payments-stage
oc get roles -n app-payments-prod
```

### Step 5: Apply Team-Specific RoleBindings

```bash
TEAM=payments
ENVS=(dev stage prod)

for ENV in "${ENVS[@]}"; do
  NS="app-${TEAM}-${ENV}"
  oc apply -n "${NS}" -f rbac/namespaces/team-${TEAM}/${ENV}/
done

# Verify
oc get rolebindings -n app-payments-dev
oc get rolebindings -n app-payments-stage
oc get rolebindings -n app-payments-prod
```

### Step 6: Create ServiceAccounts for CI/GitOps

```bash
for ENV in dev stage prod; do
  NS="app-payments-${ENV}"
  oc create serviceaccount ci-deployer -n "${NS}" --dry-run=client -o yaml | oc apply -f -
done

# Verify
oc get sa -n app-payments-dev
```

---

## YAML Validation

All 23 YAML files have been **syntax-validated**:

```
✓ rbac/cluster/clusterrolebinding-cyber-audit.yaml
✓ rbac/cluster/clusterrolebinding-platform-admin.yaml
✓ rbac/cluster/clusterrolebinding-sre-cluster-read.yaml
✓ rbac/namespaces/_base/role-deployer.yaml
✓ rbac/namespaces/_base/role-developer-dev.yaml
✓ rbac/namespaces/_base/role-developer-nonprod.yaml
✓ rbac/namespaces/_base/role-support.yaml
✓ rbac/namespaces/team-payments/dev/rolebinding-ci-deployer.yaml
✓ rbac/namespaces/team-payments/dev/rolebinding-cyber-view.yaml
✓ rbac/namespaces/team-payments/dev/rolebinding-dev-developers-edit.yaml
✓ rbac/namespaces/team-payments/dev/rolebinding-devops-admin.yaml
✓ rbac/namespaces/team-payments/dev/rolebinding-sre-support.yaml
✓ rbac/namespaces/team-payments/prod/rolebinding-breakglass-admin.yaml
✓ rbac/namespaces/team-payments/prod/rolebinding-ci-deployer.yaml
✓ rbac/namespaces/team-payments/prod/rolebinding-cyber-view.yaml
✓ rbac/namespaces/team-payments/prod/rolebinding-devops-admin.yaml
✓ rbac/namespaces/team-payments/prod/rolebinding-prod-developers-view.yaml
✓ rbac/namespaces/team-payments/prod/rolebinding-sre-support.yaml
✓ rbac/namespaces/team-payments/stage/rolebinding-ci-deployer.yaml
✓ rbac/namespaces/team-payments/stage/rolebinding-cyber-view.yaml
✓ rbac/namespaces/team-payments/stage/rolebinding-devops-admin.yaml
✓ rbac/namespaces/team-payments/stage/rolebinding-sre-support.yaml
✓ rbac/namespaces/team-payments/stage/rolebinding-stage-developers-view.yaml
```

To validate on your cluster:

```bash
# Syntax validation (dry-run client-side)
for file in $(find rbac -name "*.yaml"); do
  kubectl apply --dry-run=client -f "$file" --validate=false || echo "ERROR: $file"
done

# Or with oc (requires connected cluster)
for file in $(find rbac -name "*.yaml"); do
  oc apply --dry-run=client -f "$file" || echo "ERROR: $file"
done
```

---

## One-Liner Commands

### Apply Everything for One Team

```bash
TEAM=payments
for ENV in dev stage prod; do
  NS="app-${TEAM}-${ENV}"
  oc apply -n "${NS}" -f rbac/namespaces/_base/ && \
  oc apply -n "${NS}" -f rbac/namespaces/team-${TEAM}/${ENV}/ && \
  oc create sa ci-deployer -n "${NS}" --dry-run=client -o yaml | oc apply -f -
done
```

### Check What a User Can Do

```bash
USER=john.smith
NS=app-payments-dev

oc auth can-i create deployments -n "${NS}" --as="${USER}"
oc auth can-i get secrets -n "${NS}" --as="${USER}"
oc auth can-i delete rolebindings -n "${NS}" --as="${USER}"
```

### Check What a ServiceAccount Can Do

```bash
SA=ci-deployer
NS=app-payments-dev

oc auth can-i create deployments -n "${NS}" \
  --as=system:serviceaccount:${NS}:${SA}
```

### Audit All Bindings in a Namespace

```bash
NS=app-payments-dev
oc get rolebindings,clusterrolebindings -n "${NS}" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.roleRef.kind}/{.roleRef.name}{"\t"}{.subjects[*].name}{"\n"}{end}'
```

### Verify User's Group Membership

```bash
oc describe group ocp-app-payments-developers
# Look for "Members:" section
```

### View All Roles in a Namespace

```bash
oc get roles -n app-payments-dev -o wide
```

### View All RoleBindings in a Namespace

```bash
oc get rolebindings -n app-payments-dev -o wide
```

---

## Adding a New Team

To add a new team (e.g., `frontend`):

### 1. Create New Team Groups in Your IdP

```
ocp-app-frontend-developers
ocp-app-frontend-leads (optional)
```

### 2. Create Namespaces

```bash
oc new-project app-frontend-dev
oc new-project app-frontend-stage
oc new-project app-frontend-prod
```

### 3. Copy and Customize Bindings

```bash
# Copy template
cp -r rbac/namespaces/team-payments rbac/namespaces/team-frontend

# Update group names
cd rbac/namespaces/team-frontend

# Replace payment group names with frontend
sed -i 's/ocp-app-payments/ocp-app-frontend/g' dev/*.yaml
sed -i 's/ocp-app-payments/ocp-app-frontend/g' stage/*.yaml
sed -i 's/ocp-app-payments/ocp-app-frontend/g' prod/*.yaml
```

### 4. Apply Everything

```bash
TEAM=frontend
for ENV in dev stage prod; do
  NS="app-${TEAM}-${ENV}"
  oc apply -n "${NS}" -f rbac/namespaces/_base/ && \
  oc apply -n "${NS}" -f rbac/namespaces/team-${TEAM}/${ENV}/
done
```

---

## Troubleshooting

### User Can't See Resources They Should

Check the user's group membership:

```bash
oc get group ocp-app-payments-developers -o yaml
# Look for the user in 'users:' section
```

Check the RoleBinding exists:

```bash
oc get rolebindings -n app-payments-dev -o wide
# Look for rolebinding matching the group
```

Test the user's access:

```bash
oc auth can-i get pods -n app-payments-dev --as=john.smith
```

### ServiceAccount Can't Deploy

Check the ServiceAccount exists:

```bash
oc get sa -n app-payments-dev
```

Check the RoleBinding:

```bash
oc get rolebindings -n app-payments-dev | grep ci-deployer
```

Test the SA's access:

```bash
oc auth can-i create deployments -n app-payments-dev \
  --as=system:serviceaccount:app-payments-dev:ci-deployer
```

### CI/GitOps Deployment Failing

Most common issues:

1. **ServiceAccount doesn't exist** → Run Step 6 in [Deployment](#deployment)
2. **Role not applied** → Run Step 4 in [Deployment](#deployment)
3. **RoleBinding doesn't reference SA** → Check `rbac/namespaces/team-<team>/<env>/rolebinding-ci-deployer.yaml`
4. **Trying to manage secrets** → CI has read-only secrets; split into separate role if needed

### Permission Denied on Secrets in Prod

**This is correct behavior.** Developers cannot read secrets in stage/prod (policy).

If you need CI to manage secrets:

```yaml
# Create in rbac/namespaces/_base/role-deployer-with-secrets.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployer-with-secrets
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
# ... (rest of deployer permissions)
```

Then bind to `ci-deployer` only in dev:

```bash
# In rbac/namespaces/team-<team>/dev/rolebinding-ci-deployer-secrets.yaml
oc apply -n app-<team>-dev -f rolebinding-ci-deployer-secrets.yaml
```

---

## File Structure

```
.
├── README.md                          ← You are here
├── rbac/
│   ├── cluster/
│   │   ├── clusterrolebinding-platform-admin.yaml
│   │   ├── clusterrolebinding-cyber-audit.yaml
│   │   └── clusterrolebinding-sre-cluster-read.yaml
│   └── namespaces/
│       ├── _base/
│       │   ├── role-support.yaml
│       │   ├── role-deployer.yaml
│       │   ├── role-developer-dev.yaml
│       │   └── role-developer-nonprod.yaml
│       └── team-payments/
│           ├── dev/
│           │   ├── rolebinding-dev-developers-edit.yaml
│           │   ├── rolebinding-devops-admin.yaml
│           │   ├── rolebinding-sre-support.yaml
│           │   ├── rolebinding-cyber-view.yaml
│           │   └── rolebinding-ci-deployer.yaml
│           ├── stage/
│           │   ├── rolebinding-stage-developers-view.yaml
│           │   ├── rolebinding-devops-admin.yaml
│           │   ├── rolebinding-sre-support.yaml
│           │   ├── rolebinding-cyber-view.yaml
│           │   └── rolebinding-ci-deployer.yaml
│           └── prod/
│               ├── rolebinding-prod-developers-view.yaml
│               ├── rolebinding-devops-admin.yaml
│               ├── rolebinding-sre-support.yaml
│               ├── rolebinding-cyber-view.yaml
│               ├── rolebinding-ci-deployer.yaml
│               └── rolebinding-breakglass-admin.yaml
```

Copy `team-payments/` and rename to add more teams.

---

## Next Steps

1. **Create IdP groups** (see [Step 1](#step-1-create-idp-groups) in Deployment)
2. **Create namespaces** (see [Step 2](#step-2-create-namespaces))
3. **Apply cluster RBAC** (see [Step 3](#step-3-apply-cluster-level-rbac-one-time))
4. **Apply team RBAC** (see [Steps 4–6](#step-4-apply-base-roles-to-all-three-namespaces))
5. **Test access** (see [One-Liner Commands](#one-liner-commands))
6. **Add new teams** (see [Adding a New Team](#adding-a-new-team))

---

## Summary

| What | Status |
|------|--------|
| **Architecture** | ✓ Locked in (namespace per team per env) |
| **Groups** | ✓ Template provided |
| **Roles** | ✓ 4 custom roles + built-in roles |
| **Bindings** | ✓ 23 YAML files, all validated |
| **Secrets policy** | ✓ Dev-only read access |
| **Documentation** | ✓ Complete with examples |
| **Ready to deploy** | ✓ Yes |