@echo off
echo ==========================================
echo   NEW EVENT PLATFORM - STARTUP SCRIPT
echo ==========================================
echo.
echo This will recreate:
echo   - EKS Cluster        (takes 15-20 mins)
echo   - EKS Nodegroup      (2 x t3.small)
echo   - RDS Database       (takes 5-10 mins)
echo   - Kubernetes Namespaces and Secrets
echo   - EBS CSI Driver + OIDC Provider
echo   - S3 Bucket already exists - skipping
echo.
echo Total time: approximately 35 minutes.
echo Press Ctrl+C to cancel or any key to continue...
pause > nul
echo.

echo [1/8] Cleaning up any leftover stacks...
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-nodegroup-workers-small --region us-east-1 --no-paginate >nul 2>&1
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-nodegroup-workers --region us-east-1 --no-paginate >nul 2>&1
aws cloudformation delete-stack --stack-name eksctl-new-event-cluster-cluster --region us-east-1 --no-paginate >nul 2>&1
echo Waiting 30 seconds for cleanup...
timeout /t 30 /nobreak > nul
echo Cleanup done!
echo.

echo [2/8] Creating EKS Cluster control plane (takes 10-15 mins)...
eksctl create cluster --name new-event-cluster --region us-east-1 --without-nodegroup --version 1.31
if %errorlevel% neq 0 (
    echo Checking if cluster already exists...
    aws eks describe-cluster --name new-event-cluster --region us-east-1 --query "cluster.status" --no-paginate
)
echo.

echo [3/8] Connecting kubectl to cluster...
aws eks update-kubeconfig --region us-east-1 --name new-event-cluster
echo kubectl connected!
echo.

echo [4/8] Fixing IAM permissions...
aws eks create-access-entry --cluster-name new-event-cluster --principal-arn arn:aws:iam::896328677531:user/admin-client --region us-east-1 --no-paginate >nul 2>&1
aws eks associate-access-policy --cluster-name new-event-cluster --principal-arn arn:aws:iam::896328677531:user/admin-client --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster --region us-east-1 --no-paginate >nul 2>&1
echo IAM permissions set!
echo.

echo [5/8] Setting up OIDC provider for EBS CSI Driver...
for /f %%i in ('aws eks describe-cluster --name new-event-cluster --region us-east-1 --query "cluster.identity.oidc.issuer" --output text --no-paginate') do set OIDC_URL=%%i
for /f "tokens=5 delims=/" %%i in ("%OIDC_URL%") do set OIDC_ID=%%i
echo OIDC ID: %OIDC_ID%
aws iam create-open-id-connect-provider --url %OIDC_URL% --client-id-list sts.amazonaws.com --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 --region us-east-1 --no-paginate >nul 2>&1
aws iam update-assume-role-policy --role-name AmazonEKS_EBS_CSI_DriverRole --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::896328677531:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/%OIDC_ID%\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringEquals\":{\"oidc.eks.us-east-1.amazonaws.com/id/%OIDC_ID%:sub\":\"system:serviceaccount:kube-system:ebs-csi-controller-sa\"}}}]}"
echo OIDC provider configured!
echo.

echo [6/8] Creating t3.small nodegroup via AWS CLI...
for /f %%a in ('aws eks describe-cluster --name new-event-cluster --region us-east-1 --query "cluster.resourcesVpcConfig.subnetIds[0]" --output text --no-paginate') do set SUBNET1=%%a
for /f %%a in ('aws eks describe-cluster --name new-event-cluster --region us-east-1 --query "cluster.resourcesVpcConfig.subnetIds[1]" --output text --no-paginate') do set SUBNET2=%%a
echo Subnets: %SUBNET1% %SUBNET2%
aws eks create-nodegroup --cluster-name new-event-cluster --nodegroup-name workers-small --node-role arn:aws:iam::896328677531:role/EKSNodeInstanceRole --subnets %SUBNET1% %SUBNET2% --instance-types t3.small --scaling-config minSize=1,maxSize=3,desiredSize=2 --ami-type AL2023_x86_64_STANDARD --region us-east-1 --no-paginate
echo Waiting for nodes to be ready (5-10 mins)...
aws eks wait nodegroup-active --cluster-name new-event-cluster --nodegroup-name workers-small --region us-east-1
echo Nodegroup ready!
echo.

