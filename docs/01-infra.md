
```sh
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra apply -auto-approve -var-file=dev.tfvars
terraform -chdir=infra destroy -auto-approve -var-file=dev.tfvars
```

```sh
# dynamodb
aws dynamodb describe-table --table-name todo-app-dev-table --query "Table.TableStatus"
# "ACTIVE"

# lambda
aws lambda get-function --function-name todo-app-dev-api

# cognito
aws cognito-idp describe-user-pool --user-pool-id ca-central-1_vzuDCzV5o

# api gateway
aws apigateway get-rest-api --rest-api-id 5ew1c8sl4b

# s3
aws s3api head-bucket --bucket todo-app-dev-web-i86ow1zo

# cloudfront
aws cloudfront get-distribution --id E3PATIL2EP58C3

```
