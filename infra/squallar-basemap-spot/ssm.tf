# Credentials the build box and the heartbeat need.
#
# TERRAFORM DOES NOT MANAGE THESE PARAMETERS, AND THAT IS THE WHOLE POINT.
#
# An earlier version declared them as `aws_ssm_parameter` with a PLACEHOLDER
# value and `lifecycle { ignore_changes = [value] }`, claiming that kept the
# real secret out of state. THAT CLAIM WAS FALSE. `aws_ssm_parameter` reads
# `value` back on every refresh, and `ignore_changes` suppresses the *diff*, not
# the *read* -- so the first refresh after the value was set would have written
# a live R2 write-credential, in plaintext, into
# `s3://mcswain-dev-tf-states`. There is no attribute-level opt-out.
#
# So the parameters are created and rotated ENTIRELY out of band, and terraform
# refers to them by an ARN it constructs from strings. It never calls
# GetParameter, never holds the value, and cannot leak what it has not read.
#
# The secondary benefit is that this is now order-independent: the parameters
# may already exist (they do -- /squallar/basemap/r2 was set by hand), which
# would have made a managed resource fail its create with ParameterAlreadyExists.
#
#   umask 077; T=$(mktemp)
#   printf '%s' '{"access_key_id":"…","secret_access_key":"…"}' > "$T"
#   aws ssm put-parameter --region us-east-1 --name /squallar/basemap/r2 \
#     --type SecureString --value file://"$T" --overwrite
#   shred -u "$T"
#
# `--value file://` and not an inline argument, so the secret never enters shell
# history.
locals {
  ssm_prefix = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter"

  # R2 Object Read & Write, scoped to the squallar-basemap bucket. JSON:
  # {"access_key_id": "...", "secret_access_key": "..."}
  r2_param_name = "/squallar/basemap/r2"
  r2_param_arn  = "${local.ssm_prefix}${local.r2_param_name}"

  # The relay API key for email.mcswain.dev:465. A BARE STRING, not JSON --
  # both the build script and the heartbeat pass it straight to SMTP AUTH as
  # the password, with "squallar" as the username.
  smtp_param_name = "/squallar/basemap/smtp"
  smtp_param_arn  = "${local.ssm_prefix}${local.smtp_param_name}"
}
