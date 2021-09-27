#!/bin/bash

DATETIME="$(date +%Y%m%d%H%M%S)"
SCRIPT_FULL_PATH=$(realpath "${0}")
SCRIPT_DIR=$(dirname "${SCRIPT_FULL_PATH}")
cd "${SCRIPT_DIR}" || exit

USAGE() {
  echo "Usage:"
  echo ""
  echo "$0 [-h|--help] [-e|--env] {environment} [-s|--service] {service_name} [-c|--command] {command}"
  echo ""
  echo "Supported environments:"
  echo "  [ shared | common | dev | uat | sit | staging | prod ]"
  echo ""
  echo "Supported services:"
  echo "  [ iam | kms | s3 | ec2 | rds | ecr | alb | sg | asg | ecs ]"
  echo ""
  echo "For stack name, environment variable will be prefixed to service and 'stack' will be appended."
  echo "  Example: Environment 'dev', service name 'kms' will become 'dev-kms-stack'"
  echo ""
  echo "Supported commands:"
  echo "  list       - list stacks (can run alone without service/env (-s|--service, -e|--env) switch i.e. -c|--command list)"
  echo "  exist      - check if stack exists"
  echo "  create     - create changeset"
  echo "  show       - show changes in latest changeset"
  echo "  deploy     - apply changes from latest changeset in CREATE_COMPLETE state"
  echo "  clean      - clean FAILED changesets"
  echo "  generate   - generate cloudformation templates, parameters and tags properties"
  echo "  delete     - delete stack (not allowed for 'prod')"
  echo "  assume     - assume role"
  echo ""
}

CHARS_CHECK() {
  if ! [[ "${CHECK_CHARS}" =~ ^[-[:alnum:]]+$ ]]; then
    echo ""
    echo "${CHECK_CHARS} : contains invalid characters. Only apha-numerics and '-' are allow."
    echo ""
    exit
  fi
}

declare -A SUPPORTED_ENVS
SUPPORTED_ENVS=([shared]="shared" [common]="common" [dev]="dev" [uat]="uat" [sit]="sit" [staging]="staging" [prod]="prod")

ENVS_CHECK() {
  if ! [[ "${CHECK_ENV}" == "${SUPPORTED_ENVS[${CHECK_ENV}]}" ]]; then
    echo ""
    echo "Environment name ${CHECK_ENV} is not allowed. Allowed environments are:"
    echo "  [ shared | common | dev | uat | sit | staging | prod ]"
    echo ""
    exit
  fi
}

declare -A SUPPORTED_SERVICES
SUPPORTED_SERVICES=([iam]="iam" [kms]="kms" [s3]="s3" [ec2]="ec2" [rds]="rds" [ecr]="ecr" [alb]="alb" [sg]="sg" [asg]="asg" [ecs]="ecs")

SERVICES_CHECK() {
  if ! [[ "${CHECK_SERVICE}" == "${SUPPORTED_SERVICES[${CHECK_SERVICE}]}" ]]; then
    echo ""
    echo "Service ${CHECK_SERVICE} is not allowed. Allowed services are:"
    echo "  [ iam | kms | s3 | ec2 | rds | ecr | alb | sg | asg | ecs ]"
    echo ""
    exit
  fi
}

declare -A COMMANDS
COMMANDS=([list]="list" [exist]="exist" [create]="create" [deploy]="deploy" [show]="show" [clean]="clean" [generate]="generate" [delete]="delete" [assume]="assume")

COMMANDS_CHECK() {
  if ! [[ "${CHECK_COMMAND}" == "${COMMANDS[${CHECK_COMMAND}]}" ]]; then
    echo ""
    echo "Command ${CHECK_COMMAND} not allowed. Allowed commands are:"
    echo "  list       - list stacks (can run alone without service/env (-s|--service, -e|--env) switch i.e. -c|--command list)"
    echo "  exist      - check if stack exists"
    echo "  create     - create changeset"
    echo "  show       - show changes in latest changeset"
    echo "  deploy     - apply changes from latest changeset in CREATE_COMPLETE state"
    echo "  clean      - clean FAILED changesets"
    echo "  generate   - generate cloudformation templates, parameters and tags properties"
    echo "  delete     - delete stack (not allowed for 'prod')"
    echo "  assume     - assume role"
    echo ""
    exit
  fi
}

DIE() {
  printf '%s\n' "${1}" >&2
  exit 1
}

if [ "${1}" == "" ]; then
  USAGE
  exit
fi

