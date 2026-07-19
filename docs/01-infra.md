
```sh
terraform -chdir=infra init -backend-config=backend.hcl
terraform -chdir=infra fmt && terraform -chdir=infra validate

terraform -chdir=infra apply -auto-approve -var-file=dev.tfvars
```

```sh
# dynamodb
aws dynamodb describe-table --table-name todo-app-dev-table --query "Table.TableStatus"
# "ACTIVE"

# lambda
aws lambda get-function --function-name todo-app-dev-api

# cognito
aws cognito-idp describe-user-pool --user-pool-id ca-central-1_vzuDCzV5o

```
