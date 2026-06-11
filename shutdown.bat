@echo off
echo ==========================================
echo   NEW EVENT PLATFORM - SHUTDOWN SCRIPT
echo ==========================================
echo.
echo WARNING: This will stop all running resources.
echo Press Ctrl+C to cancel or any key to continue...
pause > nul
echo.

echo [1/3] Deleting EKS Nodegroup (takes 5-10 mins)...
eksctl delete nodegroup --region=us-east-1 --cluster=new-event-cluster --name=workers
if %errorlevel% neq 0 (
    echo WARNING: Nodegroup deletion had issues - check AWS console
) else (
    echo Nodegroup deleted successfully!
)
echo.

echo [2/3] Stopping RDS Database...
aws rds stop-db-instance --db-instance-identifier new-event-db --region us-east-1
if %errorlevel% neq 0 (
    echo WARNING: RDS stop had issues - check AWS console
) else (
    echo RDS stopping... (takes 3-5 mins to fully stop)
)
echo.

echo [3/3] Verifying shutdown...
echo.
echo === Checking Nodegroups ===
aws eks list-nodegroups --cluster-name new-event-cluster --region us-east-1
echo.
echo === Checking RDS Status ===
aws rds describe-db-instances --db-instance-identifier new-event-db --query "DBInstances[0].DBInstanceStatus" --output text --region us-east-1
echo.

echo ==========================================
echo   SHUTDOWN COMPLETE!
echo.  
echo   Still running (cannot be stopped):
echo   - EKS Control Plane ($0.10/hr = $2.40/day)
echo.
echo   Stopped (no charges):
echo   - EC2 Worker Nodes (was free tier anyway)
echo   - RDS Database (was free tier anyway)
echo ==========================================
pause
