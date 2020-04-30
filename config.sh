# Location of the directory which contains the upstream and dist-git workspaces
WORKSPACE_DIR="${WORKSPACE_DIR:-${HOME}/work/op-p12n}"

# Location of the directory which contains this config.sh file
SCRIPT_DIR="${SCRIPT_DIR:-${WORKSPACE_DIR}/productize-pipelines}"

UPSTREAM_DIR="${WORKSPACE_DIR}/upstream"
DIST_GIT_DIR="${WORKSPACE_DIR}/dist-git"

# Build pipeline flags
push_enabled=true          # Enable push to dist-git repos
force_build_enabled=false

# Specify partial dist-git URL
OP_DIST_GIT_URL="ssh://${USER}@pkgs.devel.redhat.com/containers"
# Specify dist-git branch
OP_DIST_GIT_BRANCH="pipelines-1.0-rhel-8"
OP_OPERATOR_METADATA_DIST_GIT_BRANCH="pipelines-1-rhel-8"

# Pipelines Repository URL's
OP_UPSTREAM_URL="git@github.com:openshift/tektoncd-pipeline.git"
# Pipelines Specify upstream tag or branch
OP_UPSTREAM_BRANCH="release-v0.11.3"

# Pipelines Triggers Repository URL's
OPT_UPSTREAM_URL="git@github.com:openshift/tektoncd-triggers.git"
# Pipelines Triggers upstream tag or branch
OPT_UPSTREAM_BRANCH="release-v0.4.0"

# Pipelines Operator Repository URL's
OPO_UPSTREAM_URL="git@github.com:openshift/tektoncd-pipeline-operator.git"
# Pipelines Triggers upstream tag or branch
OPO_UPSTREAM_BRANCH="v0.11.x"
