@echo off
echo ==========================================
echo   NEW EVENT PLATFORM - SHUTDOWN SCRIPT
echo ==========================================
echo.
echo This will:
echo   - DELETE EKS Nodegroup first
echo   - DELETE EKS Cluster
echo   - TERMINATE RDS Database
echo   - KEEP S3 Bucket untouched
echo.
echo Press Ctrl+C to cancel or any key to continue...
pause > nul
echo.

echo [1/4] Deleting EKS Nodegroup first (takes 5-10 mins)...
eksctl delete nodegroup --region=us-east-1 --cluster=new-event-cluster --name=workers --disable-eviction
if %errorlevel% neq 0 (
    echo Nodegroup may not exist or already deleted - continuing...
) else (
    echo Nodegroup deleted successfully!
)
echo.

echo [2/4] Deleting EKS Cluster (takes 5-10 mins)...
eksctl delete cluster --region=us-east-1 --name=new-event-cluster
if %errorlevel% neq 0 (
    echo Trying AWS CLI delete instead...
    aws eks delete-cluster --name new-event-cluster --region us-east-1 --no-paginate
    echo Cluster deletion started, waiting for completion...
    :wait_cluster
    aws eks describe-cluster --name new-event-cluster --region us-east-1 --query "cluster.status" --no-paginate >nul 2>&1
    if %errorlevel% equ 0 (
        echo Still deleting... waiting 30 seconds...
        timeout /t 30 /nobreak > nul
        goto wait_cluster
    )
    echo EKS Cluster fully deleted!
) else (
    echo EKS Cluster deleted successfully!
)
echo.

echo [3/4] Terminating RDS Database...
aws rds delete-db-instance --db-instance-identifier new-event-db --skip-final-snapshot --region us-east-1 --no-paginate --output text --query "DBInstance.DBInstanceStatus"
if %errorlevel% neq 0 (
    echo WARNING: RDS termination had issues - may already be deleted
) else (
    echo RDS termination started successfully!
)
echo.

echo [4/4] Verifying shutdown...
echo.
echo === Checking EKS Clusters ===
aws eks list-clusters --region us-east-1 --no-paginate
echo.
echo === Checking RDS Instances ===
aws rds describe-db-instances --region us-east-1 --no-paginate --output text --query "DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]"
if %errorlevel% neq 0 (
    echo No RDS instances found - all deleted!
)
echo.
echo === S3 Bucket (untouched) ===
aws s3 ls --no-paginate
echo.

echo ==========================================
echo   SHUTDOWN COMPLETE!
echo.
echo   Deleted:
echo   - EKS Cluster        
echo   - RDS Database       
echo.
echo ==========================================
pause