while :; do
  case ${1} in
    -h|--help)
      USAGE
      exit
      ;;
    -e|--env)
      if [ "${2}" ]; then
        CHECK_CHARS=${2}; CHARS_CHECK
        CHECK_ENV="$(echo ${2} | tr '[:upper:]' '[:lower:]')"; ENVS_CHECK
        ENVIRONMENT_UPPER="$(echo ${2} | tr '[:lower:]' '[:upper:]')"
        ENVIRONMENT_LOWER="$(echo ${2} | tr '[:upper:]' '[:lower:]')"
        ENVIRONMENT="${ENVIRONMENT_LOWER}"
        ENVIRONMENT_TAG="${ENVIRONMENT_UPPER}"
        shift
      else
        DIE 'ERROR: Environment validation failed.'
      fi
      ;;
    -s|--service)
      if [ "${2}" ]; then
        CHECK_CHARS=${2}; CHARS_CHECK
        CHECK_SERVICE="${2}"; SERVICES_CHECK
        SERVICE="${2}"
        STACK_NAME_INPUT="${ENVIRONMENT}-${SERVICE}-stack"
        shift
      else
        DIE 'ERROR: Stack name validation failed'
      fi
      ;;
    -c|--command)
      if [ "${2}" ]; then
        CHECK_CHARS=${2}; CHARS_CHECK
        CHECK_COMMAND="${2}"; COMMANDS_CHECK
        COMMAND="${2}"
        shift
      else
        DIE 'ERROR: Stack name validation failed'
      fi
      ;;
    *)
      break
      ;;
  esac
  shift
done

STACK_NAME="${STACK_NAME_INPUT}"

if [ "${ENVIRONMENT}" == "" ] && [ "${COMMAND}" != "list" ]; then
  echo ""
  echo "Environment is required."
  echo ""
  USAGE
  exit
else
  STACK_NAME="${STACK_NAME_INPUT}"
fi

if [ "${ENVIRONMENT}" == "prod" ] && [ "${COMMAND}" == "delete" ]; then
  echo ""
  echo "Deletion is not allowed in PROD."
  echo ""
  USAGE
  exit
fi

if [ "${SERVICE}" == "" ]; then
 if [ "${COMMAND}" != "list" ] && [ "${COMMAND}" != "assume" ]; then
    echo ""
    echo "The command '${COMMAND}' require valid stack name."
    echo "Only 'list' and 'assume' command can run without stack name."
    echo ""
    USAGE
    exit
  fi
fi

echo "Command: ${COMMAND}"
echo "Stack Name: ${STACK_NAME}"
echo "Environment: ${ENVIRONMENT}"
echo "Environment Tag: ${ENVIRONMENT_TAG}"



declare -A ACCOUNT_IDS
ACCOUNT_IDS=([shared]="555555555555" [dev]="666666666666" [uat]="777777777777" [prod]="888888888888")

if [ "${ENVIRONMENT}" != "" ]; then
  if [ "${ACCOUNT_IDS[${ENVIRONMENT}]}" != "" ];then
    ACCOUNT_ID="${ACCOUNT_IDS[${ENVIRONMENT}]}"
    DEFAULT_ENVIRONMENT="${ENVIRONMENT}"
  else
    DEFAULT_ENVIRONMENT="dev"
    ACCOUNT_ID="${ACCOUNT_IDS[${DEFAULT_ENVIRONMENT}]}"
  fi
  STS_PROFILE="devops-${DEFAULT_ENVIRONMENT}"
else
  STS_PROFILE="devops-dev"
fi

STS_MAIN_PROFILE="devops-main"

ASSUME_ROLE() {
  export AWS_PROFILE="${STS_MAIN_PROFILE}"
  export AWS_REGION="${DEFAULT_REGION}"
  ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/Admin"
  ROLE_SESSION_NAME="${STS_PROFILE}-session"
  PROFILE_NAME="${STS_PROFILE}"

  TEMP_ROLE=$(aws sts assume-role --role-arn ${ROLE_ARN} --role-session-name ${ROLE_SESSION_NAME})

  export AWS_ACCESS_KEY_ID=$(echo ${TEMP_ROLE} | jq -r .Credentials.AccessKeyId)
  export AWS_SECRET_ACCESS_KEY=$(echo ${TEMP_ROLE} | jq -r .Credentials.SecretAccessKey)
  export AWS_SESSION_TOKEN=$(echo ${TEMP_ROLE} | jq -r .Credentials.SessionToken)

  aws configure set profile.${PROFILE_NAME}.aws_access_key_id ${AWS_ACCESS_KEY_ID}
  aws configure set profile.${PROFILE_NAME}.aws_secret_access_key ${AWS_SECRET_ACCESS_KEY}
  aws configure set profile.${PROFILE_NAME}.aws_session_token ${AWS_SESSION_TOKEN}

  aws --profile ${PROFILE_NAME} sts get-caller-identity
}


