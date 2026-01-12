#!/bin/bash
set -euo pipefail

# Load Testing Script
# This script generates load on services to test scaling and resilience

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

show_usage() {
    echo "Usage: $0 <service> <requests> [duration]"
    echo ""
    echo "Services:"
    echo "  api-service    - Load test API service"
    echo "  worker-service - Load test worker service"
    echo ""
    echo "Examples:"
    echo "  $0 api-service 1000"
    echo "  $0 api-service 1000 60  # 1000 requests over 60 seconds"
    exit 1
}

if [ $# -lt 2 ]; then
    show_usage
fi

SERVICE=$1
REQUESTS=$2
DURATION=${3:-60}

# Get service endpoint
SERVICE_ENDPOINT=""
NAMESPACE="production"

case $SERVICE in
    api-service)
        SERVICE_ENDPOINT=$(kubectl get svc api-service -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
        PORT=80
        ;;
    worker-service)
        SERVICE_ENDPOINT=$(kubectl get svc worker-service -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
        PORT=8080
        ;;
    *)
        print_error "Unknown service: $SERVICE"
        show_usage
        ;;
esac

if [ -z "$SERVICE_ENDPOINT" ]; then
    print_error "Service $SERVICE not found in namespace $NAMESPACE"
    exit 1
fi

print_status "Starting load test on $SERVICE"
print_status "Endpoint: $SERVICE_ENDPOINT:$PORT"
print_status "Requests: $REQUESTS"
print_status "Duration: ${DURATION}s"

# Check if curl is available
if ! command -v curl &> /dev/null; then
    print_warning "curl not found. Creating a load test pod..."
    
    # Create a temporary pod for load testing
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: load-test-$(date +%s)
  namespace: $NAMESPACE
spec:
  containers:
  - name: load-test
    image: curlimages/curl:latest
    command: ["sh", "-c"]
    args:
    - |
      echo "Starting load test..."
      for i in \$(seq 1 $REQUESTS); do
        curl -s -o /dev/null -w "%{http_code}\n" http://$SERVICE_ENDPOINT:$PORT/ || true
        sleep $(echo "scale=3; $DURATION / $REQUESTS" | bc)
      done
      echo "Load test complete"
  restartPolicy: Never
EOF
    
    print_status "Load test pod created. Monitor with:"
    echo "  kubectl logs -f -n $NAMESPACE load-test-*"
else
    # Use local curl
    print_status "Running load test locally..."
    
    RATE=$(echo "scale=2; $REQUESTS / $DURATION" | bc)
    print_status "Request rate: ${RATE} req/s"
    
    for i in $(seq 1 $REQUESTS); do
        curl -s -o /dev/null -w "Request $i: %{http_code}\n" \
            http://$SERVICE_ENDPOINT:$PORT/ || true
        sleep $(echo "scale=3; $DURATION / $REQUESTS" | bc)
    done
fi

print_status "Load test complete. Monitor resource usage:"
echo "  kubectl top nodes"
echo "  kubectl top pods -n $NAMESPACE"
echo "  kubectl get hpa -n $NAMESPACE  # If HPA is configured"
echo ""

