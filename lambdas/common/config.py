"""Runtime configuration, read from Lambda environment variables."""


class Config:
    """Immutable view of the environment a handler runs in."""

    def __init__(self, **values):
        self.__dict__.update(values)

    @classmethod
    def from_env(cls, env=None):
        import os

        env = os.environ if env is None else env
        get = env.get

        return cls(
            region=get("AWS_REGION") or get("AWS_DEFAULT_REGION") or "us-east-1",
            users_table=get("USERS_TABLE", "users"),
            labs_table=get("LABS_TABLE", "labs"),
            sessions_table=get("SESSIONS_TABLE", "sessions"),
            activity_table=get("ACTIVITY_TABLE", "activity"),
            orchestrator_function=get("ORCHESTRATOR_FUNCTION", ""),
            terminator_function=get("TERMINATOR_FUNCTION", ""),
            ami_parameter_prefix=get("AMI_PARAMETER_PREFIX", "/cloudybt/ami"),
            launch_template_name=get("LAB_LAUNCH_TEMPLATE", ""),
            lab_security_group_id=get("LAB_SECURITY_GROUP_ID", ""),
            lab_subnet_id=get("LAB_SUBNET_ID", ""),
            lab_instance_profile=get("LAB_INSTANCE_PROFILE", ""),
            tailscale_auth_key_parameter=get("TAILSCALE_AUTH_KEY_PARAMETER", ""),
            project_tag=get("PROJECT_TAG", "cloudybttounsi"),
            ttl_minutes=int(get("TTL_MINUTES", "60")),
            ready_timeout_seconds=int(get("READY_TIMEOUT_SECONDS", "180")),
            max_active_labs_per_user=int(get("MAX_ACTIVE_LABS_PER_USER", "4")),
            max_active_labs_platform=int(get("MAX_ACTIVE_LABS_PLATFORM", "4")),
            monthly_budget_usd=float(get("MONTHLY_BUDGET_USD", "20")),
        )