DEFAULT_REGION="ap-southeast-2"
AWS_CLI=/usr/local/bin/aws
alias cfn="AWS_REGION=${DEFAULT_REGION} AWS_PROFILE=${STS_PROFILE} ${AWS_CLI} cloudformation"


alias list_stack="cfn list-stacks --stack-status-filter \
  CREATE_IN_PROGRESS \
  CREATE_COMPLETE \
  ROLLBACK_IN_PROGRESS  \
  ROLLBACK_FAILED  \
  ROLLBACK_COMPLETE  \
  DELETE_IN_PROGRESS  \
  DELETE_FAILED  \
  UPDATE_IN_PROGRESS  \
  UPDATE_COMPLETE_CLEANUP_IN_PROGRESS \
  UPDATE_COMPLETE \
  UPDATE_FAILED \
  UPDATE_ROLLBACK_IN_PROGRESS \
  UPDATE_ROLLBACK_FAILED \
  UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS \
  UPDATE_ROLLBACK_COMPLETE \
  REVIEW_IN_PROGRESS \
  IMPORT_IN_PROGRESS \
  IMPORT_COMPLETE \
  IMPORT_ROLLBACK_IN_PROGRESS \
  IMPORT_ROLLBACK_FAILED \
  IMPORT_ROLLBACK_COMPLETE \
  --query 'StackSummaries[*].StackName' --output text"


if [ "${COMMAND}" == "list" ]; then
  if [ "${ENVIRONMENT}" != "" ] && [ "${SERVICE}" != "" ]; then
    STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep "${ENVIRONMENT}" | grep "${SERVICE}")
    DEFAULT_ENVIRONMENT="${ENVIRONMENT}"
  elif [ "${ENVIRONMENT}" != "" ]; then
    STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep "${ENVIRONMENT}")
    DEFAULT_ENVIRONMENT="${ENVIRONMENT}"
  elif [ "${SERVICE}" != "" ]; then
    STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep "${SERVICE}")
    DEFAULT_ENVIRONMENT="dev"
  else
    STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n')
    DEFAULT_ENVIRONMENT="dev"
  fi

  if [ "${STACK_EXIST_CHECK}" != "" ]; then
    echo "[FOUND]: Stack found in '${DEFAULT_ENVIRONMENT}'"
    for stack in ${STACK_EXIST_CHECK}; do
      echo "  --> ${stack}"
    done
  else
    echo "[NOT FOUND]: Stack not found in '${DEFAULT_ENVIRONMENT}'"
  fi
fi

if [ "${COMMAND}" == "exist" ]; then
  STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep -E "^${STACK_NAME}$")
  if [ "${STACK_EXIST_CHECK}" == "${STACK_NAME}" ]; then
    echo "[FOUND]: ${STACK_EXIST_CHECK}"
  else
    echo "[NOT FOUND]: ${STACK_NAME}"
  fi
fi


CFN_TEMPLATES_DIR=${SCRIPT_DIR}/templates/${ENVIRONMENT}/${SERVICE}
CFN_PARAMETERS_DIR=${SCRIPT_DIR}/parameters/${ENVIRONMENT}/${SERVICE}
CFN_TAGS_DIR=${SCRIPT_DIR}/tags/${ENVIRONMENT}/${SERVICE}

CHANGESET_NAME="${STACK_NAME}-changeset-${DATETIME}"

CREATE_CHANGE_SET() {
  cfn create-change-set \
    --stack-name ${STACK_NAME} \
    --template-body file://${CFN_TEMPLATES_DIR}/${STACK_NAME}.yaml \
    --parameters file://${CFN_PARAMETERS_DIR}/${STACK_NAME}_parameters.json \
    --change-set-name ${CHANGESET_NAME} \
    --tags $(cat ${CFN_TAGS_DIR}/${STACK_NAME}_tags_updates.properties)
}

SHOW_CHANGES() {
  CHANGESETS="$(cfn list-change-sets --stack-name ${STACK_NAME} --query 'Summaries[?Status==`CREATE_COMPLETE`].ChangeSetName' --output text)"
  LATEST_CHANGESET="$(echo ${CHANGESETS} | tr ' ' '\n' | sort -Vr | head -1)"
  
  if [ "${LATEST_CHANGESET}" != "" ]; then
    SHOW_CHANGES=$(cfn describe-change-set --stack-name ${STACK_NAME} --change-set-name ${LATEST_CHANGESET})
    echo "${SHOW_CHANGES}" | jq '.'
  fi
}

CLEAN_UP_FAILED() {
  FAILED_CHANGESETS="$(cfn list-change-sets --stack-name ${STACK_NAME} --query 'Summaries[?Status==`FAILED`].ChangeSetName' --output text)"

  if [ "${FAILED_CHANGESETS}" != "" ]; then
    for FAILED in ${FAILED_CHANGESETS}; do
      echo "Removing: ${FAILED}"
      cfn delete-change-set --change-set-name ${FAILED} --stack-name ${STACK_NAME}
    done
  else
    echo "No FAILED change set found."
  fi
}

