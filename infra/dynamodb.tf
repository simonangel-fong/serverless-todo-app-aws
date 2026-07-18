# dynamodb.tf
locals {
  dynamodb_table_name = "${local.name_prefix}-table"
  owner_index_name    = "owner-index"
}

resource "aws_dynamodb_table" "todo" {
  name         = local.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "owner_id"
    type = "S"
  }

  global_secondary_index {
    name            = local.owner_index_name
    hash_key        = "owner_id"
    projection_type = "ALL"
  }

  tags = {
    Name = local.dynamodb_table_name
  }
}
