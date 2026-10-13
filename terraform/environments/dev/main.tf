module "network" {
  source = "../../modules/network"

  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
  tags        = local.common_tags
}

module "data" {
  source = "../../modules/data"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

module "lab" {
  source = "../../modules/lab"

  name_prefix = local.name_prefix
  vpc_id      = module.network.vpc_id
  subnet_id   = module.network.public_subnet_ids["public-0"]
  ami_ids     = var.ami_ids
  tags        = local.common_tags
}

module "api" {
  source = "../../modules/api"

  name_prefix = local.name_prefix
  tags        = local.common_tags

  lambda_source_dir = "${path.root}/../../lambdas"

  users_table_name    = module.data.users_table_name
  users_table_arn     = module.data.users_table_arn
  labs_table_name     = module.data.labs_table_name
  labs_table_arn      = module.data.labs_table_arn
  sessions_table_name = module.data.sessions_table_name
  sessions_table_arn  = module.data.sessions_table_arn
  activity_table_name = module.data.activity_table_name
  activity_table_arn  = module.data.activity_table_arn

  lab_subnet_id             = module.lab.subnet_id
  lab_security_group_id     = module.lab.security_group_id
  lab_instance_profile_name = module.lab.instance_profile_name
  launch_template_name      = module.lab.launch_template_name

  ttl_minutes              = var.ttl_minutes
  max_active_labs_per_user = var.max_active_labs_per_user
  max_active_labs_platform = var.max_active_labs_platform
  ready_timeout_seconds    = var.ready_timeout_seconds
}

module "frontend" {
  source = "../../modules/frontend"

  name_prefix = local.name_prefix
  source_dir  = "${path.root}/../../frontend"
  tags        = local.common_tags
}

module "governance" {
  source = "../../modules/governance"

  name_prefix = local.name_prefix
  tags        = local.common_tags
}
