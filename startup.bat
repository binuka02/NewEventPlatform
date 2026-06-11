@echo off
echo ==========================================
echo   NEW EVENT PLATFORM - STARTUP SCRIPT
echo ==========================================
echo.
echo This will recreate:
echo   - EKS Cluster        (takes 15-20 mins)
echo   - RDS Database       (takes 5-10 mins)
echo   - Kubernetes Secrets (instant)
echo   - S3 Bucket already exists - skipping
echo.
echo Total time: approximately 30 minutes.
echo Press Ctrl+C to cancel or any key to continue...
pause > nul
echo.

echo [1/5] Creating EKS Cluster (takes 15-20 mins)...
eksctl create cluster --name new-event-cluster --region us-east-1 --nodegroup-name workers --node-type t3.micro --nodes 2 --nodes-min 1 --nodes-max 4 --managed --version 1.31
if %errorlevel% neq 0 (
    echo.
    echo eksctl timed out - cluster may still be creating on AWS...
    echo Waiting 3 minutes then checking...
    timeout /t 180 /nobreak
    echo.
    echo Checking nodegroup status...
    aws eks list-nodegroups --cluster-name new-event-cluster --region us-east-1
    echo.
    echo -----------------------------------------------
    echo If nodegroup list is empty, do this manually:
    echo 1. Go to AWS Console - EKS - new-event-cluster
    echo 2. Click Compute tab
    echo 3. Click Add node group
    echo 4. Name: workers
    echo 5. Instance type: t3.micro
    echo 6. Desired: 2, Min: 1, Max: 4
    echo 7. Click Create
    echo 8. Come back here and press any key
    echo -----------------------------------------------
    pause > nul
)
echo.

echo [2/5] Connecting kubectl to cluster...
aws eks update-kubeconfig --region us-east-1 --name new-event-cluster
if %errorlevel% neq 0 (
    echo ERROR: kubectl connection failed!
    pause
    exit /b 1
)
echo kubectl connected!
echo.

echo [3/5] Creating RDS PostgreSQL Database...
aws rds create-db-instance --db-instance-identifier new-event-db --db-instance-class db.t4g.micro --engine postgres --master-username postgres --master-user-password NewEvent2026! --allocated-storage 20 --no-multi-az --db-name neweventdb --region us-east-1
if %errorlevel% neq 0 (
    echo WARNING: RDS creation had issues - check AWS console
) else (
    echo RDS creation started...
    echo Waiting for RDS to be available (5-10 mins)...
    aws rds wait db-instance-available --db-instance-identifier new-event-db --region us-east-1
    echo RDS is ready!
)
echo.

echo [4/5] Creating Kubernetes Namespaces and Secrets...
kubectl create namespace production
kubectl create namespace monitoring  
kubectl create namespace analytics
echo.
echo Getting RDS endpoint...
for /f "tokens=*" %%i in ('aws rds describe-db-instances --db-instance-identifier new-event-db --query "DBInstances[0].Endpoint.Address" --output text --region us-east-1') do set RDS_HOST=%%i
echo RDS Endpoint: %RDS_HOST%
echo.
kubectl create secret generic db-secret --from-literal=host=%RDS_HOST% --from-literal=port=5432 --from-literal=database=neweventdb --from-literal=username=postgres --from-literal=password=NewEvent2026! -n production
kubectl create secret generic aws-secret --from-literal=bucket-name=new-event-notifications-896328677531 --from-literal=region=us-east-1 -n production
echo Secrets created!
echo.

echo [5/5] Verifying everything is running...
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
echo.
echo   EKS Cluster : new-event-cluster
echo   RDS Endpoint: %RDS_HOST%
echo   S3 Bucket   : new-event-notifications-896328677531
echo   Region      : us-east-1
echo ==========================================
pause