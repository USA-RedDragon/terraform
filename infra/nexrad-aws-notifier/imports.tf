# Adoption only. The role and its inline policy were created by hand and are in
# use by the running deployment; these blocks bring them into state as they
# are. Without them the plan would try to create a role that already exists.
#
# The first plan must show these two imports and an in-place update of the
# role's assume_role_policy, adding the GitHub statement, and nothing else.

import {
  to = aws_iam_role.nexrad_aws_notifier
  id = "nexrad-aws-notifier"
}

import {
  to = aws_iam_role_policy.nexrad_aws_notifier
  id = "nexrad-aws-notifier:nexrad-aws-notifierPolicy"
}
