#!/usr/bin/env bash
set -e

script_dir="$(dirname "$0")"
ENVIRONMENT_FILE="$script_dir/../environment.sh"
if [ ! -f "$ENVIRONMENT_FILE" ]; then
    echo "Fatal: environment file $ENVIRONMENT_FILE does not exist!" 2>&1
    exit 1
fi

. $ENVIRONMENT_FILE

jenkins_ip="$(aws cloudformation describe-stacks --stack-name $dromedary_jenkins_stack_name --output text --query 'Stacks[0].Outputs[?OutputKey==`PublicDns`].OutputValue')"
codepipeline_role_arn="$(aws cloudformation describe-stacks --stack-name $dromedary_iam_stack_name --output text --query 'Stacks[0].Outputs[?OutputKey==`CodePipelineTrustRoleARN`].OutputValue')"
jenkins_url="http://$jenkins_ip:8080"

generate_cli_json() {
    cat << _END_
{
    "category": "$1",
    "provider": "$dromedary_custom_action_provider",
    "version": "1",
    "settings": {
        "entityUrlTemplate": "$jenkins_url/job/{Config:ProjectName}",
        "executionUrlTemplate": "$jenkins_url/job/{Config:ProjectName}/{ExternalExecutionId}"
    },
    "configurationProperties": [
        {
            "name": "ProjectName",
            "required": true,
            "key": true,
            "secret": false,
            "queryable": true
        }
    ],
    "inputArtifactDetails": {
        "minimumCount": 0,
        "maximumCount": 5
    },
    "outputArtifactDetails": {
        "minimumCount": 0,
        "maximumCount": 5
    }
}
_END_
}

aws codepipeline create-custom-action-type --cli-input-json "$(generate_cli_json Build)"
aws codepipeline create-custom-action-type --cli-input-json "$(generate_cli_json Test)"

pipelinejson=$(mktemp /tmp/dromedary-pipeline.json.XXXX)
pipeline_name="Dromedary$(echo $dromedary_hostname | tr '[[:lower:]]' '[[:upper:]]')"

cp "$script_dir/../pipeline/pipeline-custom-deploy.json" $pipelinejson

sed s/DromedaryJenkins/$dromedary_custom_action_provider/g $pipelinejson > $pipelinejson.new && mv $pipelinejson.new $pipelinejson
sed s/DromedaryPipelineName/$pipeline_name/g $pipelinejson > $pipelinejson.new && mv $pipelinejson.new $pipelinejson
sed s,arn:aws:iam::123456789012:role/AWS-CodePipeline-Service,$codepipeline_role_arn,g $pipelinejson > $pipelinejson.new && mv $pipelinejson.new $pipelinejson
sed s/codepipeline-us-east-1-XXXXXXXXXXX/$dromedary_s3_bucket/g $pipelinejson > $pipelinejson.new && mv $pipelinejson.new $pipelinejson

aws codepipeline create-pipeline --pipeline file://$pipelinejson || exit $?

echo "export dromedary_codepipeline=$pipeline_name" >> "$ENVIRONMENT_FILE"
rm -f $pipelinejson
