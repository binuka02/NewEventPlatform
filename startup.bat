@echo off
echo ==========================================
echo   NEW EVENT PLATFORM - STARTUP SCRIPT
echo ==========================================
echo.

echo [1/4] Creating EKS Nodegroup (takes 10-15 mins)...
eksctl create nodegroup --cluster new-event-cluster --region us-east-1 --name workers --node-type t3.micro --nodes 2 --nodes-min 1 --nodes-max 4 --managed
if %errorlevel% neq 0 (
    echo ERROR: Failed to create nodegroup!
    pause
    exit /b 1
)
echo Nodegroup created successfully!
echo.

echo [2/4] Connecting kubectl to cluster...
aws eks update-kubeconfig --region us-east-1 --name new-event-cluster
echo kubectl connected!
echo.

echo [3/4] Starting RDS Database...
aws rds start-db-instance --db-instance-identifier new-event-db --region us-east-1
echo RDS starting... (takes 3-5 mins)
echo.

echo [4/4] Waiting for nodes to be Ready...
kubectl wait --for=condition=Ready nodes --all --timeout=300s
echo.

echo [5/4] Verifying everything is running...
echo.
echo === Kubernetes Nodes ===
kubectl get nodes
echo.
echo === Namespaces ===
kubectl get namespaces
echo.
echo === Secrets ===
kubectl get secrets -n production
echo.

echo ==========================================
echo   STARTUP COMPLETE! Happy coding!
echo   EKS Cluster : new-event-cluster
echo   RDS Endpoint: new-event-db.cy9gc2e8ykby.us-east-1.rds.amazonaws.com
echo   S3 Bucket   : new-event-notifications-896328677531
echo ==========================================
pause
