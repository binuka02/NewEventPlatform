@echo off
echo ==========================================
echo   NEW EVENT PLATFORM - SHUTDOWN SCRIPT
echo ==========================================
echo.
echo This will:
echo   - DELETE EKS Nodegroup (workers-small)
echo   - DELETE EKS Cluster
echo   - DELETE CloudFormation stacks
echo   - TERMINATE RDS Database
echo   - KEEP S3 Bucket untouched
echo   - KEEP Lambda function untouched
echo.
echo Press Ctrl+C to cancel or any key to continue...
pause > nul
echo.

echo [1/5] Deleting EKS Nodegroups...
eksctl delete nodegroup --region=us-east-1 --cluster=new-event-cluster --name=workers-small --disable-eviction >nul 2>&1
eksctl delete nodegroup --region=us-east-1 --cluster=new-event-cluster --name=workers-medium --disable-eviction >nul 2>&1
eksctl delete nodegroup --region=us-east-1 --cluster=new-event-cluster --name=workers --disable-eviction >nul 2>&1
echo Nodegroup deletion initiated!
echo.

echo [2/5] Deleting EKS Cluster...
eksctl delete cluster --region=us-east-1 --name=new-event-cluster
echo.

echo [3/5] Force deleting CloudFormation stacks...
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-nodegroup-workers-small --region us-east-1 --no-paginate >nul 2>&1
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-nodegroup-workers-medium --region us-east-1 --no-paginate >nul 2>&1
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-nodegroup-workers --region us-east-1 --no-paginate >nul 2>&1
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-cluster --region us-east-1 --no-paginate >nul 2>&1
echo Waiting for CloudFormation stacks to fully delete...

:wait_cf
aws cloudformation describe-stacks --stack-name eksctl-new-event-cluster-cluster --region us-east-1 --query "Stacks[0].StackStatus" --no-paginate >nul 2>&1
if %errorlevel% equ 0 (
    echo Still deleting CloudFormation stack... waiting 20 seconds...
    timeout /t 20 /nobreak > nul
    goto wait_cf
)
echo CloudFormation stacks fully deleted!
echo.

echo [4/5] Terminating RDS Database...
aws rds delete-db-instance --db-instance-identifier new-event-db --skip-final-snapshot --region us-east-1 --no-paginate --output text --query "DBInstance.DBInstanceStatus" >nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: RDS may already be deleted - skipping
) else (
    echo RDS termination started!
)
echo.

echo [5/5] Waiting for all resources to fully terminate...
timeout /t 60 /nobreak > nul
echo.

echo ==========================================
echo   FINAL STATUS CHECK
echo ==========================================
echo.

echo === EKS Clusters ===
aws eks list-clusters --region us-east-1 --no-paginate --output table
echo.

echo === RDS Instances ===
aws rds describe-db-instances --region us-east-1 --no-paginate --output table --query "DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus,DBInstanceClass]" 2>nul
if %errorlevel% neq 0 (
    echo No RDS instances found - fully deleted!
)
echo.

echo === S3 Buckets (kept) ===
aws s3 ls --no-paginate
echo.

echo === EC2 Instances ===
aws ec2 describe-instances --region us-east-1 --no-paginate --output table --query "Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType]" --filters "Name=instance-state-name,Values=running,pending,stopping,stopped" 2>nul
if %errorlevel% neq 0 (
    echo No EC2 instances found!
)
echo.

echo ==========================================
echo   SHUTDOWN SUMMARY
echo ==========================================
echo.
echo   Deleted:
echo   - EKS Cluster             = $0.00/day
echo   - EKS Nodegroup (4xsmall) = $0.00/day
echo   - CloudFormation Stacks   = $0.00/day
echo   - RDS Database            = $0.00/day
echo   - EC2 Nodes               = $0.00/day
echo.
echo   Kept:
echo   - S3 Bucket               = $0.00 (free tier)
echo   - Lambda Function         = $0.00 (pay per use)
echo   - EBS Volumes (PVCs)      = ~$0.10/day each
echo.
echo   TOTAL DAILY COST = ~$0.20/day (EBS volumes only)
echo.
echo   Run startup.bat to recreate when ready.
echo   (Takes approximately 40 minutes)
echo ==========================================
echo.
echo Press any key to close this window...
pause > nul