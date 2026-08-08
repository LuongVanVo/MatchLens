module "network" {
  source                   = "../../modules/network"
  environment              = var.environment
  aws_region               = var.aws_region
  vpc_cidr                 = var.vpc_cidr
  az_count                 = var.az_count
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  nat_instance_count       = var.nat_instance_count
}

module "storage" {
  source      = "../../modules/storage"
  environment = var.environment
}

module "database" {
  source = "../../modules/database"

  environment           = var.environment
  vpc_id                = module.network.vpc_id
  private_db_subnet_ids = module.network.private_db_subnet_ids
  db_subnet_group_name  = module.network.db_subnet_group_name

  multi_az            = false
  create_read_replica = false
}

module "security" {
  source = "../../modules/security"

  environment = var.environment
  github_org  = "LuongVanVo"

  raw_videos_bucket_arn           = module.storage.raw_videos_bucket_arn
  processed_highlights_bucket_arn = module.storage.processed_highlights_bucket_arn
  raw_tracking_data_bucket_arn    = module.storage.raw_tracking_bucket_arn
  curated_data_bucket_arn         = module.storage.curated_data_bucket_arn
  athena_results_bucket_arn       = module.storage.athena_results_bucket_arn

  dynamodb_table_arn = module.database.dynamodb_table_arn
  db_secret_arn      = module.database.rds_secret_arn
}

module "messaging" {
  source = "../../modules/messaging"

  environment = var.environment
  aws_region  = var.aws_region

  raw_videos_bucket_arn            = module.storage.raw_videos_bucket_arn
  raw_videos_bucket_name           = module.storage.raw_videos_bucket_name
  processed_highlights_bucket_arn  = module.storage.processed_highlights_bucket_arn
  processed_highlights_bucket_name = module.storage.processed_highlights_bucket_name

  vpc_id                 = module.network.vpc_id
  private_app_subnet_ids = module.network.private_app_subnet_ids
  rds_security_group_id  = module.database.rds_security_group_id
  db_secret_arn          = module.database.rds_secret_arn

  dispatcher_role_arn           = module.security.dispatcher_lambda_role_arn
  status_updater_role_arn       = module.security.status_updater_lambda_role_arn
  mediaconvert_trigger_role_arn = module.security.mediaconvert_trigger_lambda_role_arn
  mediaconvert_role_arn         = module.security.mediaconvert_service_role_arn

  max_receive_count  = 3
  visibility_timeout = 900
}

module "compute" {
  source = "../../modules/compute"

  environment = var.environment
  aws_region  = var.aws_region
  owner       = var.owner

  vpc_id                 = module.network.vpc_id
  public_subnet_ids      = module.network.public_subnet_ids
  private_app_subnet_ids = module.network.private_app_subnet_ids

  backend_image_uri = var.backend_image_uri
  worker_image_uri  = var.worker_image_uri

  backend_task_role_arn           = module.security.backend_task_role_arn
  backend_task_execution_role_arn = module.security.backend_task_execution_role_arn

  worker_task_role_arn           = module.security.worker_task_role_arn
  worker_task_execution_role_arn = module.security.worker_task_execution_role_arn

  database_url_master  = var.database_url_master
  database_url_replica = var.database_url_replica

  jwt_access_public_key   = var.jwt_access_public_key
  jwt_access_private_key  = var.jwt_access_private_key
  jwt_refresh_private_key = var.jwt_refresh_private_key

  raw_videos_bucket_name           = module.storage.raw_videos_bucket_name
  processed_highlights_bucket_name = module.storage.processed_highlights_bucket_name
  raw_tracking_bucket_name         = module.storage.raw_tracking_bucket_name
  dynamodb_table_name              = module.database.dynamodb_table_name

  enable_worker_service       = false
  video_processing_queue_url  = module.messaging.video_processing_queue_url
  video_processing_queue_arn  = module.messaging.video_processing_queue_arn
  video_processing_queue_name = module.messaging.video_processing_queue_name
  status_callbacks_queue_url  = module.messaging.status_callbacks_queue_url

  backend_desired_count = 1
  backend_min_capacity  = 1
  backend_max_capacity  = 2

  worker_desired_count = 0
  worker_min_capacity  = 0
  worker_max_capacity  = 2
}