DEPLOY_EMPTY_STACK() {
  STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep -E "^${STACK_NAME}$")
  EMPTY_STACK_TEMPLATE=${CFN_TEMPLATES_DIR}/${STACK_NAME}_empty_stack.yaml
  EMPTY_STACK_TAGS=${CFN_TAGS_DIR}/${STACK_NAME}_tags.properties
  if [ "${STACK_EXIST_CHECK}" != "${STACK_NAME}" ]; then
    cfn deploy --stack-name "${STACK_NAME}" --template-file ${EMPTY_STACK_TEMPLATE} --tags $(cat ${EMPTY_STACK_TAGS})
  else
    echo "${STACK_NAME} already exists."
    exit
  fi
}

DEPLOY_CHANGESET() {
  CHANGESETS="$(cfn list-change-sets --stack-name ${STACK_NAME} --query 'Summaries[?Status==`CREATE_COMPLETE`].ChangeSetName' --output text)"
  LATEST_CHANGESET="$(echo ${CHANGESETS} | tr ' ' '\n' | sort -Vr | head -1)"
  
  if [ "${LATEST_CHANGESET}" != "" ]; then
    cfn execute-change-set --change-set-name ${LATEST_CHANGESET} --stack-name ${STACK_NAME}
  else
    echo "No change set found."
  fi
}

DELETE_STACK() {
  STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep -E "^${STACK_NAME}$")
  
  if [ "${STACK_EXIST_CHECK}" == "${STACK_NAME}" ]; then
    echo "Deleting stack: ${STACK_NAME}"
    cfn delete-stack --stack-name ${STACK_NAME}
  else
    echo "No stack to delete."
  fi
}


if [ "${COMMAND}" == "generate" ]; then
  if [ "${ENVIRONMENT}" != "" ] && [ "${SERVICE}" != "" ]; then
    if ! [ -d ${CFN_TEMPLATES_DIR} ]; then
        mkdir -p ${CFN_TEMPLATES_DIR}
        echo "${CFN_TEMPLATES_DIR}"
    fi
    if ! [ -d ${CFN_PARAMETERS_DIR} ]; then
        mkdir -p ${CFN_PARAMETERS_DIR}
        echo "${CFN_PARAMETERS_DIR}"
    fi
    if ! [ -d ${CFN_TAGS_DIR} ]; then
        mkdir -p ${CFN_TAGS_DIR}
        echo "${CFN_TAGS_DIR}"
    fi
  fi
fi

if [ "${COMMAND}" == "deploy" ]; then
  if [ "${ENVIRONMENT}" != "" ] && [ "${SERVICE}" != "" ]; then
    STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep -E "^${STACK_NAME}$")
    if [ "${STACK_EXIST_CHECK}" != "${STACK_NAME}" ]; then
      DEPLOY_EMPTY_STACK
    else
      DEPLOY_CHANGESET
    fi
  fi
fi

if [ "${COMMAND}" == "create" ]; then
  if [ "${ENVIRONMENT}" != "" ] && [ "${SERVICE}" != "" ]; then
    STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep -E "^${STACK_NAME}$")
    if [ "${STACK_EXIST_CHECK}" == "${STACK_NAME}" ]; then
      CREATE_CHANGE_SET
    fi
  fi
fi

if [ "${COMMAND}" == "show" ]; then
  if [ "${ENVIRONMENT}" != "" ] && [ "${SERVICE}" != "" ]; then
    STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep -E "^${STACK_NAME}$")
    if [ "${STACK_EXIST_CHECK}" == "${STACK_NAME}" ]; then
      SHOW_CHANGES
    fi
  fi
fi

if [ "${COMMAND}" == "clean" ]; then
  if [ "${ENVIRONMENT}" != "" ] && [ "${SERVICE}" != "" ]; then
    STACK_EXIST_CHECK=$(list_stack | tr '\t' '\n' | grep -E "^${STACK_NAME}$")
    if [ "${STACK_EXIST_CHECK}" == "${STACK_NAME}" ]; then
      CLEAN_UP_FAILED
    fi
  fi
fi

if [ "${COMMAND}" == "delete" ]; then
  if [ "${ENVIRONMENT}" != "" ] && [ "${SERVICE}" != "" ] && [ "${ENVIRONMENT}" != "prod" ]; then
    DELETE_STACK
  fi
fi

if [ "${COMMAND}" == "assume" ]; then
  if [ "${ENVIRONMENT}" != "" ]; then
    ASSUME_ROLE
  fi
fi



