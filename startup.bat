@echo off
echo ==========================================
echo   NEW EVENT PLATFORM - STARTUP SCRIPT
echo ==========================================
echo.
echo This will recreate:
echo   - EKS Cluster        (takes 15-20 mins)
echo   - RDS Database       (takes 5-10 mins)
echo   - Kubernetes Namespaces and Secrets
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
    aws eks list-nodegroups --cluster-name new-event-cluster --region us-east-1 --no-paginate
    echo.
    echo -----------------------------------------------
    echo If nodegroup list is empty, do this manually:
    echo 1. Go to AWS Console - EKS - new-event-cluster
    echo 2. Click Compute tab
    echo 3. Click Add node group
    echo 4. Name: workers
    echo 5. Select NodeInstanceRole
    echo 6. Instance type: t3.micro
    echo 7. Desired: 2, Min: 1, Max: 4
    echo 8. Select all subnets
    echo 9. Click Create
    echo 10. Come back here and press any key
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

echo [3/5] Fixing IAM permissions...
aws eks create-access-entry --cluster-name new-event-cluster --principal-arn arn:aws:iam::896328677531:user/admin-client --region us-east-1 >nul 2>&1
aws eks associate-access-policy --cluster-name new-event-cluster --principal-arn arn:aws:iam::896328677531:user/admin-client --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster --region us-east-1 --no-paginate
echo IAM permissions set!
echo.

echo [4/5] Creating RDS PostgreSQL Database...
aws rds create-db-instance --db-instance-identifier new-event-db --db-instance-class db.t4g.micro --engine postgres --master-username postgres --master-user-password NewEvent2026! --allocated-storage 20 --no-multi-az --db-name neweventdb --region us-east-1 --no-paginate --output text --query "DBInstance.DBInstanceStatus"
if %errorlevel% neq 0 (
    echo WARNING: RDS creation had issues - check AWS console
) else (
    echo RDS creation started...
    echo Waiting for RDS to be available (5-10 mins)...
    aws rds wait db-instance-available --db-instance-identifier new-event-db --region us-east-1
    echo RDS is ready!
)
echo.

echo [5/5] Creating Kubernetes Namespaces and Secrets...
kubectl create namespace production
kubectl create namespace monitoring
kubectl create namespace analytics
echo.
echo Getting RDS endpoint...
for /f "tokens=*" %%i in ('aws rds describe-db-instances --db-instance-identifier new-event-db --query "DBInstances[0].Endpoint.Address" --output text --region us-east-1 --no-paginate') do set RDS_HOST=%%i
echo RDS Endpoint: %RDS_HOST%
echo.

echo Creating database secret...
kubectl create secret generic db-secret --from-literal=host=%RDS_HOST% --from-literal=port=5432 --from-literal=database=neweventdb --from-literal=username=postgres --from-literal=password=NewEvent2026! -n production

echo Creating AWS secret with Lambda URL...
kubectl create secret generic aws-secret --from-literal=bucket-name=new-event-notifications-896328677531 --from-literal=region=us-east-1 --from-literal=lambda-url=https://fjpqigjzk4tbjt6jcwco35m5mu0xwxut.lambda-url.us-east-1.on.aws/ -n production

echo Secrets created!
echo.

echo Verifying everything is running...
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
echo   EKS Cluster  : new-event-cluster
echo   RDS Endpoint : %RDS_HOST%
echo   S3 Bucket    : new-event-notifications-896328677531
echo   Lambda URL   : https://fjpqigjzk4tbjt6jcwco35m5mu0xwxut.lambda-url.us-east-1.on.aws/
echo   Region       : us-east-1
echo ==========================================
pause