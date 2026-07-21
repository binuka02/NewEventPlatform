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
echo   - DELETE RDS DB Subnet Group
echo   - KEEP S3 Bucket untouched
echo   - KEEP Lambda function untouched
echo.
echo Press Ctrl+C to cancel or any key to continue...
pause > nul
echo.

echo [1/6] Scaling down ClickHouse and cleaning up its PersistentVolumeClaim...
kubectl scale deployment clickhouse --replicas=0 -n analytics >nul 2>&1
echo Waiting 20 seconds for the ClickHouse pod to terminate and release its volume...
timeout /t 20 /nobreak > nul
kubectl delete pvc clickhouse-pvc -n analytics --ignore-not-found --timeout=30s >nul 2>&1
echo Waiting 10 seconds for the EBS CSI Driver to deprovision the volume...
timeout /t 10 /nobreak > nul
echo PVC cleanup done!
echo.

echo [2/6] Deleting EKS Nodegroups...
eksctl delete nodegroup --region=us-east-1 --cluster=new-event-cluster --name=workers-small --disable-eviction >nul 2>&1
eksctl delete nodegroup --region=us-east-1 --cluster=new-event-cluster --name=workers-medium --disable-eviction >nul 2>&1
eksctl delete nodegroup --region=us-east-1 --cluster=new-event-cluster --name=workers --disable-eviction >nul 2>&1
echo Nodegroup deletion initiated!
echo.

echo [3/6] Deleting EKS Cluster...
eksctl delete cluster --region=us-east-1 --name=new-event-cluster
echo.

echo [4/6] Force deleting CloudFormation stacks...
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-nodegroup-workers-small --region us-east-1 --no-paginate >nul 2>&1
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-nodegroup-workers-medium --region us-east-1 --no-paginate >nul 2>&1
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-nodegroup-workers --region us-east-1 --no-paginate >nul 2>&1
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-cluster --region us-east-1 --no-paginate >nul 2>&1
echo Waiting for CloudFormation stacks to fully delete (max 10 minutes)...

set /a CF_WAIT_COUNT=0
:wait_cf
aws cloudformation describe-stacks --stack-name eksctl-new-event-cluster-cluster --region us-east-1 --query "Stacks[0].StackStatus" --no-paginate >nul 2>&1
if %errorlevel% equ 0 (
    set /a CF_WAIT_COUNT+=1
    if %CF_WAIT_COUNT% geq 30 (
        echo WARNING: CloudFormation stack deletion is taking longer than 10 minutes.
        echo Check the AWS Console under CloudFormation for a stuck resource
        echo ^(often a security group still referenced by an ENI or Load Balancer^),
        echo resolve it there, then continue running this script manually if needed.
        goto cf_done
    )
    echo Still deleting CloudFormation stack... waiting 20 seconds... ^(attempt %CF_WAIT_COUNT%/30^)
    timeout /t 20 /nobreak > nul
    goto wait_cf
)
:cf_done
echo CloudFormation stacks fully deleted!
echo.

echo [5/6] Terminating RDS Database...
aws rds delete-db-instance --db-instance-identifier new-event-db --skip-final-snapshot --region us-east-1 --no-paginate --output text --query "DBInstance.DBInstanceStatus" >nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: RDS may already be deleted - skipping
) else (
    echo RDS termination started!
)
echo.

echo [6/6] Waiting for all resources to fully terminate...
timeout /t 60 /nobreak > nul
echo Deleting DB subnet group (now that RDS no longer uses it)...
aws rds delete-db-subnet-group --db-subnet-group-name new-event-db-subnet-group --region us-east-1 --no-paginate >nul 2>&1
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
echo   - RDS DB Subnet Group     = $0.00 (no cost, but cleaned up for a fresh next run)
echo   - EC2 Nodes               = $0.00/day
echo   - ClickHouse EBS Volume   = $0.00/day (deleted via PVC before cluster teardown)
echo.
echo   Kept:
echo   - S3 Bucket               = $0.00 (free tier)
echo   - Lambda Function         = $0.00 (pay per use)
echo.
echo   NOTE: If you have EBS volumes from BEFORE this fix was added, check
echo   EC2 - Elastic Block Store - Volumes in the AWS Console for any
echo   leftover "available" (unattached) volumes and delete them manually.
echo.
echo   TOTAL DAILY COST = ~$0.00/day
echo.
echo   Run startup.bat to recreate when ready.
echo   (Takes approximately 40 minutes)
echo ==========================================
echo.
echo Press any key to close this window...
pause > nul