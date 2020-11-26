# Simple Terraform EC2

## Scope
1) Terraform aws ec2
2) Terraform variables and defaults


## Commands

Initialize/load dependencies etc.
```
terraform init
```


Can test the plan and test destroy of the plan
```
terraform plan
terraform plan -destroy
```

Terraform apply with default
```
terraform apply
```

Terraform apply with custom EC2 tag

```
terraform apply -var 'name=Custom'
```

Terraform destroy
```
terraform destroy
```