echo [7/8] Creating RDS PostgreSQL Database...
aws rds create-db-instance --db-instance-identifier new-event-db --db-instance-class db.t4g.micro --engine postgres --master-username postgres --master-user-password NewEvent2026! --allocated-storage 20 --no-multi-az --db-name neweventdb --region us-east-1 --no-paginate --output text --query "DBInstance.DBInstanceStatus" >nul 2>&1
echo RDS creation started...
echo Waiting for RDS to be available (5-10 mins)...
aws rds wait db-instance-available --db-instance-identifier new-event-db --region us-east-1
echo RDS is ready!
echo.

echo [8/8] Creating Kubernetes Namespaces, Secrets and EBS CSI Addon...
kubectl create namespace production >nul 2>&1
kubectl create namespace monitoring >nul 2>&1
kubectl create namespace analytics >nul 2>&1
echo Namespaces ready!
echo.
for /f %%i in ('aws rds describe-db-instances --db-instance-identifier new-event-db --query "DBInstances[0].Endpoint.Address" --output text --region us-east-1 --no-paginate') do set RDS_HOST=%%i
echo RDS Endpoint: %RDS_HOST%
kubectl create secret generic db-secret --from-literal=host=%RDS_HOST% --from-literal=port=5432 --from-literal=database=neweventdb --from-literal=username=postgres --from-literal=password=NewEvent2026! -n production --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic aws-secret --from-literal=bucket-name=new-event-notifications-896328677531 --from-literal=region=us-east-1 --from-literal=lambda-url=https://fjpqigjzk4tbjt6jcwco35m5mu0xwxut.lambda-url.us-east-1.on.aws/ -n production --dry-run=client -o yaml | kubectl apply -f -
echo Secrets created!
echo.
echo Installing EBS CSI Driver addon...
aws eks create-addon --cluster-name new-event-cluster --addon-name aws-ebs-csi-driver --service-account-role-arn arn:aws:iam::896328677531:role/AmazonEKS_EBS_CSI_DriverRole --region us-east-1 --no-paginate >nul 2>&1
echo EBS CSI Driver installing...
echo Waiting 2 minutes for EBS CSI to be ready...
timeout /t 120 /nobreak > nul
echo.
echo Restarting EBS CSI controller to pick up OIDC...
kubectl rollout restart deployment/ebs-csi-controller -n kube-system >nul 2>&1
echo.
echo Deploying all services...
kubectl apply -f kubernetes/ >nul 2>&1
echo Services deployed!
echo.
echo Creating ClickHouse table...
timeout /t 30 /nobreak > nul
for /f %%i in ('kubectl get pod -n analytics -l app=clickhouse -o jsonpath^={.items[0].metadata.name}') do set CH_POD=%%i
kubectl exec -n analytics %CH_POD% -- clickhouse-client --query "CREATE TABLE IF NOT EXISTS analytics.web_events (event_type String, session_id String, timestamp DateTime, page_url String, user_agent String, section_name String DEFAULT '', speaker_name String DEFAULT '', track_name String DEFAULT '', has_name UInt8 DEFAULT 0, has_email UInt8 DEFAULT 0, referrer String DEFAULT '', screen_width UInt16 DEFAULT 0, screen_height UInt16 DEFAULT 0, extra String DEFAULT '') ENGINE = MergeTree() ORDER BY (timestamp, event_type, session_id)" >nul 2>&1
echo ClickHouse table ready!
echo.
echo Verifying everything is running...
echo.
echo === Kubernetes Nodes ===
kubectl get nodes
echo.
echo === All Pods ===
kubectl get pods --all-namespaces
echo.
echo === Services ===
kubectl get svc -n production
echo.
echo ==========================================
echo   STARTUP COMPLETE! Happy coding!
echo.
echo   EKS Cluster  : new-event-cluster
echo   RDS Endpoint : %RDS_HOST%
echo   S3 Bucket    : new-event-notifications-896328677531
echo   Lambda URL   : https://fjpqigjzk4tbjt6jcwco35m5mu0xwxut.lambda-url.us-east-1.on.aws/
echo   Region       : us-east-1
echo.
echo   Frontend URL : check kubectl get svc -n production
echo ==========================================
pause