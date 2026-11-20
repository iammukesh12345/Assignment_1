
#!/usr/bin/env bash
set -Eeuo pipefail

# Employee Management Kubernetes Deployment
# Designed for local Kind cluster on AWS EC2.

CLUSTER_NAME="employee-cluster"
NAMESPACE="employee-management"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
K8S_DIR="$SRC_DIR/kubernetes"

BACKEND_IMAGE="${BACKEND_IMAGE:-employee-backend:v1}"
FRONTEND_IMAGE="${FRONTEND_IMAGE:-employee-frontend:v1}"

log() {
    echo
    echo "========== $1 =========="
}

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

# ------------------------------------------------------------
# Validate dependencies and cluster
# ------------------------------------------------------------

log "Checking prerequisites"

for tool in docker kind kubectl; do
    command -v "$tool" >/dev/null || fail "$tool not found"
done

docker info >/dev/null 2>&1 || fail "Docker unavailable"

kind get clusters | grep -Fxq "$CLUSTER_NAME" ||
    fail "Kind cluster $CLUSTER_NAME not found"

kubectl config use-context "kind-${CLUSTER_NAME}"

kubectl get nodes

# ------------------------------------------------------------
# Generate Kubernetes manifests
# ------------------------------------------------------------

log "Generating Kubernetes manifests"

mkdir -p "$K8S_DIR"

cat > "$K8S_DIR/namespace.yaml" <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: employee-management
EOF

cat > "$K8S_DIR/configmap.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: employee-config
  namespace: employee-management
data:
  DB_HOST: postgres
  DB_PORT: "5432"
  DB_USER: employee
  DB_NAME: employees
  ALLOWED_ORIGINS: "*"
EOF

cat > "$K8S_DIR/postgres.yaml" <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: employee-management
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: standard
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: employee-management
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              value: employee
            - name: POSTGRES_DB
              value: employees
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: DB_PASSWORD
          volumeMounts:
            - name: postgres-storage
              mountPath: /var/lib/postgresql/data
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - pg_isready -U employee -d employees
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests:
              memory: 128Mi
              cpu: 100m
            limits:
              memory: 512Mi
      volumes:
        - name: postgres-storage
          persistentVolumeClaim:
            claimName: postgres-data
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: employee-management
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
EOF

cat > "$K8S_DIR/backend.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: employee-management
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
        - name: backend
          image: employee-backend:v1
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: employee-config
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: DB_PASSWORD
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests:
              memory: 64Mi
              cpu: 50m
            limits:
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: employee-management
spec:
  selector:
    app: backend
  ports:
    - port: 8080
      targetPort: 8080
EOF

cat > "$K8S_DIR/frontend.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: employee-management
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: frontend
          image: employee-frontend:v1
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            requests:
              memory: 32Mi
              cpu: 25m
            limits:
              memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: employee-management
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
EOF

# ------------------------------------------------------------
# Validate database password
# ------------------------------------------------------------

log "Checking database password"

if [[ -z "${DB_PASSWORD:-}" ]]; then
    read -r -s -p "Enter Kubernetes PostgreSQL password: " DB_PASSWORD
    echo
fi

[[ -n "$DB_PASSWORD" ]] || fail "Database password is empty"

# ------------------------------------------------------------
# Create namespace and secret
# ------------------------------------------------------------

log "Creating namespace"

kubectl apply -f "$K8S_DIR/namespace.yaml"

log "Creating PostgreSQL Secret"

kubectl -n "$NAMESPACE" create secret generic postgres-secret \
    --from-literal=DB_PASSWORD="$DB_PASSWORD" \
    --dry-run=client -o yaml |
    kubectl apply -f -

unset DB_PASSWORD

# ------------------------------------------------------------
# Load images into Kind
# ------------------------------------------------------------

log "Loading Docker images into Kind"

kind load docker-image \
    "$BACKEND_IMAGE" \
    "$FRONTEND_IMAGE" \
    --name "$CLUSTER_NAME"

# ------------------------------------------------------------
# Deploy application
# ------------------------------------------------------------

log "Deploying PostgreSQL"

kubectl apply -f "$K8S_DIR/configmap.yaml"
kubectl apply -f "$K8S_DIR/postgres.yaml"

kubectl -n "$NAMESPACE" rollout status \
    deployment/postgres --timeout=180s

log "Deploying backend"

kubectl apply -f "$K8S_DIR/backend.yaml"

kubectl -n "$NAMESPACE" rollout status \
    deployment/backend --timeout=180s

log "Deploying frontend"

kubectl apply -f "$K8S_DIR/frontend.yaml"

kubectl -n "$NAMESPACE" rollout status \
    deployment/frontend --timeout=180s

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------

log "Checking Kubernetes resources"

kubectl -n "$NAMESPACE" get pods
kubectl -n "$NAMESPACE" get services
kubectl -n "$NAMESPACE" get pvc

log "Deployment completed"

echo "Application: http://localhost:8081"
echo "Use an SSH tunnel to access it from your laptop."

